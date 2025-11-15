--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)

type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

type Payload = {
	ItemId: string,
	Facing: string,
	Orientation: string,
	StartCellX: number,
	StartCellZ: number,
	EndCellX: number,
	EndCellZ: number,
	Level: number?,
	SurfaceId: string?,
}

type PlannedSegment = { cellX: number, cellZ: number }

local function isDiagonalFacing(facing: Facing): boolean
	return facing == "NorthEast" or facing == "NorthWest" or facing == "SouthEast" or facing == "SouthWest"
end

local function resolveWallDimensionsFromSpec(spec: { [string]: any }?): (number, number, number, number, number)
	local defaultWidth = 4
	local defaultHeight = 12
	local defaultThickness = 0.5
	local defaultDiagonalMultiplier = math.sqrt(2)
	local defaultMinFrame = 0.2

	if typeof(spec) ~= "table" then
		return defaultWidth, defaultHeight, defaultThickness, defaultDiagonalMultiplier, defaultMinFrame
	end

	local dims = spec.WallDimensions
	if typeof(dims) ~= "table" then
		return defaultWidth, defaultHeight, defaultThickness, defaultDiagonalMultiplier, defaultMinFrame
	end

	local width = typeof(dims.NominalWidth) == "number" and dims.NominalWidth or defaultWidth
	local height = typeof(dims.NominalHeight) == "number" and dims.NominalHeight or defaultHeight
	local thickness = typeof(dims.NominalThickness) == "number" and dims.NominalThickness or defaultThickness
	local diagonalMultiplier = typeof(dims.DiagonalLengthMultiplier) == "number" and dims.DiagonalLengthMultiplier
		or defaultDiagonalMultiplier
	local minFrame = typeof(dims.MinFrameThickness) == "number" and dims.MinFrameThickness or defaultMinFrame

	return width, height, thickness, diagonalMultiplier, minFrame
end

local function buildWallMetadata(spec: { [string]: any }?, facing: Facing): { [string]: any }
	local width, height, thickness, diagonalMultiplier, minFrame = resolveWallDimensionsFromSpec(spec)
	local effectiveWidth = width
	if isDiagonalFacing(facing) then
		effectiveWidth *= diagonalMultiplier
	end

	return {
		WallSizeX = width,
		WallSizeY = height,
		WallSizeZ = thickness,
		EffectiveWallWidth = effectiveWidth,
		DiagonalLengthMultiplier = diagonalMultiplier,
		MinFrameThickness = minFrame,
	}
end

local function PlaceWallStrip(player: Player, payload: Payload): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local level = state:NormalizeLevel(payload.Level)

	if type(payload) ~= "table" then
		return false, "Invalid payload"
	end

	local grid = state.Grid

	local itemId = payload.ItemId
	local spec = itemId and ItemFinder.FindItemById(itemId)
	if not spec then
		return false, "Invalid item ID"
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	if placementType ~= "Wall" then
		return false, "Item is not a wall"
	end

	if spec.RequiresExistingWall == true then
		return false, "Cannot drag replace-only wall segments"
	end

	local facingString = payload.Facing
	if typeof(facingString) ~= "string" or facingString == "" then
		return false, "Invalid facing"
	end
	local resolvedFacing = PlacementKey.NormalizeFacing(facingString :: any)
	local facing: Facing = resolvedFacing :: Facing

	local orientation = payload.Orientation
	local isDiagonalForward = orientation == "DiagonalForward"
	local isDiagonalBackward = orientation == "DiagonalBackward"
	local isDiagonal = isDiagonalForward or isDiagonalBackward

	if orientation ~= "Horizontal" and orientation ~= "Vertical" and not isDiagonal then
		return false, "Invalid wall strip orientation"
	end
	local startCellXValue = tonumber(payload.StartCellX)
	local startCellZValue = tonumber(payload.StartCellZ)
	local endCellXValue = tonumber(payload.EndCellX)
	local endCellZValue = tonumber(payload.EndCellZ)
	if not startCellXValue or not startCellZValue or not endCellXValue or not endCellZValue then
		return false, "Invalid wall strip coordinates"
	end

	local startCellX = math.floor(startCellXValue)
	local startCellZ = math.floor(startCellZValue)
	local endCellX = math.floor(endCellXValue)
	local endCellZ = math.floor(endCellZValue)

	if startCellX < 1 or startCellX > grid.Columns or endCellX < 1 or endCellX > grid.Columns then
		return false, "Strip outside plot bounds"
	end
	if startCellZ < 1 or startCellZ > grid.Rows or endCellZ < 1 or endCellZ > grid.Rows then
		return false, "Strip outside plot bounds"
	end

	local requiresFloorOnBothSides = spec.RequiresFloorOnBothSides == true
	if requiresFloorOnBothSides and isDiagonal then
		return false, "Diagonal walls cannot require floor support"
	end

	local plannedSegments: { PlannedSegment } = {}

	if orientation == "Horizontal" then
		if startCellZ ~= endCellZ then
			return false, "Horizontal strips must stay on a single row"
		end

		local minX = math.min(startCellX, endCellX)
		local maxX = math.max(startCellX, endCellX)
		local cellZ = startCellZ

		if minX < 1 or maxX > grid.Columns then
			return false, "Strip outside plot bounds"
		end

		local count = maxX - minX + 1
		plannedSegments = table.create(count) :: { PlannedSegment }
		for cellX = minX, maxX do
			if not state:CanPlaceWall(cellX, cellZ, facing, requiresFloorOnBothSides, level) then
				return false, ("Wall blocked at (%d, %d)"):format(cellX, cellZ)
			end

			local key = state:PlacementKeyForType(cellX, cellZ, facing, "Wall", level)
			if state.Save.PlacedObjects[key] then
				return false, "A wall already occupies part of that strip"
			end

			plannedSegments[#plannedSegments + 1] = { cellX = cellX, cellZ = cellZ }
		end
	elseif orientation == "Vertical" then
		if startCellX ~= endCellX then
			return false, "Vertical strips must stay on a single column"
		end

		local minZ = math.min(startCellZ, endCellZ)
		local maxZ = math.max(startCellZ, endCellZ)
		local cellX = startCellX

		if minZ < 1 or maxZ > grid.Rows then
			return false, "Strip outside plot bounds"
		end

		local count = maxZ - minZ + 1
		plannedSegments = table.create(count) :: { PlannedSegment }

		for cellZ = minZ, maxZ do
			if not state:CanPlaceWall(cellX, cellZ, facing, requiresFloorOnBothSides, level) then
				return false, ("Wall blocked at (%d, %d)"):format(cellX, cellZ)
			end

			local key = state:PlacementKeyForType(cellX, cellZ, facing, "Wall", level)
			if state.Save.PlacedObjects[key] then
				return false, "A wall already occupies part of that strip"
			end

			plannedSegments[#plannedSegments + 1] = { cellX = cellX, cellZ = cellZ }
		end
	else
		local deltaX = endCellX - startCellX
		local deltaZ = endCellZ - startCellZ
		if math.abs(deltaX) ~= math.abs(deltaZ) then
			return false, "Diagonal strips must move equally in X and Z"
		end
		local stepX = if deltaX >= 0 then 1 else -1
		local stepZ = if isDiagonalForward then stepX else -stepX
		if deltaX ~= 0 or deltaZ ~= 0 then
			local product = deltaX * deltaZ
			if isDiagonalForward and product < 0 then
				return false, "Diagonal forward strips must move in the same direction"
			end
			if isDiagonalBackward and product > 0 then
				return false, "Diagonal backward strips must move in opposite directions"
			end
		end

		local span = math.abs(deltaX)
		plannedSegments = table.create(span + 1) :: { PlannedSegment }
		for i = 0, span do
			local cellX = startCellX + stepX * i
			local cellZ = startCellZ + stepZ * i
			if cellX < 1 or cellX > grid.Columns or cellZ < 1 or cellZ > grid.Rows then
				return false, "Strip outside plot bounds"
			end
			if not state:CanPlaceWall(cellX, cellZ, facing, false, level) then
				return false, ("Wall blocked at (%d, %d)"):format(cellX, cellZ)
			end

			local key = state:PlacementKeyForType(cellX, cellZ, facing, "Wall", level)
			if state.Save.PlacedObjects[key] then
				return false, "A wall already occupies part of that strip"
			end

			plannedSegments[#plannedSegments + 1] = { cellX = cellX, cellZ = cellZ }
		end
	end

	local segmentCount = #plannedSegments
	if segmentCount < 1 then
		return false, "Nothing to place"
	end

	local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, spec, segmentCount)
	if not canAfford then
		return false, failureReason or "Not enough cash"
	end

	local segmentMetadata = buildWallMetadata(spec, facing)
	local wallSurfaceId = Helpers.resolveSurfaceId(spec, payload.SurfaceId)
	if wallSurfaceId then
		segmentMetadata.SurfaceId = wallSurfaceId
	end

	for _, segment in plannedSegments do
		local placed = state:PlaceWall(
			itemId,
			segment.cellX,
			segment.cellZ,
			1,
			1,
			facing,
			requiresFloorOnBothSides,
			segmentMetadata,
			level
		)
		if not placed then
			return false, "Failed to place wall strip"
		end

		WorldPlacer.Spawn(player, grid, itemId, segment.cellX, segment.cellZ, facing, level, {
			metadata = segmentMetadata,
		})
		Helpers.sendPlacementDelta(
			player,
			"Placed",
			itemId,
			segment.cellX,
			segment.cellZ,
			facing,
			segmentMetadata,
			level
		)
	end

	Helpers.deductPlacementCost(player, currencyState, totalCost)

	return true, "Wall strip placed"
end

return PlaceWallStrip
