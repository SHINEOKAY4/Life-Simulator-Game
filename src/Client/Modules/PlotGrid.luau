--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotGrid.lua
local Runservice = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotContext = PlayerGui:WaitForChild("PlotContext")

local PlotGrid = {}
local Connection: RBXScriptConnection? = nil
local accumulatedTime = 0

PlotGrid.Visible = false

local function OnHeartbeat(deltaTime)
	accumulatedTime += deltaTime

	if accumulatedTime >= 0.5 then
		accumulatedTime = 0
		if PlotGrid.Visible and not PlotFinder.IsWithinBounds(Player) then
			PlotGrid.Visible = false
			PlotGrid.Hide()
		end
	end
end

function PlotGrid.Init()
	print("PlotGrid module initialized.")
	PlotContext.ToggleGridAction.Pressed:Connect(function()
		print("PlotContext button pressed.")

		if PlotFinder.IsWithinBounds(Player) then
			PlotGrid.Visible = not PlotGrid.Visible

			if PlotGrid.Visible then
				PlotGrid.Show()
				Connection = Runservice.Heartbeat:Connect(OnHeartbeat)
			else
				PlotGrid.Hide()
			end
		end
	end)
end

function PlotGrid.Show()
	print("Showing plot grid.")
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local surface = plotModel and plotModel:FindFirstChild("Surface") :: BasePart

	local gridVisual = surface and surface:FindFirstChild("GridVisual") :: Texture

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	gridVisual.Transparency = 0
end

function PlotGrid.Hide()
	print("Hiding plot grid.")

	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local surface = plotModel and plotModel:FindFirstChild("Surface") :: BasePart

	local gridVisual = surface and surface:FindFirstChild("GridVisual") :: Texture

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	gridVisual.Transparency = 1
end

return PlotGrid
