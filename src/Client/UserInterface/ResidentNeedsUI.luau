--!strict
-- StarterPlayerScripts/Client/UserInterface/NeedsInterface.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ResidentUIEnabled = ActiveQueryFolder:FindFirstChild("ResidentUIEnabled") :: BoolValue

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local CutawayViewController = require(script.Parent.Parent.Modules.CutawayViewController)

local ResidentGui = PlayerGui:WaitForChild("ResidentGui") :: ScreenGui
local ResidentNeedsFrame = ResidentGui:WaitForChild("ResidentNeedsFrame") :: Frame
local HungerInfoBar = ResidentNeedsFrame:WaitForChild("HungerInfoBar") :: Frame
local EnergyInfoBar = ResidentNeedsFrame:WaitForChild("EnergyInfoBar") :: Frame
local FunInfoBar = ResidentNeedsFrame:WaitForChild("FunInfoBar") :: Frame
local SocialInfoBar = ResidentNeedsFrame:WaitForChild("SocialInfoBar") :: Frame
local HygieneInfoBar = ResidentNeedsFrame:WaitForChild("HygieneInfoBar") :: Frame
local BladderInfoBar = ResidentNeedsFrame:WaitForChild("BladderInfoBar") :: Frame

local ResidentSelectionChangedSignal = GoodSignal.new()

local ResidentUI = {
	ResidentSelectionChanged = ResidentSelectionChangedSignal,
}
local Connections = {} :: { RBXScriptConnection }
local CurrentSelected = nil :: Model?
local CutawayLevelConnection: RBXScriptConnection? = nil

local CUTAWAY_SOURCE = "ResidentSelection"

local function updateResidentCutaway()
	if not CurrentSelected then
		return
	end
	CutawayViewController.Request(CUTAWAY_SOURCE, {
		Priority = 8,
		TargetLevel = PlotStateStore.GetActiveLevel(),
	})
end

local function releaseResidentCutaway()
	if CutawayLevelConnection then
		CutawayLevelConnection:Disconnect()
		CutawayLevelConnection = nil
	end
	CutawayViewController.Release(CUTAWAY_SOURCE)
end

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
	ResidentSelectionChangedSignal:Fire(residentModel)
	if CutawayLevelConnection then
		CutawayLevelConnection:Disconnect()
		CutawayLevelConnection = nil
	end
	updateResidentCutaway()
	CutawayLevelConnection = PlotStateStore.OnActiveLevelChanged(function()
		if CurrentSelected then
			updateResidentCutaway()
		end
	end)
	-- Update all bars initially
	local hunger = residentModel:GetAttribute("Hunger") :: number
	local energy = residentModel:GetAttribute("Energy") :: number
	local fun = residentModel:GetAttribute("Fun") :: number
	local social = residentModel:GetAttribute("Social") :: number
	local hygiene = residentModel:GetAttribute("Hygiene") :: number
	local bladder = residentModel:GetAttribute("Bladder") :: number

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
	updateBar(BladderInfoBar, bladder)
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
		residentModel:GetAttributeChangedSignal("Bladder"):Connect(function()
			local newBladder = residentModel:GetAttribute("Bladder") :: number
			updateBar(BladderInfoBar, newBladder)
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
	releaseResidentCutaway()
	ResidentNeedsFrame.Visible = false
	ResidentUIEnabled.Value = false
	CurrentSelected = nil
	ResidentSelectionChangedSignal:Fire(nil)
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
end

function ResidentUI.GetCurrentSelectedResident()
	return CurrentSelected
end
return ResidentUI
