--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local ThermostatUI = {}

local GUI_NAME = "ThermostatGUI"

type Props = {
	InitialTemp: number, -- In Celsius
	MinAchievable: number?, -- In Celsius
	MaxAchievable: number?, -- In Celsius
	OnChanged: (number) -> (), -- Returns Celsius
	OnClose: () -> (),
}

local currentScreen: ScreenGui? = nil

local function cToF(c: number): number
	return (c * 9 / 5) + 32
end

local function fToC(f: number): number
	return (f - 32) * 5 / 9
end

function ThermostatUI.Mount(props: Props)
	ThermostatUI.Unmount()

	local minF = cToF(props.MinAchievable or 15)
	local maxF = cToF(props.MaxAchievable or 30)
	local range = maxF - minF
	local isSystemActive = range > 1.0

	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui")

	local screen = Instance.new("ScreenGui")
	screen.Name = GUI_NAME
	screen.ResetOnSpawn = false
	screen.Parent = playerGui
	currentScreen = screen

	-- Main Container
	local frame = Instance.new("Frame")
	frame.Name = "MainFrame"
	frame.Size = UDim2.fromOffset(220, 160) -- Slightly taller for warning
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	frame.BorderSizePixel = 0
	frame.Parent = screen

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 12)
	corner.Parent = frame

	-- Title
	local title = Instance.new("TextLabel")
	title.Text = "Thermostat"
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Color3.fromRGB(255, 255, 255)
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Position = UDim2.fromOffset(0, 10)
	title.Parent = frame

	-- Temp Display
	local tempDisplay = Instance.new("TextLabel")
	tempDisplay.Text = string.format("%.1f°F", cToF(props.InitialTemp))
	tempDisplay.Font = Enum.Font.Gotham
	tempDisplay.TextSize = 32
	tempDisplay.TextColor3 = Color3.fromRGB(100, 200, 255)
	tempDisplay.BackgroundTransparency = 1
	tempDisplay.Size = UDim2.new(1, 0, 0, 40)
	tempDisplay.Position = UDim2.fromOffset(0, 40)
	tempDisplay.Parent = frame

	-- Slider Track
	local sliderTrack = Instance.new("Frame")
	sliderTrack.Name = "Track"
	sliderTrack.Size = UDim2.new(0.8, 0, 0, 6)
	sliderTrack.Position = UDim2.new(0.1, 0, 0, 100)
	sliderTrack.BackgroundColor3 = Color3.fromRGB(60, 60, 65)
	sliderTrack.BorderSizePixel = 0
	sliderTrack.Parent = frame
	sliderTrack.Visible = isSystemActive

	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = sliderTrack

	-- Slider Knob
	local knob = Instance.new("Frame")
	knob.Name = "Knob"
	knob.Size = UDim2.fromOffset(20, 20)
	knob.AnchorPoint = Vector2.new(0.5, 0.5)
	knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	knob.Parent = sliderTrack

	local knobCorner = Instance.new("UICorner")
	knobCorner.CornerRadius = UDim.new(1, 0)
	knobCorner.Parent = knob

	-- Warning Label (if inactive)
	if not isSystemActive then
		local warning = Instance.new("TextLabel")
		warning.Text = "System Offline / No Power"
		warning.Font = Enum.Font.GothamBold
		warning.TextSize = 14
		warning.TextColor3 = Color3.fromRGB(255, 80, 80)
		warning.BackgroundTransparency = 1
		warning.Size = UDim2.new(1, 0, 0, 30)
		warning.Position = UDim2.fromOffset(0, 90)
		warning.Parent = frame

		tempDisplay.TextColor3 = Color3.fromRGB(150, 150, 150)
	end

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Text = "X"
	closeBtn.Size = UDim2.fromOffset(24, 24)
	closeBtn.Position = UDim2.new(1, -8, 0, 8)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
	closeBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = frame

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(0.5, 0)
	closeCorner.Parent = closeBtn

	closeBtn.MouseButton1Click:Connect(function()
		ThermostatUI.Unmount()
		props.OnClose()
	end)

	-- Logic
	local dragging = false
	local currentTempF = cToF(props.InitialTemp)

	local function updateFromScale(scale: number, suppressCallback: boolean?)
		if not isSystemActive then
			return
		end

		scale = math.clamp(scale, 0, 1)
		knob.Position = UDim2.fromScale(scale, 0.5)

		currentTempF = minF + (maxF - minF) * scale
		tempDisplay.Text = string.format("%.1f°F", currentTempF)

		-- Color update (using F)
		if currentTempF < 68 then
			tempDisplay.TextColor3 = Color3.fromRGB(100, 200, 255)
		elseif currentTempF > 77 then
			tempDisplay.TextColor3 = Color3.fromRGB(255, 100, 100)
		else
			tempDisplay.TextColor3 = Color3.fromRGB(255, 255, 255)
		end

		if not suppressCallback then
			props.OnChanged(fToC(currentTempF))
		end
	end

	-- Init position
	if isSystemActive then
		local startScale = (cToF(props.InitialTemp) - minF) / (maxF - minF)
		updateFromScale(startScale, true)
	end

	knob.InputBegan:Connect(function(input)
		if not isSystemActive then
			return
		end
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = true
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if
			input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch
		then
			dragging = false
		end
	end)

	UserInputService.InputChanged:Connect(function(input: InputObject)
		if
			dragging
			and (
				input.UserInputType == Enum.UserInputType.MouseMovement
				or input.UserInputType == Enum.UserInputType.Touch
			)
		then
			local mousePos = input.Position.X
			local trackAbsPos = sliderTrack.AbsolutePosition.X
			local trackAbsSize = sliderTrack.AbsoluteSize.X

			local scale = (mousePos - trackAbsPos) / trackAbsSize
			updateFromScale(scale)
		end
	end)
end

function ThermostatUI.Unmount()
	if currentScreen then
		currentScreen:Destroy()
		currentScreen = nil
	end
end

return ThermostatUI
