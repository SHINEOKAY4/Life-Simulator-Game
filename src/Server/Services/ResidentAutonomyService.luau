--!strict
-- ServerScriptService/Server/Services/ResidentAutonomyService.lua

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local DirectActionService = require(ServerScriptService.Server.Services.DirectActionService)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TraitUtils = require(ReplicatedStorage.Shared.Utilities.TraitUtils)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local ResidentActionHandlers = require(ServerScriptService.Server.Modules.ResidentActionHandlers)
local NeedEffects = require(ServerScriptService.Server.Utilities.NeedEffects)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)

type ResidentState = any
type StationInstances = { [string]: StationRecord }
type StationRecord = {
	Id: string,
	Residents: { [number]: string },
	Occupied: boolean,
	Model: Model?,
	ActiveOverride: string?,
}
type NeedDecision = {
	StationType: string,
	UniqueId: string,
	StationRecord: StationRecord,
	ItemSpec: { [string]: any },
	StationModel: Model,
	NeedName: string,
	RestModeOverride: string?,
}

local AUTONOMY_TASK = "ResidentAutonomy"
local AUTONOMY_INTERVAL = 1.0 -- seconds
local ROAM_ACTION_NAME = "Auto:Roam" -- keeps roaming preemptible when higher value actions appear

local NeedToStationType = {
	Hunger = "CookStation",
	Energy = "RestStation",
	Hygiene = "HygieneStation",
	Social = "SocialStation",
	Fun = "FunStation",
}

local roamRandom = Random.new()

local Needs = NeedConfig.Needs
local Circadian = NeedConfig.Circadian

local NeedPrioritySeed = { "Hunger", "Energy", "Hygiene", "Social", "Fun" }
local NeedEvaluationOrder = {} :: { string }

local ResidentCooldowns = setmetatable({} :: { [ResidentState]: { [string]: number } }, { __mode = "k" })
local ResidentPending = setmetatable({} :: { [ResidentState]: string? }, { __mode = "k" })
local ResidentNextEvaluation = setmetatable({} :: { [ResidentState]: number }, { __mode = "k" })

local SecondsPerFullDayCached = TimeScale.GetSecondsPerFullDay()
local NeedCooldownSeconds: { [string]: number } = {}
local HandlerCache: { [string]: any } = {}
local StationIteratorState: { [number]: { [string]: { version: number, order: { string }, index: number } } } = {}
local ItemSpecCache: { [string]: { [string]: any }? } = {}

local ResidentAutonomyService = {}

local function rebuildNeedEvaluationOrder()
	table.clear(NeedEvaluationOrder)
	local seen = {} :: { [string]: boolean }
	for _, needName in ipairs(NeedPrioritySeed) do
		if Needs[needName] and NeedToStationType[needName] then
			NeedEvaluationOrder[#NeedEvaluationOrder + 1] = needName
			seen[needName] = true
		end
	end
	local extras = {} :: { string }
	for needName in pairs(Needs) do
		if NeedToStationType[needName] and not seen[needName] then
			extras[#extras + 1] = needName
		end
	end
	table.sort(extras)
	for _, needName in ipairs(extras) do
		NeedEvaluationOrder[#NeedEvaluationOrder + 1] = needName
	end
end

rebuildNeedEvaluationOrder()

local function getPlayerByUserId(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

local function getOrCreateCooldowns(resident: ResidentState)
	local entry = ResidentCooldowns[resident]
	if not entry then
		entry = {}
		ResidentCooldowns[resident] = entry
	end
	return entry
end

local function setNeedCooldown(resident: ResidentState, needName: string)
	local entry = getOrCreateCooldowns(resident)
	entry[needName] = os.clock()
end

local function convertMinutesToSeconds(minutes: number): number
	if minutes <= 0 then
		return 0
	end
	return minutes * (SecondsPerFullDayCached / (24 * 60))
end

local function refreshNeedCooldowns()
	for key in pairs(NeedCooldownSeconds) do
		NeedCooldownSeconds[key] = nil
	end
	for needName, def in pairs(Needs) do
		NeedCooldownSeconds[needName] = convertMinutesToSeconds(def.CooldownMinutes)
	end
	rebuildNeedEvaluationOrder()
end

local function refreshTimeScaleCaches()
	SecondsPerFullDayCached = TimeScale.GetSecondsPerFullDay()
	refreshNeedCooldowns()
end

local function getNeedCooldownSeconds(needName: string, def: NeedConfig.NeedDef): number
	local cached = NeedCooldownSeconds[needName]
	if cached ~= nil then
		return cached
	end
	local seconds = convertMinutesToSeconds(def.CooldownMinutes)
	NeedCooldownSeconds[needName] = seconds
	return seconds
end

local function getStationHandler(stationType: string)
	local cached = HandlerCache[stationType]
	if cached ~= nil then
		return cached
	end
	local handler = DirectActionService.GetHandler(stationType)
	HandlerCache[stationType] = handler
	return handler
end

local function getStationIterator(
	userId: number,
	stationType: string,
	stationMap: StationInstances?,
	stationVersion: number
): { version: number, order: { string }, index: number }?
	if not stationMap then
		local perUser = StationIteratorState[userId]
		if perUser then
			perUser[stationType] = nil
			if next(perUser) == nil then
				StationIteratorState[userId] = nil
			end
		end
		return nil
	end
	local perUser = StationIteratorState[userId]
	if not perUser then
		perUser = {}
		StationIteratorState[userId] = perUser
	end
	local state = perUser[stationType] :: { version: number, order: { string }, index: number }?
	if not state or state.version ~= stationVersion then
		local order = {} :: { string }
		for uniqueId in pairs(stationMap) do
			if typeof(uniqueId) == "string" then
				order[#order + 1] = uniqueId
			end
		end
		local newState = {
			version = stationVersion,
			order = order,
			index = 1,
		}
		perUser[stationType] = newState
		state = newState
	end
	return state
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

local function computeNextEvaluationDelay(resident: ResidentState): number
	local secondsPerGameHour = SecondsPerFullDayCached / 24
	local soonest: number? = nil
	for needName, def in pairs(Needs) do
		if NeedToStationType[needName] then
			local decayPerHour = def.DecayPerHour
			if decayPerHour > 0 then
				local value = resident:GetNeed(needName)
				if value > def.Low then
					local delta = value - def.Low
					local hoursUntilLow = delta / decayPerHour
					if hoursUntilLow > 0 then
						local secondsUntilLow = hoursUntilLow * secondsPerGameHour
						if not soonest or secondsUntilLow < soonest then
							soonest = secondsUntilLow
						end
					end
				end
			end
		end
	end
	local clamped = math.clamp(soonest or AUTONOMY_INTERVAL, AUTONOMY_INTERVAL, 10)
	return clamped
end

local function isNeedOnCooldown(
	resident: ResidentState,
	needName: string,
	cooldownSeconds: number,
	nowClock: number
): boolean
	if cooldownSeconds <= 0 then
		return false
	end
	local entry = ResidentCooldowns[resident]
	if not entry then
		return false
	end
	local last = entry[needName]
	if not last then
		return false
	end
	return nowClock - last < cooldownSeconds
end

local function hasCriticalNeed(resident: ResidentState, ignoreNeed: string?): boolean
	for needName, def in pairs(Needs) do
		if needName ~= ignoreNeed then
			local value = resident:GetNeed(needName)
			if value <= def.Critical then
				return true
			end
		end
	end
	return false
end

local function isNight(clockTime: number): boolean
	local nightStart = Circadian.NightStart
	local dayStart = Circadian.DayStart
	if nightStart <= dayStart then
		return clockTime >= nightStart and clockTime < dayStart
	end
	return clockTime >= nightStart or clockTime < dayStart
end

local function releaseStationOccupancy(station: StationRecord, residentName: string)
	local index = table.find(station.Residents, residentName)
	if index then
		table.remove(station.Residents, index)
	end
	if #station.Residents == 0 then
		station.Occupied = false
		station.Model = nil
	end
	if station.ActiveOverride == residentName then
		station.ActiveOverride = nil
	end
end

local function resolveStationModelForPlayer(player: Player, uniqueId: string): Model?
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local container = plotModel:FindFirstChild("Container")
	if not container then
		return nil
	end
	local model = container:FindFirstChild(uniqueId)
	if model and model:IsA("Model") then
		return model
	end
	return nil
end

local function findAvailableStation(
	player: Player,
	stationType: string,
	residentName: string
): (string?, StationRecord?, { [string]: any }?, Model?)
	local stationCache = PlotService.GetStationsForPlayer(player)
	local stationMap = stationCache[stationType] :: StationInstances?
	local stationVersion = PlotService.GetStationVersion(player, stationType)
	local iterator = getStationIterator(player.UserId, stationType, stationMap, stationVersion)
	if not iterator then
		return nil, nil, nil, nil
	end
	local order = iterator.order
	local total = #order
	if total == 0 then
		return nil, nil, nil, nil
	end
	for _ = 1, total do
		local uniqueId = order[iterator.index]
		iterator.index += 1
		if iterator.index > total then
			iterator.index = 1
		end
		if uniqueId then
			local station = stationMap and stationMap[uniqueId]
			if station and not table.find(station.Residents, residentName) then
				local itemSpec = ItemSpecCache[station.Id]
				if itemSpec == nil then
					itemSpec = ItemFinder.FindItemById(station.Id)
					ItemSpecCache[station.Id] = itemSpec
				end
				if itemSpec then
					local maxOccupancy = itemSpec.maxOccupancy
					local hasCapacity = true
					if typeof(maxOccupancy) == "number" and maxOccupancy > 0 then
						hasCapacity = #station.Residents < maxOccupancy
					end
					if hasCapacity then
						if not station.Model then
							station.Model = resolveStationModelForPlayer(player, uniqueId)
						end
						local model = station.Model
						if model then
							return uniqueId, station, itemSpec, model
						end
					end
				end
			end
		end
	end
	return nil, nil, nil, nil
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

local function getResidentRootPart(resident: ResidentState): BasePart?
	local model = resident and resident.Model
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	return nil
end

local function getResidentRootPosition(resident: ResidentState): Vector3?
	local root = getResidentRootPart(resident)
	return if root then root.Position else nil
end

local function faceWorldPosition(resident: ResidentState, lookAt: Vector3)
	local root = getResidentRootPart(resident)
	if not root then
		return
	end
	local origin = root.Position
	local target = Vector3.new(lookAt.X, origin.Y, lookAt.Z)
	root.CFrame = CFrame.new(origin, target)
end

local function enqueueDirectSocialPair(
	primaryName: string,
	primaryResident: ResidentState,
	partnerName: string,
	partnerResident: ResidentState
): boolean
	local primaryBehavior = ResidentActionHandlers.GetDirectSocialBehavior()
	local partnerBehavior = ResidentActionHandlers.GetDirectSocialBehavior()
	if not primaryBehavior or not partnerBehavior then
		return false
	end
	local primaryPosition = getResidentRootPosition(primaryResident)
	local partnerPosition = getResidentRootPosition(partnerResident)
	if not primaryPosition or not partnerPosition then
		return false
	end
	local midpoint = (primaryPosition + partnerPosition) * 0.5
	local directionVector = partnerPosition - primaryPosition
	local separation = 2
	local forward = if directionVector.Magnitude >= 1 then directionVector.Unit else Vector3.new(0, 0, 1)
	local targetPrimary = midpoint - forward * separation
	local targetPartner = midpoint + forward * separation
	local averageY = (primaryPosition.Y + partnerPosition.Y) * 0.5
	targetPrimary = Vector3.new(targetPrimary.X, averageY, targetPrimary.Z)
	targetPartner = Vector3.new(targetPartner.X, averageY, targetPartner.Z)
	local session = {
		Ready = {} :: { [string]: boolean },
		Cancelled = false,
	}
	ResidentPending[primaryResident] = "Social"
	ResidentPending[partnerResident] = "Social"
	ResidentNextEvaluation[primaryResident] = nil
	ResidentNextEvaluation[partnerResident] = nil

	local function runDirectSocialAction(
		residentName: string,
		residentState: ResidentState,
		behavior: any,
		targetPosition: Vector3,
		partnerNameInner: string,
		partnerState: ResidentState
	)
		local actionName = string.format("Auto:DirectSocial:%s", partnerNameInner)
		residentState:EnqueueAction(actionName, function(context)
			local cancelToken = context.CancelToken :: any
			if session.Cancelled or cancelToken.Cancelled then
				ResidentPending[residentState] = nil
				return
			end
			local arrived = ResidentMovement.GoToWorldPosition(residentState, targetPosition, {
				CancelToken = cancelToken,
				TimeoutSeconds = 18,
				DebugName = string.format("DirectSocial:%s", residentName),
			})
			if not arrived or cancelToken.Cancelled then
				if not session.Cancelled then
					session.Cancelled = true
					if not cancelToken.Cancelled then
						partnerState:CancelCurrentAction("DirectSocialPartnerFailed")
					end
				end
				ResidentPending[residentState] = nil
				session.Ready[residentName] = nil
				return
			end
			session.Ready[residentName] = true
			while not session.Cancelled and not cancelToken.Cancelled do
				if session.Ready[partnerNameInner] then
					break
				end
				RunService.Heartbeat:Wait()
			end
			if session.Cancelled or cancelToken.Cancelled then
				session.Ready[residentName] = nil
				ResidentPending[residentState] = nil
				return
			end
			local partnerPositionCurrent = getResidentRootPosition(partnerState) or targetPosition
			faceWorldPosition(residentState, partnerPositionCurrent)
			local succeeded = NeedEffects.Run(residentState, cancelToken, behavior, {
				StationType = "SocialStation",
				ActionName = "chat",
				NeedName = "Social",
				PartnerName = partnerNameInner,
			})
			if succeeded then
				setNeedCooldown(residentState, "Social")
			else
				if not session.Cancelled then
					session.Cancelled = true
					if not cancelToken.Cancelled then
						partnerState:CancelCurrentAction("DirectSocialCancelled")
					end
				end
			end
			session.Ready[residentName] = nil
			ResidentPending[residentState] = nil
		end)
	end

	runDirectSocialAction(primaryName, primaryResident, primaryBehavior, targetPrimary, partnerName, partnerResident)
	runDirectSocialAction(partnerName, partnerResident, partnerBehavior, targetPartner, primaryName, primaryResident)
	return true
end

local function preemptRoamForDirectSocial(resident: ResidentState)
	if ResidentPending[resident] ~= ROAM_ACTION_NAME then
		return
	end
	resident:CancelCurrentAction("DirectSocialInvite")
	resident:ClearQueuedActions()
	ResidentPending[resident] = nil
end

local function shouldEvaluate(resident: ResidentState): boolean
	if resident == nil then
		return false
	end
	if not resident.AutoActionsEnabled then
		return false
	end
	if resident.CurrentOverride ~= nil then
		return false
	end
	if resident.IsBusy then
		return false
	end
	local queue = resident.ActionQueue
	if not queue then
		return false
	end
	if not queue:IsEmpty() then
		return false
	end
	if ResidentPending[resident] ~= nil then
		return false
	end
	return true
end

local function computeNeedScore(
	resident: ResidentState,
	needName: string,
	def: NeedConfig.NeedDef,
	value: number,
	clockTime: number,
	nowClock: number
): number
	local night = isNight(clockTime)
	if needName == "Energy" and not night and value > def.Critical then
		return 0
	end
	local deficit = math.max(0, def.Low - value)
	if deficit <= 0 then
		return 0
	end
	local normalized = math.clamp(deficit / math.max(1, def.Low), 0, 1)
	local score = normalized
	if value <= def.Critical then
		score += 1
	end
	if needName == "Energy" and night then
		score *= 1 + Circadian.SleepBias
	end
	local traitBias = TraitUtils.GetNeedScoreBias(resident:GetTraits(), needName)
	local moodBias = resident:GetMoodBias(needName, nowClock)
	local biasTotal = traitBias + moodBias
	if biasTotal ~= 0 then
		local multiplier = 1 + biasTotal
		if multiplier <= 0 then
			return 0
		end
		score *= multiplier
	end
	return score
end

local function attemptGroundRest(
	player: Player,
	residentName: string,
	resident: ResidentState,
	_nowClock: number?,
	_clockTime: number?
): boolean
	local energyDef = Needs.Energy
	if not energyDef then
		return false
	end
	local energyValue = resident:GetNeed("Energy")
	if _clockTime and not isNight(_clockTime) and energyValue > energyDef.Critical then
		return false
	end
	if energyValue >= energyDef.Low then
		return false
	end
	local uniqueId = findAvailableStation(player, "RestStation", residentName)
	if uniqueId then
		return false
	end
	local behavior = ResidentActionHandlers.GetRestBehavior("Ground")
	if not behavior then
		return false
	end
	local actionName = "Auto:GroundRest"
	ResidentPending[resident] = "Energy"
	ResidentNextEvaluation[resident] = nil
	resident:EnqueueAction(actionName, function(context)
		local cancelToken = context.CancelToken
		if cancelToken.Cancelled then
			ResidentPending[resident] = nil
			return
		end
		local initialLine = ResidentChat.SelectChatText(resident, behavior.ChatPhrases, nil)
		if initialLine then
			ResidentChat.ShowAction(resident, initialLine)
		end
		local succeeded = NeedEffects.Run(resident, cancelToken, behavior, {
			StationType = "GroundRest",
			ActionName = "rest",
			NeedName = "Energy",
		})
		ResidentPending[resident] = nil
		if succeeded then
			setNeedCooldown(resident, "Energy")
		end
	end)
	return true
end

local function chooseRestMode(def: NeedConfig.NeedDef, energyValue: number, clockTime: number): string
	if energyValue <= def.Critical then
		return "Sleep"
	end
	if isNight(clockTime) then
		return "Sleep"
	end
	return "DaySleep"
end

local function attemptDirectSocial(player: Player, residentName: string, resident: ResidentState): boolean
	local socialDef = Needs.Social
	if not socialDef then
		return false
	end
	local nowClock = os.clock()
	local value = resident:GetNeed("Social")
	if hasCriticalNeed(resident, "Social") then
		return false
	end
	local deficit = socialDef.Low - value
	if deficit <= 0 then
		return false
	end
	local moodMultiplier = math.max(0, 1 + resident:GetMoodBias("Social", nowClock))
	if deficit * moodMultiplier <= 0 then
		return false
	end
	local residents = ResidentService.GetResidents(player)
	if not residents then
		return false
	end
	local bestName: string? = nil
	local bestState: ResidentState? = nil
	local bestDeficit = 0
	local bestScore = 0
	for candidateName, candidateState in pairs(residents) do
		if candidateName ~= residentName and candidateState ~= nil then
			local candidatePending = ResidentPending[candidateState]
			local candidateAvailable = shouldEvaluate(candidateState)
			if not candidateAvailable and candidatePending == ROAM_ACTION_NAME then
				preemptRoamForDirectSocial(candidateState)
				candidatePending = ResidentPending[candidateState]
				candidateAvailable = true
			end
			if candidateAvailable and candidatePending == nil then
				if not hasCriticalNeed(candidateState, "Social") then
					local candidateValue = candidateState:GetNeed("Social")
					local candidateDeficit = socialDef.Low - candidateValue
					if candidateDeficit > 0 then
						local candidateMoodMultiplier = math.max(0, 1 + candidateState:GetMoodBias("Social", nowClock))
						local candidateScore = candidateDeficit * candidateMoodMultiplier
						if candidateScore > bestScore then
							bestScore = candidateScore
							bestDeficit = candidateDeficit
							bestName = candidateName
							bestState = candidateState
						end
					end
				end
			end
		end
	end
	if bestName and bestState and bestDeficit > 0 then
		return enqueueDirectSocialPair(residentName, resident, bestName, bestState)
	end
	return false
end

local function buildAssignment(player: Player, residentName: string, resident: ResidentState, decision: NeedDecision)
	return {
		Player = player,
		ResidentName = residentName,
		ResidentState = resident,
		StationType = decision.StationType,
		StationId = decision.UniqueId,
		ItemId = decision.StationRecord.Id,
		ItemSpec = decision.ItemSpec,
		StationRecord = decision.StationRecord,
		StationModel = decision.StationModel,
		NeedName = decision.NeedName,
		RestModeOverride = decision.RestModeOverride,
	}
end

local function enqueueNeedAction(player: Player, residentName: string, resident: ResidentState, decision: NeedDecision)
	local handler = getStationHandler(decision.StationType)
	if not handler then
		return false
	end
	local station = decision.StationRecord
	station.Occupied = true
	if not table.find(station.Residents, residentName) then
		table.insert(station.Residents, residentName)
	end
	local assignment = buildAssignment(player, residentName, resident, decision)
	local actionName = string.format("Auto:%s:%s", decision.StationType, decision.NeedName)
	ResidentPending[resident] = decision.NeedName
	ResidentNextEvaluation[resident] = nil
	resident:EnqueueAction(actionName, function(context)
		if context.CancelToken.Cancelled then
			releaseStationOccupancy(station, residentName)
			ResidentPending[resident] = nil
			return
		end
		local ok, result = (xpcall :: any)(handler, debug.traceback, context, assignment)
		releaseStationOccupancy(station, residentName)
		ResidentPending[resident] = nil
		if ok then
			setNeedCooldown(resident, decision.NeedName)
		else
			warn(string.format("[ResidentAutonomy] Handler for %s failed: %s", decision.StationType, tostring(result)))
			error(result)
		end
	end)
	return true
end

-- Idle fallback: send residents to a random unlocked cell on their plot.
local function enqueueRoamAction(player: Player, residentName: string, resident: ResidentState): boolean
	local actionName = ROAM_ACTION_NAME
	ResidentPending[resident] = actionName
	resident:EnqueueAction(actionName, function(context)
		local cancelToken = context.CancelToken
		if cancelToken.Cancelled then
			ResidentPending[resident] = nil
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
			-- No roam target available; yield briefly to avoid tight loops.
			task.wait(1)
		end
		ResidentPending[resident] = nil
	end)
	return true
end

function ResidentAutonomyService.EvaluateResidentNeeds(
	player: Player,
	residentName: string,
	resident: ResidentState,
	nowClock: number,
	clockTime: number
): NeedDecision?
	local bestDecision: NeedDecision? = nil
	local bestScore = 0
	for _, needName in ipairs(NeedEvaluationOrder) do
		local def = Needs[needName]
		if def then
			local stationType = NeedToStationType[needName]
			if stationType and DirectActionService.HasHandler(stationType) then
				local value = resident:GetNeed(needName)
				local score = computeNeedScore(resident, needName, def, value, clockTime, nowClock)
				if score > 0 then
					local cooldownSeconds = getNeedCooldownSeconds(needName, def)
					local onCooldown = isNeedOnCooldown(resident, needName, cooldownSeconds, nowClock)
					if onCooldown and needName == "Energy" then
						local bypass = value <= def.Critical
						if not bypass and value < def.Low and isNight(clockTime) then
							bypass = true
						end
						if bypass then
							onCooldown = false
						end
					end
					if not onCooldown then
						local uniqueId, stationRecord, itemSpec, stationModel =
							findAvailableStation(player, stationType, residentName)
						if uniqueId and stationRecord and itemSpec and stationModel then
							if score > bestScore then
								bestScore = score
								local restModeOverride = if needName == "Energy"
									then chooseRestMode(def, value, clockTime)
									else nil
								local nextDecision: NeedDecision = {
									StationType = stationType,
									UniqueId = uniqueId :: string,
									StationRecord = stationRecord,
									ItemSpec = itemSpec,
									StationModel = stationModel :: Model,
									NeedName = needName,
									RestModeOverride = restModeOverride,
								}
								bestDecision = nextDecision
							end
						end
					end
				end
			end
		end
	end
	return bestDecision
end

function ResidentAutonomyService.EvaluateResidentJob(
	player: Player,
	residentName: string,
	resident: ResidentState
): boolean
	if not resident.AutoJobEnabled then
		return false
	end
	local save = resident.Save
	local occupation = if save then save.Occupation else nil
	local hasJob = typeof(occupation) == "string" and occupation ~= "" and occupation ~= "Unemployed"
	if hasJob then
		return false
	end
	local uniqueId, stationRecord, itemSpec, stationModel = findAvailableStation(player, "FunStation", residentName)
	if uniqueId and stationRecord and itemSpec and stationModel then
		local decision: NeedDecision = {
			StationType = "FunStation",
			UniqueId = uniqueId,
			StationRecord = stationRecord,
			ItemSpec = itemSpec,
			StationModel = stationModel,
			NeedName = "Fun",
		}
		if enqueueNeedAction(player, residentName, resident, decision) then
			return true
		end
	end
	return enqueueRoamAction(player, residentName, resident)
end

function ResidentAutonomyService.TrySatisfyNeedsForResident(
	player: Player,
	residentName: string,
	residentState: ResidentState,
	nowClock: number?,
	clockTime: number?
): boolean
	if not shouldEvaluate(residentState) then
		return false
	end
	local evaluationClock = nowClock or os.clock()
	local scheduled = ResidentNextEvaluation[residentState]
	if scheduled and evaluationClock < scheduled then
		return false
	end
	ResidentNextEvaluation[residentState] = nil
	local evaluationTime = clockTime or TimeScale.GetClockTime()
	local decision = ResidentAutonomyService.EvaluateResidentNeeds(
		player,
		residentName,
		residentState,
		evaluationClock,
		evaluationTime
	)
	if not decision then
		if attemptGroundRest(player, residentName, residentState, evaluationClock, evaluationTime) then
			return true
		end
		local otherCriticalNeeds = hasCriticalNeed(residentState, "Social")
		if not otherCriticalNeeds then
			if attemptDirectSocial(player, residentName, residentState) then
				return true
			end
		end
		local jobQueued = ResidentAutonomyService.EvaluateResidentJob(player, residentName, residentState)
		if not jobQueued then
			local delay = computeNextEvaluationDelay(residentState)
			ResidentNextEvaluation[residentState] = evaluationClock + delay
		end
		return jobQueued
	end
	if enqueueNeedAction(player, residentName, residentState, decision) then
		ResidentNextEvaluation[residentState] = nil
		return true
	end
	local delay = computeNextEvaluationDelay(residentState)
	ResidentNextEvaluation[residentState] = evaluationClock + delay
	return false
end

local function handleStationRemoved(player: Player, _stationType: string, _uniqueId: string, residentNames: { string })
	if typeof(residentNames) ~= "table" then
		return
	end
	for _, residentName in ipairs(residentNames) do
		if typeof(residentName) == "string" and residentName ~= "" then
			local residentState = ResidentService.GetResident(player, residentName)
			if residentState then
				residentState:CancelCurrentAction("StationRemoved")
				residentState:ClearQueuedActions()
				ResidentMovement.LeaveSeat(residentState, nil)
				ResidentPending[residentState] = nil
				ResidentNextEvaluation[residentState] = nil
				task.defer(function()
					ResidentAutonomyService.TrySatisfyNeedsForResident(
						player,
						residentName,
						residentState,
						os.clock(),
						TimeScale.GetClockTime()
					)
				end)
			end
		end
	end
end

function ResidentAutonomyService.Decide()
	local nowClock = os.clock()
	local clockTime = TimeScale.GetClockTime()
	local allResidents = ResidentService.GetResidents()
	for userId, residents in pairs(allResidents) do
		local player = getPlayerByUserId(userId)
		if player then
			for residentName, residentState in pairs(residents) do
				ResidentAutonomyService.TrySatisfyNeedsForResident(
					player,
					residentName,
					residentState,
					nowClock,
					clockTime
				)
			end
		end
	end
end

local function startTask()
	if not WorldUpdate.IsSubscribed(AUTONOMY_TASK) then
		WorldUpdate.Subscribe(AUTONOMY_TASK, AUTONOMY_INTERVAL, function()
			ResidentAutonomyService.Decide()
		end)
	end
end

function ResidentAutonomyService.Init()
	refreshTimeScaleCaches()
	Lighting:GetAttributeChangedSignal("SecondsPerFullDay"):Connect(refreshTimeScaleCaches)
	PlotService.PlotClaimed:Connect(function(player)
		StationIteratorState[player.UserId] = nil
	end)
	PlotService.PlotUnclaimed:Connect(function(player)
		StationIteratorState[player.UserId] = nil
	end)
	PlotService.StationRemoved:Connect(handleStationRemoved)
	ResidentService.PlayerResidentsChanged:Connect(function()
		-- Cooldowns use weak keys; no explicit cleanup needed beyond clearing pending flags.
	end)
	startTask()
end

return ResidentAutonomyService
