--!strict

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)

local RoomDebugOverlay = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local activeQueryFolder = playerGui:WaitForChild("ActiveQuery")

local debugValue: BoolValue? = nil
local markersFolder: Folder? = nil
local activeMarkers: { [string]: BasePart } = {}

local MARKER_FOLDER_NAME = "RoomDebugMarkers"
local LABEL_SIZE = UDim2.fromOffset(160, 50)
local LABEL_OFFSET = Vector3.new(0, 2.5, 0)

local function ensureMarkersFolder(): Folder
	if markersFolder and markersFolder.Parent then
		return markersFolder
	end

	local folder = Instance.new("Folder")
	folder.Name = MARKER_FOLDER_NAME
	folder.Parent = Workspace
	markersFolder = folder
	return folder
end

local function destroyMarkers()
	for key, part in pairs(activeMarkers) do
		if part then
			part:Destroy()
		end
		activeMarkers[key] = nil
	end
end

local function ensureDebugValue(): BoolValue
	if debugValue and debugValue.Parent then
		return debugValue
	end

	local existing = activeQueryFolder:FindFirstChild("RoomDebugEnabled")
	if existing and existing:IsA("BoolValue") then
		debugValue = existing
		return existing
	end

	local value = Instance.new("BoolValue")
	value.Name = "RoomDebugEnabled"
	value.Value = false
	value.Parent = activeQueryFolder
	debugValue = value
	return value
end

local function makeMarkerKey(level: number, roomId: number): string
	return ("%d:%d"):format(level, roomId)
end

local function computeRoomCenter(room: any)
	local centerX = math.floor((room.MinCellX + room.MaxCellX) * 0.5 + 0.5)
	local centerZ = math.floor((room.MinCellZ + room.MaxCellZ) * 0.5 + 0.5)
	return centerX, centerZ
end

local function createMarker(room: any)
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return
	end

	local centerX, centerZ = computeRoomCenter(room)
	local worldPosition = grid:CellToWorldCenter(centerX, centerZ)
	if not worldPosition then
		return
	end

	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local floorHeight = PlotStateStore.GetFloorHeightStuds()
	local levelOffset = (room.Level - defaultLevel) * floorHeight
	local partPosition = worldPosition + Vector3.new(0, levelOffset + 0.5, 0)

	local folder = ensureMarkersFolder()
	local markerPart = Instance.new("Part")
	markerPart.Name = ("RoomMarker_%d"):format(room.Id)
	markerPart.Transparency = 1
	markerPart.CanCollide = false
	markerPart.CanQuery = false
	markerPart.CanTouch = false
	markerPart.Anchored = true
	markerPart.Size = Vector3.new(0.2, 0.2, 0.2)
	markerPart.CFrame = CFrame.new(partPosition)
	markerPart.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "RoomLabel"
	billboard.AlwaysOnTop = true
	billboard.Size = LABEL_SIZE
	billboard.StudsOffsetWorldSpace = LABEL_OFFSET
	billboard.MaxDistance = 800
	billboard.Adornee = markerPart
	billboard.Parent = markerPart

	local background = Instance.new("Frame")
	background.BackgroundTransparency = 0.25
	background.BackgroundColor3 = Color3.fromRGB(34, 119, 255)
	background.BorderSizePixel = 0
	background.Size = UDim2.fromScale(1, 1)
	background.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = background

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(12, 61, 138)
	stroke.Thickness = 1.5
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = background

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.5
	label.TextScaled = true
	label.Text = string.format("Room %d (Lvl %d)\n%d cells", room.Id, room.Level, room.CellCount)
	label.Parent = background

	activeMarkers[makeMarkerKey(room.Level, room.Id)] = markerPart
end

local function rebuildMarkers()
	destroyMarkers()

	local toggle = ensureDebugValue()
	if not toggle.Value then
		return
	end

	local grid = PlotStateStore.GetGrid()
	if not grid then
		return
	end

	local activeLevel = PlotStateStore.GetActiveLevel()
	PlotStateStore.IterateRooms(activeLevel, function(room)
		createMarker(room)
		return nil
	end)
end

local function onDebugToggleChanged()
	if ensureDebugValue().Value then
		rebuildMarkers()
	else
		destroyMarkers()
	end
end

function RoomDebugOverlay.SetEnabled(enabled: boolean)
	ensureDebugValue().Value = enabled
end

function RoomDebugOverlay.Init()
	local value = ensureDebugValue()
	value:GetPropertyChangedSignal("Value"):Connect(onDebugToggleChanged)

	PlotStateStore.OnActiveLevelChanged(function()
		if value.Value then
			task.defer(rebuildMarkers)
		end
	end)

	PlotStateStore.OnRoomSnapshotChanged(function()
		if value.Value then
			task.defer(rebuildMarkers)
		end
	end)

	player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		if value.Value then
			task.defer(rebuildMarkers)
		else
			destroyMarkers()
		end
	end)

	if value.Value then
		rebuildMarkers()
	end
end

return RoomDebugOverlay
