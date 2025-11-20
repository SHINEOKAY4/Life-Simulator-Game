--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local UtilityService = require(ServerScriptService.Server.Services.UtilityService)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local function ConnectUtility(player: Player, payload: { SourceKey: string, TargetKey: string }): (boolean, string)
	local sourceKey = payload.SourceKey
	local targetKey = payload.TargetKey

	if not sourceKey or not targetKey then
		return false, "Invalid keys"
	end

	if sourceKey == targetKey then
		return false, "Cannot connect to self"
	end

	local plotState = PlotService.GetState(player)
	if not plotState then
		return false, "No plot found"
	end

	local sourceObj = plotState.Save.PlacedObjects[sourceKey]
	local targetObj = plotState.Save.PlacedObjects[targetKey]

	if not sourceObj or not targetObj then
		return false, "Object not found"
	end

	local sourceSpec = ItemFinder.FindItemById(sourceObj.id)
	local targetSpec = ItemFinder.FindItemById(targetObj.id)

	if not sourceSpec or not targetSpec then
		return false, "Invalid item spec"
	end

	-- Validate compatibility
	local canConnect = false
	local connectionRadius = 0

	local isPower = (sourceSpec.PowerSource or sourceSpec.PowerConductor)
		and (targetSpec.PowerConductor or targetSpec.PowerSource)
	local isWater = (sourceSpec.WaterSource or sourceSpec.WaterConductor)
		and (targetSpec.WaterConductor or targetSpec.WaterSource)

	if isPower or isWater then
		-- Check distance
		-- Use the radius of the Conductor (Target usually, or Source if it's a relay)
		local r1 = sourceSpec.ConnectionRadius or 0
		local r2 = targetSpec.ConnectionRadius or 0
		connectionRadius = math.max(r1, r2)
		canConnect = true
	end

	if not canConnect then
		return false, "Incompatible connection types"
	end

	local dx = (sourceObj.cellX - targetObj.cellX) * 4
	local dz = (sourceObj.cellZ - targetObj.cellZ) * 4
	local centerDist = math.sqrt(dx * dx + dz * dz)

	-- Calculate object extents to measure from edge-to-edge roughly
	local function getObjectExtent(obj: any, spec: any)
		local w = (obj.WidthCells or spec.WidthCells or 1) * 4
		local d = (obj.DepthCells or spec.DepthCells or 1) * 4
		-- Use half the diagonal as a generous "radius" of the object itself
		return math.sqrt(w * w + d * d) / 2
	end

	local extent1 = getObjectExtent(sourceObj, sourceSpec)
	local extent2 = getObjectExtent(targetObj, targetSpec)

	-- The distance between the "surfaces" is roughly centerDist - extents
	local surfaceDist = math.max(0, centerDist - extent1 - extent2)

	-- Add a generous tolerance because client uses exact attachment positions which might be closer
	if surfaceDist > connectionRadius + 4 then
		return false, "Target out of range"
	end

	-- Update Metadata
	local sourceMetadata = sourceObj.Metadata or {}
	local typedSourceMetadata = sourceMetadata :: { [string]: any }
	local sourceConnections = typedSourceMetadata.Connections or {}

	local targetMetadata = targetObj.Metadata or {}
	local typedTargetMetadata = targetMetadata :: { [string]: any }
	local targetConnections = typedTargetMetadata.Connections or {}

	-- Check if already connected (check both sides to be safe)
	for _, key in ipairs(sourceConnections) do
		if key == targetKey then
			return false, "Already connected"
		end
	end
	for _, key in ipairs(targetConnections) do
		if key == sourceKey then
			return false, "Already connected"
		end
	end

	table.insert(sourceConnections, targetKey)
	typedSourceMetadata.Connections = sourceConnections
	sourceObj.Metadata = sourceMetadata

	table.insert(targetConnections, sourceKey)
	typedTargetMetadata.Connections = targetConnections
	targetObj.Metadata = targetMetadata

	-- Notify client of update
	Packets.UtilityUpdate:FireClient(player, {
		{ Key = sourceKey, Metadata = sourceMetadata },
		{ Key = targetKey, Metadata = targetMetadata },
	})

	print("[ConnectUtility] Connection successful. Calling Recalculate...")
	-- Recalculate power
	UtilityService.Recalculate(player)
	print("[ConnectUtility] Recalculate returned.")

	return true, "Connected"
end

return ConnectUtility
