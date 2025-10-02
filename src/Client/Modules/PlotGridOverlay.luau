--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotGridOverlay.lua
local Runservice = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotContext = PlayerGui:WaitForChild("PlotContext")
local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")

local PlotGridOverlay = {}
local Connection: RBXScriptConnection? = nil
local accumulatedTime = 0

PlotGridOverlay.Visible = false

local function OnHeartbeat(deltaTime)
	accumulatedTime += deltaTime

	if accumulatedTime >= 0.5 then
		accumulatedTime = 0
		if PlotGridOverlay.Visible and not PlotFinder.IsWithinBounds(Player) then
			PlotGridOverlay.Visible = false
			PlotGridOverlay.Hide()
		end
	end
end

function PlotGridOverlay.Init()
	print("PlotGridOverlay module initialized.")

	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value and PlotBuilderEnabled.Value then
			PlotGridOverlay.Hide()
		end
	end)

	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value == true then
			PlotGridOverlay.Show()
		else
			PlotGridOverlay.Hide()
		end
	end)
	PlotContext.ToggleGridAction.Pressed:Connect(function()
		print("PlotContext button pressed.")

		if PlotFinder.IsWithinBounds(Player) then
			PlotGridOverlay.Visible = not PlotGridOverlay.Visible

			if PlotGridOverlay.Visible then
				PlotGridOverlay.Show()
				Connection = Runservice.Heartbeat:Connect(OnHeartbeat)
			else
				PlotGridOverlay.Hide()
			end
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
end

function PlotGridOverlay.Hide()
	print("Hiding plot grid.")

	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local GridSurface = plotModel and plotModel:FindFirstChild("GridSurface") :: BasePart

	local gridVisual = GridSurface and GridSurface:FindFirstChild("GridVisual") :: Texture

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	gridVisual.Transparency = 1
end

return PlotGridOverlay
