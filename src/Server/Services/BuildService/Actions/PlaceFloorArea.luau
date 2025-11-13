--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)

local MAX_FLOOR_AREA_CELLS = 256

type Facing = "North" | "East" | "South" | "West"

type Payload = {
	ItemId: string,
	StartCellX: number,
	StartCellZ: number,
	EndCellX: number,
	EndCellZ: number,
	Level: number?,
}

local function PlaceFloorArea(player: Player, payload: Payload): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local level = state:NormalizeLevel(payload.Level)

	local itemId = payload.ItemId
	local itemData = itemId and ItemFinder.FindItemById(itemId) or nil
	if not itemData then
		return false, "Invalid item ID"
	end

	if itemData.PlacementType ~= "Floor" then
		return false, "Box placement only supports floor items"
	end

	local startX = math.floor(payload.StartCellX)
	local startZ = math.floor(payload.StartCellZ)
	local endX = math.floor(payload.EndCellX)
	local endZ = math.floor(payload.EndCellZ)

	local minCellX = math.min(startX, endX)
	local minCellZ = math.min(startZ, endZ)
	local maxCellX = math.max(startX, endX)
	local maxCellZ = math.max(startZ, endZ)

	if maxCellX < 1 or maxCellZ < 1 then
		return false, "Selection outside plot"
	end

	local grid = state.Grid
	local columns = grid.Columns
	local rows = grid.Rows
	if minCellX < 1 or minCellZ < 1 or maxCellX > columns or maxCellZ > rows then
		return false, "Selection outside plot bounds"
	end

	local widthCells = maxCellX - minCellX + 1
	local depthCells = maxCellZ - minCellZ + 1
	local facing: Facing = "North"

	local totalCells = widthCells * depthCells
	if totalCells < 1 then
		return false, "Nothing to place"
	end

	if totalCells > MAX_FLOOR_AREA_CELLS then
		return false, "Selection too large"
	end

	if not state:CanPlaceFloor(minCellX, minCellZ, widthCells, depthCells, facing, level) then
		return false, "Selection blocked"
	end

	local canAfford, failureReason, totalCost, currencyState =
		Helpers.ensurePlacementFunds(player, itemData, totalCells)
	if not canAfford then
		return false, failureReason or "Not enough cash"
	end

	local success = state:PlaceFloor(itemId, minCellX, minCellZ, widthCells, depthCells, facing, level)
	if not success then
		return false, "Failed to place floor"
	end

	local metadata = {
		WidthCells = widthCells,
		DepthCells = depthCells,
	}

	WorldPlacer.Spawn(player, grid, itemId, minCellX, minCellZ, facing, level, {
		metadata = metadata,
		sizeCells = metadata,
	})

	Helpers.sendPlacementDelta(player, "Placed", itemId, minCellX, minCellZ, facing, metadata, level)
	Helpers.deductPlacementCost(player, currencyState, totalCost)

	return true, "Floors placed"
end

return PlaceFloorArea
