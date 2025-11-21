--!strict
-- ServerScriptService/Server/Services/UtilityService.luau

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local UtilityService = {}
local LightCache = {} -- [number (UserId)] -> { [string (PlacementKey)] -> Light }

local function findLight(instance: Instance): Light?
	if instance:IsA("Model") then
		for _, desc in ipairs(instance:GetDescendants()) do
			if desc:IsA("Attachment") and desc.Name == "Attachment" then
				local found = desc:FindFirstChildWhichIsA("PointLight")
					or desc:FindFirstChildWhichIsA("SpotLight")
					or desc:FindFirstChildWhichIsA("SurfaceLight")
				if found then
					return found
				end
			end
		end

		local fallback = instance:FindFirstChildWhichIsA("PointLight", true)
			or instance:FindFirstChildWhichIsA("SpotLight", true)
			or instance:FindFirstChildWhichIsA("SurfaceLight", true)
		return fallback
	elseif instance:IsA("BasePart") then
		return instance:FindFirstChildWhichIsA("PointLight", true)
			or instance:FindFirstChildWhichIsA("SpotLight", true)
			or instance:FindFirstChildWhichIsA("SurfaceLight", true)
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

function UtilityService.Init()
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
	-- local powerRelays = {} -- Outlets/Conductors (Unused in explicit connection mode)
	local waterSources = {}
	local consumers = {}

	-- 1. Scan all objects
	print("[UtilityService] Recalculating for player", player.Name)
	for key, obj in pairs(plotState.Save.PlacedObjects) do
		local spec = ItemFinder.FindItemById(obj.id)
		if not spec then
			continue
		end

		if spec.PowerSource then
			local isGridPower = spec.Tags and table.find(spec.Tags, "GridPower")
			local isOutage = player:GetAttribute("BillingPowerOutageActive") == true

			if isGridPower and isOutage then
				print("[UtilityService] Grid Power disabled due to outage:", spec.Name, key)
			else
				table.insert(powerSources, {
					key = key,
					x = obj.cellX,
					z = obj.cellZ,
					radius = spec.PowerRadius or 8,
					yLevel = obj.yLevel or 0,
				})
			end
		end

		if spec.WaterSource then
			table.insert(waterSources, {
				key = key,
				x = obj.cellX,
				z = obj.cellZ,
				radius = spec.WaterRadius or 5,
				yLevel = obj.yLevel or 0,
			})
		end

		-- We track consumers AND conductors for updates
		if spec.RequiresPower or spec.RequiresWater or spec.PowerConductor or spec.WaterConductor then
			table.insert(consumers, { key = key, obj = obj, spec = spec })
		end
	end

	-- 2. Calculate Power Network (Graph Traversal)
	local poweredConductors = {} -- [key] = true

	-- Initialize with sources
	local powerQueue = {}
	for _, source in ipairs(powerSources) do
		table.insert(powerQueue, source.key)
	end

	-- Propagate power through connections
	local visitedPower = {}
	for _, key in ipairs(powerQueue) do
		visitedPower[key] = true
	end

	local powerHead = 1
	while powerHead <= #powerQueue do
		local currentKey = powerQueue[powerHead]
		powerHead += 1

		local obj = plotState.Save.PlacedObjects[currentKey]
		if not obj then
			continue
		end

		local metadata = obj.Metadata or {}
		local connections = (metadata :: { [string]: any }).Connections
		if typeof(connections) == "table" then
			for _, targetKey in ipairs(connections) do
				if not visitedPower[targetKey] then
					local targetObj = plotState.Save.PlacedObjects[targetKey]
					if targetObj then
						local targetSpec = ItemFinder.FindItemById(targetObj.id)
						if targetSpec then
							if targetSpec.PowerConductor or targetSpec.PowerSource then
								visitedPower[targetKey] = true
								poweredConductors[targetKey] = true
								table.insert(powerQueue, targetKey)
							elseif targetSpec.RequiresPower then
								-- Consumers are powered if connected, but don't extend the network
								visitedPower[targetKey] = true
								poweredConductors[targetKey] = true
							end
						end
					end
				end
			end
		end
	end

	-- 3. Calculate Water Network (Graph Traversal - Same as Power)
	local wateredNodes = {} -- [key] = {x, z, radius}
	local wateredConductors = {} -- [key] = true

	local waterQueue = {}
	for _, source in ipairs(waterSources) do
		wateredNodes[source.key] = {
			x = source.x,
			z = source.z,
			radius = source.radius,
			yLevel = source.yLevel,
		}
		table.insert(waterQueue, source.key)
	end

	local visitedWater = {}
	for _, key in ipairs(waterQueue) do
		visitedWater[key] = true
	end

	local waterHead = 1
	while waterHead <= #waterQueue do
		local currentKey = waterQueue[waterHead]
		waterHead += 1

		local obj = plotState.Save.PlacedObjects[currentKey]
		if not obj then
			continue
		end

		local metadata = obj.Metadata or {}
		local connections = (metadata :: { [string]: any }).Connections
		if typeof(connections) == "table" then
			for _, targetKey in ipairs(connections) do
				if not visitedWater[targetKey] then
					local targetObj = plotState.Save.PlacedObjects[targetKey]
					if targetObj then
						local targetSpec = ItemFinder.FindItemById(targetObj.id)
						if targetSpec and (targetSpec.WaterConductor or targetSpec.WaterSource) then
							visitedWater[targetKey] = true
							wateredConductors[targetKey] = true
							wateredNodes[targetKey] = {
								x = targetObj.cellX,
								z = targetObj.cellZ,
								radius = targetSpec.WaterRadius or 0,
								yLevel = targetObj.yLevel or 0,
							}
							table.insert(waterQueue, targetKey)
						end
					end
				end
			end
		end
	end

	local function isWatered(cx: number, cz: number, cy: number?)
		cy = cy or 0
		for _, node in pairs(wateredNodes) do
			local dx = cx - node.x
			local dz = cz - node.z
			local dy = (cy :: number) - (node.yLevel or 0)
			if dx * dx + dz * dz + dy * dy <= node.radius * node.radius then
				return true
			end
		end
		return false
	end

	-- 4. Update Consumers AND Conductors
	local changes = {}
	local levelsToUpdate = {} -- [level] = true

	for _, item in ipairs(consumers) do
		local obj = item.obj
		local spec = item.spec
		local needsUpdate = false
		local metadata: { [string]: any } = obj.Metadata or {}
		if typeof(metadata) ~= "table" then
			metadata = {}
		end

		if forceUpdateKeys and forceUpdateKeys[item.key] then
			needsUpdate = true
		end

		-- Check Power
		if spec.RequiresPower or spec.PowerConductor then
			-- Items are powered if connected to the power network
			local powered = poweredConductors[item.key] == true

			-- Check manual switch state
			local isOn = true
			if metadata.IsOn ~= nil then
				isOn = metadata.IsOn
			end

			-- Update light state for lighting items
			if spec.RequiresPower then
				local tags = spec.Tags
				if typeof(tags) == "table" and table.find(tags, "Light") then
					print(`[UtilityService] Checking light item: {spec.Name}, Key: {item.key}, Powered: {powered}`)
					local light = resolveLight(player, item.key)
					if light then
						local shouldBeEnabled = powered and isOn
						print(`[UtilityService] Found light instance, setting Enabled to {shouldBeEnabled}`)
						if light.Enabled ~= shouldBeEnabled then
							light.Enabled = shouldBeEnabled
						end
					else
						warn(`[UtilityService] Could not resolve Light instance for {spec.Name} at key: {item.key}`)
					end
				end
			end

			if metadata.IsPowered ~= powered then
				metadata.IsPowered = powered
				needsUpdate = true
			end
		end

		-- Check Water
		if spec.RequiresWater then
			local watered = isWatered(obj.cellX, obj.cellZ, obj.yLevel)
			if metadata.IsWatered ~= watered then
				metadata.IsWatered = watered
				needsUpdate = true
			end
		elseif spec.WaterConductor then
			-- Conductors are watered if they are part of the active network
			local watered = wateredConductors[item.key] == true
			if metadata.IsWatered ~= watered then
				metadata.IsWatered = watered
				needsUpdate = true
			end
		end

		if needsUpdate then
			obj.Metadata = metadata
			table.insert(changes, {
				Key = item.key,
				Metadata = metadata,
			})
			if plotState.NormalizeLevel then
				levelsToUpdate[plotState:NormalizeLevel(obj.yLevel)] = true
			end
		end
	end

	-- Send updates
	if #changes > 0 then
		Packets.UtilityUpdate:FireClient(player, changes)

		-- Update Room Stats
		for level, _ in pairs(levelsToUpdate) do
			if (plotState :: any).UpdateRoomStats then
				(plotState :: any):UpdateRoomStats(level)
			end
		end
	end
end

return UtilityService
