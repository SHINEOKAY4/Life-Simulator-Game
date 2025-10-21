--!strict
-- StarterPlayerScripts/Client/UserInterface/NeedsInterface.lua

local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ResidentUIEnabled = ActiveQueryFolder:FindFirstChild("ResidentUIEnabled") :: BoolValue

local ResidentGui = PlayerGui:WaitForChild("ResidentGui") :: ScreenGui
local ResidentNeedsFrame = ResidentGui:WaitForChild("ResidentNeedsFrame") :: Frame
local HungerInfoBar = ResidentNeedsFrame:WaitForChild("HungerInfoBar") :: Frame
local EnergyInfoBar = ResidentNeedsFrame:WaitForChild("EnergyInfoBar") :: Frame
local FunInfoBar = ResidentNeedsFrame:WaitForChild("FunInfoBar") :: Frame
local SocialInfoBar = ResidentNeedsFrame:WaitForChild("SocialInfoBar") :: Frame
local HygieneInfoBar = ResidentNeedsFrame:WaitForChild("HygieneInfoBar") :: Frame

local ResidentUI = {}
local Connections = {} :: { RBXScriptConnection }
local CurrentSelected = nil :: Model?

local workingResidents: { [string]: boolean } = {}

function ResidentUI.Init() end

function ResidentUI.Show(residentModel: Model)
	if CurrentSelected == residentModel then
		return
	end
	CurrentSelected = residentModel
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
	ResidentGui.Enabled = true
	ResidentUIEnabled.Value = true
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
		local percentLabel = foreground:FindFirstChild("Percent") :: TextLabel
		percentLabel.Text = tostring(math.floor(value)) .. "%"
		bar.BackgroundColor3 = barColor
		bar.Size = UDim2.fromScale(value / 100, 1)
	end

	updateBar(HungerInfoBar, hunger)
	updateBar(EnergyInfoBar, energy)
	updateBar(FunInfoBar, fun)
	updateBar(SocialInfoBar, social)
	updateBar(HygieneInfoBar, hygiene)
	-- Connect signals to update bars when attributes change
	workingResidents[residentModel.Name] = residentModel:GetAttribute("IsOnShift") == true

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
	table.insert(
		Connections,
		residentModel:GetAttributeChangedSignal("IsOnShift"):Connect(function()
			local isWorking = residentModel:GetAttribute("IsOnShift") == true
			workingResidents[residentModel.Name] = isWorking
		end)
	)
end

function ResidentUI.Hide(isOnlyUI: boolean?)
	if isOnlyUI then
		ResidentNeedsFrame.Visible = false
		ResidentUIEnabled.Value = false
		return
	end
	ResidentNeedsFrame.Visible = false
	ResidentUIEnabled.Value = false
	CurrentSelected = nil
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
end

function ResidentUI.GetCurrentSelectedResident()
	return CurrentSelected
end
return ResidentUI
