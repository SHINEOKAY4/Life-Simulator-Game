--!strict
-- ServerScriptService/Server/Services/UtilityService.luau

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local UtilityService = {}

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

local function setServerLightState(player: Player, placementKey: string, spec: { [string]: any }, powered: boolean)
	local tags = spec.Tags
	if typeof(tags) ~= "table" or not table.find(tags, "Light") then
		return
	end

	local model = WorldPlacer.GetPlacementModel(player, placementKey)
	if not model then
		return
	end

	local light = findLight(model)
	if not light then
		return
	end

	if light.Enabled ~= powered then
		light.Enabled = powered
	end
end

function UtilityService.Recalculate(player: Player)
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
			table.insert(powerSources, {
				key = key,
				x = obj.cellX,
				z = obj.cellZ,
				radius = spec.PowerRadius or 8,
				yLevel = obj.yLevel or 0,
			})
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
	local poweredNodes = {} -- [key] = {x, z, radius}
	local poweredConductors = {} -- [key] = true

	-- Initialize with sources
	local powerQueue = {}
	for _, source in ipairs(powerSources) do
		poweredNodes[source.key] = {
			x = source.x,
			z = source.z,
			radius = source.radius,
			yLevel = source.yLevel,
		}
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
						if targetSpec and (targetSpec.PowerConductor or targetSpec.PowerSource) then
							visitedPower[targetKey] = true
							poweredConductors[targetKey] = true
							poweredNodes[targetKey] = {
								x = targetObj.cellX,
								z = targetObj.cellZ,
								radius = targetSpec.PowerRadius or 0,
								yLevel = targetObj.yLevel or 0,
							}
							table.insert(powerQueue, targetKey)
						end
					end
				end
			end
		end
	end

	local function isPowered(cx: number, cz: number, cy: number?)
		cy = cy or 0
		for _, node in pairs(poweredNodes) do
			local dx = cx - node.x
			local dz = cz - node.z
			local dy = (cy :: number) - (node.yLevel or 0)
			if dx * dx + dz * dz + dy * dy <= node.radius * node.radius then
				return true
			end
		end
		return false
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
	for _, item in ipairs(consumers) do
		local obj = item.obj
		local spec = item.spec
		local needsUpdate = false
		local metadata: { [string]: any } = obj.Metadata or {}
		if typeof(metadata) ~= "table" then
			metadata = {}
		end

		-- Check Power
		if spec.RequiresPower then
			local powered = isPowered(obj.cellX, obj.cellZ, obj.yLevel)
			setServerLightState(player, item.key, spec, powered)
			if metadata.IsPowered ~= powered then
				metadata.IsPowered = powered
				needsUpdate = true
			end
		elseif spec.PowerConductor then
			-- Conductors are powered if they are part of the active network
			local powered = poweredConductors[item.key] == true
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
		end
	end

	-- Send updates
	if #changes > 0 then
		Packets.UtilityUpdate:FireClient(player, changes)
	end
end

return UtilityService
