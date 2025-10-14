--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementUtils = require(script.Parent:WaitForChild("PlacementUtils"))
local WallConstraints = require(script.Parent:WaitForChild("WallConstraints"))

export type Facing = string

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
	Orientation: "Horizontal" | "Vertical",
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
local anchorOrientation: ("Horizontal" | "Vertical")? = nil
local anchorItemId: string? = nil
local currentSummary: WallStripSelectionInfo? = nil
local currentHighlightCells: { number } = {}

local floorSupportMap: { [number]: boolean } = {}

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

local function determineOrientation(facing: Facing?): ("Horizontal" | "Vertical")?
	if facing == "North" or facing == "South" then
		return "Horizontal"
	end
	if facing == "East" or facing == "West" then
		return "Vertical"
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
	local orientation: ("Horizontal" | "Vertical")? = determineOrientation(normalizedFacing)
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
	local orientationLiteral: "Horizontal" | "Vertical" = if orientationValue == "Horizontal"
		then "Horizontal"
		else "Vertical"

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
		Orientation = orientationLiteral,
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
	isChunkUnlocked: (number, number) -> boolean
): boolean
	if cellX < 1 or cellX > grid.Columns then
		return false
	end
	if cellZ < 1 or cellZ > grid.Rows then
		return false
	end

	if not validateChunkRange(grid, chunkSize, cellX, cellZ, facing, isChunkUnlocked) then
		return false
	end

	local edgeOccupant = WallConstraints.GetEdgeOccupant(cellX, cellZ, facing)
	if edgeOccupant ~= nil then
		return false
	end

	local key = PlacementKey.ForPlacementType(cellX, cellZ, facing :: any, "Wall")
	local occupant = placed and placed[key]
	if occupant then
		return false
	end

	if spec and spec.RequiresFloorOnBothSides == true then
		local map = floorMap or {}
		if not hasFloorSupport(grid, map, cellX, cellZ, facing) then
			return false
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
		anchorOrientation = orientationValue :: "Horizontal" | "Vertical"
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
			anchorOrientation = orientationValue :: "Horizontal" | "Vertical"
		end
		if not anchorCellX or not anchorCellZ then
			anchorCellX = currentCellX
			anchorCellZ = currentCellZ
		end
	end

	local anchorX = anchorCellX or currentCellX
	local anchorZ = anchorCellZ or currentCellZ
	local orientationValue: ("Horizontal" | "Vertical")? = anchorOrientation
	if not orientationValue then
		resetState()
		return
	end
	local orientationLiteral: "Horizontal" | "Vertical" = if orientationValue == "Horizontal"
		then "Horizontal"
		else "Vertical"

	local facingValue: Facing = (anchorFacing or normalizedFacing) :: Facing

	local startCellX = anchorX
	local endCellX = anchorX
	local startCellZ = anchorZ
	local endCellZ = anchorZ

	if orientationLiteral == "Horizontal" then
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
		end
	else
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
		end
	end

	local floorMapRef: { [number]: boolean }? = nil
	if args.spec and args.spec.RequiresFloorOnBothSides == true then
		floorMapRef = PlacementUtils.PopulateCellMapForType(grid, placed, "Floor", floorSupportMap, nil)
	end

	local highlightCells: { number } = {}
	local canPlace = true

	if orientationLiteral == "Horizontal" then
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
					args.isChunkUnlocked
				)
			then
				canPlace = false
			end

			highlightCells[#highlightCells + 1] = grid:CellToIndex(cellX, anchorZ)
		end
	else
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
					args.isChunkUnlocked
				)
			then
				canPlace = false
			end

			highlightCells[#highlightCells + 1] = grid:CellToIndex(anchorX, cellZ)
		end
	end

	local segmentCount = if orientationLiteral == "Horizontal"
		then endCellX - startCellX + 1
		else endCellZ - startCellZ + 1

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
		Orientation = orientationLiteral,
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
