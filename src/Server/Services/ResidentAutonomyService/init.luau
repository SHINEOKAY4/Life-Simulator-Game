--!strict
-- ServerScriptService/Server/Services/ResidentAutonomyService.lua

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local TraitUtils = require(ReplicatedStorage.Shared.Utilities.TraitUtils)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)

local Constants = require(script.Constants)
local State = require(script.State)
local Utils = require(script.Utils)
local ActionQueue = require(script.ActionQueue)
local StationManager = require(script.StationManager)
local TipsService = require(ServerScriptService.Server.Services.TipsService)
local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)

local TenantService -- Lazy loaded to avoid circular dependency

export type ResidentState = any

local ResidentAutonomyService = {}

local PlayerCache: { [number]: Player } = {}

local function onPlayerAdded(player: Player)
	PlayerCache[player.UserId] = player
end

local function onPlayerRemoving(player: Player)
	PlayerCache[player.UserId] = nil
end

for _, player in ipairs(Players:GetPlayers()) do
	onPlayerAdded(player)
end
Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

local function isNight(clockTime: number): boolean
	return clockTime >= 22 or clockTime < 6
end

local function wander(player: Player, residentName: string, resident: ResidentState): boolean
	local plotState = PlotService.GetState(player)
	if not plotState then
		return false
	end

	local unlockedChunks = plotState.Save.UnlockedChunks
	if not unlockedChunks or #unlockedChunks == 0 then
		return false
	end

	local randomChunk = unlockedChunks[math.random(1, #unlockedChunks)]
	local chunkSize = plotState.ChunkSizeInCells or 5
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return false
	end

	local gridObject = PlotService.GetGrid(plotIndex)
	if not gridObject then
		return false
	end

	local minX = (randomChunk.cx - 1) * chunkSize + 1
	local maxX = randomChunk.cx * chunkSize
	local minZ = (randomChunk.cz - 1) * chunkSize + 1
	local maxZ = randomChunk.cz * chunkSize

	local cellX = math.random(minX, maxX)
	local cellZ = math.random(minZ, maxZ)
	local worldPos = gridObject:CellToWorldCenter(cellX, cellZ)

	return ActionQueue.enqueueFallbackAction(player, residentName, resident, "Wander", {
		TargetPosition = worldPos,
	})
end

local function applyDecay(player: Player, resident: ResidentState, gameHours: number)
	if gameHours <= 0 then
		return
	end
	local globalPaused = false
	if resident and typeof(resident.IsNeedDecayPaused) == "function" then
		globalPaused = resident:IsNeedDecayPaused()
	end
	if globalPaused then
		return
	end

	-- Resolve tenant traits for decay multipliers (Cached)
	local now = os.clock()
	local tenantMultipliers = resident._CachedTenantMultipliers
	if not tenantMultipliers or (now - (resident._LastTenantMultiplierUpdate or 0) > 10) then
		tenantMultipliers = {}
		if resident.Save and resident.Save.TenantId then
			if not TenantService then
				TenantService = require(ServerScriptService.Server.Services.TenantService)
			end
			local leases = TenantService.GetActiveLeases(player)
			if leases and leases[resident.Save.TenantId] then
				local lease = leases[resident.Save.TenantId]
				if lease.Traits then
					for _, traitId in ipairs(lease.Traits) do
						local trait = TenantTraits.GetTrait(traitId)
						if trait and trait.Effects and trait.Effects.NeedDecayMultipliers then
							for need, mult in pairs(trait.Effects.NeedDecayMultipliers) do
								tenantMultipliers[need] = (tenantMultipliers[need] or 1) * mult
							end
						end
					end
				end
			end
		end
		resident._CachedTenantMultipliers = tenantMultipliers
		resident._LastTenantMultiplierUpdate = now
	end

	local hasNeedPauseCheck = resident and typeof(resident.IsNeedPaused) == "function"
	for needName, definition in pairs(NeedConfig.Needs) do
		if hasNeedPauseCheck and resident:IsNeedPaused(needName) then
			continue
		end
		local value = resident:GetNeed(needName)
		local traits = if resident.GetTraits then resident:GetTraits() else nil
		local decayMultiplier = TraitUtils.GetNeedDecayMultiplier(traits, needName)

		if tenantMultipliers[needName] then
			decayMultiplier *= tenantMultipliers[needName]
		end

		local decayRate = definition.DecayPerHour * decayMultiplier
		local newValue = math.clamp(value - decayRate * gameHours, definition.Min, definition.Max)
		if newValue ~= value then
			resident:SetNeed(needName, newValue)
		end
	end
end

local function tryUseStation(
	player: Player,
	residentName: string,
	resident: ResidentState,
	stationType: string,
	stationCache: { [string]: any }
): boolean
	local uniqueId, stationRecord, itemSpec, stationModel =
		StationManager.findAvailableStation(player, stationType, residentName, stationCache, nil)

	if uniqueId and stationRecord and itemSpec and stationModel then
		local decision = {
			StationType = stationType,
			UniqueId = uniqueId,
			StationRecord = stationRecord,
			ItemSpec = itemSpec,
			StationModel = stationModel,
			NeedName = "Satisfaction", -- Generic need name for simple system
			ActionMode = nil,
			TargetContainerId = nil,
			PreparedMealId = nil,
			PreparedMealServings = nil,
			PreparedMealHungerPerPortion = nil,
		}
		return ActionQueue.enqueueNeedAction(player, residentName, resident, decision)
	end
	return false
end

function ResidentAutonomyService.DecideForResident(
	player: Player,
	residentName: string,
	resident: ResidentState,
	nowClock: number,
	clockTime: number,
	stationCache: { [string]: any }
)
	if not Utils.shouldEvaluate(resident) then
		return
	end

	local scheduled = State.getNextEvaluation(resident)
	if scheduled and nowClock < scheduled then
		return
	end
	State.clearNextEvaluation(resident)

	-- Simple Logic Loop
	local energy = resident:GetNeed("Energy")
	local night = isNight(clockTime)

	-- 1. Sleep Logic
	if energy < 10 or (night and energy < 60) then
		if tryUseStation(player, residentName, resident, "RestStation", stationCache) then
			return
		end
		-- If tired but no bed, complain? Or just wander.
	end

	-- 2. Amenity Logic (Daytime or not tired)
	-- Pick a random amenity type to use
	local amenityTypes = { "FunStation", "SocialStation", "HygieneStation", "CookStation", "ComfortStation" }
	-- Shuffle
	for i = #amenityTypes, 2, -1 do
		local j = math.random(i)
		amenityTypes[i], amenityTypes[j] = amenityTypes[j], amenityTypes[i]
	end

	for _, stationType in ipairs(amenityTypes) do
		-- 50% chance to skip checking this type to add randomness
		if math.random() < 0.5 then
			continue
		end
		if tryUseStation(player, residentName, resident, stationType, stationCache) then
			return
		end
	end

	-- 3. Wander Logic
	if wander(player, residentName, resident) then
		-- Set a delay before next evaluation so they don't spam wander
		local delay = math.random(5, 10)
		State.setNextEvaluation(resident, nowClock + delay)
		return
	end

	-- If nothing happened, wait a bit
	State.setNextEvaluation(resident, nowClock + 2)
end

local function updatePassiveFun(residents: { [string]: ResidentState }, stationCache: { [string]: any })
	-- Keep this for now, maybe rename to "PassiveSatisfaction" later
	local funStations = stationCache["FunStation"]
	local funScore = 0
	if funStations then
		local count = 0
		for _ in pairs(funStations) do
			count += 1
		end
		funScore = count * 25
	end
	funScore = math.clamp(funScore, 0, 100)

	for _, resident in pairs(residents) do
		resident:SetNeed("Fun", funScore)
	end
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
				ResidentMovement.ClearRestPose(residentState)
				State.setPending(residentState, nil)
				State.clearNextEvaluation(residentState)
			end
		end
	end
end

function ResidentAutonomyService.Decide(dt: number)
	local nowClock = os.clock()
	local clockTime = TimeScale.GetClockTime()
	local allResidents = ResidentService.GetResidents()
	local gameHours = TimeScale.GameHoursFromRealDelta(dt)

	for userId, residents in pairs(allResidents) do
		local player = PlayerCache[userId]
		if player then
			local stationCache = PlotService.GetStationsForPlayer(player)
			updatePassiveFun(residents, stationCache)

			for residentName, residentState in pairs(residents) do
				-- Update Needs Decay
				applyDecay(player, residentState, gameHours)

				-- Satisfaction Logic
				local satisfaction = residentState:GetSatisfaction()

				-- Tip Logic (Simplified)
				local isSatisfied = satisfaction >= 0.5
				local wasSatisfied = residentState.WasSatisfied

				if wasSatisfied == nil then
					residentState.WasSatisfied = isSatisfied
				elseif not wasSatisfied and isSatisfied then
					residentState.WasSatisfied = true
					local root = residentState.Model and residentState.Model.PrimaryPart
					if root then
						TipsService.SpawnTip(player, residentName, 50, root.Position, "Satisfaction")
					end
				elseif wasSatisfied and not isSatisfied then
					residentState.WasSatisfied = false
				end

				-- Dissatisfaction Accumulation
				residentState:UpdateDissatisfaction(dt, satisfaction, 0.35)

				if residentState:GetDissatisfactionTime() > 1200 then
					local tenantId = residentState.Save.TenantId
					if tenantId then
						if not TenantService then
							TenantService = require(ServerScriptService.Server.Services.TenantService)
						end
						task.defer(function()
							TenantService.EvictTenant(player, tenantId)
						end)
					end
				end

				ResidentAutonomyService.DecideForResident(
					player,
					residentName,
					residentState,
					nowClock,
					clockTime,
					stationCache
				)
			end
		end
	end
end

local function startTask()
	if not WorldUpdate.IsSubscribed(Constants.AUTONOMY_TASK) then
		WorldUpdate.Subscribe(Constants.AUTONOMY_TASK, Constants.AUTONOMY_INTERVAL, function(dt)
			ResidentAutonomyService.Decide(dt)
		end)
	end
end

function ResidentAutonomyService.Init()
	State.refreshTimeScaleCaches()
	Lighting:GetAttributeChangedSignal("SecondsPerFullDay"):Connect(State.refreshTimeScaleCaches)
	PlotService.PlotClaimed:Connect(function(player)
		State.StationIteratorState[player.UserId] = nil
	end)
	PlotService.PlotUnclaimed:Connect(function(player)
		State.StationIteratorState[player.UserId] = nil
	end)
	PlotService.StationRemoved:Connect(handleStationRemoved)
	startTask()
end

return ResidentAutonomyService
