--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)

type Facing = any

type Payload = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: string,
}

local function Build(player: Player, payload: Payload): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local facingValue: Facing? = Helpers.coerceFacing(payload.Facing)
	if not facingValue then
		return false, "Invalid facing"
	end

	local facing: Facing = facingValue

	local itemData = ItemFinder.FindItemById(payload.ItemId)
	if not itemData then
		return false, "Invalid item ID"
	end

	local placementType = itemData.PlacementType or itemData.Type or "CellObject"

	local allowedFacing = itemData.Facing :: { Facing }?
	if placementType ~= "Floor" and allowedFacing and #allowedFacing > 0 then
		if not table.find(allowedFacing, facing) then
			return false, "Invalid facing for this item"
		end
	end

	if itemData.PlacementType == "Floor" then
		local widthCells = itemData.WidthCells or itemData.Width or 1
		local depthCells = itemData.DepthCells or itemData.Depth or 1
		local floorFacing: Facing = "North"
		local success =
			state:PlaceFloor(payload.ItemId, payload.CellX, payload.CellZ, widthCells, depthCells, floorFacing)
		if not success then
			return false, "Failed to place floor"
		end

		local metadata = {
			WidthCells = widthCells,
			DepthCells = depthCells,
		}
		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, floorFacing, {
			metadata = metadata,
			sizeCells = metadata,
		})

		Helpers.sendPlacementDelta(
			player,
			"Placed",
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			floorFacing,
			metadata
		)

		return true, "Floor placed"
	elseif itemData.PlacementType == "CellObject" then
		local widthCells = itemData.WidthCells or itemData.Width or 1
		local depthCells = itemData.DepthCells or itemData.Depth or 1

		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.CellX, payload.CellZ, widthCells, depthCells, facing) then
				return false, "Floor required under all cells"
			end
		end

		local success = state:Place(payload.ItemId, payload.CellX, payload.CellZ, widthCells, depthCells, facing)

		if not success then
			return false, "Failed to place cell object"
		end

		local stationType = if itemData.StationType then itemData.StationType else nil
		if stationType then
			local placementKey = state:PlacementKeyForType(payload.CellX, payload.CellZ, facing, placementType)
			PlotService.AddStationForPlayer(player, stationType, placementKey, payload.ItemId)
		end
		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Helpers.sendPlacementDelta(player, "Placed", payload.ItemId, payload.CellX, payload.CellZ, facing, nil)
		return true, "Cell object placed"
	elseif itemData.PlacementType == "Wall" then
		local requiresFloorOnBothSides = itemData.RequiresFloorOnBothSides or false
		if itemData.RequiresExistingWall then
			local replacedId, err = state:ReplaceWallSegment(
				payload.ItemId,
				payload.CellX,
				payload.CellZ,
				facing,
				requiresFloorOnBothSides,
				itemData.ReplaceableWallTag
			)
			if not replacedId then
				return false, err or "Failed to replace wall"
			end

			WorldPlacer.Despawn(player, replacedId, payload.CellX, payload.CellZ, facing)
			local key = state:PlacementKeyForType(payload.CellX, payload.CellZ, facing, "Wall")
			local savedDoor = state.Save.PlacedObjects[key]
			WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing, {
				previousWallId = replacedId,
				metadata = savedDoor and savedDoor.Metadata,
			})

			Helpers.sendPlacementDelta(player, "Removed", replacedId, payload.CellX, payload.CellZ, facing, nil)
			Helpers.sendPlacementDelta(
				player,
				"Placed",
				payload.ItemId,
				payload.CellX,
				payload.CellZ,
				facing,
				savedDoor and savedDoor.Metadata
			)

			return true, "Door installed"
		end

		local success =
			state:PlaceWall(payload.ItemId, payload.CellX, payload.CellZ, 1, 1, facing, requiresFloorOnBothSides)
		if not success then
			return false, "Failed to place wall"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Helpers.sendPlacementDelta(player, "Placed", payload.ItemId, payload.CellX, payload.CellZ, facing, nil)

		return true, "Wall placed"
	elseif itemData.PlacementType == "Roof" then
		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if
				not state:HasFloorUnderFootprint(
					payload.CellX,
					payload.CellZ,
					itemData.WidthCells,
					itemData.DepthCells,
					facing
				)
			then
				return false, "Floor required under roof"
			end
		end

		local success = state:PlaceRoof(
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			itemData.WidthCells,
			itemData.DepthCells,
			facing
		)
		if not success then
			return false, "Failed to place roof"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Helpers.sendPlacementDelta(player, "Placed", payload.ItemId, payload.CellX, payload.CellZ, facing, nil)

		return true, "Roof placed"
	else
		return false, "Unknown placement type"
	end
end

return Build
