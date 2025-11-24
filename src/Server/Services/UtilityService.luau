--!strict
-- ServerScriptService/Server/Services/UtilityService.luau

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local PlacedObjectUtils = require(ReplicatedStorage.Shared.Utilities.PlacedObjectUtils)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local UtilityService = {}
local LightCache = {} -- [number (UserId)] -> { [string (PlacementKey)] -> Light }

-- Batching system to reduce network traffic
local PendingUpdates: { [number]: { [string]: any } } = {} -- [userId][key] = metadata
local DirtyPlayers: { [number]: boolean } = {} -- [userId] = true
local BATCH_INTERVAL = 0.2 -- Send batched updates every 0.2 seconds

local LIGHT_TYPES = { "PointLight", "SpotLight", "SurfaceLight" }

local function findLightInContainer(container: Instance): Light?
	for _, lightType in LIGHT_TYPES do
		local light = container:FindFirstChildWhichIsA(lightType :: any, true)
		if light and (light:IsA("PointLight") or light:IsA("SpotLight") or light:IsA("SurfaceLight")) then
			return light :: Light
		end
	end
	return nil
end

local function findLight(instance: Instance): Light?
	if instance:IsA("Model") then
		for _, descendant in instance:GetDescendants() do
			if descendant:IsA("Attachment") and descendant.Name == "Attachment" then
				local light = findLightInContainer(descendant)
				if light then
					return light
				end
			end
		end
		return findLightInContainer(instance)
	elseif instance:IsA("BasePart") then
		return findLightInContainer(instance)
	end
	return nil
end

local function resolveLight(player: Player, placementKey: string): Light?
	local userId = player.UserId
	local playerCache = LightCache[userId]
	if not playerCache then
		playerCache = {}
		LightCache[userId] = playerCache
	end

	local cached = playerCache[placementKey]
	if cached then
		if cached.Parent then
			return cached
		else
			playerCache[placementKey] = nil
		end
	end

	local model = WorldPlacer.GetPlacementModel(player, placementKey)
	if not model then
		return nil
	end

	local light = findLight(model)
	if light then
		playerCache[placementKey] = light
	end
	return light
end

local function flushBatchedUpdates()
	-- Send all pending updates in batches
	for userId, updates in pairs(PendingUpdates) do
		if not DirtyPlayers[userId] then
			continue
		end

		local player = game.Players:GetPlayerByUserId(userId)
		if not player then
			PendingUpdates[userId] = nil
			DirtyPlayers[userId] = nil
			continue
		end

		local plotState = PlotService.GetState(player)
		if not plotState then
			continue
		end

		-- Build changes array
		local changes = {}
		local levelsToUpdate = {}
		for key, metadata in pairs(updates) do
			table.insert(changes, {
				Key = key,
				Metadata = metadata,
			})

			-- Track levels for room stat updates
			local obj = plotState.Save.PlacedObjects[key]
			if obj and plotState.NormalizeLevel then
				levelsToUpdate[plotState:NormalizeLevel(obj.yLevel)] = true
			end
		end

		-- Send batched update
		if #changes > 0 then
			Packets.UtilityUpdate:FireClient(player, changes)

			-- Update Room Stats
			for level, _ in pairs(levelsToUpdate) do
				if (plotState :: any).UpdateRoomStats then
					(plotState :: any):UpdateRoomStats(level)
				end
			end
		end

		-- Clear batch
		PendingUpdates[userId] = {}
		DirtyPlayers[userId] = nil
	end
end

function UtilityService.Init()
	-- Start batched update loop
	WorldUpdate.Subscribe("UtilityService::BatchedUpdates", BATCH_INTERVAL, flushBatchedUpdates)
	Packets.TogglePowerRequest.OnServerInvoke = function(player, payload)
		local key = payload.Key
		local isOn = payload.IsOn

		local plotState = PlotService.GetState(player)
		if not plotState then
			return false, "No plot"
		end

		local obj = plotState.Save.PlacedObjects[key]
		if not obj then
			return false, "Object not found"
		end

		local metadata: { [string]: any } = obj.Metadata or {}
		if typeof(metadata) ~= "table" then
			metadata = {}
		end
		metadata.IsOn = isOn
		obj.Metadata = metadata

		-- Trigger recalculate to update visuals/logic
		UtilityService.Recalculate(player, { [key] = true })

		return true, "Success"
	end
end

function UtilityService.ClearCache(player: Player)
	LightCache[player.UserId] = nil
end

function UtilityService.Recalculate(player: Player, forceUpdateKeys: { [string]: boolean }?)
	print("[UtilityService] Recalculate called for:", player.Name)
	local plotState = PlotService.GetState(player)
	if not plotState then
		print("[UtilityService] No plot state found for:", player.Name)
		return
	end

	local powerSources = {}
	local waterSources = {}
	local consumers = {}

	-- 1. Scan all objects using PlacedObjectUtils
	print("[UtilityService] Recalculating for player", player.Name)

	local isOutage = player:GetAttribute("BillingPowerOutageActive") == true

	-- Type cast for compatibility with PlacedObjectUtils
	local placedObjects = plotState.Save.PlacedObjects :: any
	PlacedObjectUtils.IterateObjects(placedObjects, nil, function(key, obj, spec)
		-- Assert coords exist (they always do in SavedPlacedObject)
		local cellX = obj.cellX :: number
		local cellZ = obj.cellZ :: number

		-- Collect power sources (excluding grid power during outages)
		if spec.PowerSource then
			local isGridPower = spec.Tags and table.find(spec.Tags, "GridPower")
			if isGridPower and isOutage then
				print("[UtilityService] Grid Power disabled due to outage:", spec.Name, key)
			else
				table.insert(powerSources, {
					key = key,
					x = cellX,
					z = cellZ,
					radius = spec.PowerRadius or 8,
					yLevel = obj.yLevel or 0,
				})
			end
		end

		-- Collect water sources
		if spec.WaterSource then
			table.insert(waterSources, {
				key = key,
				x = cellX,
				z = cellZ,
				radius = spec.WaterRadius or 5,
				yLevel = obj.yLevel or 0,
			})
		end

		-- Collect consumers and conductors for updates
		if spec.RequiresPower or spec.RequiresWater or spec.PowerConductor or spec.WaterConductor then
			table.insert(consumers, { key = key, obj = obj, spec = spec })
		end
	end)

	-- 2. Calculate Utility Networks using unified graph traversal
	local function buildUtilityNetwork(
		sources: { any },
		checkConductor: (spec: any) -> boolean,
		checkConsumer: (spec: any) -> boolean
	): ({ [string]: boolean }, { [string]: boolean })
		local connectedNodes = {}
		local visitedNodes = {}
		local queue = {}

		-- Initialize with sources
		for _, source in sources do
			table.insert(queue, source.key)
			visitedNodes[source.key] = true
		end

		-- Propagate through connections via BFS
		local head = 1
		while head <= #queue do
			local currentKey = queue[head]
			head += 1

			local obj = plotState.Save.PlacedObjects[currentKey]
			if not obj then
				continue
			end

			local metadata = obj.Metadata or {}
			local connections = (metadata :: { [string]: any }).Connections
			if typeof(connections) == "table" then
				for _, targetKey in connections do
					if not visitedNodes[targetKey] then
						local targetObj = plotState.Save.PlacedObjects[targetKey]
						if targetObj then
							local targetSpec = ItemFinder.FindItemById(targetObj.id)
							if targetSpec then
								local isConductor = checkConductor(targetSpec)
								local isConsumer = checkConsumer(targetSpec)

								if isConductor or isConsumer then
									visitedNodes[targetKey] = true
									connectedNodes[targetKey] = true

									-- Only conductors extend the network
									if isConductor then
										table.insert(queue, targetKey)
									end
								end
							end
						end
					end
				end
			end
		end

		return connectedNodes, visitedNodes
	end

	-- Power network
	local poweredConductors = buildUtilityNetwork(powerSources, function(spec)
		return spec.PowerConductor or spec.PowerSource
	end, function(spec)
		return spec.RequiresPower
	end)

	-- Water network with radius tracking
	local wateredConductors = {}
	local wateredNodes = {}

	for _, source in waterSources do
		wateredNodes[source.key] = {
			x = source.x,
			z = source.z,
			radius = source.radius,
			yLevel = source.yLevel,
		}
	end

	local waterConnected = buildUtilityNetwork(
		waterSources,
		function(spec)
			return spec.WaterConductor or spec.WaterSource
		end,
		function(_spec)
			return false
		end -- Water consumers checked via radius
	)

	-- Populate water node data for conductors
	for key in waterConnected do
		if not wateredNodes[key] then
			local obj = plotState.Save.PlacedObjects[key]
			if obj then
				local spec = ItemFinder.FindItemById(obj.id)
				if spec then
					wateredNodes[key] = {
						x = obj.cellX,
						z = obj.cellZ,
						radius = spec.WaterRadius or 0,
						yLevel = obj.yLevel or 0,
					}
				end
			end
		end
		wateredConductors[key] = true
	end

	local function isWatered(cellX: number, cellZ: number, yLevel: number?): boolean
		local cy = yLevel or 0
		for _, node in wateredNodes do
			local dx = cellX - node.x
			local dz = cellZ - node.z
			local dy = cy - (node.yLevel or 0)
			if dx * dx + dz * dz + dy * dy <= node.radius * node.radius then
				return true
			end
		end
		return false
	end

	local function updateMetadataField(metadata: { [string]: any }, key: string, newValue: boolean): boolean
		if metadata[key] ~= newValue then
			metadata[key] = newValue
			return true
		end
		return false
	end

	local function updateLightState(targetPlayer: Player, spec: any, key: string, isPowered: boolean, isOn: boolean)
		local tags = spec.Tags
		if typeof(tags) == "table" and table.find(tags, "Light") then
			print(`[UtilityService] Checking light item: {spec.Name}, Key: {key}, Powered: {isPowered}`)
			local light = resolveLight(targetPlayer, key)
			if light then
				local shouldBeEnabled = isPowered and isOn
				print(`[UtilityService] Found light instance, setting Enabled to {shouldBeEnabled}`)
				if light.Enabled ~= shouldBeEnabled then
					light.Enabled = shouldBeEnabled
				end
			else
				warn(`[UtilityService] Could not resolve Light instance for {spec.Name} at key: {key}`)
			end
		end
	end

	-- 3. Update Consumers AND Conductors
	for _, item in consumers do
		local obj = item.obj
		local spec = item.spec
		local needsUpdate = forceUpdateKeys and forceUpdateKeys[item.key]
		local metadata: { [string]: any } = obj.Metadata or {}
		if typeof(metadata) ~= "table" then
			metadata = {}
		end

		-- Check Power
		if spec.RequiresPower or spec.PowerConductor then
			local isPowered = poweredConductors[item.key] == true
			local isOn = if metadata.IsOn ~= nil then metadata.IsOn else true

			if spec.RequiresPower then
				updateLightState(player, spec, item.key, isPowered, isOn)
			end

			if updateMetadataField(metadata, "IsPowered", isPowered) then
				needsUpdate = true
			end
		end

		-- Check Water
		if spec.RequiresWater then
			local watered = isWatered(obj.cellX :: number, obj.cellZ :: number, obj.yLevel)
			if updateMetadataField(metadata, "IsWatered", watered) then
				needsUpdate = true
			end
		elseif spec.WaterConductor then
			local watered = wateredConductors[item.key] == true
			if updateMetadataField(metadata, "IsWatered", watered) then
				needsUpdate = true
			end
		end

		if needsUpdate then
			obj.Metadata = metadata

			-- Accumulate in batch instead of sending immediately
			local userId = player.UserId
			if not PendingUpdates[userId] then
				PendingUpdates[userId] = {}
			end
			PendingUpdates[userId][item.key] = metadata
			DirtyPlayers[userId] = true
		end
	end

	-- Batch will be sent on next WorldUpdate cycle (0.2s)
end

return UtilityService
