--!strict
-- StarterPlayerScripts/Client/UserInterface/ResidentRoster.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local ResidentNeedsUI = require(script.Parent.ResidentNeedsUI)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ResidentsStore = require(script.Parent.Parent.ClientStores.ResidentsStore)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ResidentGui = PlayerGui:WaitForChild("ResidentGui")
local Profile = ResidentGui:WaitForChild("Profile")
local ResidentSelectionFrame = ResidentGui:WaitForChild("ResidentSelectionFrame")
local ResidentNeedsFrame = ResidentGui:WaitForChild("ResidentNeedsFrame")
local ResidentButtons = ResidentGui:WaitForChild("ResidentButtons")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled") :: BoolValue
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled") :: BoolValue
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled") :: BoolValue
local RadialBillboardButtonEnabled = ActiveQueryFolder:WaitForChild("RadialBillboardButtonEnabled") :: BoolValue
local JobSelectionUIEnabled = ActiveQueryFolder:FindFirstChild("JobSelectionUIEnabled") :: BoolValue
local _ResidentRadialEnabled = ActiveQueryFolder:FindFirstChild("ResidentRadialEnabled") :: BoolValue

local Roster = ResidentSelectionFrame.Background.Roster

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local InterfacesTemplates = AssetsFolder:WaitForChild("InterfacesTemplates")
local TemplateFrame = InterfacesTemplates:WaitForChild("ResidentFrameTemplate")

local HoverTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HoverSizeGoal = UDim2.fromScale(0.155, 1.525)

local INPUT_DEBOUNCE_SECONDS = 0.2

type FrameInfo = {
	Frame: Frame,
	DefaultSize: UDim2,
	PlaySizeTween: (UDim2) -> (),
}

local ResidentRoster = {}
local Connections = {} :: { [string]: { RBXScriptConnection } }
local FrameData = {} :: { [string]: FrameInfo }
local SelectedResidentName: string? = nil

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("ResidentRoster/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, Player.UserId)
end

local function deselectResident()
	local currentName = SelectedResidentName
	if not currentName then
		return
	end

	local currentData = FrameData[currentName]
	if currentData then
		currentData.PlaySizeTween(currentData.DefaultSize)
	end
	SelectedResidentName = nil
	ResidentNeedsFrame.Visible = false
	ResidentButtons.Visible = false
	Profile.Visible = false
	ResidentNeedsUI.Hide()
end

local function selectResident(residentName: string, residentModel: Model)
	if SelectedResidentName == residentName then
		deselectResident()
		return
	end

	local previousName = SelectedResidentName
	if previousName and previousName ~= residentName then
		local previousData = FrameData[previousName]
		if previousData then
			previousData.PlaySizeTween(previousData.DefaultSize)
		end
	end

	SelectedResidentName = residentName
	ResidentSelectionFrame.Visible = true
	ResidentNeedsFrame.Visible = true
	ResidentButtons.Visible = true
	ResidentNeedsUI.Show(residentModel)

	local currentData = FrameData[residentName]
	if currentData then
		currentData.PlaySizeTween(HoverSizeGoal)
	end
end

local function CreateResidentImageButton(residentData: any)
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local residentsFolder = plotModel:FindFirstChild("Residents") :: Folder
	local residentModel = residentsFolder:FindFirstChild(residentData.Name) :: Model
	local imageModel = residentModel:Clone()

	local newFrame = TemplateFrame:Clone()
	newFrame.Name = residentData.Name
	local portraitButton = newFrame.PortraitButton
	local residentNameLabel = newFrame.ResidentName
	local viewportFrame = portraitButton.Image.ViewportFrame
	local worldModel = viewportFrame.WorldModel
	local targetPivot = CFrame.new(0, -1, 4, -1, 0, 0, 0, 1, 0, 0, 0, -1)
	local defaultSize = newFrame.Size
	local activeTween: Tween? = nil

	local function playSizeTween(targetSize: UDim2)
		if activeTween then
			activeTween:Cancel()
		end
		local newTween = TweenService:Create(newFrame, HoverTweenInfo, { Size = targetSize })
		activeTween = newTween
		newTween:Play()
	end
	residentNameLabel.Text = residentData.Name
	local animateScript = imageModel:FindFirstChild("Animate") :: Script
	if animateScript then
		animateScript:Destroy()
	end
	imageModel.Parent = worldModel
	imageModel:PivotTo(targetPivot)

	local mouseEnterConnection = portraitButton.MouseEnter:Connect(function()
		playSizeTween(HoverSizeGoal)
	end)
	local mouseLeaveConnection = portraitButton.MouseLeave:Connect(function()
		if SelectedResidentName == residentData.Name then
			return
		end
		playSizeTween(defaultSize)
	end)
	Connections[residentData.Name] = { mouseEnterConnection, mouseLeaveConnection }
	FrameData[residentData.Name] = {
		Frame = newFrame,
		DefaultSize = defaultSize,
		PlaySizeTween = playSizeTween,
	}
	newFrame.Parent = Roster
	return newFrame, residentModel
end

function ResidentRoster.Init(): ()
	-- Placeholder for future Resident Roster UI initialization.

	ObjectSelectorEnabled.Changed:Connect(function()
		if ObjectSelectorEnabled.Value then
			ResidentRoster.Hide()
		else
			ResidentSelectionFrame.Visible = true
		end
	end)
	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value then
			ResidentRoster.Hide()
		else
			ResidentSelectionFrame.Visible = true
		end
	end)

	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value then
			ResidentRoster.Hide()
		else
			ResidentSelectionFrame.Visible = true
		end
	end)
	RadialBillboardButtonEnabled.Changed:Connect(function()
		if RadialBillboardButtonEnabled.Value then
			ResidentRoster.Hide()
		else
			ResidentSelectionFrame.Visible = true
		end
	end)

	JobSelectionUIEnabled.Changed:Connect(function()
		if JobSelectionUIEnabled.Value then
			ResidentRoster.Hide()
		else
			ResidentSelectionFrame.Visible = true
		end
	end)
	ResidentsStore.ResidentAdded:Connect(function(userId: number, residentData: any)
		print("Resident added for userId:", userId, "Resident Name:", residentData.Name)
		local residentFrame, residentModel = CreateResidentImageButton(residentData)
		local portraitButton = residentFrame.PortraitButton :: TextButton
		local activationConnection = portraitButton.Activated:Connect(function()
			runDebounced(string.format("Select/%s", residentData.Name), function()
				print("Selected resident:", residentData.Name)
				selectResident(residentData.Name, residentModel)
			end)
		end)
		Connections[residentData.Name] = Connections[residentData.Name] or {}
		table.insert(Connections[residentData.Name], activationConnection)
	end)

	ResidentsStore.ResidentRemoved:Connect(function(userId: number, residentName: string)
		print("Resident removed for userId:", userId, "Resident Name:", residentName)
		local residentFrame = Roster:FindFirstChild(residentName) :: Frame
		if residentFrame then
			residentFrame:Destroy()
		end
		local residentConnections = Connections[residentName]
		if residentConnections then
			for _, connection in ipairs(residentConnections) do
				connection:Disconnect()
			end
			Connections[residentName] = nil
		end
		FrameData[residentName] = nil
		if SelectedResidentName == residentName then
			deselectResident()
		end
	end)
end

function ResidentRoster.Hide()
	deselectResident()
	ResidentSelectionFrame.Visible = false
end
return ResidentRoster
