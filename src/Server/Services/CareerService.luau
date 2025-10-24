--!strict
-- ServerScriptService/Server/Services/CareerService.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local JobCatalog = require(ReplicatedStorage.Shared.Configurations.JobCatalog)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local JobPackets = require(ReplicatedStorage.Network.JobPackets)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ResidentPlacer = require(ServerScriptService.Server.Utilities.ResidentPlacer)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)

local PayrollService -- Lazy loaded to avoid circular dependency

export type CareerResult = {
	Success: boolean,
	Message: string?,
}

local CareerService = {}

local MAX_STREAK_BONUS = 0.25
local STREAK_STEP = 0.02
local COMMUTE_TIMEOUT_SECONDS = 12
local SHIFT_PREP_IDLE_TIMEOUT = 5
local SHIFT_PREP_FORCE_IDLE_TIMEOUT = 2
local MIN_ENERGY_FOR_SHIFT = 4

local ProfessionById: { [string]: JobCatalog.JobEntry } = {}
for _, job in JobCatalog.Jobs do
	if job.Type == "Profession" then
		ProfessionById[job.Id] = job
	end
end

local function resolveCareerName(careerId: string?): string
	if type(careerId) ~= "string" or careerId == "" then
		return "Unemployed"
	end
	local definition = ProfessionById[careerId]
	if definition and type(definition.Name) == "string" and definition.Name ~= "" then
		return definition.Name
	end
	return careerId
end

type ActiveResidentShift = {
	JobId: string,
	StartClock: number,
	SecondsPerMinute: number,
	EnergyConnection: RBXScriptConnection?,
	ForcedReason: string?,
}

local activeShiftsByUser: { [number]: { [string]: ActiveResidentShift } } = {}

local ENERGY_SHIFT_EXIT_THRESHOLD = 1
local MIN_SHIFT_MINUTES_FOR_PAYOUT = 5

local function ensureCareerFields(save: any)
	if typeof(save) ~= "table" then
		return
	end
	if typeof(save.Occupation) ~= "string" then
		save.Occupation = "Unemployed"
	end
	if typeof(save.CurrentCareerId) ~= "string" then
		save.CurrentCareerId = if save.Occupation ~= "Unemployed" then save.Occupation else ""
	end
	if typeof(save.CareerStreak) ~= "number" then
		save.CareerStreak = 0
	end
	if typeof(save.MomentumExpireClock) ~= "number" then
		save.MomentumExpireClock = 0
	end
end

local function getResidentState(player: Player, residentName: string?): (any?, string?)
	if type(residentName) ~= "string" or residentName == "" then
		return nil, "Select a resident first."
	end
	local residentState = ResidentService.GetResident(player, residentName)
	if residentState == nil then
		return nil, "Resident not found."
	end
	return residentState, nil
end

local function validateRequirements(residentState: any, career: JobCatalog.JobEntry): (boolean, string?)
	local save = residentState.Save
	ensureCareerFields(save)
	local statistics = if typeof(save.Statistics) == "table" then save.Statistics else nil
	if statistics == nil then
		statistics = {}
	end
	for _, requirement in ipairs(career.Requirements) do
		local statName = requirement.Stat
		local requiredLevel = requirement.Level
		local currentValue = statistics[statName]
		if type(currentValue) ~= "number" then
			currentValue = 0
		end
		if currentValue < requiredLevel then
			return false, ("%s requires %s %d."):format(career.Name, statName, requiredLevel)
		end
	end
	return true, nil
end

function CareerService.Init()
	ResidentService.PlayerResidentsChanged:Connect(function(player)
		local residents = ResidentService.GetResidents(player)
		if not residents then
			return
		end
		for _, residentState in pairs(residents) do
			local save = (residentState :: any).Save
			ensureCareerFields(save)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		local map = activeShiftsByUser[player.UserId]
		if map then
			for _, shiftRecord in pairs(map) do
				if shiftRecord.EnergyConnection then
					shiftRecord.EnergyConnection:Disconnect()
					shiftRecord.EnergyConnection = nil
				end
			end
		end
		activeShiftsByUser[player.UserId] = nil
	end)
	JobPackets.StartResidentShift.OnServerInvoke = function(player: Player, residentName: string?)
		local ok, success, message = pcall(CareerService.StartResidentShift, player, residentName or "")
		if not ok then
			warn(string.format("[CareerService] StartResidentShift failed: %s", tostring(success)))
			return false, "Could not start the shift."
		end
		return success, message or ""
	end
	JobPackets.StopResidentShift.OnServerInvoke = function(player: Player, residentName: string?)
		local ok, success, message, payout = pcall(CareerService.StopResidentShift, player, residentName or "")
		if not ok then
			warn(string.format("[CareerService] StopResidentShift failed: %s", tostring(success)))
			return false, "Could not complete the shift.", 0
		end
		return success, message or "", payout or 0
	end
end

function CareerService.GetCareerInfo(careerId: string): JobCatalog.JobEntry?
	return ProfessionById[careerId]
end

function CareerService.GetCareerForResident(player: Player, residentName: string?): string?
	local residentState = ResidentService.GetResident(player, residentName or "")
	if not residentState then
		return nil
	end
	local save = (residentState :: any).Save
	ensureCareerFields(save)
	return save.CurrentCareerId
end

function CareerService.ClearCareerForResident(player: Player, residentName: string?): CareerResult
	local residentState, errorMessage = getResidentState(player, residentName)
	if not residentState then
		return { Success = false, Message = errorMessage }
	end
	local save = residentState.Save
	ensureCareerFields(save)
	save.CurrentCareerId = ""
	save.Occupation = "Unemployed"
	save.CareerStreak = 0
	save.MomentumExpireClock = 0
	return { Success = true, Message = "Career cleared." }
end

function CareerService.SetCareerForResident(player: Player, residentName: string?, careerId: string): CareerResult
	local career = ProfessionById[careerId]
	if not career then
		return { Success = false, Message = "Unknown career." }
	end
	local residentState, errorMessage = getResidentState(player, residentName)
	if not residentState then
		return { Success = false, Message = errorMessage }
	end
	local allowed, denial = validateRequirements(residentState, career)
	if not allowed then
		return { Success = false, Message = denial }
	end
	local save = residentState.Save
	ensureCareerFields(save)
	local resolvedResidentName = residentName or "This resident"
	local currentCareerId = save.CurrentCareerId
	if type(currentCareerId) == "string" and currentCareerId ~= "" then
		if currentCareerId == career.Id then
			return {
				Success = false,
				Message = string.format(
					"%s already works as %s.",
					resolvedResidentName,
					resolveCareerName(currentCareerId)
				),
			}
		end
		return {
			Success = false,
			Message = string.format(
				"%s already has a career as %s. Ask them to quit first.",
				resolvedResidentName,
				resolveCareerName(currentCareerId)
			),
		}
	end
	save.CurrentCareerId = career.Id
	save.Occupation = career.Id
	return { Success = true, Message = career.Name .. " secured." }
end

local function getGigState(player: Player)
	return PlayerSession.TryGetData(player, "GigState")
end

local function pullMomentumMultiplier(gigState: any?): (number, boolean)
	if typeof(gigState) ~= "table" then
		return 1, false
	end
	local boost = gigState.MomentumBoost
	if typeof(boost) ~= "table" then
		return 1, false
	end
	local amount = tonumber(boost.Amount)
	local expiresAt = tonumber(boost.ExpiresAt)
	if amount and amount > 0 and expiresAt and expiresAt > os.time() then
		boost.Amount = 0
		boost.ExpiresAt = 0
		return 1 + amount, true
	end
	return 1, false
end

local function getPlotSpawnCFrame(player: Player): CFrame?
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local spawnPart = plotModel:FindFirstChild("Spawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame
	end
	return nil
end

local function commuteResidentToSpawn(
	residentName: string,
	residentState: any,
	spawnCFrame: CFrame?,
	cancelToken: ResidentMovement.CancelToken?
)
	task.spawn(function()
		local targetCFrame = spawnCFrame
		if spawnCFrame then
			local ok = ResidentMovement.GoToWorldPosition(residentState, spawnCFrame.Position, {
				CancelToken = cancelToken,
				TimeoutSeconds = COMMUTE_TIMEOUT_SECONDS,
				DebugName = string.format("Commute:%s", residentName),
			})
			if not ok then
				local model = residentState.Model
				if model then
					model:PivotTo(spawnCFrame)
				end
			end
		else
			local model = residentState.Model
			if model then
				targetCFrame = model:GetPivot()
			end
		end
		if cancelToken and cancelToken.Cancelled then
			return
		end
		if not residentState.IsOnShift then
			return
		end
		if targetCFrame and residentState.Model then
			residentState.Model:PivotTo(targetCFrame)
		end
		ResidentPlacer.Despawn(residentState)
	end)
end

local function haltResidentActivitiesForShift(residentState: any): boolean
	if residentState == nil then
		return false
	end
	local wasBusy = residentState.IsBusy == true
	if wasBusy then
		residentState:CancelCurrentAction("ShiftStart")
	end
	residentState:ClearQueuedActions()
	local idle = residentState:WaitUntilIdle(SHIFT_PREP_IDLE_TIMEOUT)
	if idle then
		return true
	end
	local cancelToken = residentState:GetCancelToken()
	if cancelToken then
		cancelToken.Cancelled = true
		cancelToken.Reason = "ShiftStart"
	end
	return residentState:WaitUntilIdle(SHIFT_PREP_FORCE_IDLE_TIMEOUT)
end

local function prepareResidentForShift(residentName: string, residentState: any, spawnCFrame: CFrame?)
	if residentState.IsOnShift then
		return false
	end
	local originalAutoActions = residentState.AutoActionsEnabled
	local originalAutoJob = residentState.AutoJobEnabled
	residentState:DisableAutomation()
	local idle = haltResidentActivitiesForShift(residentState)
	if not idle then
		residentState:SetAutoActionEnabled(typeof(originalAutoActions) == "boolean" and originalAutoActions or true)
		residentState:SetAutoJobEnabled(typeof(originalAutoJob) == "boolean" and originalAutoJob or true)
		residentState:ResetCancelToken()
		return false
	end
	residentState:ResetCancelToken()
	ResidentMovement.LeaveSeat(residentState, nil)
	ResidentMovement.ClearRestPose(residentState)
	local commuteToken: ResidentMovement.CancelToken = { Cancelled = false, Reason = nil }
	residentState._CareerShiftState = {
		AutoActionsEnabled = originalAutoActions,
		AutoJobEnabled = originalAutoJob,
		CommuteToken = commuteToken,
	}
	residentState.IsOnShift = true
	local model = residentState.Model
	if model then
		model:SetAttribute("IsOnShift", true)
		local currentCareer = residentState.Save.CurrentCareerId
		model:SetAttribute("WorkingJobId", if type(currentCareer) == "string" then currentCareer else "")
	end
	commuteResidentToSpawn(residentName, residentState, spawnCFrame, commuteToken)
	return true
end

local function resumeResidentFromShift(player: Player, residentState: any)
	local shiftRecord = residentState._CareerShiftState
	residentState._CareerShiftState = nil
	if shiftRecord and shiftRecord.CommuteToken then
		shiftRecord.CommuteToken.Cancelled = true
		shiftRecord.CommuteToken.Reason = "ShiftEnded"
	end
	if residentState.IsOnShift then
		residentState.IsOnShift = false
	end
	if shiftRecord then
		residentState:SetAutoActionEnabled(shiftRecord.AutoActionsEnabled == nil or shiftRecord.AutoActionsEnabled)
		residentState:SetAutoJobEnabled(shiftRecord.AutoJobEnabled == nil or shiftRecord.AutoJobEnabled)
	else
		residentState:EnableAutomation()
	end
	ResidentPlacer.Spawn(player, residentState)
	ResidentMovement.ClearRestPose(residentState)
	ResidentMovement.LeaveSeat(residentState, nil)
	local model = residentState.Model
	if model then
		model:SetAttribute("IsOnShift", false)
		model:SetAttribute("WorkingJobId", "")
	end
end

local function computePayoutForResident(
	job: JobCatalog.JobEntry,
	save: any,
	minutesWorked: number,
	momentumMultiplier: number
): number
	local minutes = math.max(0, minutesWorked)
	if minutes < MIN_SHIFT_MINUTES_FOR_PAYOUT then
		return 0
	end
	local basePerMinute = math.max(0, job.BasePay)
	local base = basePerMinute * minutes
	local streak = math.max(0, tonumber(save.CareerStreak) or 0)
	local streakMultiplier = 1 + math.min(streak * STREAK_STEP, MAX_STREAK_BONUS)
	local payout = math.floor(base * streakMultiplier * momentumMultiplier + 0.5)
	return payout
end

local function getActiveShiftMap(player: Player): { [string]: ActiveResidentShift }
	local map = activeShiftsByUser[player.UserId]
	if not map then
		map = {}
		activeShiftsByUser[player.UserId] = map
	end
	return map
end

local function clearActiveShift(player: Player, residentName: string, existing: ActiveResidentShift?)
	local map = activeShiftsByUser[player.UserId]
	if map then
		local shiftRecord = existing or map[residentName]
		if shiftRecord and shiftRecord.EnergyConnection then
			shiftRecord.EnergyConnection:Disconnect()
			shiftRecord.EnergyConnection = nil
		end
		map[residentName] = nil
		if next(map) == nil then
			activeShiftsByUser[player.UserId] = nil
		end
	end
end

local function secondsPerInGameMinute(): number
	local secondsPerDay = TimeScale.GetSecondsPerFullDay()
	local seconds = secondsPerDay / (24 * 60)
	if seconds <= 0 then
		return 1
	end
	return seconds
end

function CareerService.StartResidentShift(player: Player, residentName: string): (boolean, string)
	local residentState, errorMessage = getResidentState(player, residentName)
	if not residentState then
		return false, errorMessage or "Unknown resident."
	end
	ensureCareerFields(residentState.Save)
	if residentState.IsOnShift then
		return false, string.format("%s is already at work.", residentName)
	end
	local energyValue = residentState:GetNeed("Energy")
	if typeof(energyValue) ~= "number" or energyValue < MIN_ENERGY_FOR_SHIFT then
		return false, string.format("%s is too exhausted to start a shift.", residentName)
	end
	local save = residentState.Save
	local careerId = save.CurrentCareerId
	if type(careerId) ~= "string" or careerId == "" then
		return false, string.format("%s does not have a career assigned.", residentName)
	end
	local job = ProfessionById[careerId]
	if not job then
		return false, "Career definition missing."
	end
	local shiftMap = getActiveShiftMap(player)
	if shiftMap[residentName] then
		return false, string.format("%s is already clocked in.", residentName)
	end
	local spawnCFrame = getPlotSpawnCFrame(player)
	if not prepareResidentForShift(residentName, residentState, spawnCFrame) then
		return false, string.format("Could not send %s to work.", residentName)
	end
	local shiftRecord: ActiveResidentShift = {
		JobId = job.Id,
		StartClock = os.clock(),
		SecondsPerMinute = secondsPerInGameMinute(),
		EnergyConnection = nil,
		ForcedReason = nil,
	}
	shiftMap[residentName] = shiftRecord
	shiftRecord.EnergyConnection = residentState.NeedsChanged:Connect(function(needName: string, newValue: number)
		if needName ~= "Energy" then
			return
		end
		if typeof(newValue) ~= "number" then
			return
		end
		if newValue > ENERGY_SHIFT_EXIT_THRESHOLD then
			return
		end
		if not residentState.IsOnShift then
			return
		end
		shiftRecord.ForcedReason = "EnergyDepleted"
		if shiftRecord.EnergyConnection then
			shiftRecord.EnergyConnection:Disconnect()
			shiftRecord.EnergyConnection = nil
		end
		task.defer(function()
			CareerService.StopResidentShift(player, residentName)
		end)
	end)
	if typeof(residentState.GetNeed) == "function" then
		local currentEnergy = residentState:GetNeed("Energy")
		if typeof(currentEnergy) == "number" and currentEnergy <= ENERGY_SHIFT_EXIT_THRESHOLD then
			if shiftRecord.EnergyConnection then
				shiftRecord.EnergyConnection:Disconnect()
				shiftRecord.EnergyConnection = nil
			end
			shiftRecord.ForcedReason = "EnergyDepleted"
			task.defer(function()
				CareerService.StopResidentShift(player, residentName)
			end)
		end
	end
	return true, string.format("%s started working as %s.", residentName, job.Name)
end

function CareerService.StopResidentShift(player: Player, residentName: string): (boolean, string, number?)
	-- Lazy load PayrollService to avoid circular dependency
	if not PayrollService then
		PayrollService = require(ServerScriptService.Server.Services.PayrollService)
	end

	local shiftMap = activeShiftsByUser[player.UserId]
	if not shiftMap then
		return false, string.format("%s is not clocked in.", residentName)
	end
	local activeShift = shiftMap[residentName]
	if not activeShift then
		return false, string.format("%s is not clocked in.", residentName)
	end
	local residentState = ResidentService.GetResident(player, residentName)
	if not residentState then
		clearActiveShift(player, residentName, activeShift)
		return false, string.format("%s is unavailable.", residentName)
	end
	local job = ProfessionById[activeShift.JobId]
	if not job then
		clearActiveShift(player, residentName, activeShift)
		resumeResidentFromShift(player, residentState)
		return false, "Career definition missing."
	end
	resumeResidentFromShift(player, residentState)
	clearActiveShift(player, residentName, activeShift)
	ensureCareerFields(residentState.Save)
	local elapsedSeconds = math.max(0, os.clock() - activeShift.StartClock)
	local secondsPerMinute = math.max(0.001, activeShift.SecondsPerMinute)
	local minutesWorked = elapsedSeconds / secondsPerMinute
	local gigState = getGigState(player)
	local momentumMultiplier, _ = pullMomentumMultiplier(gigState)

	-- Calculate payout for display purposes
	local estimatedPayout = computePayoutForResident(job, residentState.Save, minutesWorked, momentumMultiplier)
	local shortShift = minutesWorked < MIN_SHIFT_MINUTES_FOR_PAYOUT

	if estimatedPayout > 0 and not shortShift then
		-- Record work time in PayrollService instead of instant payout
		local adjustedBasePay = job.BasePay * momentumMultiplier
		local streakMultiplier = 1
			+ math.min((residentState.Save.CareerStreak :: any or 0) * STREAK_STEP, MAX_STREAK_BONUS)
		adjustedBasePay = adjustedBasePay * streakMultiplier

		PayrollService.RecordWorkTime(player, residentName, elapsedSeconds, job.Id, adjustedBasePay / 60)
		residentState.Save.CareerStreak = math.max(0, (residentState.Save.CareerStreak :: any) or 0) + 1
	end

	local message
	if estimatedPayout > 0 and not shortShift then
		local suffix = " Earnings will be paid during the next payroll cycle."
		if activeShift.ForcedReason == "EnergyDepleted" then
			message = string.format("%s left work exhausted and earned ~$%d.%s", residentName, estimatedPayout, suffix)
		else
			message = string.format("%s earned ~$%d this shift.%s", residentName, estimatedPayout, suffix)
		end
	else
		if activeShift.ForcedReason == "EnergyDepleted" then
			message = string.format("%s left work exhausted with no payout.", residentName)
		elseif shortShift then
			message = string.format("%s ended the shift too quickly for a payout.", residentName)
		else
			message = string.format("%s ended the shift with no payout.", residentName)
		end
	end

	print(
		string.format(
			"[CareerService] Shift complete for %s (%s): minutes=%.2f estimated=$%d reason=%s",
			residentName,
			player.Name,
			minutesWorked,
			estimatedPayout,
			activeShift.ForcedReason or "Manual"
		)
	)
	return true, message, estimatedPayout
end

return CareerService
