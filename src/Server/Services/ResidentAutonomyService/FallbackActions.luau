--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local State = require(script.Parent.State)
local Utils = require(script.Parent.Utils)
local Constants = require(script.Parent.Constants)
local StationManager = require(script.Parent.StationManager)
local ActionQueue = require(script.Parent.ActionQueue)
local RandomProvider = require(script.Parent.RandomProvider)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

export type ResidentState = any
type StationCache = { [string]: any }

type Module = {
	enqueueRoamAction: (Player, string, ResidentState) -> boolean,
	evaluateResidentJob: (Player, string, ResidentState, StationCache?) -> boolean,
	TriggerImmediateBladderEmergency: (ResidentState) -> boolean,
}

local FallbackActions = {}
local roamRandom = RandomProvider.get()
local begRandom = RandomProvider.get()

local EMERGENCY_RELIEF_ACTION_NAME = "Auto:EmergencyRelief"
local EMERGENCY_RELIEF_DURATION_SECONDS = 6
local EMERGENCY_RELIEF_HYGIENE_PENALTY = 32
local EMERGENCY_RELIEF_TARGET_RATIO = 0.7
local EMERGENCY_RELIEF_CHAT_LINES = {
	"I... couldn't hold it...",
	"That was embarrassing...",
}
local WATER_SPILL_LIFETIME_SECONDS = 20
local WATER_SPILL_RAYCAST_DISTANCE = 16

local lastEmergencyByResident = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })

local function spawnWaterSpillEffect(resident: ResidentState)
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return
	end
	local template = assets:FindFirstChild("WaterSpill")
	if not template or not template:IsA("Model") then
		return
	end
	local residentModel = resident and resident.Model
	if not residentModel or not residentModel:IsA("Model") then
		return
	end

	local rootPart: BasePart? = nil
	if residentModel.PrimaryPart and residentModel.PrimaryPart:IsA("BasePart") then
		rootPart = residentModel.PrimaryPart
	else
		rootPart = residentModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	end
	if not rootPart then
		return
	end

	local origin = rootPart.Position
	local targetPosition = origin
	local rayParams = RaycastParams.new()
	rayParams.FilterDescendantsInstances = { residentModel }
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.IgnoreWater = true
	local rayDirection = Vector3.new(0, -WATER_SPILL_RAYCAST_DISTANCE, 0)
	local result = Workspace:Raycast(origin, rayDirection, rayParams)
	if result then
		targetPosition = result.Position
	else
		targetPosition = origin - Vector3.new(0, rootPart.Size.Y * 0.5, 0)
	end

	local waterSpill = template:Clone()
	waterSpill:PivotTo(CFrame.new(targetPosition))
	waterSpill.Parent = Workspace

	task.delay(WATER_SPILL_LIFETIME_SECONDS, function()
		if waterSpill.Parent then
			waterSpill:Destroy()
		end
	end)
end

local function applyEmergencyReliefEffect(
	resident: ResidentState,
	needs: { [string]: any },
	bladderDef: { [string]: any }
)
	local maxValue = if typeof(bladderDef.Max) == "number" then bladderDef.Max else 100
	local minValue = if typeof(bladderDef.Min) == "number" then bladderDef.Min else 0
	local targetValue = math.floor(maxValue * EMERGENCY_RELIEF_TARGET_RATIO + 0.5)
	targetValue = math.clamp(targetValue, minValue, maxValue)
	resident:SetNeed("Bladder", targetValue)

	local hygieneDef = needs.Hygiene
	if hygieneDef then
		local hygieneValue = resident:GetNeed("Hygiene")
		local hygieneMin = if typeof(hygieneDef.Min) == "number" then hygieneDef.Min else 0
		local hygieneMax = if typeof(hygieneDef.Max) == "number" then hygieneDef.Max else 100
		local newHygiene = math.clamp(hygieneValue - EMERGENCY_RELIEF_HYGIENE_PENALTY, hygieneMin, hygieneMax)
		if newHygiene ~= hygieneValue then
			resident:SetNeed("Hygiene", newHygiene)
		end
	end

	State.setNeedCooldown(resident, "Bladder")
	State.clearNextEvaluation(resident)
	lastEmergencyByResident[resident] = os.clock()
	spawnWaterSpillEffect(resident)
end

function FallbackActions.TriggerImmediateBladderEmergency(resident: ResidentState): boolean
	local needs = State.getNeeds()
	local bladderDef = needs.Bladder
	if bladderDef == nil then
		return false
	end

	local bladderValue = resident:GetNeed("Bladder")
	if typeof(bladderValue) ~= "number" then
		return false
	end

	local minValue = if typeof(bladderDef.Min) == "number" then bladderDef.Min else 0
	if bladderValue > minValue then
		return false
	end

	local lastTrigger = lastEmergencyByResident[resident]
	if lastTrigger ~= nil then
		local elapsed = os.clock() - lastTrigger
		if elapsed >= 0 and elapsed < 1 then
			return false
		end
	end

	ResidentChat.ShowAction(resident, EMERGENCY_RELIEF_CHAT_LINES)
	applyEmergencyReliefEffect(resident, needs, bladderDef)
	return true
end

local JOG_ACTION_NAME = Constants.JOG_ACTION_NAME or "Auto:Jog"
local JOG_MIN_INTERVAL_SECONDS = math.max(Constants.JOG_MIN_INTERVAL_SECONDS or 0, 0)
local JOG_DURATION_SECONDS = math.max(Constants.JOG_DURATION_SECONDS or 30, 10)
local JOG_TICK_INTERVAL = math.max(Constants.JOG_TICK_INTERVAL or 3, 1)
local JOG_FUN_PER_TICK = math.max(Constants.JOG_FUN_PER_TICK or 6, 1)
local JOG_MOVE_SPEED_MULTIPLIER = math.max(Constants.JOG_MOVE_SPEED_MULTIPLIER or 1.5, 1.0)
local JOG_MOVE_TIMEOUT_SECONDS = math.max(Constants.JOG_MOVE_TIMEOUT_SECONDS or 1, 1)
local JOG_CHAT_LINES = Constants.JOG_CHAT_LINES

local BEG_ACTION_NAME = Constants.BEG_ACTION_NAME
local BEG_ACTION_LABEL = Constants.BEG_ACTION_LABEL
local BEG_TICK_SECONDS = Constants.BEG_TICK_SECONDS
local BEG_CHAT_INTERVAL_SECONDS = Constants.BEG_CHAT_INTERVAL_SECONDS
local BEG_STATION_REFRESH_INTERVAL = Constants.BEG_STATION_REFRESH_INTERVAL
local BEG_PAYOUT_CURRENCY = Constants.BEG_PAYOUT_CURRENCY
local BEG_PAYOUT_CHANCE = math.clamp(Constants.BEG_PAYOUT_CHANCE or 0.15, 0, 1)
local BEG_PAYOUT_MIN = math.max(Constants.BEG_PAYOUT_MIN or 1, 1)
local BEG_PAYOUT_MAX = math.max(Constants.BEG_PAYOUT_MAX or 5, BEG_PAYOUT_MIN)
local BEG_CHAT_LINES = Constants.BEG_CHAT_LINES
local BEG_ROAM_MIN_DISTANCE = math.max(Constants.BEG_ROAM_MIN_DISTANCE or 10, 5)
local BEG_ROAM_MAX_DISTANCE = math.max(Constants.BEG_ROAM_MAX_DISTANCE or 25, BEG_ROAM_MIN_DISTANCE)
local BEG_ROAM_HEIGHT_OFFSET = Constants.BEG_ROAM_HEIGHT_OFFSET or 0
local BEG_MOVE_TIMEOUT_SECONDS = math.max(Constants.BEG_MOVE_TIMEOUT_SECONDS or 0, 1)
local BEG_ROAM_INTERVAL_SECONDS = math.max(Constants.BEG_ROAM_INTERVAL_SECONDS or 8, 3)

local function getResidentName(resident: ResidentState): string
	local save = resident and resident.Save
	local name = if typeof(save) == "table" and typeof(save.Name) == "string" then save.Name else nil
	return name or "Resident"
end

-- Picks a random position within the plot at a specified distance range from spawn
local function computeBeggingDestination(player: Player): Vector3?
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local spawnPart = plotModel:FindFirstChild("Spawn")
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return nil
	end
	local spawnPosition = spawnPart.Position

	-- Generate random angle (0 to 2π)
	local angle = begRandom:NextNumber(0, math.pi * 2)

	-- Generate random distance within the configured range
	local distance = begRandom:NextNumber(BEG_ROAM_MIN_DISTANCE, BEG_ROAM_MAX_DISTANCE)

	-- Calculate position using polar coordinates
	local offsetX = math.cos(angle) * distance
	local offsetZ = math.sin(angle) * distance

	local targetPosition =
		Vector3.new(spawnPosition.X + offsetX, spawnPosition.Y + BEG_ROAM_HEIGHT_OFFSET, spawnPosition.Z + offsetZ)

	return targetPosition
end

local function getUnlockedChunkIndices(runtimeState: any): { number }
	local save = runtimeState.Save
	local version = if save then #save.UnlockedChunks else 0
	local cached = runtimeState._autonomyUnlockedCache
	local cachedVersion = runtimeState._autonomyUnlockedVersion
	if cached and cachedVersion == version then
		return cached
	end
	local chunkUnlocked = runtimeState.ChunkUnlocked
	local rebuilt = {} :: { number }
	for index = 1, #chunkUnlocked do
		if chunkUnlocked[index] then
			rebuilt[#rebuilt + 1] = index
		end
	end
	runtimeState._autonomyUnlockedCache = rebuilt
	runtimeState._autonomyUnlockedVersion = version
	return rebuilt
end

-- Picks a position for jogging - extends beyond plot boundaries for outdoor exercise
local function chooseJoggingPosition(player: Player): Vector3?
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local spawnPart = plotModel:FindFirstChild("Spawn")
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return nil
	end
	local spawnPosition = spawnPart.Position

	-- Generate random angle (0 to 2π) for direction
	local angle = roamRandom:NextNumber(0, math.pi * 2)

	-- Jogging goes FURTHER than begging - 30 to 60 studs from spawn
	-- This makes residents jog outside/around the plot
	local distance = roamRandom:NextNumber(30, 60)

	-- Calculate position using polar coordinates
	local offsetX = math.cos(angle) * distance
	local offsetZ = math.sin(angle) * distance

	local targetPosition = Vector3.new(
		spawnPosition.X + offsetX,
		spawnPosition.Y, -- Keep at ground level
		spawnPosition.Z + offsetZ
	)

	return targetPosition
end

local function chooseRoamPosition(player: Player): Vector3?
	local runtimeState = PlotService.GetState(player)
	if not runtimeState then
		return nil
	end
	local grid = runtimeState.Grid
	if not grid then
		return nil
	end
	local chunkColumns = runtimeState.ChunkColumns
	local chunkSize = runtimeState.ChunkSizeInCells
	local unlockedChunks = getUnlockedChunkIndices(runtimeState)
	if #unlockedChunks == 0 then
		return nil
	end
	local attempts = 0
	local fallbackChunkIndex = nil
	while attempts < 20 do
		attempts += 1
		local chunkIndex = unlockedChunks[roamRandom:NextInteger(1, #unlockedChunks)]
		fallbackChunkIndex = chunkIndex
		local chunkX = ((chunkIndex - 1) % chunkColumns) + 1
		local chunkZ = math.floor((chunkIndex - 1) / chunkColumns) + 1
		local cellX = (chunkX - 1) * chunkSize + roamRandom:NextInteger(0, chunkSize - 1) + 1
		local cellZ = (chunkZ - 1) * chunkSize + roamRandom:NextInteger(0, chunkSize - 1) + 1
		if cellX > grid.Columns or cellZ > grid.Rows then
			continue
		end
		local cellIndex = grid:CellToIndex(cellX, cellZ)
		if runtimeState.CellFree[cellIndex] then
			return grid:CellToWorldCenter(cellX, cellZ, 0)
		end
	end
	if fallbackChunkIndex ~= nil then
		local chunkX = ((fallbackChunkIndex - 1) % chunkColumns) + 1
		local chunkZ = math.floor((fallbackChunkIndex - 1) / chunkColumns) + 1
		return grid:ChunkCenterCFrame(chunkX, chunkZ, chunkSize, 0).Position
	end
	return nil
end

local function enqueueJogAction(player: Player, resident: ResidentState, _stationCache: StationCache?): boolean
	local needs = State.getNeeds()
	local funDef = needs.Fun
	if funDef == nil then
		return false
	end

	local startingFun = resident:GetNeed("Fun")
	local comfortThreshold = math.min(funDef.Low + funDef.Hysteresis, funDef.Max)
	if startingFun >= comfortThreshold then
		return false
	end

	-- Only block jogging if there's a SURVIVAL critical need (Hunger/Energy)
	-- Don't block for non-survival needs (Social/Hygiene/Fun) that have no stations
	-- This allows jogging to provide SOME relief when residents are stuck with unmet non-survival needs
	local hungerDef = needs.Hunger
	local energyDef = needs.Energy
	if hungerDef then
		local hungerValue = resident:GetNeed("Hunger")
		if hungerValue <= hungerDef.Critical then
			return false -- Starving, can't jog
		end
	end
	if energyDef then
		local energyValue = resident:GetNeed("Energy")
		if energyValue <= energyDef.Critical then
			return false -- Exhausted, can't jog
		end
	end

	local now = os.clock()
	local lastJog = State.getLastJog(resident)
	if lastJog and now - lastJog < JOG_MIN_INTERVAL_SECONDS then
		return false
	end

	local pendingAction = JOG_ACTION_NAME
	State.setPending(resident, pendingAction)
	State.clearNextEvaluation(resident)
	State.recordJog(resident, now)

	resident:EnqueueAction(pendingAction, function(context)
		local cancelToken = context.CancelToken
		local finalized = false
		local funPausePushed = false

		local function finalize(_cancelled: boolean, elapsedTime: number)
			if finalized then
				return
			end
			finalized = true
			if funPausePushed then
				resident:PopNeedPause("Fun")
				funPausePushed = false
			end
			State.setPending(resident, nil)
			State.setNeedCooldown(resident, "Fun")
			State.recordJog(resident, os.clock())

			-- Note: Fun is already updated incrementally during jog, no need to add more here
		end

		-- Pause Fun decay during jog
		resident:PushNeedPause("Fun")
		funPausePushed = true

		-- Show chat message
		if type(JOG_CHAT_LINES) == "table" and #JOG_CHAT_LINES > 0 then
			ResidentChat.ShowAction(resident, JOG_CHAT_LINES)
		end

		-- Increase humanoid walk speed for jogging
		local model = resident.Model
		local humanoid = model and model:FindFirstChildOfClass("Humanoid")
		local originalWalkSpeed = nil
		if humanoid then
			originalWalkSpeed = humanoid.WalkSpeed
			humanoid.WalkSpeed = originalWalkSpeed * JOG_MOVE_SPEED_MULTIPLIER
		end

		local startTime = os.clock()
		local lastTickTime = startTime
		local totalFunGained = 0
		local waypointIndex = 0

		-- Continuous jogging loop
		while os.clock() - startTime < JOG_DURATION_SECONDS do
			if cancelToken.Cancelled then
				if humanoid and originalWalkSpeed then
					humanoid.WalkSpeed = originalWalkSpeed
				end
				finalize(true, os.clock() - startTime)
				return
			end

			-- Increment Fun periodically during jog (like station usage)
			local currentTime = os.clock()
			if currentTime - lastTickTime >= JOG_TICK_INTERVAL then
				lastTickTime = currentTime
				local currentFun = resident:GetNeed("Fun")
				local newFun = math.clamp(currentFun + JOG_FUN_PER_TICK, funDef.Min, funDef.Max)
				resident:SetNeed("Fun", newFun)
				totalFunGained += JOG_FUN_PER_TICK
			end

			-- Move to new waypoint continuously (using jogging positions, not roam)
			waypointIndex += 1
			local targetPosition = chooseJoggingPosition(player)
			if targetPosition then
				ResidentMovement.GoToWorldPosition(resident, targetPosition, {
					CancelToken = cancelToken,
					TimeoutSeconds = JOG_MOVE_TIMEOUT_SECONDS,
					DebugName = string.format("Jog:%s#%d", getResidentName(resident), waypointIndex),
				})
			else
				-- If can't find position, just wait a bit
				task.wait(1)
			end

			-- Brief pause between waypoints (keeps movement continuous but not instant)
			if not cancelToken.Cancelled then
				task.wait(0.5)
			end
		end

		-- Restore original walk speed
		if humanoid and originalWalkSpeed then
			humanoid.WalkSpeed = originalWalkSpeed
		end

		finalize(false, JOG_DURATION_SECONDS)
	end)

	return true
end

local function hasStationForNeed(player: Player, stationType: string, stationCache: StationCache?): boolean
	local cache = stationCache
	if cache == nil then
		cache = PlotService.GetStationsForPlayer(player)
	end
	if cache == nil then
		return false
	end
	local scope = cache[stationType]
	if scope == nil then
		return false
	end
	return next(scope) ~= nil
end

local function evaluateBeggingInterrupt(
	player: Player,
	resident: ResidentState,
	stationCache: StationCache?
): (string?, string?)
	local needs = State.getNeeds()
	for needName, def in pairs(needs) do
		local value = resident:GetNeed(needName)
		if typeof(value) ~= "number" then
			continue
		end
		if needName == "Hunger" then
			if value <= def.Critical then
				return "NeedUrgent:Hunger", "Hunger"
			end
		elseif needName ~= "Energy" then
			if value <= def.Critical then
				local stationType = State.NeedToStationType[needName]
				if stationType and hasStationForNeed(player, stationType, stationCache) then
					return "NeedUrgent:" .. needName, needName
				end
			end
		end
	end
	return nil, nil
end

local function enqueueEmergencyReliefAction(
	player: Player,
	resident: ResidentState,
	stationCache: StationCache?
): boolean
	local needs = State.getNeeds()
	local bladderDef = needs.Bladder
	if bladderDef == nil then
		return false
	end

	local bladderValue = resident:GetNeed("Bladder")
	if typeof(bladderValue) ~= "number" then
		return false
	end

	local minValue = if typeof(bladderDef.Min) == "number" then bladderDef.Min else 0
	local reachedMin = bladderValue <= minValue -- Force emergency relief when bladder is fully drained

	if not reachedMin and not State.isSurvivalNeedUnavailable(resident, "Bladder") then
		return false
	end

	local criticalValue = if typeof(bladderDef.Critical) == "number" then bladderDef.Critical else minValue
	if not reachedMin and bladderValue > criticalValue then
		return false
	end

	local stationType = State.NeedToStationType.Bladder
	if not reachedMin and stationType and hasStationForNeed(player, stationType, stationCache) then
		return false
	end

	State.setPending(resident, EMERGENCY_RELIEF_ACTION_NAME)
	State.clearNextEvaluation(resident)

	resident:EnqueueAction(EMERGENCY_RELIEF_ACTION_NAME, function(context)
		local cancelToken = context.CancelToken

		local function cleanup()
			State.setPending(resident, nil)
		end

		if cancelToken.Cancelled then
			cleanup()
			return
		end

		ResidentChat.ShowAction(resident, EMERGENCY_RELIEF_CHAT_LINES)

		local deadline = os.clock() + EMERGENCY_RELIEF_DURATION_SECONDS
		while os.clock() < deadline do
			if cancelToken.Cancelled then
				cleanup()
				return
			end
			local remaining = deadline - os.clock()
			if remaining <= 0 then
				break
			end
			task.wait(math.min(0.5, remaining))
		end

		if cancelToken.Cancelled then
			cleanup()
			return
		end

		applyEmergencyReliefEffect(resident, needs, bladderDef)
		cleanup()
	end)

	return true
end

function FallbackActions.enqueueRoamAction(player: Player, residentName: string, resident: ResidentState): boolean
	local now = os.clock()
	local stationCache = PlotService.GetStationsForPlayer(player)
	if Utils.shouldBlockRoam(player, resident, stationCache) then
		return false
	end

	local lastRoam = State.getLastRoam(resident)
	local minInterval = Constants.ROAM_MIN_INTERVAL_SECONDS
	if lastRoam and now - lastRoam < minInterval then
		return false
	end

	local actionName = Constants.ROAM_ACTION_NAME
	State.setPending(resident, actionName)
	State.recordRoam(resident, now)
	resident:EnqueueAction(actionName, function(context)
		local cancelToken = context.CancelToken
		if cancelToken.Cancelled then
			State.setPending(resident, nil)
			return
		end
		local targetPosition = chooseRoamPosition(player)
		if targetPosition then
			ResidentMovement.GoToWorldPosition(resident, targetPosition, {
				CancelToken = cancelToken,
				TimeoutSeconds = 18,
				DebugName = string.format("Roam:%s", residentName),
			})
			if not cancelToken.Cancelled then
				task.wait(roamRandom:NextNumber(1.5, 3.5))
			end
		else
			task.wait(1)
		end
		local finishedAt = os.clock()
		State.recordRoam(resident, finishedAt)
		State.setPending(resident, nil)
	end)
	return true
end

local function enqueueBegAction(player: Player, resident: ResidentState, stationCache: StationCache?): boolean
	local interruptReason = evaluateBeggingInterrupt(player, resident, stationCache)
	if interruptReason ~= nil then
		return false
	end
	State.setPending(resident, BEG_ACTION_NAME)
	State.clearNextEvaluation(resident)
	resident:EnqueueAction(BEG_ACTION_NAME, function(context)
		local cancelToken = context.CancelToken
		local pendingCleared = false
		local function clearPending()
			if pendingCleared then
				return
			end
			pendingCleared = true
			State.setPending(resident, nil)
		end

		local currencyState = PlayerSession.GetDataAwait(player, "CurrencyState")
		if currencyState == nil then
			clearPending()
			return
		end

		local residentDisplayName = getResidentName(resident)
		local chatInterval = if BEG_CHAT_INTERVAL_SECONDS > 0 then BEG_CHAT_INTERVAL_SECONDS else 0
		local chatElapsed = 0
		local stationElapsed = 0
		local roamElapsed = 0
		local lastUpdate = os.clock()
		local cachedStations = stationCache or PlotService.GetStationsForPlayer(player)

		-- Initial roam
		local destinationPosition = computeBeggingDestination(player)
		if destinationPosition then
			local debugLabel = string.format("BegRoam:%s", residentDisplayName)
			ResidentMovement.GoToWorldPosition(resident, destinationPosition, {
				CancelToken = cancelToken,
				TimeoutSeconds = BEG_MOVE_TIMEOUT_SECONDS,
				DebugName = debugLabel,
			})
		end

		if cancelToken and cancelToken.Cancelled then
			clearPending()
			return
		end

		ResidentChat.ShowAction(resident, BEG_CHAT_LINES)

		while true do
			if cancelToken and cancelToken.Cancelled then
				break
			end

			local now = os.clock()
			local delta = now - lastUpdate
			lastUpdate = now

			if delta > 0 then
				-- Chance-based payout system
				local roll = begRandom:NextNumber(0, 1)
				if roll < BEG_PAYOUT_CHANCE then
					local payout = begRandom:NextInteger(BEG_PAYOUT_MIN, BEG_PAYOUT_MAX)
					-- Only add currency if payout is greater than 0
					if payout > 0 then
						CurrencyService.Add(player, BEG_PAYOUT_CURRENCY, payout, currencyState, {
							Source = "Begging",
							ResidentName = residentDisplayName,
						})
					end
				end

				if chatInterval > 0 then
					chatElapsed += delta
					if chatElapsed >= chatInterval then
						chatElapsed -= chatInterval
						ResidentChat.ShowAction(resident, BEG_CHAT_LINES)
					end
				end

				stationElapsed += delta
				if stationElapsed >= BEG_STATION_REFRESH_INTERVAL then
					cachedStations = PlotService.GetStationsForPlayer(player)
					stationElapsed = 0
				end

				-- Roam to new location periodically
				roamElapsed += delta
				if roamElapsed >= BEG_ROAM_INTERVAL_SECONDS then
					roamElapsed = 0
					local newDestination = computeBeggingDestination(player)
					if newDestination and cancelToken and not cancelToken.Cancelled then
						local debugLabel = string.format("BegRoam:%s", residentDisplayName)
						ResidentMovement.GoToWorldPosition(resident, newDestination, {
							CancelToken = cancelToken,
							TimeoutSeconds = BEG_MOVE_TIMEOUT_SECONDS,
							DebugName = debugLabel,
						})
					end
				end
			end

			local reason, needName = evaluateBeggingInterrupt(player, resident, cachedStations)
			if reason then
				ResidentChat.ShowInterrupt(resident, reason, {
					Player = player,
					ActionName = BEG_ACTION_LABEL,
					NeedName = needName,
				})
				break
			end

			task.wait(BEG_TICK_SECONDS)
		end

		clearPending()
	end)
	return true
end

function FallbackActions.evaluateResidentJob(
	player: Player,
	residentName: string,
	resident: ResidentState,
	stationCache: StationCache?
): boolean
	if enqueueEmergencyReliefAction(player, resident, stationCache) then
		return true
	end
	if not resident.AutoJobEnabled then
		return FallbackActions.enqueueRoamAction(player, residentName, resident)
	end

	-- Check if Fun need is low - prioritize jogging over everything else in fallback
	local needs = State.getNeeds()
	local funDef = needs.Fun
	local funValue = resident:GetNeed("Fun")
	local funNeedsAttention = funDef and funValue < (funDef.Low + funDef.Hysteresis)

	-- If Fun is low, try jogging first
	if funNeedsAttention and enqueueJogAction(player, resident, stationCache) then
		return true
	end

	-- Try fun station if jogging didn't trigger
	local uniqueId, stationRecord, itemSpec, stationModel =
		StationManager.findAvailableStation(player, "FunStation", residentName, stationCache)
	if uniqueId and stationRecord and itemSpec and stationModel then
		local decision = {
			StationType = "FunStation",
			UniqueId = uniqueId,
			StationRecord = stationRecord,
			ItemSpec = itemSpec,
			StationModel = stationModel,
			NeedName = "Fun",
		} :: ActionQueue.NeedDecision
		if ActionQueue.enqueueNeedAction(player, residentName, resident, decision) then
			return true
		end
	end

	-- Fall back to begging (no job, Fun is satisfied, or jog on cooldown)
	if enqueueBegAction(player, resident, stationCache) then
		return true
	end

	return FallbackActions.enqueueRoamAction(player, residentName, resident)
end

return FallbackActions :: Module
