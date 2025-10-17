--!strict
-- ServerScriptService/Client/Modules/ResidentSelector.lua

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local ResidentController = require(script.Parent.ResidentController)
local ResidentRadialUI = require(script.Parent.Parent.UserInterface.ResidentRadialUI)
local ResidentUI = require(script.Parent.Parent.UserInterface.ResidentUI)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local Player = Players.LocalPlayer

local PlayerGui = Player:WaitForChild("PlayerGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local ResidentSelectorContext = InputContextsFolder:WaitForChild("ResidentSelectorContext")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled") :: BoolValue
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled") :: BoolValue
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled") :: BoolValue
local RadialBillboardButtonEnabled = ActiveQueryFolder:WaitForChild("RadialBillboardButtonEnabled") :: BoolValue
local JobSelectionUIEnabled = ActiveQueryFolder:FindFirstChild("JobSelectionUIEnabled") :: BoolValue
local _ResidentRadialEnabled = ActiveQueryFolder:FindFirstChild("ResidentRadialEnabled") :: BoolValue
--local ObjectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled") :: BoolValue

local ResidentSelector = {}

local DOUBLE_CLICK_WINDOW = 0.2

type PendingMove = {
	Resident: Model,
	Timestamp: number,
}

local pendingMove: PendingMove? = nil

local function resetPendingMove()
	pendingMove = nil
end

local function findStationUnderCursor(unitRay: Ray, plotModel: Model): Model?
	local container = plotModel:FindFirstChild("Container")
	if not container then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { container }
	params.IgnoreWater = true

	local result = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, params)
	if not result or not result.Instance then
		return nil
	end

	local hitModel = result.Instance:FindFirstAncestorOfClass("Model")
	if not hitModel then
		return nil
	end

	local itemIdAttr = hitModel:GetAttribute("ItemId")
	if typeof(itemIdAttr) ~= "string" or itemIdAttr == "" then
		return nil
	end

	local itemSpec = ItemFinder.FindItemById(itemIdAttr)
	if not itemSpec or itemSpec.Station ~= true then
		return nil
	end

	return hitModel
end

local function OnWorldClick()
	local plotModel = PlotStateStore.GetPlotModel()
	if not plotModel then
		warn("No plot model found.")
		return
	end

	local unitRay = Player:GetMouse().UnitRay
	local residentFolder = plotModel:FindFirstChild("Residents")
	local residentParams = RaycastParams.new()
	residentParams.FilterType = Enum.RaycastFilterType.Include
	residentParams.FilterDescendantsInstances = if residentFolder then { residentFolder } else {}
	residentParams.IgnoreWater = true

	local residentHit = if residentFolder
		then Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, residentParams)
		else nil

	if residentHit and residentHit.Instance then
		local selectedModel = residentHit.Instance:FindFirstAncestorOfClass("Model")
		if not selectedModel or not selectedModel:FindFirstChildOfClass("Humanoid") then
			return
		end

		resetPendingMove()
		ResidentUI.Show(selectedModel)
		return
	end

	local residentModel = ResidentUI.GetCurrentSelectedResident()
	if residentModel then
		local stationModel = findStationUnderCursor(unitRay, plotModel)
		if stationModel then
			resetPendingMove()
			ResidentRadialUI.Show(stationModel)
			return
		end
	end

	if not residentModel then
		warn("No resident currently selected to move.")
		resetPendingMove()
		return
	end

	local activeResident = residentModel :: Model

	local ignoreList = {}
	if Player.Character then
		table.insert(ignoreList, Player.Character)
	end
	if residentFolder then
		table.insert(ignoreList, residentFolder)
	end
	local movementParams = RaycastParams.new()
	movementParams.FilterType = Enum.RaycastFilterType.Exclude
	movementParams.FilterDescendantsInstances = ignoreList
	movementParams.IgnoreWater = true

	local movementHit = Workspace:Raycast(unitRay.Origin, unitRay.Direction * 1000, movementParams)
	local targetPosition = if movementHit then movementHit.Position else (unitRay.Origin + unitRay.Direction * 100)

	local now = os.clock()
	local pending = pendingMove
	if pending and pending.Resident == activeResident then
		if now - pending.Timestamp <= DOUBLE_CLICK_WINDOW then
			resetPendingMove()
			local success, message = ResidentController.RequestMoveToLocation(activeResident, targetPosition)
			if not success then
				warn(message or "Failed to request resident movement")
			end
			return
		end
	end

	pendingMove = {
		Resident = activeResident,
		Timestamp = now,
	}
end

function ResidentSelector.Init()
	ObjectSelectorEnabled.Changed:Connect(function()
		if ObjectSelectorEnabled.Value and ResidentSelectorContext.Enabled then
			ResidentSelectorContext.Enabled = false
			ResidentUI.Hide()
		else
			ResidentSelectorContext.Enabled = true
		end
	end)

	JobSelectionUIEnabled.Changed:Connect(function()
		if JobSelectionUIEnabled.Value and ResidentSelectorContext.Enabled then
			ResidentSelectorContext.Enabled = false
			ResidentUI.Hide()
		else
			ResidentSelectorContext.Enabled = true
		end
	end)
	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value and ResidentSelectorContext.Enabled then
			ResidentSelectorContext.Enabled = false
			ResidentUI.Hide()
		else
			ResidentSelectorContext.Enabled = true
		end
	end)

	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value and ResidentSelectorContext.Enabled then
			ResidentSelectorContext.Enabled = false
			ResidentUI.Hide()
		else
			ResidentSelectorContext.Enabled = true
		end
	end)

	RadialBillboardButtonEnabled.Changed:Connect(function()
		if RadialBillboardButtonEnabled.Value and ResidentSelectorContext.Enabled then
			ResidentSelectorContext.Enabled = false
			ResidentUI.Hide()
		else
			ResidentSelectorContext.Enabled = true
		end
	end)

	ResidentSelectorContext.SelectResident.Pressed:Connect(function()
		-- Add all the conditions that would block resident selection here
		if
			ObjectSelectorEnabled.Value
			or PlotBuilderEnabled.Value
			or PlotExpansionEnabled.Value
			or RadialBillboardButtonEnabled.Value
			or JobSelectionUIEnabled.Value
		then
			return
		end
		OnWorldClick()
	end)
end

function ResidentSelector.Show() end

function ResidentSelector.Hide() end

return ResidentSelector
