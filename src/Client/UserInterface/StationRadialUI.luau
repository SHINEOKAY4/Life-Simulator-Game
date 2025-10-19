-- ServerScriptService/Client/UserInterface/StationRadialUI.lua

local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentUI = require(script.Parent.ResidentUI)
local ResidentController = require(script.Parent.Parent.Modules.ResidentController)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local StationSelectorContext = InputContextsFolder:WaitForChild("StationSelectorContext")

local _ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local StationRadial = PlayerGui:WaitForChild("StationRadial") :: BillboardGui
local HubFrame = StationRadial:WaitForChild("Root"):FindFirstChild("Hub") :: Frame
local Root = StationRadial:FindFirstChild("Root") :: Frame
local AssignButton = Root:FindFirstChild("AssignButton") :: TextButton

local StationRadialUI = {}
local OriginalButtonPositions: { [TextButton]: UDim2 } = {}
local CurrentSelectedStation: Model? = nil
local INPUT_DEBOUNCE_SECONDS = 0.2

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("StationRadialUI/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, Player.UserId)
end

local function TextGenerator(stationType: string): string
	if stationType == "CookStation" then
		return "Cook"
	elseif stationType == "FunStation" then
		return "Play"
	elseif stationType == "RestStation" then
		return "Rest"
	elseif stationType == "HygieneStation" then
		return "Clean Up"
	elseif stationType == "SocialStation" then
		return "Socialize"
	end

	return "Unknown Station"
end

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

for _, descendant in ipairs(StationRadial:GetDescendants()) do
	tryRegisterDescendant(descendant)
end

StationRadial.DescendantAdded:Connect(function(descendant)
	tryRegisterDescendant(descendant)
end)

local function animateButtonsOut()
	if not HubFrame then
		return
	end

	for _, descendant in ipairs(StationRadial:GetDescendants()) do
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

function StationRadialUI.Init()
	-- Initialize the UI elements here
	StationSelectorContext.CloseStation.Pressed:Connect(function()
		runDebounced("Close", function()
			StationRadialUI.Hide()
		end)
	end)

	StationSelectorContext.AssignResident.Pressed:Connect(function()
		runDebounced("Assign", function()
			local currentStation = StationRadialUI.GetCurrentSelectedStation()
			local residentModel = ResidentUI.GetCurrentSelectedResident()
			local currentStationName = currentStation and currentStation.Name or "None"
			local residentName = residentModel and residentModel.Name or "None"

			if currentStation and residentModel then
				local success, message = ResidentController.RequestResidentToStation(residentName, currentStationName)
				if not success then
					warn(message or "Failed to assign resident to station")
				end
			end
			StationRadialUI.Hide()
		end)
	end)
end

function StationRadialUI.Show(adorneeModel: Model, stationType: string)
	if CurrentSelectedStation == adorneeModel then
		return
	end
	StationRadial.Enabled = true
	StationRadial.Adornee = adorneeModel
	local text = TextGenerator(stationType)
	AssignButton.Text = text
	CurrentSelectedStation = adorneeModel
	animateButtonsOut()
end

function StationRadialUI.Hide()
	--StationRadial.Enabled = false -- Commented out because we want to keep it enabled for input to finish processing
	StationRadial.Adornee = nil
	CurrentSelectedStation = nil
end

function StationRadialUI.GetCurrentSelectedStation(): Model?
	return CurrentSelectedStation
end
return StationRadialUI
