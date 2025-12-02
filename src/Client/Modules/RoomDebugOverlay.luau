--!strict
-- Minimal room debug overlay - shows server room diagnostics

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local activeQueryFolder = playerGui:WaitForChild("ActiveQuery")

local RoomDebugOverlay = {}
local enabled = false
local markers: { BasePart } = {}
local updateConnection: RBXScriptConnection? = nil
local lastFetch = 0
local FETCH_INTERVAL = 3

local function clearMarkers()
	for _, part in markers do
		part:Destroy()
	end
	table.clear(markers)
end

local function createMarker(room: any, grid: any, defaultLevel: number, floorHeight: number)
	local centerX = math.floor((room.MinCellX + room.MinCellX + room.SizeX - 1) / 2 + 0.5)
	local centerZ = math.floor((room.MinCellZ + room.MinCellZ + room.SizeZ - 1) / 2 + 0.5)
	local worldPos = grid:CellToWorldCenter(centerX, centerZ)
	if not worldPos then
		return
	end

	local levelOffset = (room.Level - defaultLevel) * floorHeight
	local part = Instance.new("Part")
	part.Name = "RoomMarker"
	part.Transparency = 1
	part.CanCollide = false
	part.CanQuery = false
	part.Anchored = true
	part.Size = Vector3.new(0.2, 0.2, 0.2)
	part.CFrame = CFrame.new(worldPos + Vector3.new(0, levelOffset + 0.5, 0))
	part.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.AlwaysOnTop = true
	billboard.Size = UDim2.fromOffset(200, 60)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0)
	billboard.MaxDistance = 800
	billboard.Adornee = part
	billboard.Parent = part

	local isReady = if room.Ready == nil then true else room.Ready
	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 0.15
	frame.BackgroundColor3 = if isReady then Color3.fromRGB(24, 164, 123) else Color3.fromRGB(176, 46, 53)
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = frame

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextScaled = true
	local status = if isReady
		then string.format("%d cells • %d/%d", room.CellCount, room.Occupied or 0, room.Capacity or 0)
		else (room.Reason or "Not ready")
	label.Text = string.format("%s (Lvl %d)\n%s", room.RoomKey or "Room", room.Level, status)
	label.Parent = frame

	table.insert(markers, part)
end

local function updateMarkers()
	if not enabled then
		return
	end

	local now = os.clock()
	if now - lastFetch < FETCH_INTERVAL then
		return
	end
	lastFetch = now

	local ok, response = pcall(function()
		return TenantPackets.RequestRoomDiagnostics:Fire({})
	end)

	if not ok or typeof(response) ~= "table" or typeof(response.Rooms) ~= "table" then
		return
	end

	clearMarkers()
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return
	end

	local roomsArray = response.Rooms
	print(string.format("[RoomDebugOverlay] Received %d rooms", #roomsArray))
	for _, room in ipairs(roomsArray) do
		print(
			string.format(
				"[RoomDebugOverlay] Room %s lvl %d cells:%d bounds:(%d,%d)+(%d,%d) ready:%s reason:%s hasBed:%s enclosed:%s capacity:%d/%d",
				tostring(room.RoomKey or "<nil>"),
				room.Level or 0,
				room.CellCount or 0,
				room.MinCellX or 0,
				room.MinCellZ or 0,
				(room.SizeX or 0) + (room.MinCellX or 0) - 1,
				(room.SizeZ or 0) + (room.MinCellZ or 0) - 1,
				tostring(room.Ready ~= false),
				tostring(room.Reason or ""),
				tostring(room.HasBed == true),
				tostring(room.IsEnclosed == true),
				room.Capacity or 0,
				room.Occupied or 0
			)
		)
	end

	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local floorHeight = PlotStateStore.GetFloorHeightStuds()

	for _, room in ipairs(roomsArray) do
		createMarker(room, grid, defaultLevel, floorHeight)
	end
end

function RoomDebugOverlay.SetEnabled(value: boolean)
	enabled = value

	if enabled then
		if not updateConnection then
			updateConnection = RunService.Heartbeat:Connect(updateMarkers)
		end
		updateMarkers()
	else
		if updateConnection then
			updateConnection:Disconnect()
			updateConnection = nil
		end
		clearMarkers()
	end
end

function RoomDebugOverlay.Init()
	local value = Instance.new("BoolValue")
	value.Name = "RoomDebugEnabled"
	value.Value = false
	value.Parent = activeQueryFolder

	value:GetPropertyChangedSignal("Value"):Connect(function()
		RoomDebugOverlay.SetEnabled(value.Value)
	end)

	PlotStateStore.OnActiveLevelChanged(function()
		if enabled then
			task.defer(updateMarkers)
		end
	end)

	PlotStateStore.OnRoomSnapshotChanged(function()
		if enabled then
			task.defer(updateMarkers)
		end
	end)
end

return RoomDebugOverlay
