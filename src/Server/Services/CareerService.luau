--!strict
-- ServerScriptService/Server/Services/CareerService.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local JobCatalog = require(ReplicatedStorage.Shared.Configurations.JobCatalog)
local CareerShiftConfig = require(ReplicatedStorage.Shared.Configurations.CareerShiftConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local JobPackets = require(ReplicatedStorage.Network.JobPackets)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PayrollService = require(ServerScriptService.Server.Services.PayrollService)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ResidentPlacer = require(ServerScriptService.Server.Utilities.ResidentPlacer)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local ShiftSchedulerService = require(ServerScriptService.Server.Services.ShiftSchedulerService)

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
	ShiftId: string?,
	StartServerTime: number,
	SecondsPerMinute: number,
	AccumulatedSeconds: number,
	EnergyConnection: RBXScriptConnection?,
	ForcedReason: string?,
}

type ShiftOperationOptions = {
	Source: "Manual" | "Scheduler",
}

type ShiftRuntimeSnapshot = ShiftSchedulerService.ShiftRuntimeSnapshot

local function sanitizeMessage(raw: string?): string
	if type(raw) ~= "string" then
		return ""
	end
	return raw:match("^%s*(.-)%s*$") or ""
end

local function resolveResidentName(residentName: string?): string
	if type(residentName) == "string" and residentName ~= "" then
		return residentName
	end
	return "Resident"
end

local function formatClockTime(clockValue: number?): string?
	if typeof(clockValue) ~= "number" then
		return nil
	end
	local totalMinutes = math.floor(clockValue * 60 + 0.5)
	local hour24 = math.floor(totalMinutes / 60) % 24
	local minutes = totalMinutes % 60
	local period = if hour24 >= 12 then "PM" else "AM"
	local hour12 = hour24 % 12
	if hour12 == 0 then
		hour12 = 12
	end
	return string.format("%d:%02d %s", hour12, minutes, period)
end

local function formatClockFromServerSeconds(serverSeconds: number?): string?
	if typeof(serverSeconds) ~= "number" then
		return nil
	end
	return formatClockTime(TimeScale.ClockTimeFromServerSeconds(serverSeconds))
end

local function describeClosedWindow(
	residentName: string,
	template: CareerShiftConfig.ShiftTemplate,
	snapshot: ShiftRuntimeSnapshot?
): string
	local shiftLabel = if template.Label and template.Label ~= "" then template.Label else "shift"
	local readableTime: string? = nil
	if snapshot then
		readableTime = formatClockFromServerSeconds(snapshot.NextStartTime)
		if not readableTime then
			readableTime = formatClockFromServerSeconds(snapshot.WindowStartTime)
		end
	end
	if not readableTime then
		readableTime = formatClockTime(template.StartClockTime)
	end
	if readableTime then
		return string.format("%s's %s window opens at %s. Try again then.", residentName, shiftLabel, readableTime)
	end
	return string.format(
		"%s's %s window is closed right now. Try again during the scheduled window.",
		residentName,
		shiftLabel
	)
end

local function isSchedulerSource(options: ShiftOperationOptions?): boolean
	return options ~= nil and options.Source == "Scheduler"
end

local function sendShiftNotice(
	player: Player?,
	residentName: string,
	shift: CareerShiftConfig.ShiftTemplate?,
	noticeType: string,
	serverSeconds: number?,
	message: string
)
	if not player or player.Parent == nil then
		return
	end
	if not shift then
		return
	end
	local clockTime = if typeof(serverSeconds) == "number"
		then TimeScale.ClockTimeFromServerSeconds(serverSeconds)
		else TimeScale.GetClockTime()
	JobPackets.ShiftNotice:FireClient(player, {
		ResidentName = residentName,
		ShiftId = shift.Id,
		ShiftLabel = shift.Label,
		NoticeType = noticeType,
		ClockTime = clockTime,
		Message = message,
	})
end

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
	if typeof(save.AssignedShiftId) ~= "string" then
		save.AssignedShiftId = ""
	end
	if typeof(save.PendingShiftResume) ~= "table" then
		save.PendingShiftResume = nil
	end
end

local function clockBaselineHours(): number
	return (tonumber(Lighting:GetAttribute("StartClockTime")) or 16.5) % 24
end

local function clockToDaySeconds(clockTime: number, secPerDay: number): number
	local baseline = clockBaselineHours()
	local deltaHours = (clockTime - baseline) % 24
	return (deltaHours / 24) * secPerDay
end

local function computeShiftDurationSeconds(template: CareerShiftConfig.ShiftTemplate): number
	local secPerDay = TimeScale.GetSecondsPerFullDay()
	local startSeconds = clockToDaySeconds(template.StartClockTime, secPerDay)
	local endSeconds = clockToDaySeconds(template.EndClockTime, secPerDay)
	local duration = (endSeconds - startSeconds) % secPerDay
	if duration <= 0 then
		duration = secPerDay
	end
	return duration
end

local function isShiftWindowOpen(template: CareerShiftConfig.ShiftTemplate): boolean
	local secPerDay = TimeScale.GetSecondsPerFullDay()
	local nowSeconds = Workspace:GetServerTimeNow()
	local startSeconds = clockToDaySeconds(template.StartClockTime, secPerDay)
	local duration = computeShiftDurationSeconds(template)
	local baseDayIndex = math.floor(nowSeconds / secPerDay)
	for dayOffset = 0, 1 do
		local dayIndex = baseDayIndex - dayOffset
		if dayIndex < 0 then
			break
		end
		local dayOfWeek = dayIndex % 7
		for _, allowedDay in template.Days do
			if allowedDay == dayOfWeek then
				local startTime = dayIndex * secPerDay + startSeconds
				local endTime = startTime + duration
				if nowSeconds >= startTime and nowSeconds < endTime then
					return true
				end
			end
		end
	end
	return false
end

type PendingShiftResume = {
	JobId: string?,
	ShiftId: string?,
	AccumulatedSeconds: number?,
	SavedAt: number?,
}

local function consumePendingShiftResume(save: any, jobId: string, currentShiftId: string?): (number, string?)
	local resume = save.PendingShiftResume
	if typeof(resume) ~= "table" then
		return 0, currentShiftId
	end
	local resumeJobId = if typeof(resume.JobId) == "string" then resume.JobId else nil
	if resumeJobId ~= jobId then
		save.PendingShiftResume = nil
		return 0, currentShiftId
	end
	local resumeShiftId = if typeof(resume.ShiftId) == "string" and resume.ShiftId ~= "" then resume.ShiftId else nil
	local resolvedShiftId = currentShiftId
	if resolvedShiftId == nil or resolvedShiftId == "" then
		resolvedShiftId = resumeShiftId
	elseif resumeShiftId ~= nil and resumeShiftId ~= resolvedShiftId then
		save.PendingShiftResume = nil
		return 0, resolvedShiftId
	end
	local template: CareerShiftConfig.ShiftTemplate? = nil
	if resolvedShiftId and resolvedShiftId ~= "" then
		template = CareerShiftConfig.GetShift(resolvedShiftId)
	end
	if not template then
		save.PendingShiftResume = nil
		return 0, resolvedShiftId
	end
	if not isShiftWindowOpen(template) then
		save.PendingShiftResume = nil
		return 0, resolvedShiftId
	end
	local accumulated = tonumber(resume.AccumulatedSeconds)
	if not accumulated or accumulated <= 0 then
		save.PendingShiftResume = nil
		return 0, resolvedShiftId
	end
	local maxDuration = computeShiftDurationSeconds(template)
	accumulated = math.clamp(accumulated, 0, maxDuration)
	save.PendingShiftResume = nil
	return accumulated, resolvedShiftId
end

local function storePendingShiftResume(residentState: any, shiftRecord: ActiveResidentShift)
	local save = residentState.Save
	ensureCareerFields(save)
	local shiftId = shiftRecord.ShiftId
	if shiftId == nil or shiftId == "" then
		shiftId = if typeof(save.AssignedShiftId) == "string" and save.AssignedShiftId ~= ""
			then save.AssignedShiftId
			else nil
	end
	if not shiftId then
		return
	end
	local template = CareerShiftConfig.GetShift(shiftId)
	if not template then
		return
	end
	if template.JobId ~= shiftRecord.JobId then
		return
	end
	if not isShiftWindowOpen(template) then
		return
	end
	local nowSeconds = Workspace:GetServerTimeNow()
	local startServer = shiftRecord.StartServerTime or nowSeconds
	local elapsed = math.max(0, nowSeconds - startServer) + (shiftRecord.AccumulatedSeconds or 0)
	local maxDuration = computeShiftDurationSeconds(template)
	if maxDuration <= 0 then
		return
	end
	local clamped = math.clamp(elapsed, 0, maxDuration)
	if clamped <= 0 then
		return
	end
	local previous = save.PendingShiftResume
	if typeof(previous) == "table" then
		local prevSeconds = tonumber(previous.AccumulatedSeconds)
		if prevSeconds and prevSeconds > clamped then
			clamped = math.min(prevSeconds, maxDuration)
		end
	end
	save.PendingShiftResume = {
		JobId = shiftRecord.JobId,
		ShiftId = shiftId,
		AccumulatedSeconds = clamped,
		SavedAt = os.time(),
	} :: PendingShiftResume
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
			for residentName, shiftRecord in pairs(map) do
				if shiftRecord.EnergyConnection then
					shiftRecord.EnergyConnection:Disconnect()
					shiftRecord.EnergyConnection = nil
				end
				local residentState = ResidentService.GetResident(player, residentName)
				if residentState then
					storePendingShiftResume(residentState, shiftRecord)
					local shiftState = residentState._CareerShiftState
					if shiftState and shiftState.CommuteToken then
						shiftState.CommuteToken.Cancelled = true
						shiftState.CommuteToken.Reason = "PlayerDisconnected"
					end
					if shiftState then
						residentState:SetAutoActionEnabled(
							shiftState.AutoActionsEnabled == nil or shiftState.AutoActionsEnabled
						)
						residentState:SetAutoJobEnabled(shiftState.AutoJobEnabled == nil or shiftState.AutoJobEnabled)
					else
						residentState:EnableAutomation()
					end
					residentState._CareerShiftState = nil
					residentState.IsOnShift = false
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
		local trimmedMessage = sanitizeMessage(message)
		if trimmedMessage == "" then
			local label = resolveResidentName(residentName)
			trimmedMessage = if success
				then string.format("%s is heading to work.", label)
				else "Could not start the shift."
		end
		return success, trimmedMessage
	end
	JobPackets.StopResidentShift.OnServerInvoke = function(player: Player, residentName: string?)
		local ok, success, message, payout = pcall(CareerService.StopResidentShift, player, residentName or "")
		if not ok then
			warn(string.format("[CareerService] StopResidentShift failed: %s", tostring(success)))
			return false, "Could not complete the shift.", 0
		end
		local trimmedMessage = sanitizeMessage(message)
		if trimmedMessage == "" then
			local label = resolveResidentName(residentName)
			trimmedMessage = if success
				then string.format("%s is heading back home.", label)
				else "Could not complete the shift."
		end
		return success, trimmedMessage, payout or 0
	end
	JobPackets.AssignResidentShift.OnServerInvoke = function(player: Player, residentName: string?, shiftId: string?)
		local ok, result = pcall(CareerService.AssignResidentShift, player, residentName or "", shiftId or "")
		if not ok then
			warn(string.format("[CareerService] AssignResidentShift failed: %s", tostring(result)))
			return false, "Could not update the schedule."
		end
		return result.Success, result.Message or ""
	end

	ShiftSchedulerService.ShiftReminder:Connect(function(payload)
		local player = payload.Player
		if not player or player.Parent == nil then
			return
		end
		local shiftRaw = payload.Shift
		if not shiftRaw then
			return
		end
		local shift = shiftRaw :: CareerShiftConfig.ShiftTemplate
		sendShiftNotice(
			player,
			payload.ResidentName,
			shift,
			"Reminder",
			payload.StartServerTime,
			string.format("%s shift starts soon.", shift.Label)
		)
	end)

	ShiftSchedulerService.ShiftStartDue:Connect(function(payload)
		local player = payload.Player
		if not player or player.Parent == nil then
			payload.Confirm({ Outcome = "Missed", Reason = "PlayerUnavailable" })
			return
		end
		local residentName = payload.ResidentName
		local shiftRaw = payload.Shift
		if not shiftRaw then
			payload.Confirm({ Outcome = "Missed", Reason = "ShiftUnavailable" })
			return
		end
		local shift = shiftRaw :: CareerShiftConfig.ShiftTemplate
		local residentState = ResidentService.GetResident(player, residentName)
		if not residentState then
			payload.Confirm({ Outcome = "Missed", Reason = "ResidentUnavailable" })
			sendShiftNotice(player, residentName, shift, "Missed", payload.StartServerTime, "Resident unavailable.")
			return
		end
		ensureCareerFields(residentState.Save)
		local assignedShiftId = residentState.Save.AssignedShiftId
		if typeof(assignedShiftId) == "string" and assignedShiftId ~= shift.Id then
			payload.Confirm({ Outcome = "Missed", Reason = "ShiftChanged" })
			sendShiftNotice(player, residentName, shift, "Missed", payload.StartServerTime, "Shift changed.")
			return
		end
		if residentState.IsOnShift then
			payload.Confirm({ Outcome = "Skipped", Reason = "AlreadyOnShift" })
			return
		end
		local success, message = CareerService.StartResidentShift(player, residentName, { Source = "Scheduler" })
		if success then
			payload.Confirm({
				Outcome = "Started",
				StartServerTimeOverride = payload.StartServerTime,
				EndServerTimeOverride = nil :: number?,
				Reason = "",
			})
			sendShiftNotice(
				player,
				residentName,
				shift,
				"AutoStart",
				payload.StartServerTime,
				string.format("%s clocked in automatically.", residentName)
			)
		else
			payload.Confirm({ Outcome = "Missed", Reason = message })
			sendShiftNotice(player, residentName, shift, "Missed", payload.StartServerTime, message)
		end
	end)

	ShiftSchedulerService.ShiftEndDue:Connect(function(payload)
		local player = payload.Player
		if not player or player.Parent == nil then
			payload.Confirm({ Outcome = "Skipped", Reason = "PlayerUnavailable", NextStartFrom = payload.EndServerTime })
			return
		end
		local residentName = payload.ResidentName
		local shiftRaw = payload.Shift
		if not shiftRaw then
			payload.Confirm({ Outcome = "Skipped", Reason = "ShiftUnavailable", NextStartFrom = payload.EndServerTime })
			return
		end
		local shift = shiftRaw :: CareerShiftConfig.ShiftTemplate
		local residentState = ResidentService.GetResident(player, residentName)
		if not residentState or not residentState.IsOnShift then
			payload.Confirm({ Outcome = "Skipped", Reason = "NotOnShift", NextStartFrom = payload.EndServerTime })
			return
		end
		local success, message = CareerService.StopResidentShift(player, residentName, { Source = "Scheduler" })
		if success then
			payload.Confirm({ Outcome = "Ended", Reason = "", NextStartFrom = payload.EndServerTime })
			sendShiftNotice(player, residentName, shift, "AutoEnd", payload.EndServerTime, message)
		else
			payload.Confirm({ Outcome = "Skipped", Reason = message, NextStartFrom = payload.EndServerTime })
		end
	end)

	ShiftSchedulerService.ShiftMissed:Connect(function(payload)
		sendShiftNotice(
			payload.Player,
			payload.ResidentName,
			payload.Shift,
			"Missed",
			nil,
			payload.Reason or "Missed shift."
		)
	end)
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
	save.PendingShiftResume = nil
	if save.AssignedShiftId ~= "" then
		save.AssignedShiftId = ""
		local resolvedName = residentState.Save.Name
		if type(resolvedName) == "string" and resolvedName ~= "" then
			ShiftSchedulerService.ClearShift(player, resolvedName)
		end
	end
	ResidentService.DispatchResidentUpdate(player, residentState)
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
	save.AssignedShiftId = ""
	save.PendingShiftResume = nil
	local resolvedName = residentState.Save.Name
	if type(resolvedName) == "string" and resolvedName ~= "" then
		ShiftSchedulerService.ClearShift(player, resolvedName)
	end
	ResidentService.DispatchResidentUpdate(player, residentState)
	return { Success = true, Message = career.Name .. " secured." }
end

function CareerService.AssignResidentShift(player: Player, residentName: string?, shiftId: string): CareerResult
	local residentState, errorMessage = getResidentState(player, residentName)
	if not residentState then
		return { Success = false, Message = errorMessage }
	end
	local save = residentState.Save
	ensureCareerFields(save)
	local residentCareer = save.CurrentCareerId
	if type(residentCareer) ~= "string" or residentCareer == "" then
		return { Success = false, Message = "Assign a career first." }
	end
	if type(shiftId) ~= "string" or shiftId == "" then
		if save.AssignedShiftId ~= "" then
			save.AssignedShiftId = ""
			save.PendingShiftResume = nil
			ShiftSchedulerService.ClearShift(player, residentState.Save.Name)
		end
		ResidentService.DispatchResidentUpdate(player, residentState)
		return { Success = true, Message = "Shift assignment cleared." }
	end
	local shift = CareerShiftConfig.GetShift(shiftId)
	if not shift then
		return { Success = false, Message = "Unknown shift." }
	end
	if shift.JobId ~= residentCareer then
		return {
			Success = false,
			Message = string.format("Shift does not belong to %s's career.", residentName or "this resident"),
		}
	end
	save.PendingShiftResume = nil
	save.AssignedShiftId = shiftId
	ShiftSchedulerService.ApplyShiftAssignment(player, residentState, shiftId)
	ResidentService.DispatchResidentUpdate(player, residentState)
	return {
		Success = true,
		Message = string.format("%s scheduled for %s.", residentName or "Resident", shift.Label),
	}
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

function CareerService.StartResidentShift(
	player: Player,
	residentName: string,
	options: ShiftOperationOptions?
): (boolean, string)
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
	local assignedShiftId = if typeof(save.AssignedShiftId) == "string" then save.AssignedShiftId else ""
	local pendingResumeSnapshot = save.PendingShiftResume

	local carriedSeconds = 0
	local resumeShiftId: string?
	carriedSeconds, resumeShiftId = consumePendingShiftResume(save, job.Id, assignedShiftId)
	local resolvedShiftId = assignedShiftId
	if resumeShiftId and resumeShiftId ~= "" then
		resolvedShiftId = resumeShiftId
	end

	local runtimeSnapshot: ShiftRuntimeSnapshot? = ShiftSchedulerService.GetShiftRuntimeSnapshot(player, residentName)
	local shiftTemplate: CareerShiftConfig.ShiftTemplate? = nil
	if resolvedShiftId ~= "" then
		shiftTemplate = CareerShiftConfig.GetShift(resolvedShiftId)
	end
	if runtimeSnapshot and runtimeSnapshot.Template then
		shiftTemplate = shiftTemplate or runtimeSnapshot.Template
	end

	if not isSchedulerSource(options) and shiftTemplate then
		local windowOpen = if runtimeSnapshot then runtimeSnapshot.IsWithinWindow else isShiftWindowOpen(shiftTemplate)
		if not windowOpen then
			save.PendingShiftResume = pendingResumeSnapshot
			local denialMessage = describeClosedWindow(residentName, shiftTemplate, runtimeSnapshot)
			return false, denialMessage
		end
	end
	local spawnCFrame = getPlotSpawnCFrame(player)
	if not prepareResidentForShift(residentName, residentState, spawnCFrame) then
		save.PendingShiftResume = pendingResumeSnapshot
		return false, string.format("Could not send %s to work.", residentName)
	end
	local shiftRecord: ActiveResidentShift = {
		JobId = job.Id,
		ShiftId = if resolvedShiftId ~= "" then resolvedShiftId else nil,
		StartServerTime = Workspace:GetServerTimeNow(),
		SecondsPerMinute = secondsPerInGameMinute(),
		AccumulatedSeconds = carriedSeconds,
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
	local message = string.format("%s started working as %s.", residentName, job.Name)
	if not isSchedulerSource(options) then
		ShiftSchedulerService.NotifyClockIn(player, residentName)
	end
	return true, message
end

function CareerService.StopResidentShift(
	player: Player,
	residentName: string,
	options: ShiftOperationOptions?
): (boolean, string, number?)
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
	local save = residentState.Save
	local nowServer = Workspace:GetServerTimeNow()
	local elapsedSeconds = math.max(0, nowServer - activeShift.StartServerTime)
		+ math.max(0, activeShift.AccumulatedSeconds or 0)
	local shiftIdForClamp = activeShift.ShiftId
	if (shiftIdForClamp == nil or shiftIdForClamp == "") and typeof(save.AssignedShiftId) == "string" then
		shiftIdForClamp = save.AssignedShiftId
	end
	if shiftIdForClamp and shiftIdForClamp ~= "" then
		local templateForClamp = CareerShiftConfig.GetShift(shiftIdForClamp)
		if templateForClamp then
			local maxDuration = computeShiftDurationSeconds(templateForClamp)
			if maxDuration > 0 then
				elapsedSeconds = math.min(elapsedSeconds, maxDuration)
			end
		end
	end
	local secondsPerMinute = math.max(0.001, activeShift.SecondsPerMinute)
	local minutesWorked = elapsedSeconds / secondsPerMinute
	local gigState = getGigState(player)
	local momentumMultiplier, _ = pullMomentumMultiplier(gigState)
	save.PendingShiftResume = nil

	-- Calculate payout for display purposes
	local estimatedPayout = computePayoutForResident(job, residentState.Save, minutesWorked, momentumMultiplier)
	local shortShift = minutesWorked < MIN_SHIFT_MINUTES_FOR_PAYOUT

	if estimatedPayout > 0 and not shortShift then
		-- Record work time in PayrollService instead of instant payout
		local adjustedBasePay = job.BasePay * momentumMultiplier
		local streakMultiplier = 1
			+ math.min((residentState.Save.CareerStreak :: any or 0) * STREAK_STEP, MAX_STREAK_BONUS)
		adjustedBasePay = adjustedBasePay * streakMultiplier

		PayrollService.RecordWorkTime(player, residentName, minutesWorked, job.Id, adjustedBasePay)
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
	if not isSchedulerSource(options) then
		ShiftSchedulerService.NotifyClockOut(player, residentName)
	end
	return true, message, estimatedPayout
end

return CareerService
