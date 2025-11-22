--!strict
-- Client/Modules/EnvironmentHUDController.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Packets = require(ReplicatedStorage.Network.TemperaturePackets)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local InsulationConstants = require(ReplicatedStorage.Shared.Configurations.InsulationConstants)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local WeatherController = require(script.Parent.WeatherController)

local EnvironmentHUDController = {}

local RoomTemperatures: { [number]: { [number]: number } } = {} -- [Level][RoomId] = Temp
local CurrentRoomId: number? = nil
local CurrentLevel: number? = nil

-- Assets
local Icons = {
	Temperature = {
		Indoor = { Image = "", Emoji = "🏠" },
		Outdoor = { Image = "", Emoji = "🌲" },
	},
	Weather = {
		Sunny = { Image = "", Emoji = "☀️" },
		Rainy = { Image = "", Emoji = "🌧️" },
		Stormy = { Image = "", Emoji = "⛈️" },
		Snowy = { Image = "", Emoji = "❄️" },
		Cloudy = { Image = "", Emoji = "☁️" },
	},
}

-- UI Elements
local TimeLabel: TextLabel? = nil
local WeatherLabel: TextLabel? = nil
local WeatherIcon: ImageLabel? = nil
local WeatherEmoji: TextLabel? = nil
local TempLabel: TextLabel? = nil
local TempIcon: ImageLabel? = nil
local TempEmoji: TextLabel? = nil

local function createUI()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	-- Check for existing
	local existing = playerGui:FindFirstChild("EnvironmentHUD")
	if existing then
		existing:Destroy()
	end

	local screen = Instance.new("ScreenGui")
	screen.Name = "EnvironmentHUD"
	screen.ResetOnSpawn = false
	screen.Parent = playerGui

	local mainFrame = Instance.new("Frame")
	mainFrame.Name = "MainFrame"
	mainFrame.Size = UDim2.fromOffset(180, 90)
	mainFrame.Position = UDim2.fromScale(0.04, 0.08)
	mainFrame.AnchorPoint = Vector2.new(0, 0)
	mainFrame.BackgroundTransparency = 1
	mainFrame.Parent = screen

	local listLayout = Instance.new("UIListLayout")
	listLayout.Parent = mainFrame
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left

	-- 1. Time Label
	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "TimeLabel"
	timeLabel.LayoutOrder = 1
	timeLabel.Size = UDim2.new(1, 0, 0, 24)
	timeLabel.BackgroundTransparency = 1
	timeLabel.Font = Enum.Font.GothamBold
	timeLabel.TextSize = 22
	timeLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	timeLabel.TextStrokeTransparency = 0.5
	timeLabel.TextXAlignment = Enum.TextXAlignment.Left
	timeLabel.Text = "12:00 PM"
	timeLabel.Parent = mainFrame

	-- 2. Weather Row
	local weatherRow = Instance.new("Frame")
	weatherRow.Name = "WeatherRow"
	weatherRow.LayoutOrder = 2
	weatherRow.Size = UDim2.new(1, 0, 0, 20)
	weatherRow.BackgroundTransparency = 1
	weatherRow.Parent = mainFrame

	local weatherLayout = Instance.new("UIListLayout")
	weatherLayout.FillDirection = Enum.FillDirection.Horizontal
	weatherLayout.SortOrder = Enum.SortOrder.LayoutOrder
	weatherLayout.Padding = UDim.new(0, 6)
	weatherLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	weatherLayout.Parent = weatherRow

	local weatherIcon = Instance.new("ImageLabel")
	weatherIcon.Name = "Icon"
	weatherIcon.LayoutOrder = 1
	weatherIcon.Size = UDim2.fromOffset(16, 16)
	weatherIcon.BackgroundTransparency = 1
	weatherIcon.Image = ""
	weatherIcon.Parent = weatherRow

	local weatherEmoji = Instance.new("TextLabel")
	weatherEmoji.Name = "Emoji"
	weatherEmoji.LayoutOrder = 1
	weatherEmoji.Size = UDim2.fromOffset(16, 16)
	weatherEmoji.BackgroundTransparency = 1
	weatherEmoji.Text = ""
	weatherEmoji.TextSize = 14
	weatherEmoji.Parent = weatherRow

	local weatherLabel = Instance.new("TextLabel")
	weatherLabel.Name = "Label"
	weatherLabel.LayoutOrder = 2
	weatherLabel.Size = UDim2.fromScale(0, 1) -- Auto size width?
	weatherLabel.AutomaticSize = Enum.AutomaticSize.X
	weatherLabel.BackgroundTransparency = 1
	weatherLabel.Font = Enum.Font.GothamMedium
	weatherLabel.TextSize = 16
	weatherLabel.TextColor3 = Color3.fromRGB(220, 220, 220)
	weatherLabel.TextStrokeTransparency = 0.6
	weatherLabel.TextXAlignment = Enum.TextXAlignment.Left
	weatherLabel.Text = "Sunny"
	weatherLabel.Visible = false
	weatherLabel.Parent = weatherRow

	-- 3. Temperature Row
	local tempRow = Instance.new("Frame")
	tempRow.Name = "TempRow"
	tempRow.LayoutOrder = 3
	tempRow.Size = UDim2.new(1, 0, 0, 20)
	tempRow.BackgroundTransparency = 1
	tempRow.Parent = mainFrame

	local tempLayout = Instance.new("UIListLayout")
	tempLayout.FillDirection = Enum.FillDirection.Horizontal
	tempLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tempLayout.Padding = UDim.new(0, 6)
	tempLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	tempLayout.Parent = tempRow

	local tempIcon = Instance.new("ImageLabel")
	tempIcon.Name = "Icon"
	tempIcon.LayoutOrder = 1
	tempIcon.Size = UDim2.fromOffset(16, 16)
	tempIcon.BackgroundTransparency = 1
	tempIcon.Image = ""
	tempIcon.Parent = tempRow

	local tempEmoji = Instance.new("TextLabel")
	tempEmoji.Name = "Emoji"
	tempEmoji.LayoutOrder = 1
	tempEmoji.Size = UDim2.fromOffset(16, 16)
	tempEmoji.BackgroundTransparency = 1
	tempEmoji.Text = ""
	tempEmoji.TextSize = 14
	tempEmoji.Parent = tempRow

	local tempLabel = Instance.new("TextLabel")
	tempLabel.Name = "Label"
	tempLabel.LayoutOrder = 2
	tempLabel.Size = UDim2.fromScale(0, 1)
	tempLabel.AutomaticSize = Enum.AutomaticSize.X
	tempLabel.BackgroundTransparency = 1
	tempLabel.Font = Enum.Font.Gotham
	tempLabel.TextSize = 16
	tempLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	tempLabel.TextStrokeTransparency = 0.6
	tempLabel.TextXAlignment = Enum.TextXAlignment.Left
	tempLabel.Text = "--°C"
	tempLabel.Parent = tempRow

	TimeLabel = timeLabel
	WeatherLabel = weatherLabel
	WeatherIcon = weatherIcon
	WeatherEmoji = weatherEmoji
	TempLabel = tempLabel
	TempIcon = tempIcon
	TempEmoji = tempEmoji
end

local function formatGameTime(clockTime: number): string
	local hours = math.floor(clockTime)
	local minutes = math.floor((clockTime - hours) * 60)
	local period = "AM"

	if hours >= 12 then
		period = "PM"
	end

	if hours == 0 then
		hours = 12
	elseif hours > 12 then
		hours = hours - 12
	end

	return string.format("%d:%02d %s", hours, minutes, period)
end

local function updateTime()
	if not TimeLabel then
		return
	end
	local clockTime = TimeScale.GetClockTime()
	TimeLabel.Text = formatGameTime(clockTime)
end

local function getTemperatureColor(tempF: number): Color3
	-- Define control points for the gradient
	local COLD = Color3.fromRGB(100, 200, 255) -- 50°F (Cold Blue)
	local COOL = Color3.fromRGB(200, 240, 255) -- 65°F (Light Blue)
	local IDEAL = Color3.fromRGB(255, 255, 255) -- 72°F (White)
	local WARM = Color3.fromRGB(255, 220, 180) -- 80°F (Light Orange)
	local HOT = Color3.fromRGB(255, 100, 100) -- 90°F (Red)

	if tempF <= 50 then
		return COLD
	end
	if tempF >= 90 then
		return HOT
	end

	if tempF < 65 then
		local alpha = (tempF - 50) / (65 - 50)
		return COLD:Lerp(COOL, alpha)
	elseif tempF < 72 then
		local alpha = (tempF - 65) / (72 - 65)
		return COOL:Lerp(IDEAL, alpha)
	elseif tempF < 80 then
		local alpha = (tempF - 72) / (80 - 72)
		return IDEAL:Lerp(WARM, alpha)
	else
		local alpha = (tempF - 80) / (90 - 80)
		return WARM:Lerp(HOT, alpha)
	end
end

local function updateTemperatureVisuals(tempC: number?, isIndoor: boolean)
	if not TempLabel or not TempIcon or not TempEmoji then
		return
	end

	local displayTemp = tempC
	if not displayTemp then
		displayTemp = WeatherController.GetCurrentTemperature()
		isIndoor = false
	end

	-- Convert Celsius to Fahrenheit
	local tempF = (displayTemp :: number * 9 / 5) + 32
	TempLabel.Text = string.format("%.1f°F", tempF)

	-- Apply gradient color
	TempLabel.TextColor3 = getTemperatureColor(tempF)

	-- Update Icon
	local iconData = if isIndoor then Icons.Temperature.Indoor else Icons.Temperature.Outdoor

	if iconData.Image ~= "" then
		TempIcon.Image = iconData.Image
		TempIcon.Visible = true
		TempEmoji.Visible = false
	else
		TempEmoji.Text = iconData.Emoji
		TempEmoji.Visible = true
		TempIcon.Visible = false
	end

	TempLabel.Visible = true
end

local function updateWeatherVisuals()
	if not WeatherLabel or not WeatherIcon or not WeatherEmoji then
		return
	end

	local state = WeatherController.GetState()
	WeatherLabel.Text = state.WeatherType

	local iconData = Icons.Weather[state.WeatherType]
	if iconData then
		if iconData.Image ~= "" then
			WeatherIcon.Image = iconData.Image
			WeatherIcon.Visible = true
			WeatherEmoji.Visible = false
		else
			WeatherEmoji.Text = iconData.Emoji
			WeatherEmoji.Visible = true
			WeatherIcon.Visible = false
		end
	end
end

function EnvironmentHUDController.Init()
	createUI()

	-- Network Listeners for Temperature
	Packets.Update.OnClientEvent:Connect(function(updates)
		for _, update in ipairs(updates) do
			local level = update.Level
			local x = update.X
			local z = update.Z
			local temp = update.Temp

			local roomId = PlotStateStore.GetRoomIdAtCell(level, x, z)
			if roomId then
				if not RoomTemperatures[level] then
					RoomTemperatures[level] = {}
				end
				RoomTemperatures[level][roomId] = temp
			end
		end
	end)

	-- Update Loop
	local lastUpdate = 0
	local UPDATE_INTERVAL = 0.1

	RunService.Heartbeat:Connect(function()
		local now = os.clock()

		-- Always update time (every frame or throttled? TimeScale is smooth, so every frame is better for clock)
		updateTime()
		updateWeatherVisuals()

		-- Throttle spatial checks
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

		-- Detection Logic
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
			level = math.floor(relY / floorHeight + 0.5)
			if level < 0 then
				level = 0
			end
		end

		if level == nil or cellX == nil or cellZ == nil then
			updateTemperatureVisuals(nil, false)
			CurrentRoomId = nil
			CurrentLevel = nil
			return
		end

		local roomId = PlotStateStore.GetRoomIdAtCell(level, cellX, cellZ)
		CurrentRoomId = roomId
		CurrentLevel = level

		if CurrentRoomId and CurrentLevel ~= nil then
			local temps = RoomTemperatures[CurrentLevel]
			local temp = temps and temps[CurrentRoomId]
			if not temp then
				temp = InsulationConstants.AmbientTemperature
			end
			updateTemperatureVisuals(temp, true)
		else
			updateTemperatureVisuals(nil, false)
		end
	end)
end

return EnvironmentHUDController
