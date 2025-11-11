--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)

type Facing = any

local function DestroyAction(
	player: Player,
	payload: { ItemId: string, CellX: number, CellZ: number, Facing: string }
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

	local payloadFacing = Helpers.coerceFacing(payload.Facing)
	local keyFacing: Facing
	if payloadFacing then
		keyFacing = payloadFacing :: Facing
	elseif savedFacingHint then
		keyFacing = savedFacingHint :: Facing
	else
		keyFacing = "North"
	end
	local key = state:PlacementKeyForType(payload.CellX, payload.CellZ, keyFacing, placementType)
	local saved = state.Save.PlacedObjects[key]
	if not saved or saved.id ~= resolvedId then
		if
			savedFromIdentifier
			and savedFromIdentifier.cellX == payload.CellX
			and savedFromIdentifier.cellZ == payload.CellZ
		then
			local fallbackSaved = savedFromIdentifier
			saved = fallbackSaved
			keyFacing = PlacementKey.NormalizeFacing(fallbackSaved.facing) :: Facing
			key = state:PlacementKeyForType(fallbackSaved.cellX, fallbackSaved.cellZ, keyFacing, placementType)
		end
	end
	if not saved or saved.id ~= resolvedId then
		return false, "Item not found at location"
	end

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
		state:RemoveFloor(payload.CellX, payload.CellZ)
	elseif placementType == "Wall" then
		local result = state:RemoveWall(payload.CellX, payload.CellZ, facing)
		if not result then
			return false, "Item not found at location"
		end
		removedId = result.removedId
		restoredId = result.restoredId
	elseif placementType == "Roof" then
		state:RemoveRoof(payload.CellX, payload.CellZ, w, d, facing)
	elseif placementType == "WallMounted" then
		local removed = state:RemoveWallMounted(payload.CellX, payload.CellZ, facing)
		if not removed or removed.id ~= resolvedId then
			return false, "Item not found at location"
		end
		savedMetadata = removed.Metadata
		removedId = removed.id
		if spec.StationType then
			PlotService.RemoveStationForPlayer(player, spec.StationType, key)
		end
	else
		state:RemoveCellObject(payload.CellX, payload.CellZ, w, d, facing)
		if spec.StationType then
			PlotService.RemoveStationForPlayer(player, spec.StationType, key)
		end
	end

	WorldPlacer.Despawn(player, removedId, payload.CellX, payload.CellZ, facing)
	Helpers.sendPlacementDelta(player, "Removed", removedId, payload.CellX, payload.CellZ, facing, savedMetadata)

	if restoredId then
		local restoredSaved = state.Save.PlacedObjects[key]
		local restoredMetadata = restoredSaved and restoredSaved.Metadata
		WorldPlacer.Spawn(player, state.Grid, restoredId, payload.CellX, payload.CellZ, facing)
		Helpers.sendPlacementDelta(player, "Placed", restoredId, payload.CellX, payload.CellZ, facing, restoredMetadata)
	end

	return true, "Removed"
end

return DestroyAction
