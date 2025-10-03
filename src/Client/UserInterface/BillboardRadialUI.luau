--!strict
-- StarterPlayerScripts/Client/UserInterface/BillboardRadialUI.lua

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local player = Players.LocalPlayer

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local RadialBillboard = AssetsFolder.VisualTools:WaitForChild("RadialBillboard") :: BillboardGui
local HubFrame = RadialBillboard:WaitForChild("Root"):FindFirstChild("Hub") :: Frame
local CenterLabel = HubFrame:FindFirstChild("CenterLabel") :: TextLabel

local BillboardRadialUI = {}

local OriginalButtonPositions: { [TextButton]: UDim2 } = {}

local function registerButton(button: TextButton)
	if OriginalButtonPositions[button] then
		return
	end

	OriginalButtonPositions[button] = button.Position
end

local function tryRegisterDescendant(descendant: Instance)
	if descendant:IsA("TextButton") then
		registerButton(descendant)
	end
end

for _, descendant in ipairs(RadialBillboard:GetDescendants()) do
	tryRegisterDescendant(descendant)
end

RadialBillboard.DescendantAdded:Connect(function(descendant)
	tryRegisterDescendant(descendant)
end)

local function AnimateButtonsIn()
	for _, button in pairs(RadialBillboard:GetDescendants()) do
		if button:IsA("TextButton") then
			registerButton(button)
			-- Tween the button to the HubFrame position
			local targetPosition = HubFrame.Position
			local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.In)
			local tween = TweenService:Create(button, tweenInfo, { Position = targetPosition })
			tween:Play()
		end
	end
end

local function AnimateButtonsOut()
	for _, button in pairs(RadialBillboard:GetDescendants()) do
		if button:IsA("TextButton") then
			-- Tween the button back to its original position, by default the position of buttons are already in original position so might have to set it to hubframe position first
			-- Need to find a way to store original position
			registerButton(button)

			button.Position = HubFrame.Position
			local originalPosition = OriginalButtonPositions[button]
			if originalPosition then
				local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				local tween = TweenService:Create(button, tweenInfo, { Position = originalPosition })
				tween:Play()
			end
		end
	end
end

function BillboardRadialUI.Init()
	print("BillboardRadialUI initialized.")
end
function BillboardRadialUI.Show(adornee: Model)
	local plotModel = PlotFinder.FindPlot(player:GetAttribute("OwnedPlotIndex") :: number)

	if not plotModel then
		warn("No plot model found.")
		return
	end
	local containerFolder = plotModel:FindFirstChild("Container") :: Folder
	RadialBillboard.Parent = containerFolder
	RadialBillboard.Adornee = adornee
	CenterLabel.Text = adornee.Name
	AnimateButtonsOut()
end

function BillboardRadialUI.Hide()
	RadialBillboard.Parent = AssetsFolder.VisualTools
	RadialBillboard.Adornee = AssetsFolder.VisualTools
	CenterLabel.Text = "Object"
	AnimateButtonsIn()
end
return BillboardRadialUI
