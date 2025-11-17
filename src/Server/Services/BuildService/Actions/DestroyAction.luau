--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)

type Facing = any

local function removeSurfaceMountsForParent(player: Player, state: any, parentKey: string)
	if typeof(parentKey) ~= "string" or parentKey == "" then
		return
	end

	local mountSnapshot = state:GetSurfaceMountsForParent(parentKey)
	for mountKey in pairs(mountSnapshot) do
		local removed = state:RemoveSurfaceMount(mountKey)
		if removed then
			WorldPlacer.DespawnSurfaceMount(player, mountKey)
			Helpers.sendSurfaceMountDelta(player, "Removed", mountKey, removed)
		end
	end
end

local function DestroyAction(
	player: Player,
	payload: { ItemId: string, CellX: number, CellZ: number, Facing: string, Level: number? }
): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local resolvedId, spec, savedFacingHint, savedFromIdentifier = Helpers.resolvePlacedItem(state, payload.ItemId)
	if not spec or not resolvedId then
		return false, "Invalid item ID"
	end
	local placementType = spec.PlacementType or spec.Type or "CellObject"
	local placementKeyType = Helpers.getPlacementKeyLabel(spec)
	local allowStacking = Helpers.allowsStacking(spec)
	local levelHint = if typeof(payload.Level) == "number" then payload.Level else nil

	local payloadFacing = Helpers.coerceFacing(payload.Facing)
	local keyFacing: Facing
	if payloadFacing then
		keyFacing = payloadFacing :: Facing
	elseif savedFacingHint then
		keyFacing = savedFacingHint :: Facing
	else
		keyFacing = "North"
	end
	local key = state:PlacementKeyForType(payload.CellX, payload.CellZ, keyFacing, placementKeyType, levelHint)
	local saved = state.Save.PlacedObjects[key]
	if not saved or saved.id ~= resolvedId then
		if
			savedFromIdentifier
			and savedFromIdentifier.cellX == payload.CellX
			and savedFromIdentifier.cellZ == payload.CellZ
		then
			local fallbackSaved = savedFromIdentifier
			local fallbackLevel = if typeof(fallbackSaved.yLevel) == "number" then fallbackSaved.yLevel else levelHint
			saved = fallbackSaved
			keyFacing = PlacementKey.NormalizeFacing(fallbackSaved.facing) :: Facing
			key = state:PlacementKeyForType(
				fallbackSaved.cellX,
				fallbackSaved.cellZ,
				keyFacing,
				placementKeyType,
				fallbackLevel
			)
		end
		if not saved or saved.id ~= resolvedId then
			for savedKey, entry in pairs(state.Save.PlacedObjects) do
				if entry.id == resolvedId then
					local ok, cellX, cellZ, _, parsedType, parsedLevel = pcall(PlacementKey.ParseWithType, savedKey)
					if ok and parsedType == placementKeyType and cellX == payload.CellX and cellZ == payload.CellZ then
						saved = entry
						keyFacing = PlacementKey.NormalizeFacing(entry.facing) :: Facing
						key = state:PlacementKeyForType(cellX, cellZ, keyFacing, placementKeyType, parsedLevel)
						break
					end
				end
			end
		end
	end
	if not saved or saved.id ~= resolvedId then
		return false, "Item not found at location"
	end

	local anchorX = saved.cellX or payload.CellX
	local anchorZ = saved.cellZ or payload.CellZ
	local savedLevel = if typeof(saved.yLevel) == "number" then saved.yLevel else levelHint
	local level = state:NormalizeLevel(savedLevel)
	key = state:PlacementKeyForType(anchorX, anchorZ, keyFacing, placementKeyType, level)

	local savedMetadata = saved.Metadata
	local w = savedMetadata and (savedMetadata.WidthCells or savedMetadata.widthCells)
		or spec.WidthCells
		or spec.Width
		or 1
	local d = savedMetadata and (savedMetadata.DepthCells or savedMetadata.depthCells)
		or spec.DepthCells
		or spec.Depth
		or 1
	local facing: Facing = PlacementKey.NormalizeFacing(saved.facing) :: Facing

	local removedId = resolvedId
	local restoredId: string? = nil

	if placementType == "Floor" then
		state:RemoveFloor(anchorX, anchorZ, w, d, facing, level)
		removeSurfaceMountsForParent(player, state, key)
	elseif placementType == "Wall" then
		local result = state:RemoveWall(anchorX, anchorZ, facing, level)
		if not result then
			return false, "Item not found at location"
		end
		removedId = result.removedId
		restoredId = result.restoredId
		removeSurfaceMountsForParent(player, state, key)
	elseif placementType == "Roof" then
		state:RemoveRoof(anchorX, anchorZ, w, d, facing, level)
		removeSurfaceMountsForParent(player, state, key)
	elseif placementType == "WallMounted" then
		local removed = state:RemoveWallMounted(anchorX, anchorZ, facing, level)
		if not removed or removed.id ~= resolvedId then
			return false, "Item not found at location"
		end
		savedMetadata = removed.Metadata
		removedId = removed.id
		if spec.StationType then
			PlotService.RemoveStationForPlayer(player, spec.StationType, key)
		end
	elseif placementType == "Ceiling" then
		local removed = state:RemoveCeilingMounted(anchorX, anchorZ, facing, level)
		if not removed or removed.id ~= resolvedId then
			return false, "Item not found at location"
		end
		savedMetadata = removed.Metadata
		removedId = removed.id
	else
		state:RemoveCellObject(anchorX, anchorZ, w, d, facing, level, {
			PlacementType = placementKeyType,
			IgnoreOccupancy = allowStacking,
		})
		if spec.StationType then
			PlotService.RemoveStationForPlayer(player, spec.StationType, key)
		end
		removeSurfaceMountsForParent(player, state, key)
	end

	WorldPlacer.Despawn(player, removedId, anchorX, anchorZ, facing, level)
	Helpers.sendPlacementDelta(player, "Removed", removedId, anchorX, anchorZ, facing, savedMetadata, level, key)

	if restoredId then
		local restoredSaved = state.Save.PlacedObjects[key]
		local restoredMetadata = restoredSaved and restoredSaved.Metadata
		WorldPlacer.Spawn(player, state.Grid, restoredId, anchorX, anchorZ, facing, level)
		local restoreKey = state:PlacementKeyForType(anchorX, anchorZ, facing, placementKeyType, level)
		Helpers.sendPlacementDelta(
			player,
			"Placed",
			restoredId,
			anchorX,
			anchorZ,
			facing,
			restoredMetadata,
			level,
			restoreKey
		)
	end

	return true, "Removed"
end

return DestroyAction
