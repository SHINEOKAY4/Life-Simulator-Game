--!strict
-- StarterPlayerScripts/Client/Modules/ObjectPreview.lua

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PreviewContext = PlayerGui:WaitForChild("PreviewContext")

local Camera = workspace.CurrentCamera

local ObjectPreview = {}

local Connection: RBXScriptConnection? = nil

local SelectedItem: Model? = nil
local CurrentItemId: string? = nil -- Added
local CurrentItemSpec: any? = nil
type Facing = "North" | "East" | "South" | "West"
type PreviewKind = "CellObject" | "Floor" | "Wall" | "Roof"
type PreviewPose = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: Facing,
	Kind: PreviewKind,
}

local CurrentKind: PreviewKind = "CellObject"

local CurrentFacing: Facing = "North"

local LastCellX: number? = nil
local LastCellZ: number? = nil
local LastFacing: string? = nil

-- Added: lightweight pool of thin Parts used to highlight the footprint cells the preview will occupy.
-- Each marker is a small anchored part sized to 1 cell (CellSize x 0.05 x CellSize), parented under the plot's Container.
local CellMarkers: { BasePart } = {} -- pool of reusable marker parts
local ActiveMarkerCount = 0 -- how many markers are currently in-use this frame
local MARKER_Y = 0.03 -- vertical lift so the quad sits above the surface and avoids z-fighting

-- Function: BuildMarker
-- Purpose: Construct a thin, neon, non-collidable part to represent 1 highlighted cell.
local function BuildMarker(cellSize: number, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = "CellPreviewMarker"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Material = Enum.Material.Pavement
	p.Size = Vector3.new(cellSize, 0.05, cellSize)
	p.Transparency = 1
	p.Color = Color3.fromRGB(159, 234, 159) -- default "can place" color; updated per-frame below
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Added: Acquire a marker from the pool or create a new one if needed.
-- Function: AcquireMarker
-- Purpose: Ensures we reuse instances (no churn) and only create when pool is exhausted.
local function AcquireMarker(cellSize: number, parent: Instance): BasePart
	ActiveMarkerCount += 1
	if ActiveMarkerCount <= #CellMarkers then
		local marker = CellMarkers[ActiveMarkerCount]
		-- Resize if CellSize changed (different plots or settings)
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

-- Added: Hide any extra, unused markers each frame.
-- Function: HideUnusedMarkers
-- Purpose: Keeps the pool around, but invisible when not needed to avoid memory churn.
local function HideUnusedMarkers()
	for i = ActiveMarkerCount + 1, #CellMarkers do
		local m = CellMarkers[i]
		if m.Transparency ~= 1 then
			m.Transparency = 1
		end
	end
end

-- Added: Batch update all markers for the current footprint.
-- Function: RenderFootprintMarkers
-- Purpose: Given a list of cell indices, positions markers at each cell center and colors them.
-- Notes:
--   - Colors all cells green if placeable, red if not (YAGNI: per-cell validity would require deeper checks).
local function RenderFootprintMarkers(grid, surface: BasePart, cells: { number }, canPlace: boolean)
	-- Parent markers next to the previewed model (plot’s Container keeps things tidy)
	local plotModel = surface.Parent :: Model
	local container = plotModel:FindFirstChild("Container") :: Folder
	if not container then
		return
	end

	local cellSize = grid.CellSize
	local colorGood = Color3.fromRGB(159, 234, 159)
	local colorBad = Color3.fromRGB(219, 136, 136)
	local tint = canPlace and colorGood or colorBad

	for i = 1, #cells do
		local cx, cz = grid:IndexToCell(cells[i]) -- convert 1D index -> 2D cell coords
		-- Acquire or create a pooled marker
		local marker = AcquireMarker(cellSize, container)

		-- Position at the cell center, aligned to plot surface, with a tiny Y lift to avoid z-fighting.
		local center = grid:CellToWorldCenterCFrame(cx, cz)
		local aligned =
			CFrame.lookAt(center.Position, center.Position + surface.CFrame.LookVector, surface.CFrame.UpVector)
		marker.CFrame = aligned * CFrame.new(0, MARKER_Y, 0)

		-- Color based on overall validity for this footprint (simple & readable)
		marker.Color = tint
		marker.Transparency = 0.2
		marker.Material = Enum.Material.Glass
	end

	-- Hide any unused markers this frame
	HideUnusedMarkers()
end

local function YawFromFacing(f: Facing)
	if f == "East" then
		return math.rad(90)
	end
	if f == "South" then
		return math.rad(180)
	end
	if f == "West" then
		return math.rad(270)
	end
	return 0
end

-- This computes how far to lift the model so the pivot does not sink below the surface.
local function GetLiftFromPivotToBottom(model: Model): number
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local pivotCFrame = model:GetPivot()

	-- Where is the pivot inside the bounding box’s frame?
	local pivotLocal = bboxCFrame:PointToObjectSpace(pivotCFrame.Position)
	-- Distance from pivot to the bottom face along +Y of the bbox
	-- (half height + the pivot’s local Y within the bbox frame)
	return (bboxSize.Y * 0.5) + pivotLocal.Y
end

local function AnyCellOverlap(a: { number }, b: { number }): boolean -- Added
	-- small set test; YAGNI: linear scan is fine for tiny footprints -- Added
	for i = 1, #a do
		local ai = a[i]
		for j = 1, #b do
			if ai == b[j] then
				return true
			end
		end
	end
	return false
end -- Added

local function ResolvePlacementEntry(entry: any): (any?, string, number, number, Facing)
	local itemId = entry.id or entry.Id or entry.ItemId
	local spec = if itemId then ItemFinder.FindItemById(itemId) else nil
	local placementType = (spec and (spec.PlacementType or spec.Type)) or "CellObject"
	local width = entry.width or entry.Width or (spec and spec.WidthCells) or 1
	local depth = entry.depth or entry.Depth or (spec and spec.DepthCells) or 1
	local facing = entry.facing or entry.Facing or "North"

	if placementType == "Floor" then
		local specWidth = spec and (spec.WidthCells or spec.Width)
		local specDepth = spec and (spec.DepthCells or spec.Depth)
		width = specWidth or width
		depth = specDepth or depth
		facing = "North"
	elseif placementType == "Wall" then
		width, depth = 1, 1
	end

	return spec, placementType, width, depth, facing :: Facing
end

local FloorCellMap: { [number]: boolean } = {}

local function PopulateCellMapForType(grid, placed, placementType: string, target: { [number]: boolean })
	table.clear(target)
	if not placed then
		return target
	end

	for i = 1, #placed do
		local entry = placed[i]
		local _, pType, width, depth, facing = ResolvePlacementEntry(entry)
		if pType == placementType then
			local cells = grid:ClippedFootprintCells(entry.cellX, entry.cellZ, width, depth, facing)
			for j = 1, #cells do
				target[cells[j]] = true
			end
		end
	end

	return target
end

local function isCellOccupiedForPreview(
	grid,
	kind: PreviewKind,
	cellX: number,
	cellZ: number,
	baseW: number,
	baseD: number,
	facing: Facing,
	placed
): boolean
	if not placed or #placed == 0 then
		return false
	end

	-- Floor: 1x1, occupied if a floor with same cell already exists
	if kind == "Floor" then
		local myCells = grid:ClippedFootprintCells(cellX, cellZ, baseW, baseD, "North")
		for i = 1, #placed do
			local p = placed[i]
			local _, pType, width, depth = ResolvePlacementEntry(p)
			if pType == "Floor" then
				local other = grid:ClippedFootprintCells(p.cellX, p.cellZ, width, depth, "North")
				if AnyCellOverlap(myCells, other) then
					return true
				end
			end
		end
		return false
	end

	-- CellObject: blocked by other CellObjects’ occupied cells (floors don’t block here)
	if kind == "CellObject" then
		local myCells = grid:ClippedFootprintCells(cellX, cellZ, baseW, baseD, facing)
		for i = 1, #placed do
			local p = placed[i]
			local _, pType, width, depth, otherFacing = ResolvePlacementEntry(p)
			if pType == "CellObject" then
				local other = grid:ClippedFootprintCells(p.cellX, p.cellZ, width, depth, otherFacing)
				if AnyCellOverlap(myCells, other) then
					return true
				end
			end
		end
		return false
	end

	if kind == "Roof" then
		local myCells = grid:ClippedFootprintCells(cellX, cellZ, baseW, baseD, facing)
		for i = 1, #placed do
			local p = placed[i]
			local _, pType, width, depth, otherFacing = ResolvePlacementEntry(p)
			if pType == "Roof" then
				local other = grid:ClippedFootprintCells(p.cellX, p.cellZ, width, depth, otherFacing)
				if AnyCellOverlap(myCells, other) then
					return true
				end
			end
		end
		return false
	end

	-- Walls don’t occupy cells; let server validate edges. -- Added
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
		grid:FootprintChunkRange(cellX, cellZ, widthCells, depthCells, facing, chunkSize) -- Changed: rename
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
	-- Roof sits slightly higher than walls/floors
	local base = grid:CellToWorldCenterCFrame(cellX, cellZ, lift)
	local aligned = AlignToSurface(base, surface)
	local yaw = CFrame.Angles(0, YawFromFacing(facing), 0)
	model:PivotTo(aligned * yaw)
end

--Preview a CellObject (WxD) at the correct world pose for the current anchor cell and facing.
-- Function: PreviewCellObject
-- Purpose: Mirror server placement logic by pivoting the preview at the anchor cell center,
--          ensuring the preview mesh lines up exactly with the highlighted footprint cells.
local function PreviewCellObject(
	model: Model,
	grid: any,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	facing: Facing,
	widthCells: number,
	depthCells: number,
	lift: number
)
	-- Anchor the preview at the geometric center of the rotated footprint so meshes cover all highlighted cells.
	local center = grid:FootprintCenterCFrame(cellX, cellZ, widthCells, depthCells, facing)
	local aligned = AlignToSurface(center, surface)
	local yaw = CFrame.Angles(0, YawFromFacing(facing), 0)

	model:PivotTo(aligned * yaw * CFrame.new(0, lift, 0))
end

function ObjectPreview.Init()
	-- Initialize the object preview

	local order: { Facing } = { "North", "East", "South", "West" } -- Added: canonical rotation order
	local indexOf: { [Facing]: number } = { North = 1, East = 2, South = 3, West = 4 } -- Added: O(1) lookup

	PreviewContext.RotateLeft.Pressed:Connect(function()
		-- Changed: Fix logic to cycle forward (clockwise) deterministically.
		-- Old code had fall-through that snapped from West -> North prematurely.
		local i = indexOf[CurrentFacing] or 1
		i = i % 4 + 1 -- 1->2->3->4->1
		CurrentFacing = order[i]
		LastFacing = nil -- Added: force pose recompute for new facing
	end)

	PreviewContext.RotateRight.Pressed:Connect(function()
		-- Changed: Fix logic to cycle backward (counter-clockwise) deterministically.
		local i = indexOf[CurrentFacing] or 1
		i = (i - 2) % 4 + 1 -- 1->4->3->2->1
		CurrentFacing = order[i]
		LastFacing = nil -- Added: force pose recompute for new facing
	end)
end

function ObjectPreview.RenderPreview(itemId: string)
	ObjectPreview.ClearPreview()

	local itemModel = ItemFinder.ResolveItemModel(itemId)
	if not itemModel then
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

	-- Prepare a simple, safe preview clone
	itemModel = itemModel:Clone()

	local lift = GetLiftFromPivotToBottom(itemModel)
	local chunkSize = PlotStateStore.GetStateSnapshot().ChunkInfo.ChunkSizeInCells
	local plotModel = surface.Parent :: Model
	local containerFolder = plotModel:FindFirstChild("Container") :: Folder
	local highlight = containerFolder:FindFirstChild("ObjectHighlight") :: Highlight

	highlight.Adornee = itemModel

	itemModel.Parent = containerFolder
	SelectedItem = itemModel

	for _, part in itemModel:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end
	-- Only raycast against the plot surface
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { surface }
	params.IgnoreWater = true

	CurrentFacing = "North"

	local previewKind: PreviewKind = PreviewKindFromItem(itemId)
	local baseW, baseD = GetItemFootprintCells(itemId)

	CurrentItemId = itemId
	CurrentKind = previewKind

	PreviewContext.RotateLeft.Enabled = (previewKind ~= "Floor")
	PreviewContext.RotateRight.Enabled = (previewKind ~= "Floor")

	Connection = RunService.PreRender:Connect(function()
		local model = SelectedItem
		if not model then
			return
		end

		-- Screen space mouse -> world ray
		local mouse = UserInputService:GetMouseLocation()
		local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)

		local result = Workspace:Raycast(ray.Origin, ray.Direction * 2048, params)
		if not result then
			return
		end

		local isInside, cellX, cellZ = grid:WorldPointToCell(result.Position) --  snapping
		if not isInside then
			cellX, cellZ = grid:WorldPointToClampedCell(result.Position) --clamp if slightly outside
		end

		if LastCellX == cellX and LastCellZ == cellZ and LastFacing == CurrentFacing then
			return
		end

		LastCellX, LastCellZ, LastFacing = cellX, cellZ, CurrentFacing

		local snapshot = PlotStateStore.GetStateSnapshot()
		local placed = snapshot.PlacedItems

		local isUnlocked: boolean
		if previewKind == "Wall" then
			isUnlocked = IsFootprintUnlocked(grid, chunkSize, cellX, cellZ, 1, 1, CurrentFacing)
		elseif previewKind == "Floor" then
			isUnlocked = IsFootprintUnlocked(grid, chunkSize, cellX, cellZ, baseW, baseD, "North")
		else
			isUnlocked = IsFootprintUnlocked(grid, chunkSize, cellX, cellZ, baseW, baseD, CurrentFacing)
		end

		local blocked = isCellOccupiedForPreview(grid, previewKind, cellX, cellZ, baseW, baseD, CurrentFacing, placed)

		if previewKind == "Wall" then
			PreviewWall(model, grid, cellX, cellZ, CurrentFacing, lift)
		elseif previewKind == "Floor" then
			PreviewFloor(model, grid, surface, cellX, cellZ, baseW, baseD, "North")
		elseif previewKind == "Roof" then
			local spec = CurrentItemSpec
			local height = spec and spec.HeightStuds or 12
			PreviewRoof(model, grid, surface, cellX, cellZ, CurrentFacing, height) -- small Y offset
		else
			PreviewCellObject(model, grid, surface, cellX, cellZ, CurrentFacing, baseW, baseD, lift)
		end

		local requiresFloor = false
		if previewKind == "Roof" then
			local spec = CurrentItemSpec
			requiresFloor = spec ~= nil and spec.Rules ~= nil and spec.Rules.RequiresFloorUnderAllCells == true
		end

		local missingFloorSupport = false
		local cells: { number }
		local canPlace = isUnlocked and not blocked

		ActiveMarkerCount = 0 -- reset pool usage for this frame

		if previewKind == "Wall" then
			-- Walls occupy a single anchor cell edge; treat as 1x1 for overlay markers.
			-- Use clipped footprint so markers never go OOB.
			cells = grid:ClippedFootprintCells(cellX, cellZ, 1, 1, CurrentFacing)
		elseif previewKind == "Floor" then
			cells = grid:ClippedFootprintCells(cellX, cellZ, baseW, baseD, "North")
		else
			-- CellObject uses its (possibly rotated) footprint.
			cells = grid:ClippedFootprintCells(cellX, cellZ, baseW, baseD, CurrentFacing)
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

		highlight.FillColor = canPlace and Color3.fromRGB(159, 234, 159) or Color3.fromRGB(219, 136, 136)
		highlight.OutlineColor = canPlace and Color3.fromRGB(137, 255, 119) or Color3.fromRGB(255, 85, 85)

		RenderFootprintMarkers(grid, surface, cells, canPlace)
	end)
end

function ObjectPreview.ClearPreview()
	-- Clear the current preview
	PreviewContext.RotateLeft.Enabled = false
	PreviewContext.RotateRight.Enabled = false

	-- Added: hide all footprint markers when leaving preview to avoid lingering visuals
	ActiveMarkerCount = 0
	HideUnusedMarkers()

	if SelectedItem then
		local containerFolder = SelectedItem.Parent
		local highlight = containerFolder and containerFolder:FindFirstChild("ObjectHighlight") :: Highlight?

		if highlight then
			highlight.Adornee = nil
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

-- Add a getter function for the location of the selected item so plot builder can query and send to server
return ObjectPreview
