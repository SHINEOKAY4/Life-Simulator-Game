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
type Facing = "North" | "East" | "South" | "West"
type PreviewKind = "CellObject" | "Floor" | "Wall"
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
	p.Transparency = 0.8
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
		marker.Transparency = 0.4
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
		marker.Transparency = 0.4
		marker.Material = Enum.Material.Neon
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

local function isCellOccupiedForPreview(
	grid,
	kind: PreviewKind,
	cellX: number,
	cellZ: number,
	baseW: number,
	baseD: number,
	facing: Facing
): boolean
	local snapshot = PlotStateStore.GetStateSnapshot()
	local placed = snapshot.PlacedItems
	if not placed or #placed == 0 then
		return false
	end

	-- Floor: 1x1, occupied if a floor with same cell already exists
	if kind == "Floor" then
		for i = 1, #placed do
			local p = placed[i]
			-- Changed: infer placement type from catalog only when needed
			local spec = ItemFinder.FindItemById(p.id or p.Id or p.ItemId) -- Added
			local pType = (spec and (spec.PlacementType or spec.Type)) or "CellObject" -- Added
			if pType == "Floor" and p.cellX == cellX and p.cellZ == cellZ then
				return true
			end
		end
		return false
	end

	-- CellObject: blocked by other CellObjects’ occupied cells (floors don’t block here)
	if kind == "CellObject" then
		local myCells = grid:ClippedFootprintCells(cellX, cellZ, baseW, baseD, facing)
		for i = 1, #placed do
			local p = placed[i]
			local spec = ItemFinder.FindItemById(p.id or p.Id or p.ItemId) -- Added
			local pType = (spec and (spec.PlacementType or spec.Type)) or "CellObject" -- Added
			if pType == "CellObject" then
				local other =
					grid:ClippedFootprintCells(p.cellX, p.cellZ, p.width or 1, p.depth or 1, p.facing or "North") -- Changed: normalize missing width/depth/facing
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

local function PreviewFloor(model: Model, grid, surface: BasePart, cellX: number, cellZ)
	local base = grid:CellToWorldCenterCFrame(cellX, cellZ)
	local alignedCFrame = AlignToSurface(base, surface)
	model:PivotTo(alignedCFrame)
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

		local isUnlocked: boolean
		if previewKind == "Wall" or previewKind == "Floor" then -- Changed
			isUnlocked = IsFootprintUnlocked(grid, chunkSize, cellX, cellZ, 1, 1, "North") -- Changed
		else
			isUnlocked = IsFootprintUnlocked(grid, chunkSize, cellX, cellZ, baseW, baseD, CurrentFacing)
		end

		local blocked = isCellOccupiedForPreview(grid, previewKind, cellX, cellZ, baseW, baseD, CurrentFacing)

		if previewKind == "Wall" then
			PreviewWall(model, grid, cellX, cellZ, CurrentFacing, lift)
		elseif previewKind == "Floor" then
			PreviewFloor(model, grid, surface, cellX, cellZ)
		else
			PreviewCellObject(model, grid, surface, cellX, cellZ, CurrentFacing, baseW, baseD, lift)
		end

		local canPlace = isUnlocked and not blocked -- Added
		highlight.FillColor = canPlace and Color3.fromRGB(159, 234, 159) or Color3.fromRGB(219, 136, 136) -- Changed
		highlight.OutlineColor = canPlace and Color3.fromRGB(137, 255, 119) or Color3.fromRGB(255, 85, 85) -- Changed

		ActiveMarkerCount = 0 -- reset pool usage for this frame

		local cells: { number }
		if previewKind == "Floor" or previewKind == "Wall" then
			-- Floors/Walls occupy a 1x1 anchor cell for the purposes of cell highlighting.
			-- Use clipped footprint so markers never go OOB.
			cells = grid:ClippedFootprintCells(cellX, cellZ, 1, 1, "North")
		else
			-- CellObject uses its (possibly rotated) footprint.
			cells = grid:ClippedFootprintCells(cellX, cellZ, baseW, baseD, CurrentFacing)
		end

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
