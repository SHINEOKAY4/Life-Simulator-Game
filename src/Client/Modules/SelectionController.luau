--!strict
-- Client/Modules/SelectionController.luau
-- Handles always-on object selection via raycasting.

local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)

local SelectionController = {}
local SelectionChanged = GoodSignal.new()

local CurrentSelection: Instance? = nil
local CurrentKey: string? = nil

local function getMouseRay()
	local mouse = Players.LocalPlayer:GetMouse()
	return mouse.UnitRay
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local plotModel = PlotStateStore.GetPlotModel()
		if not plotModel then
			return
		end

		local container = plotModel:FindFirstChild("Container")
		if not container then
			return
		end

		local ray = getMouseRay()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Include
		params.FilterDescendantsInstances = { container }
		params.IgnoreWater = true

		local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

		local newSelection: Instance? = nil
		local newKey: string? = nil

		if result and result.Instance then
			-- Find the model or part that represents the placed object
			-- The container has children named by their PlacementKey
			local candidate = result.Instance
			while candidate and candidate.Parent ~= container do
				candidate = candidate.Parent
			end

			if candidate and candidate.Parent == container then
				newSelection = candidate
				newKey = candidate.Name
			end
		end

		if newSelection ~= CurrentSelection then
			CurrentSelection = newSelection
			CurrentKey = newKey
			SelectionChanged:Fire(CurrentSelection, CurrentKey)
		end
	end
end

function SelectionController.Init()
	UserInputService.InputBegan:Connect(onInputBegan)
end

function SelectionController.GetSelection(): (Instance?, string?)
	return CurrentSelection, CurrentKey
end

function SelectionController.OnSelectionChanged(callback: (Instance?, string?) -> ())
	return SelectionChanged:Connect(callback)
end

return SelectionController
