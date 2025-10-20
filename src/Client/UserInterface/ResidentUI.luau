--!strict
-- StarterPlayerScripts/Client/UserInterface/NeedsInterface.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ResidentUIEnabled = ActiveQueryFolder:FindFirstChild("ResidentUIEnabled") :: BoolValue

local ResidentGui = PlayerGui:WaitForChild("ResidentGui") :: ScreenGui
local MainFrame = ResidentGui:WaitForChild("Main") :: Frame
local HungerInfoBar = MainFrame:WaitForChild("HungerInfoBar") :: Frame
local EnergyInfoBar = MainFrame:WaitForChild("EnergyInfoBar") :: Frame
local FunInfoBar = MainFrame:WaitForChild("FunInfoBar") :: Frame
local SocialInfoBar = MainFrame:WaitForChild("SocialInfoBar") :: Frame
local HygieneInfoBar = MainFrame:WaitForChild("HygieneInfoBar") :: Frame

local JobPackets = require(ReplicatedStorage.Network.JobPackets)

local ResidentUI = {}
local Connections = {} :: { RBXScriptConnection }
local CurrentSelected = nil :: Model?
local WorkButton: TextButton? = nil
local workingResidents: { [string]: boolean } = {}

local BUTTON_DEFAULT_COLOR = Color3.fromRGB(0, 170, 255)
local BUTTON_STOP_COLOR = Color3.fromRGB(220, 70, 70)

local function updateWorkButtonDisplay(residentModel: Model?)
	if not WorkButton then
		return
	end
	if not residentModel then
		WorkButton.Visible = false
		return
	end
	local residentName = residentModel.Name
	local isWorking = workingResidents[residentName] == true
	WorkButton.Visible = true
	WorkButton.Text = if isWorking then "End Shift" else "Start Work"
	WorkButton.BackgroundColor3 = if isWorking then BUTTON_STOP_COLOR else BUTTON_DEFAULT_COLOR
	WorkButton.AutoButtonColor = true
	WorkButton.Active = true
end

local function setWorkingState(residentName: string, isWorking: boolean)
	workingResidents[residentName] = isWorking
	if CurrentSelected and CurrentSelected.Name == residentName then
		updateWorkButtonDisplay(CurrentSelected)
	end
end

local function ensureWorkButton()
	if WorkButton then
		return
	end
	local button = Instance.new("TextButton")
	button.Name = "WorkToggleButton"
	button.Size = UDim2.fromOffset(180, 40)
	button.Position = UDim2.new(0.5, 0, 1, 12)
	button.AnchorPoint = Vector2.new(0.5, 0)
	button.BackgroundColor3 = BUTTON_DEFAULT_COLOR
	button.BorderSizePixel = 0
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Font = Enum.Font.GothamMedium
	button.TextSize = 16
	button.Text = "Start Work"
	button.AutoButtonColor = true
	button.Visible = false
	button.Parent = MainFrame

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button

	WorkButton = button
	button.Activated:Connect(function()
		local selected = CurrentSelected
		if not selected then
			return
		end
		local residentName = selected.Name
		local isWorking = workingResidents[residentName] == true
		button.Active = false
		button.AutoButtonColor = false
		if isWorking then
			local success, message, payout = JobPackets.StopResidentShift:Fire(residentName)
			if not success then
				warn(string.format("Failed to end shift for %s: %s", residentName, tostring(message)))
			else
				setWorkingState(residentName, false)
				if type(payout) == "number" and payout > 0 then
					print(string.format("%s earned $%d this shift.", residentName, payout))
				end
			end
		else
			local success, message = JobPackets.StartResidentShift:Fire(residentName)
			if not success then
				warn(string.format("Failed to start shift for %s: %s", residentName, tostring(message)))
			else
				setWorkingState(residentName, true)
			end
		end
		button.Active = true
		button.AutoButtonColor = true
		updateWorkButtonDisplay(CurrentSelected)
	end)
end

function ResidentUI.Init()
	ensureWorkButton()
end

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

	ensureWorkButton()
	workingResidents[residentModel.Name] = residentModel:GetAttribute("IsOnShift") == true
	updateWorkButtonDisplay(residentModel)

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
			if CurrentSelected == residentModel then
				updateWorkButtonDisplay(residentModel)
			end
		end)
	)
end

function ResidentUI.Hide(isOnlyUI: boolean?)
	if isOnlyUI then
		ResidentGui.Enabled = false
		ResidentUIEnabled.Value = false
		if WorkButton then
			updateWorkButtonDisplay(nil)
		end
		return
	end
	ResidentGui.Enabled = false
	ResidentUIEnabled.Value = false
	CurrentSelected = nil
	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end
	if WorkButton then
		updateWorkButtonDisplay(nil)
	end
end

function ResidentUI.GetCurrentSelectedResident()
	return CurrentSelected
end
return ResidentUI
