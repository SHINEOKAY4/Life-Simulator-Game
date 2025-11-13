--!strict

local PlacementUtils = require(script.Parent.PlacementUtils)
local Renderer = require(script.Parent.Renderer)
local PlotStateStore = require(script.Parent.Parent.Parent.ClientStores.PlotStateStore)

type Facing = string
export type RoofSelectionInfo = {
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
	Level: number?,
}

export type RoofUpdateResult = {
	canPlace: boolean,
	fillColor: Color3,
	outlineColor: Color3,
	summary: RoofSelectionInfo,
}

type MoveOriginInfo = PlacementUtils.MoveOriginInfo

type RoofUpdateArgs = {
	model: Model,
	grid: any,
	surface: BasePart,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	itemId: string?,
	spec: any?,
	placed: any,
	ignorePlacement: MoveOriginInfo?,
	isChunkUnlocked: (number, number) -> boolean,
	level: number?,
}

local MAX_ROOF_SELECTION_CELLS = 256

local selectionActive = false
local anchorCellX: number? = nil
local anchorCellZ: number? = nil
local currentSummary: RoofSelectionInfo? = nil
local placementHandler: ((RoofSelectionInfo) -> ())? = nil

local previewPart: BasePart? = nil
local previewBaseSize: Vector3? = nil
local previewBaseWidthCells = 1
local previewBaseDepthCells = 1

local roofCellMap: { [number]: boolean } = {}
local floorCellMap: { [number]: boolean } = {}

local PLACEABLE_FILL = Color3.fromRGB(159, 234, 159)
local PLACEABLE_OUTLINE = Color3.fromRGB(137, 255, 119)
local BLOCKED_FILL = Color3.fromRGB(219, 136, 136)
local BLOCKED_OUTLINE = Color3.fromRGB(255, 85, 85)

local RoofPreview = {}

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

function RoofPreview.Prepare(model: Model, baseWidthCells: number, baseDepthCells: number)
	previewPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
	if previewPart then
		previewBaseSize = previewPart.Size
	else
		previewBaseSize = nil
	end
	previewBaseWidthCells = baseWidthCells
	previewBaseDepthCells = baseDepthCells
end

function RoofPreview.ReleasePreviewPart()
	previewPart = nil
	previewBaseSize = nil
	previewBaseWidthCells = 1
	previewBaseDepthCells = 1
end

function RoofPreview.Clear()
	selectionActive = false
	anchorCellX = nil
	anchorCellZ = nil
	currentSummary = nil
	if previewPart and previewBaseSize then
		previewPart.Size = previewBaseSize
	end
end

function RoofPreview.SetPlacementHandler(handler: ((RoofSelectionInfo) -> ())?)
	placementHandler = handler
end

function RoofPreview.GetPlacementHandler(): ((RoofSelectionInfo) -> ())?
	return placementHandler
end

function RoofPreview.TryBeginDrag(
	currentKind: string,
	currentItemId: string?,
	cellX: number?,
	cellZ: number?,
	isMousePressed: boolean
): boolean
	if currentKind ~= "Roof" then
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

function RoofPreview.IsDragInProgress(): boolean
	return selectionActive
end

function RoofPreview.GetSelectionSummary(): RoofSelectionInfo?
	return currentSummary
end

function RoofPreview.Update(args: RoofUpdateArgs): RoofUpdateResult?
	local model = args.model
	if not model then
		return
	end

	local anchorX = anchorCellX or args.cellX
	local anchorZ = anchorCellZ or args.cellZ
	local targetCellX = args.cellX
	local targetCellZ = args.cellZ

	local ignorePlacement = args.ignorePlacement
	if ignorePlacement and ignorePlacement.PlacementType == "Roof" then
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

	local resolvedLevel = if typeof(args.level) == "number" then args.level else PlotStateStore.GetActiveLevel()
	local levelHeight = PlotStateStore.GetLevelHeight(resolvedLevel)

	Renderer.PreviewRoof(
		model,
		args.grid,
		args.surface,
		minCellX,
		minCellZ,
		selectionWidthCells,
		selectionDepthCells,
		"North",
		levelHeight,
		args.spec
	)

	local areaUnlocked =
		isSelectionUnlocked(args.grid, args.chunkSize, minCellX, minCellZ, maxCellX, maxCellZ, args.isChunkUnlocked)

	PlacementUtils.PopulateCellMapForType(args.grid, args.placed, "Roof", roofCellMap, ignorePlacement, resolvedLevel)

	local roofOccupied = false
	for _, index in indices do
		if roofCellMap[index] then
			roofOccupied = true
			break
		end
	end

	local missingFloorSupport = false
	if args.spec and args.spec.Rules and args.spec.Rules.RequiresFloorUnderAllCells then
		PlacementUtils.PopulateCellMapForType(
			args.grid,
			args.placed,
			"Floor",
			floorCellMap,
			ignorePlacement,
			resolvedLevel
		)
		for _, index in indices do
			if not floorCellMap[index] then
				missingFloorSupport = true
				break
			end
		end
	end

	local selectionTooLarge = cellCount > MAX_ROOF_SELECTION_CELLS
	local canPlace = areaUnlocked and not roofOccupied and not missingFloorSupport and not selectionTooLarge

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

return RoofPreview
