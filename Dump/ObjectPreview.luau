--!strict
-- StarterPlayerScripts/Client/Modules/ObjectPreview.lua

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local PreviewContext = InputContextsFolder:WaitForChild("PreviewContext")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local PreviewHighlight = AssetsFolder.VisualTools:WaitForChild("PreviewHighlight") :: Highlight

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local objectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled")

local Camera = workspace.CurrentCamera

local ObjectPreview = {}

local Connection: RBXScriptConnection? = nil

local SelectedItem: Model? = nil
local CurrentItemId: string? = nil
local CurrentItemSpec: any? = nil
export type Facing = PlacementHelpers.Facing
type PreviewKind = "CellObject" | "Floor" | "Wall" | "Roof"
type PreviewPose = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: Facing,
	Kind: PreviewKind,
}

type MoveOriginInfo = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: Facing,
	PlacementType: string,
}

local CurrentKind: PreviewKind = "CellObject"

local CurrentFacing: Facing = "North"

local LastCellX: number? = nil
local LastCellZ: number? = nil
local LastFacing: string? = nil

local CurrentPivotRotation: CFrame = CFrame.identity

local MoveOriginSignature: MoveOriginInfo? = nil
local MoveHoldActive = false
local MoveHoldMousePosition: Vector2? = nil
local MOUSE_MOVE_RELEASE_THRESHOLD = 2

-- Pool of thin Parts used to highlight the footprint cells the preview will occupy.
local CellMarkers: { BasePart } = {}
local ActiveMarkerCount = 0
local MARKER_Y = 0.08 -- Lift markers slightly above the surface to avoid z-fighting for tall previews.
local FLOOR_MARKER_Y = -0.02 -- Sink floor markers slightly so thin floor meshes stay visible.

type FloorSelectionInfo = {
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
}

local MAX_FLOOR_SELECTION_CELLS = 256
local FloorSelectionActive = false
local FloorSelectionAnchorX: number? = nil
local FloorSelectionAnchorZ: number? = nil
local CurrentFloorSelection: FloorSelectionInfo? = nil
local FloorPlacementHandler: ((FloorSelectionInfo) -> ())? = nil
local FloorPreviewPart: BasePart? = nil
local FloorPreviewBaseSize: Vector3? = nil
local FloorPreviewBaseWidthCells = 1
local FloorPreviewBaseDepthCells = 1
type EdgeKind = "Wall" | "Interior"

local EDGE_KIND_WALL: EdgeKind = "Wall"
local EDGE_KIND_INTERIOR: EdgeKind = "Interior"

local HorizontalWallEdges: { [string]: EdgeKind } = {}
local VerticalWallEdges: { [string]: EdgeKind } = {}

local function EdgeKey(edgeX: number, edgeZ: number): string
	return string.format("%d:%d", edgeX, edgeZ)
end

local function setEdgeOccupied(alignment: "Horizontal" | "Vertical", key: string, kind: EdgeKind)
	if alignment == "Horizontal" then
		HorizontalWallEdges[key] = kind
	else
		VerticalWallEdges[key] = kind
	end
end

local function clearFloorSelectionState(keepSummary: boolean?)
	FloorSelectionActive = false
	FloorSelectionAnchorX = nil
	FloorSelectionAnchorZ = nil
	if not keepSummary then
		CurrentFloorSelection = nil
	end
	local part = FloorPreviewPart
	local baseSize = FloorPreviewBaseSize
	if part and baseSize then
		part.Size = baseSize
	end
end

local function computeFloorSelectionCells(
	grid,
	anchorX: number,
	anchorZ: number,
	currentX: number,
	currentZ: number
): ({ number }, number, number, number, number, number)
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
	maxCellZ: number
): boolean
	local selectionWidth = maxCellX - minCellX + 1
	local selectionDepth = maxCellZ - minCellZ + 1
	local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
		grid:FootprintChunkRange(minCellX, minCellZ, selectionWidth, selectionDepth, "North", chunkSize)
	for chunkZ = minChunkZ, maxChunkZ do
		for chunkX = minChunkX, maxChunkX do
			if not PlotStateStore.IsChunkUnlocked(chunkX, chunkZ) then
				return false
			end
		end
	end
	return true
end

local function BuildMarker(cellSize: number, parent: Instance): BasePart
	local markerPart = Instance.new("Part")
	markerPart.Name = "CellPreviewMarker"
	markerPart.Anchored = true
	markerPart.CanCollide = false
	markerPart.CanTouch = false
	markerPart.CanQuery = false
	markerPart.Material = Enum.Material.Pavement
	markerPart.Size = Vector3.new(cellSize, 0.05, cellSize)
	markerPart.Transparency = 1
	markerPart.Color = Color3.fromRGB(159, 234, 159)
	markerPart.TopSurface = Enum.SurfaceType.Smooth
	markerPart.BottomSurface = Enum.SurfaceType.Smooth
	markerPart.Parent = parent
	return markerPart
end

local function AcquireMarker(cellSize: number, parent: Instance): BasePart
	ActiveMarkerCount += 1
	if ActiveMarkerCount <= #CellMarkers then
		local marker = CellMarkers[ActiveMarkerCount]
		-- Resize if the cell size changed (different plots or settings).
		if math.abs(marker.Size.X - cellSize) > 1e-3 then
			marker.Size = Vector3.new(cellSize, 0.05, cellSize)
		end
		if marker.Parent ~= parent then
			marker.Parent = parent
		end
		marker.Transparency = 0.8
		return marker
	end
	local marker = BuildMarker(cellSize, parent)
	table.insert(CellMarkers, marker)
	return marker
end

local function HideUnusedMarkers()
	for i = ActiveMarkerCount + 1, #CellMarkers do
		local marker = CellMarkers[i]
		if marker.Transparency ~= 1 then
			marker.Transparency = 1
		end
	end
end

local function RenderFootprintMarkers(
	grid,
	surface: BasePart,
	cells: { number },
	canPlace: boolean,
	previewKind: PreviewKind
)
	-- Parent markers next to the previewed model (the plot container keeps things tidy).
	local plotModel = surface.Parent :: Model
	local container = plotModel:FindFirstChild("Container") :: Folder
	if not container then
		return
	end

	local cellSize = grid.CellSize
	local placeableColor = Color3.fromRGB(159, 234, 159)
	local blockedColor = Color3.fromRGB(219, 136, 136)
	local markerColor = canPlace and placeableColor or blockedColor

	for i = 1, #cells do
		local cellXIndex, cellZIndex = grid:IndexToCell(cells[i]) -- Convert index back to cell coordinates.
		-- Acquire or create a pooled marker.
		local marker = AcquireMarker(cellSize, container)

		-- Position at the cell center, aligned to the plot surface, with a tiny Y lift to avoid z-fighting.
		local center = grid:CellToWorldCenterCFrame(cellXIndex, cellZIndex)
		local aligned =
			CFrame.lookAt(center.Position, center.Position + surface.CFrame.LookVector, surface.CFrame.UpVector)
		local markerYOffset = if previewKind == "Floor" then FLOOR_MARKER_Y else MARKER_Y
		marker.CFrame = aligned * CFrame.new(0, markerYOffset, 0)

		-- Color based on overall validity for this footprint.
		marker.Color = markerColor
		marker.Transparency = 0.2
		marker.Material = Enum.Material.Glass
	end

	-- Hide any unused markers this frame.
	HideUnusedMarkers()
end

local YawFromFacing = PlacementHelpers.GetYawFromFacing
local GetFlatAlignedCFrame = PlacementHelpers.GetFlatAlignedCFrame
local GetRotationOnly = PlacementHelpers.GetRotation
local GetPivotRotation = PlacementHelpers.GetPivotRotation
local GetLiftAlongDirection = PlacementHelpers.GetLiftAlongDirection

local function AnyCellOverlap(firstCells: { number }, secondCells: { number }): boolean
	-- Cell footprints are tiny, so a nested loop is sufficient here.
	for i = 1, #firstCells do
		local firstCellIndex = firstCells[i]
		for j = 1, #secondCells do
			if firstCellIndex == secondCells[j] then
				return true
			end
		end
	end
	return false
end

local function ResolvePlacementEntry(entry: any): (any?, string, number, number, Facing)
	local itemId = entry.id or entry.Id or entry.ItemId
	local itemSpec = if itemId then ItemFinder.FindItemById(itemId) else nil
	local placementType = (itemSpec and (itemSpec.PlacementType or itemSpec.Type)) or "CellObject"
	local metadata = entry.Metadata
	local width = entry.width or entry.Width or entry.widthCells or entry.WidthCells
	if metadata then
		width = width or metadata.WidthCells or metadata.widthCells or metadata.Width or metadata.width
	end
	local depth = entry.depth or entry.Depth or entry.depthCells or entry.DepthCells
	if metadata then
		depth = depth or metadata.DepthCells or metadata.depthCells or metadata.Depth or metadata.depth
	end
	local facing = entry.facing or entry.Facing or "North"

	if placementType == "Floor" then
		local specWidth = itemSpec and (itemSpec.WidthCells or itemSpec.Width)
		local specDepth = itemSpec and (itemSpec.DepthCells or itemSpec.Depth)
		width = width or specWidth
		depth = depth or specDepth
		facing = "North"
	elseif placementType == "Wall" then
		width, depth = 1, 1
	else
		local specWidth = itemSpec and (itemSpec.WidthCells or itemSpec.Width)
		local specDepth = itemSpec and (itemSpec.DepthCells or itemSpec.Depth)
		width = width or specWidth
		depth = depth or specDepth
	end

	width = width or 1
	depth = depth or 1

	return itemSpec, placementType, width, depth, facing :: Facing
end

local FloorCellMap: { [number]: boolean } = {}

local function PopulateCellMapForType(grid, placed, placementType: string, target: { [number]: boolean })
	table.clear(target)
	if not placed then
		return target
	end

	for _, placedEntry in pairs(placed) do
		local _, entryPlacementType, width, depth, facing = ResolvePlacementEntry(placedEntry)
		if entryPlacementType == placementType then
			local cells = grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, facing)
			for j = 1, #cells do
				target[cells[j]] = true
			end
		end
	end

	return target
end

local function EdgeOfCell(cellX: number, cellZ: number, facing: Facing): ("Horizontal" | "Vertical", number, number)
	if facing == "North" then
		return "Horizontal", cellX, cellZ
	elseif facing == "South" then
		return "Horizontal", cellX, cellZ + 1
	elseif facing == "West" then
		return "Vertical", cellX, cellZ
	else
		return "Vertical", cellX + 1, cellZ
	end
end

local function matchesIgnorePlacement(entry, placementType: string, facing: Facing, ignorePlacement: MoveOriginInfo?)
	if not ignorePlacement then
		return false
	end

	if placementType ~= ignorePlacement.PlacementType then
		return false
	end

	local normalizedFacing = PlacementKey.NormalizeFacing(facing)
	local ignoreFacing = PlacementKey.NormalizeFacing(ignorePlacement.Facing)
	if normalizedFacing ~= ignoreFacing then
		return false
	end

	if entry.cellX ~= ignorePlacement.CellX or entry.cellZ ~= ignorePlacement.CellZ then
		return false
	end

	local entryId = entry.id or entry.Id or entry.ItemId
	return entryId == ignorePlacement.ItemId
end

local function PopulateWallEdgeMaps(grid, placed, ignorePlacement: MoveOriginInfo?)
	table.clear(HorizontalWallEdges)
	table.clear(VerticalWallEdges)
	if not placed then
		return
	end

	if not grid then
		return
	end

	for _, entry in pairs(placed) do
		local _, placementType, width, depth, facing = ResolvePlacementEntry(entry)
		local entryFacing: Facing = facing :: Facing
		if matchesIgnorePlacement(entry, placementType, entryFacing, ignorePlacement) then
			continue
		end
		if placementType == "Wall" then
			local normalizedFacing: Facing = PlacementKey.NormalizeFacing(entryFacing)
			local alignment, edgeX, edgeZ = EdgeOfCell(entry.cellX, entry.cellZ, normalizedFacing)
			local key = EdgeKey(edgeX, edgeZ)
			setEdgeOccupied(alignment :: "Horizontal" | "Vertical", key, EDGE_KIND_WALL)
		elseif placementType == "CellObject" then
			local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
				grid:FootprintBounds(entry.cellX, entry.cellZ, width, depth, facing)
			local rotatedWidth = maxCellX - minCellX
			local rotatedDepth = maxCellZ - minCellZ

			if rotatedWidth >= 1 then
				for cellZ = minCellZ, maxCellZ do
					for cellX = minCellX, maxCellX - 1 do
						local alignment, edgeX, edgeZ = EdgeOfCell(cellX, cellZ, "East")
						if alignment == "Vertical" then
							local key = EdgeKey(edgeX, edgeZ)
							setEdgeOccupied("Vertical", key, EDGE_KIND_INTERIOR)
						end
					end
				end
			end

			if rotatedDepth >= 1 then
				for cellZ = minCellZ, maxCellZ - 1 do
					for cellX = minCellX, maxCellX do
						local alignment, edgeX, edgeZ = EdgeOfCell(cellX, cellZ, "South")
						if alignment == "Horizontal" then
							local key = EdgeKey(edgeX, edgeZ)
							setEdgeOccupied("Horizontal", key, EDGE_KIND_INTERIOR)
						end
					end
				end
			end
		end
	end
end

local function isCellOccupiedForPreview(
	grid,
	kind: PreviewKind,
	cellX: number,
	cellZ: number,
	baseWidthCells: number,
	baseDepthCells: number,
	facing: Facing,
	placed,
	ignorePlacement: MoveOriginInfo?
): boolean
	if not placed or next(placed) == nil then
		return false
	end

	-- Floor: 1x1, occupied if a floor already exists in the same cell.
	if kind == "Floor" then
		local myCells = grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, "North")
		for _, placedEntry in pairs(placed) do
			local _, placementType, width, depth, otherFacing = ResolvePlacementEntry(placedEntry)
			if
				not (
					ignorePlacement
					and placedEntry.id == ignorePlacement.ItemId
					and placedEntry.cellX == ignorePlacement.CellX
					and placedEntry.cellZ == ignorePlacement.CellZ
					and otherFacing == ignorePlacement.Facing
					and placementType == ignorePlacement.PlacementType
				)
			then
				if placementType == "Floor" then
					local other =
						grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, "North")
					if AnyCellOverlap(myCells, other) then
						return true
					end
				end
			end
		end
		return false
	end

	-- CellObject: blocked by other CellObjects’ occupied cells (floors do not block here).
	if kind == "CellObject" then
		local myCells = grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, facing)
		for _, placedEntry in pairs(placed) do
			local _, placementType, width, depth, otherFacing = ResolvePlacementEntry(placedEntry)
			if
				not (
					ignorePlacement
					and placedEntry.id == ignorePlacement.ItemId
					and placedEntry.cellX == ignorePlacement.CellX
					and placedEntry.cellZ == ignorePlacement.CellZ
					and otherFacing == ignorePlacement.Facing
					and placementType == ignorePlacement.PlacementType
				)
			then
				if placementType == "CellObject" then
					local other =
						grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, otherFacing)
					if AnyCellOverlap(myCells, other) then
						return true
					end
				end
			end
		end
		return false
	end

	if kind == "Roof" then
		local myCells = grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, facing)
		for _, placedEntry in pairs(placed) do
			local _, placementType, width, depth, otherFacing = ResolvePlacementEntry(placedEntry)
			if
				not (
					ignorePlacement
					and placedEntry.id == ignorePlacement.ItemId
					and placedEntry.cellX == ignorePlacement.CellX
					and placedEntry.cellZ == ignorePlacement.CellZ
					and otherFacing == ignorePlacement.Facing
					and placementType == ignorePlacement.PlacementType
				)
			then
				if placementType == "Roof" then
					local other =
						grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, otherFacing)
					if AnyCellOverlap(myCells, other) then
						return true
					end
				end
			end
		end
		return false
	end

	-- Walls do not occupy cells; let the server validate edges.
	return false
end

local function PreviewKindFromItem(itemId: string): PreviewKind
	local item = ItemFinder.FindItemById(itemId)
	local itemType = item and item.PlacementType or "CellObject"

	if itemType == "Floor" then
		return "Floor"
	elseif itemType == "Wall" then
		return "Wall"
	elseif itemType == "Roof" then
		return "Roof"
	else
		return "CellObject"
	end
end

local function GetItemFootprintCells(itemId: string): (number, number)
	local item = ItemFinder.FindItemById(itemId)
	local widthCells = item and item.WidthCells or 1
	local depthCells = item and item.DepthCells or 1
	return widthCells, depthCells
end

local function AlignToSurface(base: CFrame, surface: BasePart): CFrame
	return CFrame.lookAt(base.Position, base.Position + surface.CFrame.LookVector, surface.CFrame.UpVector)
end

local function IsFootprintUnlocked(
	grid: any,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): boolean
	local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
		grid:FootprintChunkRange(cellX, cellZ, widthCells, depthCells, facing, chunkSize)
	for cz = minChunkZ, maxChunkZ do
		for cx = minChunkX, maxChunkX do
			if not PlotStateStore.IsChunkUnlocked(cx, cz) then
				return false
			end
		end
	end
	return true
end

local function PreviewWall(model: Model, grid: any, cellX: number, cellZ: number, facing: Facing, lift: number)
	local edgeCFrame = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing)
	model:PivotTo(edgeCFrame * CFrame.new(0, lift, 0))
end

local function PreviewFloor(
	model: Model,
	grid,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
)
	local center = grid:FootprintCenterCFrame(cellX, cellZ, widthCells, depthCells, facing)
	local alignedCFrame = AlignToSurface(center, surface)
	model:PivotTo(alignedCFrame)
end

local function PreviewRoof(
	model: Model,
	grid,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	facing: Facing,
	lift: number
)
	-- Roof sits slightly higher than walls and floors.
	local base = grid:CellToWorldCenterCFrame(cellX, cellZ, lift)
	local aligned = AlignToSurface(base, surface)
	local yaw = CFrame.Angles(0, YawFromFacing(facing), 0)
	model:PivotTo(aligned * yaw)
end

-- Preview a CellObject footprint so the mesh aligns with highlighted cells.
local function PreviewCellObject(
	model: Model,
	grid: any,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	facing: Facing,
	widthCells: number,
	depthCells: number,
	lift: number,
	pivotRotation: CFrame
)
	-- Anchor the preview at the geometric center of the rotated footprint so meshes cover all highlighted cells.
	local center = grid:FootprintCenterCFrame(cellX, cellZ, widthCells, depthCells, facing)
	local flatAligned = GetFlatAlignedCFrame(surface, center.Position)
	local baseRotation = GetRotationOnly(flatAligned)
	local yaw = CFrame.Angles(0, YawFromFacing(facing), 0)
	local orientation = baseRotation * yaw * pivotRotation
	local surfaceUp = surface.CFrame.UpVector
	local liftedPosition = center.Position + surfaceUp * lift

	model:PivotTo(CFrame.new(liftedPosition) * orientation)
end

function ObjectPreview.Init()
	-- Initialize the object preview.

	local order: { Facing } = { "North", "East", "South", "West" }
	local indexOf: { [Facing]: number } = { North = 1, East = 2, South = 3, West = 4 }

	PreviewContext.RotateLeft.Pressed:Connect(function()
		local i = indexOf[CurrentFacing] or 1
		i = i % 4 + 1 -- 1->2->3->4->1
		CurrentFacing = order[i]
		LastFacing = nil
	end)

	PreviewContext.RotateRight.Pressed:Connect(function()
		local i = indexOf[CurrentFacing] or 1
		i = (i - 2) % 4 + 1 -- 1->4->3->2->1
		CurrentFacing = order[i]
		LastFacing = nil
	end)

	PreviewContext.CancelPreview.Pressed:Connect(function()
		ObjectPreview.ClearPreview()
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		if not FloorSelectionActive then
			return
		end
		local summary = CurrentFloorSelection
		clearFloorSelectionState()
		if not summary or not summary.ItemId then
			return
		end
		if FloorPlacementHandler and summary.CanPlace then
			FloorPlacementHandler(summary)
		end
	end)
end

function ObjectPreview.RenderPreview(itemId: string, initialFacing: Facing?)
	ObjectPreview.ClearPreview()

	local sourceModel = ItemFinder.ResolveItemModel(itemId)
	if not sourceModel then
		warn("Item model not found for ID: " .. itemId)
		return
	end

	CurrentItemSpec = ItemFinder.FindItemById(itemId)

	if not PlotStateStore.IsReady() then
		warn("PlotStateStore is not ready.")
		return
	end

	local grid = PlotStateStore.GetGrid()
	local surface = PlotStateStore.GetSurface()

	if not grid or not surface then
		warn("Plot grid or surface not available.")
		return
	end

	local plotParent = surface.Parent
	if not plotParent or not plotParent:IsA("Model") then
		warn("Plot surface parent is missing or not a Model.")
		return
	end

	local plotModel = plotParent :: Model
	local containerFolder = plotModel:FindFirstChild("Container") :: Folder?
	if not containerFolder then
		warn("Plot container not found for preview.")
		return
	end

	-- Prepare a simple, safe preview clone.
	local itemModel = sourceModel:Clone()

	CurrentPivotRotation = GetPivotRotation(itemModel)
	local surfaceUp = surface.CFrame.UpVector
	local extraLift = 0
	if typeof(CurrentItemSpec) == "table" then
		local offset = CurrentItemSpec.SurfaceOffsetStuds
		if typeof(offset) == "number" then
			extraLift = offset
		end
	end
	local lift = GetLiftAlongDirection(itemModel, surfaceUp) + extraLift
	local chunkSize = PlotStateStore.GetStateSnapshot().ChunkInfo.ChunkSizeInCells
	PreviewHighlight.Adornee = itemModel

	itemModel.Parent = containerFolder
	SelectedItem = itemModel

	objectPreviewEnabled.Value = true
	PreviewContext.CancelPreview.Enabled = true

	for _, part in itemModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end
	-- Only raycast against the plot surface.
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { surface }
	raycastParams.IgnoreWater = true

	CurrentFacing = initialFacing or "North"

	local previewKind: PreviewKind = PreviewKindFromItem(itemId)
	local baseWidthCells, baseDepthCells = GetItemFootprintCells(itemId)

	CurrentItemId = itemId
	CurrentKind = previewKind

	if previewKind == "Floor" then
		FloorPreviewPart = itemModel.PrimaryPart or itemModel:FindFirstChildWhichIsA("BasePart", true)
		if FloorPreviewPart then
			FloorPreviewBaseSize = FloorPreviewPart.Size
			FloorPreviewBaseWidthCells = baseWidthCells
			FloorPreviewBaseDepthCells = baseDepthCells
		else
			FloorPreviewBaseSize = nil
		end
	else
		FloorPreviewPart = nil
		FloorPreviewBaseSize = nil
		FloorPreviewBaseWidthCells = baseWidthCells
		FloorPreviewBaseDepthCells = baseDepthCells
	end

	PreviewContext.RotateLeft.Enabled = (previewKind ~= "Floor")
	PreviewContext.RotateRight.Enabled = (previewKind ~= "Floor")

	Connection = RunService.PreRender:Connect(function()
		local model = SelectedItem
		if not model then
			return
		end

		-- Cast a ray from the current mouse position.
		local mouse = UserInputService:GetMouseLocation()
		if MoveHoldActive then
			local originalMousePosition = MoveHoldMousePosition
			if originalMousePosition then
				if (mouse - originalMousePosition).Magnitude > MOUSE_MOVE_RELEASE_THRESHOLD then
					MoveHoldActive = false
					MoveHoldMousePosition = nil
				end
			else
				MoveHoldMousePosition = mouse
			end
		end
		local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)

		local result = Workspace:Raycast(ray.Origin, ray.Direction * 2048, raycastParams)
		if not result then
			return
		end

		local isInside, cellX, cellZ = grid:WorldPointToCell(result.Position)
		if not isInside then
			cellX, cellZ = grid:WorldPointToClampedCell(result.Position)
		end

		local originSignature = MoveOriginSignature
		if MoveHoldActive then
			if originSignature and originSignature.CellX ~= nil and originSignature.CellZ ~= nil then
				cellX = originSignature.CellX
				cellZ = originSignature.CellZ
			else
				MoveHoldActive = false
				MoveHoldMousePosition = nil
			end
		end

		if LastCellX == cellX and LastCellZ == cellZ and LastFacing == CurrentFacing then
			return
		end

		LastCellX, LastCellZ, LastFacing = cellX, cellZ, CurrentFacing

		local snapshot = PlotStateStore.GetStateSnapshot()
		local placed = snapshot.PlacedItems

		local ignorePlacement: MoveOriginInfo? = nil
		if MoveOriginSignature ~= nil and CurrentItemId == MoveOriginSignature.ItemId then
			ignorePlacement = MoveOriginSignature
		end

		if previewKind == "Floor" then
			ActiveMarkerCount = 0

			local anchorX = FloorSelectionAnchorX or cellX
			local anchorZ = FloorSelectionAnchorZ or cellZ
			local indices, minCellX, minCellZ, maxCellX, maxCellZ, cellCount =
				computeFloorSelectionCells(grid, anchorX, anchorZ, cellX, cellZ)
			local selectionWidthCells = maxCellX - minCellX + 1
			local selectionDepthCells = maxCellZ - minCellZ + 1

			PreviewFloor(model, grid, surface, minCellX, minCellZ, selectionWidthCells, selectionDepthCells, "North")

			local areaUnlocked = isSelectionUnlocked(grid, chunkSize, minCellX, minCellZ, maxCellX, maxCellZ)
			PopulateCellMapForType(grid, placed, "Floor", FloorCellMap)
			if ignorePlacement and ignorePlacement.PlacementType == "Floor" then
				local ignoreIndex = grid:CellToIndex(ignorePlacement.CellX, ignorePlacement.CellZ)
				FloorCellMap[ignoreIndex] = nil
			end

			local occupied = false
			for i = 1, #indices do
				if FloorCellMap[indices[i]] then
					occupied = true
					break
				end
			end

			local selectionTooLarge = cellCount > MAX_FLOOR_SELECTION_CELLS
			local canPlaceFloor = areaUnlocked and not occupied and not selectionTooLarge

			local part = FloorPreviewPart
			local baseSize = FloorPreviewBaseSize
			if part and baseSize then
				local widthScale = selectionWidthCells / math.max(FloorPreviewBaseWidthCells, 1)
				local depthScale = selectionDepthCells / math.max(FloorPreviewBaseDepthCells, 1)
				part.Size = Vector3.new(baseSize.X * widthScale, baseSize.Y, baseSize.Z * depthScale)
			end

			CurrentFloorSelection = {
				ItemId = CurrentItemId,
				AnchorCellX = anchorX,
				AnchorCellZ = anchorZ,
				CurrentCellX = cellX,
				CurrentCellZ = cellZ,
				MinCellX = minCellX,
				MinCellZ = minCellZ,
				MaxCellX = maxCellX,
				MaxCellZ = maxCellZ,
				CellCount = cellCount,
				CanPlace = canPlaceFloor,
				WidthCells = selectionWidthCells,
				DepthCells = selectionDepthCells,
			}

			PreviewHighlight.FillColor = canPlaceFloor and Color3.fromRGB(159, 234, 159)
				or Color3.fromRGB(219, 136, 136)
			PreviewHighlight.OutlineColor = canPlaceFloor and Color3.fromRGB(137, 255, 119)
				or Color3.fromRGB(255, 85, 85)

			return
		end

		local isUnlocked =
			IsFootprintUnlocked(grid, chunkSize, cellX, cellZ, baseWidthCells, baseDepthCells, CurrentFacing)

		local blocked = isCellOccupiedForPreview(
			grid,
			previewKind,
			cellX,
			cellZ,
			baseWidthCells,
			baseDepthCells,
			CurrentFacing,
			placed,
			ignorePlacement
		)

		local wallEdgeOccupant: EdgeKind? = nil
		if previewKind == "Wall" then
			PopulateWallEdgeMaps(grid, placed, ignorePlacement)
			local alignment, edgeX, edgeZ = EdgeOfCell(cellX, cellZ, CurrentFacing)
			local edgeKey = EdgeKey(edgeX, edgeZ)
			if alignment == "Horizontal" then
				wallEdgeOccupant = HorizontalWallEdges[edgeKey]
			else
				wallEdgeOccupant = VerticalWallEdges[edgeKey]
			end
			if wallEdgeOccupant == EDGE_KIND_INTERIOR then
				blocked = true
			end
		end

		if previewKind == "Wall" then
			local spec = CurrentItemSpec
			if spec and spec.RequiresExistingWall then
				local placementKey = PlacementKey.ForPlacementType(cellX, cellZ, CurrentFacing, "Wall")
				local occupant = placed and placed[placementKey]
				if not occupant then
					blocked = true
				else
					local occupantMatchesOrigin = false
					if ignorePlacement then
						local sameId = occupant.id == ignorePlacement.ItemId
						local sameCell = occupant.cellX == ignorePlacement.CellX
							and occupant.cellZ == ignorePlacement.CellZ
						local sameFacing = PlacementKey.NormalizeFacing(occupant.facing) == ignorePlacement.Facing
						occupantMatchesOrigin = sameId and sameCell and sameFacing
					end

					if occupantMatchesOrigin then
						blocked = false
					else
						local replaceableTag = spec.ReplaceableWallTag
						local occupantCheckId = occupant.id
						local occupantSpec = occupantCheckId and ItemFinder.FindItemById(occupantCheckId) or nil
						if occupantSpec and occupantSpec.RequiresExistingWall == true then
							local maybePreviousId = occupant.Metadata and occupant.Metadata.PreviousId
							if typeof(maybePreviousId) == "string" and maybePreviousId ~= "" then
								occupantCheckId = maybePreviousId
								occupantSpec = ItemFinder.FindItemById(maybePreviousId)
							end
						end

						local canReplace = occupantSpec ~= nil and occupantSpec.PlacementType == "Wall"
						if canReplace and replaceableTag then
							canReplace = ItemFinder.HasTag(occupantCheckId, replaceableTag)
						end
						if not canReplace then
							blocked = true
						end
					end
				end
			end
		end

		if previewKind == "Wall" then
			local spec = CurrentItemSpec
			if (not spec or spec.RequiresExistingWall ~= true) and wallEdgeOccupant == EDGE_KIND_WALL then
				blocked = true
			end
		end

		if previewKind == "Wall" then
			PreviewWall(model, grid, cellX, cellZ, CurrentFacing, lift)
		elseif previewKind == "Roof" then
			local itemSpec = CurrentItemSpec
			local height = itemSpec and itemSpec.HeightStuds or 12
			PreviewRoof(model, grid, surface, cellX, cellZ, CurrentFacing, height)
		else
			PreviewCellObject(
				model,
				grid,
				surface,
				cellX,
				cellZ,
				CurrentFacing,
				baseWidthCells,
				baseDepthCells,
				lift,
				CurrentPivotRotation
			)
		end

		local requiresFloor = false
		if previewKind == "Roof" then
			local itemSpec = CurrentItemSpec
			requiresFloor = itemSpec ~= nil
				and itemSpec.Rules ~= nil
				and itemSpec.Rules.RequiresFloorUnderAllCells == true
		end

		local missingFloorSupport = false
		local cells: { number }
		local canPlace = isUnlocked and not blocked

		ActiveMarkerCount = 0

		if previewKind == "Wall" then
			-- Walls occupy a single anchor cell edge; treat as 1x1 for overlay markers and clamp to bounds.
			cells = grid:ClippedFootprintCells(cellX, cellZ, 1, 1, CurrentFacing)
		else
			-- CellObject uses its (possibly rotated) footprint.
			cells = grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, CurrentFacing)
		end

		if previewKind == "CellObject" and not blocked then
			local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
				grid:FootprintBounds(cellX, cellZ, baseWidthCells, baseDepthCells, CurrentFacing)
			local rotatedWidth = maxCellX - minCellX + 1
			local rotatedDepth = maxCellZ - minCellZ + 1

			if rotatedWidth > 1 or rotatedDepth > 1 then
				PopulateWallEdgeMaps(grid, placed, ignorePlacement)

				if rotatedWidth > 1 then
					for z = minCellZ, maxCellZ do
						for x = minCellX, maxCellX - 1 do
							local alignment, edgeX, edgeZ = EdgeOfCell(x, z, "East")
							if alignment == "Vertical" then
								local key = EdgeKey(edgeX, edgeZ)
								if VerticalWallEdges[key] then
									blocked = true
									break
								end
							end
						end
						if blocked then
							break
						end
					end
				end

				if not blocked and rotatedDepth > 1 then
					for z = minCellZ, maxCellZ - 1 do
						for x = minCellX, maxCellX do
							local alignment, edgeX, edgeZ = EdgeOfCell(x, z, "South")
							if alignment == "Horizontal" then
								local key = EdgeKey(edgeX, edgeZ)
								if HorizontalWallEdges[key] then
									blocked = true
									break
								end
							end
						end
						if blocked then
							break
						end
					end
				end
			end
		end

		if requiresFloor and not missingFloorSupport then
			PopulateCellMapForType(grid, placed, "Floor", FloorCellMap)
			for i = 1, #cells do
				if not FloorCellMap[cells[i]] then
					missingFloorSupport = true
					break
				end
			end
		end

		if requiresFloor and missingFloorSupport then
			canPlace = false
		end

		if blocked then
			canPlace = false
		end

		PreviewHighlight.FillColor = canPlace and Color3.fromRGB(159, 234, 159) or Color3.fromRGB(219, 136, 136)
		PreviewHighlight.OutlineColor = canPlace and Color3.fromRGB(137, 255, 119) or Color3.fromRGB(255, 85, 85)

		RenderFootprintMarkers(grid, surface, cells, canPlace, previewKind)
	end)
end

function ObjectPreview.ClearPreview()
	-- Clear the current preview.
	PreviewContext.RotateLeft.Enabled = false
	PreviewContext.RotateRight.Enabled = false
	PreviewContext.CancelPreview.Enabled = false
	objectPreviewEnabled.Value = false
	ActiveMarkerCount = 0
	HideUnusedMarkers()
	clearFloorSelectionState()

	if SelectedItem then
		if PreviewHighlight then
			PreviewHighlight.Adornee = nil
		end

		SelectedItem:Destroy()
		SelectedItem = nil
	end

	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	LastCellX, LastCellZ = nil, nil
	CurrentItemId = nil
	CurrentItemSpec = nil
	CurrentPivotRotation = CFrame.identity
	MoveOriginSignature = nil
	MoveHoldActive = false
	MoveHoldMousePosition = nil
end

function ObjectPreview.GetCurrentPose(): PreviewPose?
	local itemId = CurrentItemId
	local cellX = LastCellX
	local cellZ = LastCellZ

	if not itemId or not cellX or not cellZ then
		return nil
	end

	return {
		ItemId = itemId,
		CellX = cellX,
		CellZ = cellZ,
		Facing = CurrentFacing,
		Kind = CurrentKind,
	}
end

function ObjectPreview.SetFloorPlacementHandler(handler: ((FloorSelectionInfo) -> ())?)
	FloorPlacementHandler = handler
end

function ObjectPreview.TryBeginFloorDrag(): boolean
	if CurrentKind ~= "Floor" then
		return false
	end
	if FloorSelectionActive then
		return true
	end
	if not CurrentItemId or not LastCellX or not LastCellZ then
		return false
	end
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		return false
	end
	FloorSelectionAnchorX = LastCellX
	FloorSelectionAnchorZ = LastCellZ
	FloorSelectionActive = true
	return true
end

function ObjectPreview.IsFloorDragInProgress(): boolean
	return FloorSelectionActive
end

function ObjectPreview.GetFloorSelectionSummary(): FloorSelectionInfo?
	return CurrentFloorSelection
end

function ObjectPreview.SetMoveOrigin(originInfo: {
	ItemId: string?,
	CellX: number?,
	CellZ: number?,
	Facing: Facing?,
}?)
	if not originInfo then
		MoveOriginSignature = nil
		MoveHoldActive = false
		MoveHoldMousePosition = nil
		return
	end

	local itemId = originInfo.ItemId
	local cellX = originInfo.CellX
	local cellZ = originInfo.CellZ
	if not itemId or cellX == nil or cellZ == nil then
		MoveOriginSignature = nil
		return
	end

	local entry = {
		id = itemId,
		cellX = cellX,
		cellZ = cellZ,
		facing = originInfo.Facing,
	}

	local _, placementType, _, _, resolvedFacingValue = ResolvePlacementEntry(entry)
	local resolvedFacing: Facing = resolvedFacingValue :: Facing

	MoveOriginSignature = {
		ItemId = itemId,
		CellX = cellX,
		CellZ = cellZ,
		Facing = resolvedFacing,
		PlacementType = placementType,
	}

	MoveHoldActive = true
	MoveHoldMousePosition = UserInputService:GetMouseLocation()
end

-- Expose the current preview pose so plot builder can send it to the server.
return ObjectPreview
