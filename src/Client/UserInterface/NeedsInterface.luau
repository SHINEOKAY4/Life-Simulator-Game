--!strict
-- StarterPlayerScripts/Client/UserInterface/NeedsInterface.lua

local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ResidentNeedsGui = PlayerGui:WaitForChild("ResidentNeedsGui") :: ScreenGui
local MainFrame = ResidentNeedsGui:WaitForChild("Main") :: Frame
local HungerInfoBar = MainFrame:WaitForChild("HungerInfoBar") :: Frame
local EnergyInfoBar = MainFrame:WaitForChild("EnergyInfoBar") :: Frame
local FunInfoBar = MainFrame:WaitForChild("FunInfoBar") :: Frame
local SocialInfoBar = MainFrame:WaitForChild("SocialInfoBar") :: Frame
local HygieneInfoBar = MainFrame:WaitForChild("HygieneInfoBar") :: Frame

local NeedsInterface = {}
local Connections = {} :: { RBXScriptConnection }
local CurrentSelected = nil :: Model?

function NeedsInterface.Init()
	-- Initialization code for NeedsInterface goes here
end

function NeedsInterface.Show(residentModel: Model)
	if CurrentSelected == residentModel then
		return
	end
	CurrentSelected = residentModel
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
	ResidentNeedsGui.Enabled = true

	-- Update all bars initially
	local hunger = residentModel:GetAttribute("Hunger") :: number
	local energy = residentModel:GetAttribute("Energy") :: number
	local fun = residentModel:GetAttribute("Fun") :: number
	local social = residentModel:GetAttribute("Social") :: number
	local hygiene = residentModel:GetAttribute("Hygiene") :: number

	local function updateBar(infoBar: Frame, value: number)
		local foreground = infoBar:FindFirstChild("Foreground") :: Frame
		local bar = foreground:FindFirstChild("Bar") :: Frame
		local barColor = Color3.fromHSV((value / 100) * 0.33, 1, 1) -- Green to Red
		bar.BackgroundColor3 = barColor
		bar.Size = UDim2.fromScale(value / 100, 1)
	end

	updateBar(HungerInfoBar, hunger)
	updateBar(EnergyInfoBar, energy)
	updateBar(FunInfoBar, fun)
	updateBar(SocialInfoBar, social)
	updateBar(HygieneInfoBar, hygiene)
	-- Connect signals to update bars when attributes change

	--=======--
	table.insert(
		Connections,
		residentModel:GetAttributeChangedSignal("Hunger"):Connect(function()
			local newHunger = residentModel:GetAttribute("Hunger") :: number
			updateBar(HungerInfoBar, newHunger)
		end)
	)
	table.insert(
		Connections,
		residentModel:GetAttributeChangedSignal("Energy"):Connect(function()
			local newEnergy = residentModel:GetAttribute("Energy") :: number
			updateBar(EnergyInfoBar, newEnergy)
		end)
	)
	table.insert(
		Connections,
		residentModel:GetAttributeChangedSignal("Fun"):Connect(function()
			local newFun = residentModel:GetAttribute("Fun") :: number
			updateBar(FunInfoBar, newFun)
		end)
	)
	table.insert(
		Connections,
		residentModel:GetAttributeChangedSignal("Social"):Connect(function()
			local newSocial = residentModel:GetAttribute("Social") :: number
			updateBar(SocialInfoBar, newSocial)
		end)
	)
	table.insert(
		Connections,
		residentModel:GetAttributeChangedSignal("Hygiene"):Connect(function()
			local newHygiene = residentModel:GetAttribute("Hygiene") :: number
			updateBar(HygieneInfoBar, newHygiene)
		end)
	)
end

function NeedsInterface.Hide()
	ResidentNeedsGui.Enabled = false
	CurrentSelected = nil
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
end
return NeedsInterface
