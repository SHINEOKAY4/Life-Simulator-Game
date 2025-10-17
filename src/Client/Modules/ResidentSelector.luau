--!strict
-- ServerScriptService/Client/Modules/ResidentSelector.lua

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local ResidentRadialUI = require(script.Parent.Parent.UserInterface.ResidentRadialUI)
local NeedsInterface = require(script.Parent.Parent.UserInterface.NeedsInterface)

local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local ResidentSelectorContext = InputContextsFolder:WaitForChild("ResidentSelectorContext")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled") :: BoolValue
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled") :: BoolValue
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled") :: BoolValue
local RadialBillboardButtonEnabled = ActiveQueryFolder:WaitForChild("RadialBillboardButtonEnabled") :: BoolValue
local ResidentRadialEnabled = ActiveQueryFolder:FindFirstChild("ResidentRadialEnabled") :: BoolValue
local ObjectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled") :: BoolValue

local ResidentSelector = {}

local function OnWorldClick()
	local plotModel = PlotStateStore.GetPlotModel()
	if not plotModel then
		warn("No plot model found.")
		return
	end

	local residentFolder = plotModel:FindFirstChild("Residents") :: Folder

	local unitRay = Player:GetMouse().UnitRay

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = { residentFolder }
	raycastParams.IgnoreWater = true

	local raycastResult = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, raycastParams)

	if raycastResult and raycastResult.Instance then
		local hitPart = raycastResult.Instance
		local selectedModel = hitPart:FindFirstAncestorOfClass("Model")
		if not selectedModel:FindFirstChild("Humanoid") then
			warn("Selected model is not a resident (missing Humanoid):", selectedModel:GetFullName())
			return
		end
		if not selectedModel then
			warn("No model ancestor found for hit part:", hitPart:GetFullName())
			return
		end

		if ResidentRadialEnabled.Value then
			return
		end

		ResidentRadialUI.Show(selectedModel)
		NeedsInterface.Show(selectedModel)
	else
		ResidentRadialUI.Hide()
		NeedsInterface.Hide()
	end
end

function ResidentSelector.Init()
	ObjectSelectorEnabled.Changed:Connect(function()
		if ObjectSelectorEnabled.Value then
			ResidentSelectorContext.Enabled = false
		else
			ResidentSelectorContext.Enabled = true
		end
	end)

	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value then
			ResidentSelectorContext.Enabled = false
		else
			ResidentSelectorContext.Enabled = true
		end
	end)

	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value then
			ResidentSelectorContext.Enabled = false
		else
			ResidentSelectorContext.Enabled = true
		end
	end)

	RadialBillboardButtonEnabled.Changed:Connect(function()
		if RadialBillboardButtonEnabled.Value then
			ResidentSelectorContext.Enabled = false
		else
			ResidentSelectorContext.Enabled = true
		end
	end)

	ResidentSelectorContext.SelectResident.Pressed:Connect(function()
		if
			ObjectSelectorEnabled.Value
			or PlotBuilderEnabled.Value
			or PlotExpansionEnabled.Value
			or RadialBillboardButtonEnabled.Value
		then
			return
		end
		OnWorldClick()
	end)
end

function ResidentSelector.Show() end

function ResidentSelector.Hide() end

return ResidentSelector
