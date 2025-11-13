--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)

type Facing = any

type Payload = {
	ItemId: string,
	FromCellX: number,
	FromCellZ: number,
	FromFacing: string,
	FromLevel: number?,
	ToCellX: number,
	ToCellZ: number,
	ToFacing: string,
	ToLevel: number?,
}

local function moveDoorSegment(
	player: Player,
	state: any,
	resolvedId: string,
	spec: any,
	fromX: number,
	fromZ: number,
	fromF: Facing,
	toX: number,
	toZ: number,
	toF: Facing,
	fromLevel: number,
	toLevel: number
): (boolean, string?)
	local requiresFloorOnBothSides = spec.RequiresFloorOnBothSides == true
	local replaceableTag = spec.ReplaceableWallTag

	local replacedId, replaceErr =
		state:ReplaceWallSegment(resolvedId, toX, toZ, toF, requiresFloorOnBothSides, replaceableTag, toLevel)
	if not replacedId then
		return false, replaceErr or "Failed to attach door at destination"
	end

	local destKey = state:PlacementKeyForType(toX, toZ, toF, "Wall", toLevel)
	local savedDoor = state.Save.PlacedObjects[destKey]

	local removeResult = state:RemoveWall(fromX, fromZ, fromF, fromLevel)
	if not removeResult then
		local revertDest = state:RemoveWall(toX, toZ, toF, toLevel)
		if revertDest and revertDest.restoredId then
			local revertDoorId, revertErr = state:ReplaceWallSegment(
				resolvedId,
				fromX,
				fromZ,
				fromF,
				requiresFloorOnBothSides,
				replaceableTag,
				fromLevel
			)
			if not revertDoorId then
				warn(("[BuildService] Failed to restore door after move failure: %s"):format(tostring(revertErr)))
			end
		end
		return false, "Door not found at original location"
	end

	local removedId = removeResult.removedId
	local restoredId = removeResult.restoredId

	WorldPlacer.Despawn(player, removedId, fromX, fromZ, fromF, fromLevel)
	Helpers.sendPlacementDelta(player, "Removed", removedId, fromX, fromZ, fromF, nil, fromLevel)

	if restoredId then
		WorldPlacer.Spawn(player, state.Grid, restoredId, fromX, fromZ, fromF, fromLevel)
		Helpers.sendPlacementDelta(player, "Placed", restoredId, fromX, fromZ, fromF, nil, fromLevel)
	end

	WorldPlacer.Despawn(player, replacedId, toX, toZ, toF, toLevel)
	Helpers.sendPlacementDelta(player, "Removed", replacedId, toX, toZ, toF, nil, toLevel)

	WorldPlacer.Spawn(player, state.Grid, resolvedId, toX, toZ, toF, toLevel, {
		previousWallId = replacedId,
		metadata = savedDoor and savedDoor.Metadata,
	})
	Helpers.sendPlacementDelta(player, "Placed", resolvedId, toX, toZ, toF, savedDoor and savedDoor.Metadata, toLevel)

	return true, nil
end

local function Move(player: Player, payload: Payload): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local resolvedId, spec = Helpers.resolvePlacedItem(state, payload.ItemId)
	if not spec or not resolvedId then
		return false, "Invalid item ID"
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	local fromFacingValue = Helpers.coerceFacing(payload.FromFacing)
	local fromF: Facing = (fromFacingValue or "North") :: Facing
	local toFacingValue = Helpers.coerceFacing(payload.ToFacing)
	local toF: Facing = (toFacingValue or fromF) :: Facing

	local fromLevel = state:NormalizeLevel(payload.FromLevel)
	local toLevel = state:NormalizeLevel(payload.ToLevel)

	local allowedFacing = spec.Facing :: { Facing }?
	if placementType ~= "Floor" and allowedFacing and #allowedFacing > 0 then
		if not table.find(allowedFacing, toF) then
			return false, "Invalid facing for this item"
		end
	end

	local width = spec.WidthCells or spec.Width or 1
	local depth = spec.DepthCells or spec.Depth or 1

	local moveSucceeded: boolean
	local moveError: string?
	local removedFacing: Facing = fromF
	local placedFacing: Facing = toF
	local fromKey = state:PlacementKeyForType(payload.FromCellX, payload.FromCellZ, fromF, placementType, fromLevel)
	local toKey = state:PlacementKeyForType(payload.ToCellX, payload.ToCellZ, toF, placementType, toLevel)
	local sourceSaved = state.Save.PlacedObjects[fromKey]
	local sourceMetadata = sourceSaved and sourceSaved.Metadata

	if placementType == "CellObject" then
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.ToCellX, payload.ToCellZ, width, depth, toF, toLevel) then
				return false, "Floor required under all cells"
			end
		end

		moveSucceeded, moveError = state:MoveCellObject(
			resolvedId,
			payload.FromCellX,
			payload.FromCellZ,
			fromF,
			payload.ToCellX,
			payload.ToCellZ,
			toF,
			fromLevel,
			toLevel
		)
	elseif placementType == "Floor" then
		removedFacing = "North"
		placedFacing = "North"
		moveSucceeded, moveError = state:MoveFloor(
			resolvedId,
			payload.FromCellX,
			payload.FromCellZ,
			payload.ToCellX,
			payload.ToCellZ,
			fromLevel,
			toLevel
		)
	elseif placementType == "Wall" then
		if spec.RequiresExistingWall then
			if payload.FromCellX == payload.ToCellX and payload.FromCellZ == payload.ToCellZ and fromF == toF then
				return true, "Moved"
			end
			local doorSucceeded, doorError = moveDoorSegment(
				player,
				state,
				resolvedId,
				spec,
				payload.FromCellX,
				payload.FromCellZ,
				fromF,
				payload.ToCellX,
				payload.ToCellZ,
				toF,
				fromLevel,
				toLevel
			)
			if not doorSucceeded then
				return false, doorError or "Door move failed"
			end
			return true, "Moved"
		end
		moveSucceeded, moveError = state:MoveWall(
			resolvedId,
			payload.FromCellX,
			payload.FromCellZ,
			fromF,
			payload.ToCellX,
			payload.ToCellZ,
			toF,
			fromLevel,
			toLevel
		)
	elseif placementType == "Roof" then
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.ToCellX, payload.ToCellZ, width, depth, toF, toLevel) then
				return false, "Floor required under roof"
			end
		end

		moveSucceeded, moveError = state:MoveRoof(
			resolvedId,
			payload.FromCellX,
			payload.FromCellZ,
			fromF,
			payload.ToCellX,
			payload.ToCellZ,
			toF,
			fromLevel,
			toLevel
		)
	else
		return false, ("Cannot move items of type '%s'"):format(tostring(placementType))
	end

	if not moveSucceeded then
		return false, moveError or "Move failed"
	end

	if spec.StationType and fromKey ~= toKey then
		PlotService.RemoveStationForPlayer(player, spec.StationType, fromKey)
		PlotService.AddStationForPlayer(player, spec.StationType, toKey, resolvedId)
	end

	WorldPlacer.Despawn(player, resolvedId, payload.FromCellX, payload.FromCellZ, removedFacing, fromLevel)
	local destSaved = state.Save.PlacedObjects[toKey]
	local destMetadata = destSaved and destSaved.Metadata
	WorldPlacer.Spawn(player, state.Grid, resolvedId, payload.ToCellX, payload.ToCellZ, placedFacing, toLevel, {
		metadata = destMetadata,
		sizeCells = destMetadata,
	})

	Helpers.sendPlacementDelta(
		player,
		"Removed",
		resolvedId,
		payload.FromCellX,
		payload.FromCellZ,
		removedFacing,
		sourceMetadata,
		fromLevel
	)
	Helpers.sendPlacementDelta(
		player,
		"Placed",
		resolvedId,
		payload.ToCellX,
		payload.ToCellZ,
		placedFacing,
		destMetadata,
		toLevel
	)

	return true, "Moved"
end

return Move
