--!strict
-- StarterPlayerScripts/Client/Modules/ObjectSelector.lua

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local BillboardRadialUI = require(script.Parent.Parent.UserInterface.BillboardRadialUI)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local ObjectSelectorContext = InputContextsFolder:WaitForChild("ObjectSelectorContext")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local SelectionHighlight = AssetsFolder.VisualTools:WaitForChild("SelectionHighlight") :: Highlight

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled") :: BoolValue
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled") :: BoolValue
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled") :: BoolValue
local RadialBillboardButtonEnabled = ActiveQueryFolder:WaitForChild("RadialBillboardButtonEnabled") :: BoolValue
local ObjectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled") :: BoolValue

local ObjectSelector = {}

local function ClearSelection()
	SelectionHighlight.Adornee = nil
	BillboardRadialUI.Hide()
end

local function OnWorldClick()
	print("Mouse button 1 pressed - ObjectSelector action triggered.")
	local plotModel = PlotStateStore.GetPlotModel()
	if not plotModel then
		warn("No plot model found.")
		return
	end

	if ObjectPreviewEnabled.Value then -- if object preview is active, ignore selection input
		return
	end
	local containerFolder = plotModel:FindFirstChild("Container") :: Folder

	local unitRay = Player:GetMouse().UnitRay

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { containerFolder }
	raycastParams.IgnoreWater = true

	local raycastResult = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 40, raycastParams)

	if raycastResult and raycastResult.Instance then
		local hitPart = raycastResult.Instance
		local selectedModel = hitPart:FindFirstAncestorOfClass("Model")
		print("Selected model:", selectedModel:GetFullName())
		SelectionHighlight.Adornee = selectedModel
		-- then open context menu for actions (e.g., delete, move, rotate) / radial menu controller script
		BillboardRadialUI.Show(selectedModel)
	else
		print("No model selected.")
		ClearSelection()
	end
end

function ObjectSelector.Init()
	print("ObjectSelector module initialized.")

	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value and ObjectSelectorEnabled.Value then
			ObjectSelector.Hide()
		end
	end)
	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value and ObjectSelectorEnabled.Value then
			ObjectSelector.Hide()
		end
	end)

	--ObjectPreviewEnabled.Changed:Connect(function()
	--	if ObjectPreviewEnabled.Value and ObjectSelectorEnabled.Value then
	--ObjectSelector.Hide()
	--	end
	--end)

	ObjectSelectorContext.SelectObject.Pressed:Connect(function()
		if RadialBillboardButtonEnabled.Value then
			return
		end
		OnWorldClick()
	end)

	ObjectSelectorContext.Toggle.Pressed:Connect(function()
		print("Toggling Object Selector")
		if not PlotFinder.IsWithinBounds(Player) then
			warn("Player is not within plot bounds.")
			return
		end

		ObjectSelectorEnabled.Value = not ObjectSelectorEnabled.Value

		if ObjectSelectorEnabled.Value then
			print("Object Selector Enabled")
			ObjectSelector.Show()
		else
			print("Object Selector Disabled")
			ObjectSelector.Hide()
		end
	end)

	Player:GetAttributeChangedSignal("WithinPlot"):Connect(function()
		local IsWithinBounds = Player:GetAttribute("WithinPlot")
		if not IsWithinBounds then
			ObjectSelector.Hide()
		end
	end)
end

function ObjectSelector.Show()
	ObjectSelectorEnabled.Value = true
	ObjectSelectorContext.SelectObject.Enabled = true
	PlotFinder.StartTracking(Player)
end

function ObjectSelector.Hide()
	ObjectSelectorEnabled.Value = false -- Do not put this in Clear selection function so we can call ClearSelection without disabling the selector
	ObjectSelectorContext.SelectObject.Enabled = false
	ClearSelection()
end
return ObjectSelector
