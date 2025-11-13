--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

type Facing = any

type Payload = { ItemId: string, FromKey: string, ToFacing: string }

local function Rotate(player: Player, payload: Payload): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	if type(payload.FromKey) ~= "string" or payload.FromKey == "" then
		return false, "Invalid placement key"
	end

	local toFacingValue = Helpers.coerceFacing(payload.ToFacing)
	if not toFacingValue then
		return false, "Invalid facing"
	end
	local targetFacing = toFacingValue :: Facing

	local resolvedId, spec = Helpers.resolvePlacedItem(state, payload.ItemId)
	if not spec or not resolvedId then
		return false, "Invalid item ID"
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	if placementType == "Wall" and spec.RequiresExistingWall then
		return false, "Doors cannot be rotated"
	end
	if placementType == "Floor" then
		return false, "Floors cannot be rotated"
	end

	local saved = state.Save.PlacedObjects[payload.FromKey]
	if not saved or saved.id ~= resolvedId then
		return false, "Item not found at key"
	end

	local parseOk, parsedCellX, parsedCellZ, parsedFacing, keyPlacementType, parsedLevel =
		pcall(PlacementKey.ParseWithType, payload.FromKey)
	if not parseOk then
		local parseErr = parsedCellX
		return false, ("Invalid placement key: %s"):format(tostring(parseErr))
	end

	local cellX = parsedCellX :: number
	local cellZ = parsedCellZ :: number
	local currentFacingValue = Helpers.coerceFacing(parsedFacing :: string?) or "North"
	local currentFacing = currentFacingValue :: Facing
	local level = if typeof(parsedLevel) == "number" then parsedLevel else state.DefaultLevel

	if keyPlacementType and keyPlacementType ~= placementType then
		return false, "Placement type mismatch"
	end

	if currentFacing == targetFacing then
		return true, "Already facing that direction"
	end

	local allowedFacing = spec.Facing :: { Facing }?
	if allowedFacing and #allowedFacing > 0 and not table.find(allowedFacing, targetFacing) then
		return false, "Invalid facing for this item"
	end

	local rotated: boolean
	local rotateErr: string?
	if placementType == "CellObject" then
		local width = spec.WidthCells or spec.Width or 1
		local depth = spec.DepthCells or spec.Depth or 1
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(cellX, cellZ, width, depth, targetFacing, level) then
				return false, "Floor required under all cells"
			end
		end
		rotated, rotateErr = state:RotateCellObject(resolvedId, payload.FromKey, targetFacing)
	elseif placementType == "Wall" then
		rotated, rotateErr = state:RotateWall(resolvedId, payload.FromKey, targetFacing)
	elseif placementType == "Roof" then
		local width = spec.WidthCells or spec.Width or 1
		local depth = spec.DepthCells or spec.Depth or 1
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(cellX, cellZ, width, depth, targetFacing, level) then
				return false, "Floor required under roof"
			end
		end
		rotated, rotateErr = state:RotateRoof(resolvedId, payload.FromKey, targetFacing)
	else
		return false, ("Cannot rotate items of type '%s'"):format(tostring(placementType))
	end

	if not rotated then
		return false, rotateErr or "Rotation failed"
	end

	if spec.StationType then
		local fromKeyNormalized = state:PlacementKeyForType(cellX, cellZ, currentFacing, placementType, level)
		local toKey = state:PlacementKeyForType(cellX, cellZ, targetFacing, placementType, level)
		if fromKeyNormalized ~= toKey then
			PlotService.RemoveStationForPlayer(player, spec.StationType, fromKeyNormalized)
			PlotService.AddStationForPlayer(player, spec.StationType, toKey, resolvedId)
		end
	end

	local metadata = saved.Metadata
	WorldPlacer.Despawn(player, resolvedId, cellX, cellZ, currentFacing, level)
	WorldPlacer.Spawn(player, state.Grid, resolvedId, cellX, cellZ, targetFacing, level, {
		metadata = metadata,
		sizeCells = metadata,
	})

	Helpers.sendPlacementDelta(player, "Removed", resolvedId, cellX, cellZ, currentFacing, metadata, level)
	Helpers.sendPlacementDelta(player, "Placed", resolvedId, cellX, cellZ, targetFacing, metadata, level)

	return true, "Rotated"
end

return Rotate
