-- ServerScriptService/Client/UserInterface/ResidentRadialUI.lua

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local ResidentSelectorContext = InputContextsFolder:WaitForChild("ResidentSelectorContext")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ResidentRadial = PlayerGui:WaitForChild("ResidentRadial") :: BillboardGui
local HubFrame = ResidentRadial:WaitForChild("Root"):FindFirstChild("Hub") :: Frame

local ResidentRadialUI = {}
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

for _, descendant in ipairs(ResidentRadial:GetDescendants()) do
	tryRegisterDescendant(descendant)
end

ResidentRadial.DescendantAdded:Connect(function(descendant)
	tryRegisterDescendant(descendant)
end)

local function animateButtonsOut()
	if not HubFrame then
		return
	end

	for _, descendant in ipairs(ResidentRadial:GetDescendants()) do
		if descendant:IsA("TextButton") then
			registerButton(descendant)
			descendant.Position = HubFrame.Position
			local originalPosition = OriginalButtonPositions[descendant]
			if originalPosition then
				local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				local tween = TweenService:Create(descendant, tweenInfo, { Position = originalPosition })
				tween:Play()
			end
		end
	end
end

function ResidentRadialUI.Init()
	-- Initialize the UI elements here
	ResidentSelectorContext.CustomizeResident.Pressed:Connect(function()
		if ResidentRadial.Enabled then
			--#TODO: Open customization menu
			ResidentRadialUI.Hide()
		end
	end)

	ResidentSelectorContext.CloseResident.Pressed:Connect(function()
		if ResidentRadial.Enabled then
			ResidentRadialUI.Hide()
		end
	end)

	ResidentSelectorContext.ProfileResident.Pressed:Connect(function()
		if ResidentRadial.Enabled then
			--#TODO: Open profile menu
			ResidentRadialUI.Hide()
		end
	end)

	ResidentSelectorContext.CommandResident.Pressed:Connect(function()
		if ResidentRadial.Enabled then
			--#TODO: Open command menu
			ResidentRadialUI.Hide()
		end
	end)
end

function ResidentRadialUI.Show(adorneeModel: Model)
	ResidentRadial.Enabled = true
	ResidentRadial.Adornee = adorneeModel
	animateButtonsOut()
end

function ResidentRadialUI.Hide()
	ResidentRadial.Enabled = false
end

return ResidentRadialUI
