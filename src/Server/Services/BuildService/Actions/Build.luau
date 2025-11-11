--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)
local PlotStateModule = require(ServerScriptService.Server.Classes.PlotState)

type Facing = PlotStateModule.Facing

type Payload = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: string,
	WallMountEnabled: boolean?,
	WallMountCellX: number?,
	WallMountCellZ: number?,
	WallMountFacing: string?,
	WallMountHeightOffset: number?,
	WallMountPosX: number?,
	WallMountPosY: number?,
	WallMountPosZ: number?,
	WallMountNormalX: number?,
	WallMountNormalY: number?,
	WallMountNormalZ: number?,
}

-- Derives authoritative world pose metadata for wall-mounted items using the plot grid.
local function computeWallMountMetadata(
	grid: any,
	itemSpec: { [string]: any }?,
	cellX: number,
	cellZ: number,
	facing: Facing,
	heightOffset: number
): { [string]: any }
	local mountConfig = if itemSpec and typeof(itemSpec.WallMountConfig) == "table"
		then itemSpec.WallMountConfig
		else nil
	local offsetFromWall = 0.1
	if mountConfig and typeof(mountConfig.OffsetFromWall) == "number" then
		offsetFromWall = mountConfig.OffsetFromWall
	end
	if offsetFromWall < 0 then
		offsetFromWall = 0
	end

	local wallCFrame = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing, heightOffset)
	local wallNormal = wallCFrame.LookVector
	if wallNormal.Magnitude < 1e-3 then
		wallNormal = Vector3.new(0, 0, -1)
	else
		wallNormal = wallNormal.Unit
	end

	local worldPosition = wallCFrame.Position + wallNormal * offsetFromWall

	return {
		WallMountData = {
			ReferenceCellX = cellX,
			ReferenceCellZ = cellZ,
			AttachedFacing = facing,
			HeightOffset = heightOffset,
			OffsetFromWall = offsetFromWall,
			WorldPosition = {
				X = worldPosition.X,
				Y = worldPosition.Y,
				Z = worldPosition.Z,
			},
			WallNormal = {
				X = wallNormal.X,
				Y = wallNormal.Y,
				Z = wallNormal.Z,
			},
		},
	}
end

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
		local totalCells = widthCells * depthCells

		local canAfford, failureReason, totalCost, currencyState =
			Helpers.ensurePlacementFunds(player, itemData, totalCells)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end
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

		Helpers.deductPlacementCost(player, currencyState, totalCost)

		return true, "Floor placed"
	elseif placementType == "WallMounted" then
		local wallEnabled = payload.WallMountEnabled == true
		if not wallEnabled then
			return false, "Wall mount target missing"
		end

		local wallCellXValue = payload.WallMountCellX
		local wallCellZValue = payload.WallMountCellZ
		if typeof(wallCellXValue) ~= "number" or typeof(wallCellZValue) ~= "number" then
			return false, "Invalid wall coordinates"
		end
		local wallCellX = math.floor(wallCellXValue + 0.5)
		local wallCellZ = math.floor(wallCellZValue + 0.5)

		local wallFacingValue = Helpers.coerceFacing(payload.WallMountFacing)
		if not wallFacingValue then
			return false, "Invalid wall facing"
		end
		local wallFacing: Facing = wallFacingValue :: any

		local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, itemData, 1)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end

		local mountConfig = itemData.WallMountConfig
		if typeof(mountConfig) ~= "table" then
			return false, "Wall mount configuration missing"
		end

		local grid = state.Grid
		if grid == nil then
			return false, "Plot grid unavailable"
		end

		local minHeight = typeof(mountConfig.MinHeight) == "number" and mountConfig.MinHeight or 0
		local maxHeightValue = typeof(mountConfig.MaxHeight) == "number" and mountConfig.MaxHeight or (minHeight + 10)
		if maxHeightValue < minHeight then
			maxHeightValue = minHeight
		end
		local requestedHeight = if typeof(payload.WallMountHeightOffset) == "number"
			then payload.WallMountHeightOffset
			else minHeight
		local heightOffset = math.clamp(requestedHeight, minHeight, maxHeightValue)

		local successCheck, placementFailure = state:CanPlaceWallMounted(wallCellX, wallCellZ, wallFacing)
		if not successCheck then
			return false, placementFailure or "Cannot attach to wall"
		end

		local metadata = computeWallMountMetadata(grid, itemData, wallCellX, wallCellZ, wallFacing, heightOffset)
		local placed, placeError = state:PlaceWallMounted(payload.ItemId, wallCellX, wallCellZ, wallFacing, metadata)
		if not placed then
			return false, placeError or "Failed to attach to wall"
		end

		local stationType = if itemData.StationType then itemData.StationType else nil
		if stationType then
			local placementKey = state:PlacementKeyForType(wallCellX, wallCellZ, wallFacing, placementType)
			PlotService.AddStationForPlayer(player, stationType, placementKey, payload.ItemId)
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, wallCellX, wallCellZ, wallFacing, {
			metadata = metadata,
		})

		Helpers.sendPlacementDelta(player, "Placed", payload.ItemId, wallCellX, wallCellZ, wallFacing, metadata)
		Helpers.deductPlacementCost(player, currencyState, totalCost)
		return true, "Wall attachment placed"
	elseif itemData.PlacementType == "CellObject" then
		local widthCells = itemData.WidthCells or itemData.Width or 1
		local depthCells = itemData.DepthCells or itemData.Depth or 1

		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.CellX, payload.CellZ, widthCells, depthCells, facing) then
				return false, "Floor required under all cells"
			end
		end

		local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, itemData, 1)
		if not canAfford then
			return false, failureReason or "Not enough cash"
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

		Helpers.deductPlacementCost(player, currencyState, totalCost)
		return true, "Cell object placed"
	elseif itemData.PlacementType == "Wall" then
		local requiresFloorOnBothSides = itemData.RequiresFloorOnBothSides or false
		local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, itemData, 1)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end
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

			Helpers.deductPlacementCost(player, currencyState, totalCost)

			return true, "Door installed"
		end

		local success =
			state:PlaceWall(payload.ItemId, payload.CellX, payload.CellZ, 1, 1, facing, requiresFloorOnBothSides)
		if not success then
			return false, "Failed to place wall"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Helpers.sendPlacementDelta(player, "Placed", payload.ItemId, payload.CellX, payload.CellZ, facing, nil)
		Helpers.deductPlacementCost(player, currencyState, totalCost)

		return true, "Wall placed"
	elseif itemData.PlacementType == "Roof" then
		local widthCells = itemData.WidthCells or itemData.Width or 1
		local depthCells = itemData.DepthCells or itemData.Depth or 1
		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.CellX, payload.CellZ, widthCells, depthCells, facing) then
				return false, "Floor required under roof"
			end
		end

		local totalCells = widthCells * depthCells
		local canAfford, failureReason, totalCost, currencyState =
			Helpers.ensurePlacementFunds(player, itemData, totalCells)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end

		local success = state:PlaceRoof(payload.ItemId, payload.CellX, payload.CellZ, widthCells, depthCells, facing)
		if not success then
			return false, "Failed to place roof"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Helpers.sendPlacementDelta(player, "Placed", payload.ItemId, payload.CellX, payload.CellZ, facing, nil)
		Helpers.deductPlacementCost(player, currencyState, totalCost)

		return true, "Roof placed"
	else
		return false, "Unknown placement type"
	end
end

return Build
