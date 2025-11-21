--!strict
-- Client/Modules/TemperatureController.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packets = require(ReplicatedStorage.Network.TemperaturePackets)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local InsulationConstants = require(ReplicatedStorage.Shared.Configurations.InsulationConstants)

local TemperatureController = {}

local RoomTemperatures: { [number]: { [number]: number } } = {} -- [Level][RoomId] = Temp
local CurrentRoomId: number? = nil
local CurrentLevel: number? = nil

local Label: TextLabel? = nil
local Container: Frame? = nil

local function createUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	print("TemperatureController: Creating UI in PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = "TemperatureHUD"
	screen.ResetOnSpawn = false
	screen.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "Container"
	container.Size = UDim2.fromOffset(120, 36)
	container.Position = UDim2.fromScale(0.5, 0.05) -- Top center
	container.AnchorPoint = Vector2.new(0.5, 0)
	container.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	container.BackgroundTransparency = 0.3
	container.BorderSizePixel = 0
	container.Visible = false -- Hidden by default
	container.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.5, 0)
	corner.Parent = container

	local label = Instance.new("TextLabel")
	label.Name = "TempLabel"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.Text = "--°F"
	label.Parent = container

	Container = container
	Label = label

	return container, label
end

local function cToF(c: number): number
	return (c * 9 / 5) + 32
end

local function updateVisuals(temp: number?)
	if not Container or not Label then
		return
	end

	if temp then
		local tempF = cToF(temp)
		Label.Text = string.format("%.1f°F", tempF)

		-- Color coding (using F)
		local color = Color3.fromRGB(255, 255, 255)
		if tempF < 60 then
			color = Color3.fromRGB(150, 200, 255)
		elseif tempF > 82 then
			color = Color3.fromRGB(255, 150, 150)
		end
		Label.TextColor3 = color

		if not Container.Visible then
			print("TemperatureController: Showing UI")
			Container.Visible = true
			-- Remove tween for debugging to ensure it's not stuck at transparency 1
			Container.BackgroundTransparency = 0.3
			Label.TextTransparency = 0
		end
	else
		if Container.Visible then
			print("TemperatureController: Hiding UI")
			Container.Visible = false
		end
	end
end

function TemperatureController.GetTemperature(level: number, roomId: number): number?
	if not RoomTemperatures[level] then
		return nil
	end
	return RoomTemperatures[level][roomId]
end

function TemperatureController.Init()
	createUI()

	Packets.Update.OnClientEvent:Connect(function(updates)
		for _, update in ipairs(updates) do
			local level = update.Level
			local x = update.X
			local z = update.Z
			local temp = update.Temp

			-- Map (X, Z) to RoomId
			-- We need to ensure PlotStateStore has calculated rooms for this level
			local roomId = PlotStateStore.GetRoomIdAtCell(level, x, z)

			if roomId then
				if not RoomTemperatures[level] then
					RoomTemperatures[level] = {}
				end
				RoomTemperatures[level][roomId] = temp
			end
		end
	end)

	local lastUpdate = 0
	local UPDATE_INTERVAL = 0.1 -- Check 10 times per second

	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - lastUpdate < UPDATE_INTERVAL then
			return
		end
		lastUpdate = now

		if not PlotStateStore.IsReady() then
			return
		end

		local player = Players.LocalPlayer
		local character = player.Character
		if not character or not character.PrimaryPart then
			return
		end

		local grid = PlotStateStore.GetGrid()
		if not grid then
			return
		end

		-- Efficient Coordinate-Based Detection (No Raycasts)
		local rootPart = character.PrimaryPart
		local pos = rootPart.Position
		local inBounds, cx, cz = grid:WorldPointToCell(pos)

		local level: number? = nil
		local cellX: number? = nil
		local cellZ: number? = nil

		if inBounds then
			cellX = cx
			cellZ = cz

			local originY = grid.OriginTopCFrame.Position.Y
			local relY = pos.Y - originY
			local floorHeight = PlotStateStore.GetFloorHeightStuds()

			-- Calculate level based on height
			-- RootPart is usually ~3 studs above floor.
			-- We round to nearest level index.
			level = math.floor(relY / floorHeight + 0.5)
			if level < 0 then
				level = 0
			end
		end

		if level == nil or cellX == nil or cellZ == nil then
			updateVisuals(nil)
			return
		end

		local roomId = PlotStateStore.GetRoomIdAtCell(level, cellX, cellZ)

		if roomId ~= CurrentRoomId or level ~= CurrentLevel then
			if roomId then
				print(string.format("TemperatureController: Entered Room ID %d at Level %d", roomId, level))
			else
				print(string.format("TemperatureController: Left Room (Now at Level %d)", level))
			end
			CurrentRoomId = roomId
			CurrentLevel = level
		end

		if CurrentRoomId and CurrentLevel ~= nil then
			local temps = RoomTemperatures[CurrentLevel]
			local temp = temps and temps[CurrentRoomId]

			-- Default to ambient if no data yet
			if not temp then
				temp = InsulationConstants.AmbientTemperature
			end

			updateVisuals(temp)
		else
			updateVisuals(nil)
		end
	end)
end

return TemperatureController
