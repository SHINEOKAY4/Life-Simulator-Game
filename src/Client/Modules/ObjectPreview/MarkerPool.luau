--!strict

local MarkerPool = {}

type PreviewKind = "CellObject" | "Floor" | "Wall" | "Roof"

local MARKER_Y = 0.08
local FLOOR_MARKER_Y = -0.02

local cellMarkers: { BasePart } = {}
local activeMarkerCount = 0

local function buildMarker(cellSize: number, parent: Instance): BasePart
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

local function acquireMarker(cellSize: number, parent: Instance): BasePart
	activeMarkerCount += 1
	if activeMarkerCount <= #cellMarkers then
		local marker = cellMarkers[activeMarkerCount]
		if math.abs(marker.Size.X - cellSize) > 1e-3 then
			marker.Size = Vector3.new(cellSize, 0.05, cellSize)
		end
		if marker.Parent ~= parent then
			marker.Parent = parent
		end
		marker.Transparency = 0.8
		return marker
	end

	local marker = buildMarker(cellSize, parent)
	table.insert(cellMarkers, marker)
	return marker
end

function MarkerPool.BeginFrame()
	activeMarkerCount = 0
end

function MarkerPool.RenderFootprintMarkers(
	grid: any,
	surface: BasePart,
	cells: { number },
	canPlace: boolean,
	previewKind: PreviewKind,
	levelHeight: number?
)
	local plotModel = surface.Parent
	if not plotModel or not plotModel:IsA("Model") then
		return
	end

	local container = plotModel:FindFirstChild("Container")
	if not container then
		return
	end

	local cellSize = grid.CellSize
	local placeableColor = Color3.fromRGB(159, 234, 159)
	local blockedColor = Color3.fromRGB(219, 136, 136)
	local markerColor = if canPlace then placeableColor else blockedColor

	local heightOffset = if typeof(levelHeight) == "number" then levelHeight else 0

	for index = 1, #cells do
		local cellXIndex, cellZIndex = grid:IndexToCell(cells[index])
		local marker = acquireMarker(cellSize, container)

		local center = grid:CellToWorldCenterCFrame(cellXIndex, cellZIndex)
		local basePosition = center.Position + Vector3.new(0, heightOffset, 0)
		local aligned = CFrame.lookAt(basePosition, basePosition + surface.CFrame.LookVector, surface.CFrame.UpVector)
		local markerYOffset = if previewKind == "Floor" then FLOOR_MARKER_Y else MARKER_Y
		marker.CFrame = aligned * CFrame.new(0, markerYOffset, 0)

		marker.Color = markerColor
		marker.Transparency = 0.2
		marker.Material = Enum.Material.Glass
	end

	MarkerPool.HideUnusedMarkers()
end

function MarkerPool.HideUnusedMarkers()
	for index = activeMarkerCount + 1, #cellMarkers do
		cellMarkers[index].Transparency = 1
	end
end

function MarkerPool.Clear()
	activeMarkerCount = 0
	MarkerPool.HideUnusedMarkers()
end

return MarkerPool
