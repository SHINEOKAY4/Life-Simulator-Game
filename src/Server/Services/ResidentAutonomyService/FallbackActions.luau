--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
}

local FallbackActions = {}
local roamRandom = RandomProvider.get()
local begRandom = RandomProvider.get()

local BEG_ACTION_NAME = Constants.BEG_ACTION_NAME
local BEG_ACTION_LABEL = Constants.BEG_ACTION_LABEL
local BEG_TICK_SECONDS = Constants.BEG_TICK_SECONDS
local BEG_CHAT_INTERVAL_SECONDS = Constants.BEG_CHAT_INTERVAL_SECONDS
local BEG_STATION_REFRESH_INTERVAL = Constants.BEG_STATION_REFRESH_INTERVAL
local BEG_PAYOUT_CURRENCY = Constants.BEG_PAYOUT_CURRENCY
local BEG_PAYOUT_PER_SECOND = Constants.BEG_PAYOUT_PER_SECOND
local BEG_CHAT_LINES = Constants.BEG_CHAT_LINES
local BEG_SPOT_FORWARD_OFFSET = math.max(Constants.BEG_SPOT_FORWARD_OFFSET or 0, 0)
local BEG_SPOT_LATERAL_JITTER = math.max(Constants.BEG_SPOT_LATERAL_JITTER or 0, 0)
local BEG_SPOT_HEIGHT_OFFSET = Constants.BEG_SPOT_HEIGHT_OFFSET or 0
local BEG_SPOT_FORWARD_VARIANCE = math.max(Constants.BEG_SPOT_FORWARD_VARIANCE or 0, 0)
local BEG_SPOT_MAX_ANGLE_RADIANS = math.rad(math.clamp(Constants.BEG_SPOT_MAX_ANGLE_DEGREES or 0, 0, 85))
local BEG_MOVE_TIMEOUT_SECONDS = math.max(Constants.BEG_MOVE_TIMEOUT_SECONDS or 0, 1)

local function getResidentName(resident: ResidentState): string
	local save = resident and resident.Save
	local name = if typeof(save) == "table" and typeof(save.Name) == "string" then save.Name else nil
	return name or "Resident"
end

-- Picks a beg spot just outside the plot entrance so residents relocate before starting the action.
local function computeBeggingDestination(player: Player): (Vector3?, Vector3?)
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil, nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil, nil
	end
	local spawnPart = plotModel:FindFirstChild("Spawn")
	if not spawnPart or not spawnPart:IsA("BasePart") then
		return nil, nil
	end
	local spawnCFrame = spawnPart.CFrame
	local outward = -spawnCFrame.LookVector
	if outward.Magnitude <= 0.001 then
		outward = spawnCFrame.LookVector
	end
	if outward.Magnitude <= 0.001 then
		return nil, nil
	end
	outward = outward.Unit
	if BEG_SPOT_MAX_ANGLE_RADIANS > 0 then
		local yaw = begRandom:NextNumber(-BEG_SPOT_MAX_ANGLE_RADIANS, BEG_SPOT_MAX_ANGLE_RADIANS)
		if yaw ~= 0 then
			local rotation = CFrame.fromAxisAngle(Vector3.new(0, 1, 0), yaw)
			local rotated = rotation:VectorToWorldSpace(outward)
			if rotated.Magnitude > 0.001 then
				outward = rotated.Unit
			end
		end
	end
	local lateral = spawnCFrame.RightVector
	if lateral.Magnitude <= 0.001 then
		lateral = Vector3.new(1, 0, 0)
	else
		lateral = lateral.Unit
	end
	local forwardOffset = math.max(BEG_SPOT_FORWARD_OFFSET, 4)
	if BEG_SPOT_FORWARD_VARIANCE > 0 then
		forwardOffset += begRandom:NextNumber(-BEG_SPOT_FORWARD_VARIANCE, BEG_SPOT_FORWARD_VARIANCE)
		if forwardOffset < 4 then
			forwardOffset = 4
		end
	end
	local lateralOffset = if BEG_SPOT_LATERAL_JITTER > 0
		then begRandom:NextNumber(-BEG_SPOT_LATERAL_JITTER, BEG_SPOT_LATERAL_JITTER)
		else 0
	local targetPosition = spawnCFrame.Position + outward * forwardOffset + lateral * lateralOffset
	targetPosition += Vector3.new(0, BEG_SPOT_HEIGHT_OFFSET, 0)
	if BEG_SPOT_HEIGHT_OFFSET == 0 then
		targetPosition = Vector3.new(targetPosition.X, spawnCFrame.Position.Y, targetPosition.Z)
	end
	return targetPosition, spawnCFrame.Position
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

		local destinationPosition, lookTarget = computeBeggingDestination(player)
		if not destinationPosition then
			clearPending()
			return
		end

		local debugLabel = string.format("BegSpot:%s", getResidentName(resident))
		local arrived = ResidentMovement.GoToWorldPosition(resident, destinationPosition, {
			CancelToken = cancelToken,
			TimeoutSeconds = BEG_MOVE_TIMEOUT_SECONDS,
			DebugName = debugLabel,
		})
		if cancelToken and cancelToken.Cancelled then
			clearPending()
			return
		end
		if not arrived then
			clearPending()
			return
		end

		if lookTarget then
			local lookPosition = lookTarget
			if (lookPosition - destinationPosition).Magnitude < 1 then
				lookPosition = destinationPosition + Vector3.new(0, 0, -1)
			end
			ResidentMovement.FaceStation(resident, CFrame.new(destinationPosition, lookPosition))
		end

		if cancelToken and cancelToken.Cancelled then
			clearPending()
			return
		end

		ResidentChat.ShowAction(resident, BEG_CHAT_LINES)

		local residentDisplayName = getResidentName(resident)
		local chatInterval = if BEG_CHAT_INTERVAL_SECONDS > 0 then BEG_CHAT_INTERVAL_SECONDS else 0
		local chatElapsed = 0
		local stationElapsed = 0
		local payoutAccumulator = 0
		local lastUpdate = os.clock()
		local cachedStations = stationCache or PlotService.GetStationsForPlayer(player)

		while true do
			if cancelToken and cancelToken.Cancelled then
				break
			end

			local now = os.clock()
			local delta = now - lastUpdate
			lastUpdate = now
			if delta > 0 then
				payoutAccumulator += delta * BEG_PAYOUT_PER_SECOND
				if payoutAccumulator >= 1 then
					local payout = math.floor(payoutAccumulator)
					if payout > 0 then
						CurrencyService.Add(player, BEG_PAYOUT_CURRENCY, payout, currencyState, {
							Source = "Begging",
							ResidentName = residentDisplayName,
						})
						payoutAccumulator -= payout
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
	if not resident.AutoJobEnabled then
		return FallbackActions.enqueueRoamAction(player, residentName, resident)
	end
	local save = resident.Save
	local currentCareerId = if save then save.CurrentCareerId else nil
	if typeof(currentCareerId) ~= "string" or currentCareerId == "" then
		local fallbackOccupation = if save then save.Occupation else nil
		if typeof(fallbackOccupation) == "string" and fallbackOccupation ~= "Unemployed" then
			currentCareerId = fallbackOccupation
		end
	end
	local hasJob = typeof(currentCareerId) == "string" and currentCareerId ~= ""
	if hasJob then
		return false
	end
	if enqueueBegAction(player, resident, stationCache) then
		return true
	end
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
	return FallbackActions.enqueueRoamAction(player, residentName, resident)
end

return FallbackActions :: Module
