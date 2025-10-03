--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotGridOverlay.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")

local PlotContext = InputContextsFolder:WaitForChild("PlotContext")
local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotGridOverlayEnabled = ActiveQueryFolder:FindFirstChild("PlotGridOverlayEnabled")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")

local PlotGridOverlay = {}

function PlotGridOverlay.Init()
	print("PlotGridOverlay module initialized.")

	-- Ensure the grid overlay is also toggled off when PlotBuilder is disabled
	-- grid overlay should only be available when plot builder is active
	PlotBuilderEnabled.Changed:Connect(function()
		if not PlotBuilderEnabled.Value then
			PlotGridOverlay.Hide()
			PlotContext.ToggleGridAction.Enabled = false
		else
			PlotContext.ToggleGridAction.Enabled = true
		end
	end)

	PlotContext.ToggleGridAction.Pressed:Connect(function()
		print("PlotContext button pressed.")
		PlotGridOverlayEnabled.Value = not PlotGridOverlayEnabled.Value
		if PlotGridOverlayEnabled.Value then
			PlotGridOverlay.Show()
		else
			PlotGridOverlay.Hide()
		end
	end)
end

function PlotGridOverlay.Show()
	print("Showing plot grid.")
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local GridSurface = plotModel and plotModel:FindFirstChild("GridSurface") :: BasePart

	local gridVisual = GridSurface and GridSurface:FindFirstChild("GridVisual") :: Texture

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	gridVisual.Transparency = 0
	PlotGridOverlayEnabled.Value = true
end

function PlotGridOverlay.Hide()
	print("Hiding plot grid.")

	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local GridSurface = plotModel and plotModel:FindFirstChild("GridSurface") :: BasePart

	local gridVisual = GridSurface and GridSurface:FindFirstChild("GridVisual") :: Texture

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	gridVisual.Transparency = 1
	PlotGridOverlayEnabled.Value = false
end

return PlotGridOverlay
