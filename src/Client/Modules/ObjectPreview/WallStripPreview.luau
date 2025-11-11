--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementUtils = require(script.Parent:WaitForChild("PlacementUtils"))
local WallConstraints = require(script.Parent:WaitForChild("WallConstraints"))

export type Facing = string

type Orientation = "Horizontal" | "Vertical" | "DiagonalForward" | "DiagonalBackward"

export type WallStripSelectionInfo = {
	ItemId: string?,
	AnchorCellX: number,
	AnchorCellZ: number,
	Facing: Facing,
	StartCellX: number,
	EndCellX: number,
	StartCellZ: number,
	EndCellZ: number,
	SegmentCount: number,
	Orientation: Orientation,
	CanPlace: boolean,
}

export type WallStripUpdateResult = {
	summary: WallStripSelectionInfo?,
	highlightCells: { number },
	canPlace: boolean,
}

export type BeginArgs = {
	itemId: string?,
	anchorCellX: number?,
	anchorCellZ: number?,
	facing: Facing?,
	spec: any?,
	isMousePressed: boolean,
}

export type UpdateArgs = {
	grid: any,
	chunkSize: number,
	placed: any,
	itemId: string?,
	spec: any?,
	currentCellX: number,
	currentCellZ: number,
	facing: Facing,
	isChunkUnlocked: (number, number) -> boolean,
}

local WallStripPreview = {}

local selectionActive = false
local anchorCellX: number? = nil
local anchorCellZ: number? = nil
local anchorFacing: Facing? = nil
local anchorOrientation: Orientation? = nil
local anchorItemId: string? = nil
local currentSummary: WallStripSelectionInfo? = nil
local currentHighlightCells: { number } = {}

local floorSupportMap: { [number]: boolean } = {}
local cellOccupancyMap: { [number]: boolean } = {}

local MAX_SEGMENTS = 48

local function resetState()
	selectionActive = false
	anchorCellX = nil
	anchorCellZ = nil
	anchorFacing = nil
	anchorOrientation = nil
	anchorItemId = nil
	currentSummary = nil
	currentHighlightCells = {}
end

local function determineOrientation(facing: Facing?): Orientation?
	if not facing then
		return nil
	end
	local normalized = PlacementKey.NormalizeFacing(facing :: any)
	if normalized == "North" or normalized == "South" then
		return "Horizontal"
	end
	if normalized == "East" or normalized == "West" then
		return "Vertical"
	end
	if normalized == "NorthEast" then
		return "DiagonalForward"
	end
	if normalized == "NorthWest" then
		return "DiagonalBackward"
	end
	return nil
end

local function hasFloorSupport(
	grid: any,
	floorMap: { [number]: boolean },
	cellX: number,
	cellZ: number,
	facing: Facing
): boolean
	if facing == "North" then
		local primaryIndex = grid:CellToIndex(cellX, cellZ)
		if not floorMap[primaryIndex] then
			return false
		end
		if cellZ > 1 then
			local secondaryIndex = grid:CellToIndex(cellX, cellZ - 1)
			if not floorMap[secondaryIndex] then
				return false
			end
		end
		return true
	end

	-- facing == "South"
	local primaryIndex = grid:CellToIndex(cellX, cellZ)
	if not floorMap[primaryIndex] then
		return false
	end
	if cellZ < grid.Rows then
		local secondaryIndex = grid:CellToIndex(cellX, cellZ + 1)
		if not floorMap[secondaryIndex] then
			return false
		end
	end
	return true
end

function WallStripPreview.Clear()
	resetState()
end

function WallStripPreview.IsDragInProgress(): boolean
	return selectionActive
end

function WallStripPreview.GetSelectionSummary(): WallStripSelectionInfo?
	return currentSummary
end

function WallStripPreview.GetHighlightCells(): { number }
	return currentHighlightCells
end

function WallStripPreview.TryBeginDrag(args: BeginArgs): boolean
	if selectionActive then
		return true
	end

	if not args.isMousePressed then
		return false
	end

	local itemId = args.itemId
	if typeof(itemId) ~= "string" or itemId == "" then
		return false
	end

	local spec = args.spec
	if typeof(spec) ~= "table" then
		return false
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	if placementType ~= "Wall" then
		return false
	end

	if spec.RequiresExistingWall == true then
		return false
	end

	local cellX = args.anchorCellX
	local cellZ = args.anchorCellZ
	if typeof(cellX) ~= "number" or typeof(cellZ) ~= "number" then
		return false
	end

	local normalizedFacing = PlacementKey.NormalizeFacing(args.facing :: any)
	local orientation: Orientation? = determineOrientation(normalizedFacing)
	if not orientation then
		return false
	end

	selectionActive = true
	anchorCellX = cellX
	anchorCellZ = cellZ
	anchorFacing = normalizedFacing :: Facing
	anchorOrientation = orientation
	anchorItemId = itemId
	currentSummary = nil
	currentHighlightCells = {}

	return true
end

function WallStripPreview.GetFallbackSummary(): WallStripSelectionInfo?
	if not selectionActive then
		return nil
	end

	local itemId = anchorItemId
	local anchorX = anchorCellX
	local anchorZ = anchorCellZ
	local facingValue = anchorFacing
	if not itemId or not anchorX or not anchorZ or not facingValue then
		return nil
	end

	local orientationValue = anchorOrientation
	if not orientationValue then
		orientationValue = determineOrientation(facingValue)
	end
	if not orientationValue then
		return nil
	end
	local finalOrientation: Orientation = orientationValue :: Orientation

	return {
		ItemId = itemId,
		AnchorCellX = anchorX,
		AnchorCellZ = anchorZ,
		Facing = facingValue,
		StartCellX = anchorX,
		EndCellX = anchorX,
		StartCellZ = anchorZ,
		EndCellZ = anchorZ,
		SegmentCount = 1,
		Orientation = finalOrientation,
		CanPlace = true,
	}
end

local function validateChunkRange(
	grid: any,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	facing: Facing,
	isChunkUnlocked: (number, number) -> boolean
): boolean
	local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
		grid:FootprintChunkRange(cellX, cellZ, 1, 1, facing :: any, chunkSize)
	for chunkZ = minChunkZ, maxChunkZ do
		for chunkX = minChunkX, maxChunkX do
			if not isChunkUnlocked(chunkX, chunkZ) then
				return false
			end
		end
	end
	return true
end

local function isWallPlacementAllowed(
	grid: any,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	facing: Facing,
	placed: any,
	spec: any?,
	floorMap: { [number]: boolean }?,
	cellMap: { [number]: boolean }?,
	isChunkUnlocked: (number, number) -> boolean
): boolean
	if cellX < 1 or cellX > grid.Columns then
		return false
	end
	if cellZ < 1 or cellZ > grid.Rows then
		return false
	end

	local resolvedFacing = PlacementKey.NormalizeFacing(facing :: any)

	if not validateChunkRange(grid, chunkSize, cellX, cellZ, resolvedFacing, isChunkUnlocked) then
		return false
	end

	local edgeOccupant = WallConstraints.GetEdgeOccupant(cellX, cellZ, resolvedFacing)
	if edgeOccupant ~= nil then
		return false
	end

	local key = PlacementKey.ForPlacementType(cellX, cellZ, resolvedFacing :: any, "Wall")
	local occupant = placed and placed[key]
	if occupant then
		return false
	end

	if spec and spec.RequiresFloorOnBothSides == true then
		if resolvedFacing == "NorthEast" or resolvedFacing == "NorthWest" then
			return false
		end
		local map = floorMap or {}
		if not hasFloorSupport(grid, map, cellX, cellZ, resolvedFacing) then
			return false
		end
	end

	if
		resolvedFacing == "NorthEast"
		or resolvedFacing == "NorthWest"
		or resolvedFacing == "SouthEast"
		or resolvedFacing == "SouthWest"
	then
		local map = cellMap
		if map then
			local index = grid:CellToIndex(cellX, cellZ)
			if map[index] then
				return false
			end
		end
	end

	return true
end

function WallStripPreview.Update(args: UpdateArgs): WallStripUpdateResult?
	if not selectionActive then
		return
	end

	local grid = args.grid
	local chunkSize = args.chunkSize
	local placed = args.placed
	local columns = grid.Columns
	local rows = grid.Rows

	local currentCellX = math.clamp(args.currentCellX, 1, columns)
	local currentCellZ = math.clamp(args.currentCellZ, 1, rows)
	local normalizedFacing = PlacementKey.NormalizeFacing(args.facing :: any)

	local function applyFacing(newFacing: Facing)
		anchorFacing = newFacing
		local orientationValue = determineOrientation(newFacing)
		if not orientationValue then
			resetState()
			return false
		end
		anchorOrientation = orientationValue :: Orientation
		anchorCellX = currentCellX
		anchorCellZ = currentCellZ
		return true
	end

	local storedFacing = anchorFacing
	if storedFacing == nil or storedFacing ~= normalizedFacing then
		if not applyFacing(normalizedFacing :: Facing) then
			return
		end
	else
		if not anchorOrientation then
			local orientationValue = determineOrientation(storedFacing)
			if not orientationValue then
				resetState()
				return
			end
			anchorOrientation = orientationValue :: Orientation
		end
		if not anchorCellX or not anchorCellZ then
			anchorCellX = currentCellX
			anchorCellZ = currentCellZ
		end
	end

	local anchorX = anchorCellX or currentCellX
	local anchorZ = anchorCellZ or currentCellZ
	local orientationValue: Orientation? = anchorOrientation
	if not orientationValue then
		resetState()
		return
	end

	local facingValue: Facing = (anchorFacing or normalizedFacing) :: Facing

	local startCellX = anchorX
	local endCellX = anchorX
	local startCellZ = anchorZ
	local endCellZ = anchorZ
	local segmentCount = 1
	local diagonalStepX = 0
	local diagonalStepZ = 0
	local diagonalSpan = 0

	if orientationValue == "Horizontal" then
		local targetCellX = math.clamp(args.currentCellX, 1, columns)
		startCellX = math.clamp(math.min(anchorX, targetCellX), 1, columns)
		endCellX = math.clamp(math.max(anchorX, targetCellX), 1, columns)
		local span = endCellX - startCellX + 1
		if span > MAX_SEGMENTS then
			if anchorX <= targetCellX then
				endCellX = startCellX + MAX_SEGMENTS - 1
			else
				startCellX = endCellX - MAX_SEGMENTS + 1
			end
			span = MAX_SEGMENTS
		end
		segmentCount = endCellX - startCellX + 1
	elseif orientationValue == "Vertical" then
		local targetCellZ = math.clamp(args.currentCellZ, 1, rows)
		startCellZ = math.clamp(math.min(anchorZ, targetCellZ), 1, rows)
		endCellZ = math.clamp(math.max(anchorZ, targetCellZ), 1, rows)
		local span = endCellZ - startCellZ + 1
		if span > MAX_SEGMENTS then
			if anchorZ <= targetCellZ then
				endCellZ = startCellZ + MAX_SEGMENTS - 1
			else
				startCellZ = endCellZ - MAX_SEGMENTS + 1
			end
			span = MAX_SEGMENTS
		end
		segmentCount = endCellZ - startCellZ + 1
	else
		local targetX = math.clamp(args.currentCellX, 1, columns)
		local targetZ = math.clamp(args.currentCellZ, 1, rows)
		local dx = targetX - anchorX
		local dz = targetZ - anchorZ
		local stepX = if dx >= 0 then 1 else -1
		local stepZ = if orientationValue == "DiagonalForward" then stepX else -stepX
		local alignmentValid = dx == 0 and dz == 0
		if not alignmentValid then
			if orientationValue == "DiagonalForward" then
				alignmentValid = (dx >= 0 and dz >= 0) or (dx <= 0 and dz <= 0)
			else
				alignmentValid = (dx >= 0 and dz <= 0) or (dx <= 0 and dz >= 0)
			end
		end
		local span = if alignmentValid then math.min(math.abs(dx), math.abs(dz)) else 0
		if span > MAX_SEGMENTS - 1 then
			span = MAX_SEGMENTS - 1
		end
		while span > 0 do
			local candidateX = anchorX + stepX * span
			local candidateZ = anchorZ + stepZ * span
			if candidateX < 1 or candidateX > columns or candidateZ < 1 or candidateZ > rows then
				span -= 1
			else
				break
			end
		end
		diagonalStepX = if span > 0 then stepX else 0
		diagonalStepZ = if span > 0 then stepZ else 0
		diagonalSpan = span
		endCellX = anchorX + (stepX * span)
		endCellZ = anchorZ + (stepZ * span)
		segmentCount = span + 1
	end

	local floorMapRef: { [number]: boolean }? = nil
	if args.spec and args.spec.RequiresFloorOnBothSides == true then
		floorMapRef = PlacementUtils.PopulateCellMapForType(grid, placed, "Floor", floorSupportMap, nil)
	end

	local cellObjectMapRef = PlacementUtils.PopulateCellMapForType(grid, placed, "CellObject", cellOccupancyMap, nil)

	local highlightCells: { number } = {}
	local canPlace = true

	if orientationValue == "Horizontal" then
		for cellX = startCellX, endCellX do
			if
				not isWallPlacementAllowed(
					grid,
					chunkSize,
					cellX,
					anchorZ,
					facingValue,
					placed,
					args.spec,
					floorMapRef,
					cellObjectMapRef,
					args.isChunkUnlocked
				)
			then
				canPlace = false
			end

			highlightCells[#highlightCells + 1] = grid:CellToIndex(cellX, anchorZ)
		end
	elseif orientationValue == "Vertical" then
		for cellZ = startCellZ, endCellZ do
			if
				not isWallPlacementAllowed(
					grid,
					chunkSize,
					anchorX,
					cellZ,
					facingValue,
					placed,
					args.spec,
					floorMapRef,
					cellObjectMapRef,
					args.isChunkUnlocked
				)
			then
				canPlace = false
			end

			highlightCells[#highlightCells + 1] = grid:CellToIndex(anchorX, cellZ)
		end
	else
		for i = 0, diagonalSpan do
			local cellX = anchorX + diagonalStepX * i
			local cellZ = anchorZ + diagonalStepZ * i
			if
				not isWallPlacementAllowed(
					grid,
					chunkSize,
					cellX,
					cellZ,
					facingValue,
					placed,
					args.spec,
					floorMapRef,
					cellObjectMapRef,
					args.isChunkUnlocked
				)
			then
				canPlace = false
			end

			highlightCells[#highlightCells + 1] = grid:CellToIndex(cellX, cellZ)
		end
	end

	currentSummary = {
		ItemId = args.itemId,
		AnchorCellX = anchorX,
		AnchorCellZ = anchorZ,
		Facing = facingValue,
		StartCellX = startCellX,
		EndCellX = endCellX,
		StartCellZ = startCellZ,
		EndCellZ = endCellZ,
		SegmentCount = segmentCount,
		Orientation = orientationValue,
		CanPlace = canPlace,
	}

	currentHighlightCells = highlightCells

	return {
		summary = currentSummary,
		highlightCells = highlightCells,
		canPlace = canPlace,
	}
end

return WallStripPreview
