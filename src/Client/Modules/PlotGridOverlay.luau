--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotGridOverlay.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")

local PlotContext = InputContextsFolder:WaitForChild("PlotContext")
local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotGridOverlayEnabled = ActiveQueryFolder:FindFirstChild("PlotGridOverlayEnabled")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")

local PlotGridOverlay = {}
local INPUT_DEBOUNCE_SECONDS = 0.2

local trackedSurface: BasePart? = nil
local surfaceAncestryConnection: RBXScriptConnection? = nil
local originalSurfaceCFrame: CFrame? = nil

local function resetSurfaceTracking()
	if surfaceAncestryConnection then
		surfaceAncestryConnection:Disconnect()
		surfaceAncestryConnection = nil
	end
	trackedSurface = nil
	originalSurfaceCFrame = nil
end

local function getGridSurface(): BasePart?
	local plotIndexValue = Player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndexValue) ~= "number" then
		return nil
	end

	local plotModel = PlotFinder.FindPlot(plotIndexValue)
	if not plotModel then
		return nil
	end

	local candidate = plotModel:FindFirstChild("GridSurface")
	if candidate and candidate:IsA("BasePart") then
		return candidate
	end

	return nil
end

local function ensureSurfaceTracked(surface: BasePart?): BasePart?
	if surface and surface == trackedSurface and originalSurfaceCFrame then
		return surface
	end

	if surfaceAncestryConnection then
		surfaceAncestryConnection:Disconnect()
		surfaceAncestryConnection = nil
	end

	if not surface then
		resetSurfaceTracking()
		return nil
	end

	trackedSurface = surface
	originalSurfaceCFrame = surface.CFrame
	surfaceAncestryConnection = surface.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			resetSurfaceTracking()
		end
	end)

	return surface
end

local function computeLevelOffset(level: number): number
	local defaultLevel = PlotStateStore.GetDefaultLevel()
	local floorHeight = PlotStateStore.GetFloorHeightStuds()
	return (level - defaultLevel) * floorHeight
end

local function updateGridSurfacePosition(targetLevel: number?): BasePart?
	local surface = ensureSurfaceTracked(getGridSurface())
	if not surface or not originalSurfaceCFrame then
		return nil
	end

	local resolvedLevel = if typeof(targetLevel) == "number" then targetLevel else PlotStateStore.GetActiveLevel()
	local offsetY = computeLevelOffset(resolvedLevel)
	local targetCFrame = originalSurfaceCFrame + Vector3.new(0, offsetY, 0)

	if surface.CFrame ~= targetCFrame then
		surface.CFrame = targetCFrame
	end

	return surface
end

function PlotGridOverlay.Init()
	-- Ensure the grid overlay is also toggled off when PlotBuilder is disabled
	-- grid overlay should only be available when plot builder is active
	PlotBuilderEnabled.Changed:Connect(function()
		if not PlotBuilderEnabled.Value then
			PlotGridOverlay.Hide()
			PlotContext.ToggleGridAction.Enabled = false
		else
			updateGridSurfacePosition()
			PlotGridOverlay.Show()
			PlotContext.ToggleGridAction.Enabled = true
		end
	end)

	PlotContext.ToggleGridAction.Pressed:Connect(function()
		Debounce.RunIfAvailable("PlotGridOverlay/Toggle", INPUT_DEBOUNCE_SECONDS, function()
			print("PlotContext button pressed.")
			PlotGridOverlayEnabled.Value = not PlotGridOverlayEnabled.Value
			if PlotGridOverlayEnabled.Value then
				PlotGridOverlay.Show()
			else
				PlotGridOverlay.Hide()
			end
		end, Player.UserId)
	end)

	PlotStateStore.OnActiveLevelChanged(function(level)
		updateGridSurfacePosition(level)
	end)

	Player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		resetSurfaceTracking()
		task.defer(function()
			updateGridSurfacePosition()
		end)
	end)

	updateGridSurfacePosition()
end

function PlotGridOverlay.Show()
	print("Showing plot grid.")
	local surface = updateGridSurfacePosition()
	local gridVisual = surface and surface:FindFirstChild("GridVisual") :: Texture

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	gridVisual.Transparency = 0
	PlotGridOverlayEnabled.Value = true
end

function PlotGridOverlay.Hide()
	print("Hiding plot grid.")

	local surface = updateGridSurfacePosition()
	local gridVisual = surface and surface:FindFirstChild("GridVisual") :: Texture

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	gridVisual.Transparency = 1
	PlotGridOverlayEnabled.Value = false
end

return PlotGridOverlay
