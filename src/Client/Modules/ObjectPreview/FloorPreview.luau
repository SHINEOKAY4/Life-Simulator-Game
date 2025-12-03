--!strict

local PlacementUtils = require(script.Parent.PlacementUtils)
local Renderer = require(script.Parent.Renderer)

type Facing = string
export type FloorSelectionInfo = {
	ItemId: string?,
	AnchorCellX: number,
	AnchorCellZ: number,
	CurrentCellX: number,
	CurrentCellZ: number,
	MinCellX: number,
	MinCellZ: number,
	MaxCellX: number,
	MaxCellZ: number,
	CellCount: number,
	WidthCells: number,
	DepthCells: number,
	CanPlace: boolean,
	Level: number,
}

export type FloorUpdateResult = {
	canPlace: boolean,
	fillColor: Color3,
	outlineColor: Color3,
	summary: FloorSelectionInfo,
}

type MoveOriginInfo = PlacementUtils.MoveOriginInfo

type FloorUpdateArgs = {
	model: Model,
	grid: any,
	surface: BasePart,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	itemId: string?,
	placed: any,
	ignorePlacement: MoveOriginInfo?,
	isChunkUnlocked: (number, number) -> boolean,
	level: number?,
	levelHeight: number?,
}

local MAX_FLOOR_SELECTION_CELLS = 256

local selectionActive = false
local anchorCellX: number? = nil
local anchorCellZ: number? = nil
local currentSummary: FloorSelectionInfo? = nil
local placementHandler: ((FloorSelectionInfo) -> ())? = nil

local previewPart: BasePart? = nil
local previewBaseSize: Vector3? = nil
local previewBaseWidthCells = 1
local previewBaseDepthCells = 1

local floorCellMap: { [number]: boolean } = {}

local PLACEABLE_FILL = Color3.fromRGB(159, 234, 159)
local PLACEABLE_OUTLINE = Color3.fromRGB(137, 255, 119)
local BLOCKED_FILL = Color3.fromRGB(219, 136, 136)
local BLOCKED_OUTLINE = Color3.fromRGB(255, 85, 85)

local FloorPreview = {}

local function computeSelectionCells(grid, anchorX: number, anchorZ: number, currentX: number, currentZ: number)
	local minCellX = math.min(anchorX, currentX)
	local minCellZ = math.min(anchorZ, currentZ)
	local maxCellX = math.max(anchorX, currentX)
	local maxCellZ = math.max(anchorZ, currentZ)
	local width = maxCellX - minCellX + 1
	local depth = maxCellZ - minCellZ + 1
	local totalCells = width * depth
	local indices = table.create(totalCells)
	local index = 0

	for cellZ = minCellZ, maxCellZ do
		local rowOffset = (cellZ - 1) * grid.Columns
		for cellX = minCellX, maxCellX do
			index += 1
			indices[index] = rowOffset + cellX
		end
	end

	return indices, minCellX, minCellZ, maxCellX, maxCellZ, totalCells
end

local function isSelectionUnlocked(
	grid,
	chunkSize: number,
	minCellX: number,
	minCellZ: number,
	maxCellX: number,
	maxCellZ: number,
	isChunkUnlocked
)
	local selectionWidth = maxCellX - minCellX + 1
	local selectionDepth = maxCellZ - minCellZ + 1
	local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
		grid:FootprintChunkRange(minCellX, minCellZ, selectionWidth, selectionDepth, "North", chunkSize)
	for chunkZ = minChunkZ, maxChunkZ do
		for chunkX = minChunkX, maxChunkX do
			if not isChunkUnlocked(chunkX, chunkZ) then
				return false
			end
		end
	end
	return true
end

function FloorPreview.Prepare(model: Model, baseWidthCells: number, baseDepthCells: number)
	previewPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if previewPart then
		previewBaseSize = previewPart.Size
	else
		previewBaseSize = nil
	end
	previewBaseWidthCells = baseWidthCells
	previewBaseDepthCells = baseDepthCells
end

function FloorPreview.ReleasePreviewPart()
	previewPart = nil
	previewBaseSize = nil
	previewBaseWidthCells = 1
	previewBaseDepthCells = 1
end

function FloorPreview.Clear()
	selectionActive = false
	anchorCellX = nil
	anchorCellZ = nil
	currentSummary = nil
	if previewPart and previewBaseSize then
		previewPart.Size = previewBaseSize
	end
end

function FloorPreview.SetPlacementHandler(handler: ((FloorSelectionInfo) -> ())?)
	placementHandler = handler
end

function FloorPreview.GetPlacementHandler(): ((FloorSelectionInfo) -> ())?
	return placementHandler
end

function FloorPreview.TryBeginDrag(
	currentKind: string,
	currentItemId: string?,
	cellX: number?,
	cellZ: number?,
	isMousePressed: boolean
): boolean
	if currentKind ~= "Floor" then
		return false
	end
	if selectionActive then
		return true
	end
	if not currentItemId or not cellX or not cellZ then
		return false
	end
	if not isMousePressed then
		return false
	end

	anchorCellX = cellX
	anchorCellZ = cellZ
	selectionActive = true
	return true
end

function FloorPreview.IsDragInProgress(): boolean
	return selectionActive
end

function FloorPreview.GetSelectionSummary(): FloorSelectionInfo?
	return currentSummary
end

function FloorPreview.Update(args: FloorUpdateArgs): FloorUpdateResult?
	local model = args.model
	if not model then
		return
	end

	local resolvedLevel = if typeof(args.level) == "number" then args.level else 0
	local levelHeight = if typeof(args.levelHeight) == "number" then args.levelHeight else 0

	local anchorX = anchorCellX or args.cellX
	local anchorZ = anchorCellZ or args.cellZ
	local targetCellX = args.cellX
	local targetCellZ = args.cellZ

	local ignorePlacement = args.ignorePlacement
	if ignorePlacement and ignorePlacement.PlacementType == "Floor" then
		local moveWidth = ignorePlacement.WidthCells
		local moveDepth = ignorePlacement.DepthCells
		if typeof(moveWidth) == "number" and moveWidth > 0 and typeof(moveDepth) == "number" and moveDepth > 0 then
			anchorX = args.cellX
			anchorZ = args.cellZ
			targetCellX = anchorX + moveWidth - 1
			targetCellZ = anchorZ + moveDepth - 1
		end
	end

	local indices, minCellX, minCellZ, maxCellX, maxCellZ, cellCount =
		computeSelectionCells(args.grid, anchorX, anchorZ, targetCellX, targetCellZ)
	local selectionWidthCells = maxCellX - minCellX + 1
	local selectionDepthCells = maxCellZ - minCellZ + 1

	Renderer.PreviewFloor(
		model,
		args.grid,
		args.surface,
		minCellX,
		minCellZ,
		selectionWidthCells,
		selectionDepthCells,
		"North",
		levelHeight
	)

	local areaUnlocked =
		isSelectionUnlocked(args.grid, args.chunkSize, minCellX, minCellZ, maxCellX, maxCellZ, args.isChunkUnlocked)
	PlacementUtils.PopulateCellMapForType(args.grid, args.placed, "Floor", floorCellMap, ignorePlacement, resolvedLevel)

	local occupied = false
	for _, index in indices do
		if floorCellMap[index] then
			occupied = true
			break
		end
	end

	-- Check if there's a roof at the level below that would conflict
	local roofBelowConflict = false
	if resolvedLevel > 0 then
		local levelBelow = resolvedLevel - 1
		local roofCellMapBelow: { [number]: boolean } = {}
		PlacementUtils.PopulateCellMapForType(
			args.grid,
			args.placed,
			"Roof",
			roofCellMapBelow,
			ignorePlacement,
			levelBelow
		)
		for _, index in indices do
			if roofCellMapBelow[index] then
				roofBelowConflict = true
				break
			end
		end
	end

	local selectionTooLarge = cellCount > MAX_FLOOR_SELECTION_CELLS
	local canPlace = areaUnlocked and not occupied and not roofBelowConflict and not selectionTooLarge

	if previewPart and previewBaseSize then
		local widthScale = selectionWidthCells / math.max(previewBaseWidthCells, 1)
		local depthScale = selectionDepthCells / math.max(previewBaseDepthCells, 1)
		previewPart.Size =
			Vector3.new(previewBaseSize.X * widthScale, previewBaseSize.Y, previewBaseSize.Z * depthScale)
	end

	currentSummary = {
		ItemId = args.itemId,
		AnchorCellX = anchorX,
		AnchorCellZ = anchorZ,
		CurrentCellX = args.cellX,
		CurrentCellZ = args.cellZ,
		MinCellX = minCellX,
		MinCellZ = minCellZ,
		MaxCellX = maxCellX,
		MaxCellZ = maxCellZ,
		CellCount = cellCount,
		WidthCells = selectionWidthCells,
		DepthCells = selectionDepthCells,
		CanPlace = canPlace,
		Level = resolvedLevel,
	}

	local fillColor = if canPlace then PLACEABLE_FILL else BLOCKED_FILL
	local outlineColor = if canPlace then PLACEABLE_OUTLINE else BLOCKED_OUTLINE

	local summary = currentSummary
	if not summary then
		return
	end

	return {
		canPlace = canPlace,
		fillColor = fillColor,
		outlineColor = outlineColor,
		summary = summary,
	}
end

return FloorPreview
