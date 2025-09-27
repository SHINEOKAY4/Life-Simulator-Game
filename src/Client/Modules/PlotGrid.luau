--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotGrid.luau
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

local function IsWithinPlotArea(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoidRootPart then
		return false
	end

	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)

	if not plotModel then
		return false
	end

	local surface = plotModel:FindFirstChild("Surface") :: BasePart
	if not surface then
		return false
	end

	local verticalTolerance = 4 -- studs around the top face

	local localPoint: Vector3 = surface.CFrame:PointToObjectSpace(humanoidRootPart.Position)
	local halfSize: Vector3 = surface.Size * 0.5

	-- Optionally add offset to go beyond the surface edges
	local offset = 0
	local withinX = math.abs(localPoint.X) <= halfSize.X + offset
	local withinZ = math.abs(localPoint.Z) <= halfSize.Z + offset

	local topY = halfSize.Y
	local withinVertical = math.abs(localPoint.Y - topY) <= verticalTolerance

	return withinX and withinZ and withinVertical
end

local function OnHeartbeat(deltaTime)
	accumulatedTime += deltaTime

	if accumulatedTime >= 0.5 then
		accumulatedTime = 0
		if PlotGrid.Visible and not IsWithinPlotArea(Player) then
			PlotGrid.Visible = false
			PlotGrid.Hide()
		end
	end
end

function PlotGrid.Init()
	print("PlotGrid module initialized.")
	PlotContext.ToggleGridAction.Pressed:Connect(function()
		print("PlotContext button pressed.")

		if IsWithinPlotArea(Player) then
			PlotGrid.Visible = not PlotGrid.Visible

			if PlotGrid.Visible then
				PlotGrid.Show()
				Connection = Runservice.Heartbeat:Connect(OnHeartbeat)
			else
				PlotGrid.Hide()

				if Connection then
					Connection:Disconnect()
					Connection = nil
				end
			end
		end
	end)
end

function PlotGrid.Show()
	print("Showing plot grid.")
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local surface = plotModel and plotModel:FindFirstChild("Surface") :: BasePart

	local gridVisual = surface and surface:FindFirstChild("GridVisual") :: SurfaceGui
	local LinesFrame = gridVisual and gridVisual:FindFirstChild("LinesFrame") :: Frame

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	LinesFrame.Visible = true
end

function PlotGrid.Hide()
	print("Hiding plot grid.")
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local surface = plotModel and plotModel:FindFirstChild("Surface") :: BasePart

	local gridVisual = surface and surface:FindFirstChild("GridVisual") :: SurfaceGui
	local LinesFrame = gridVisual and gridVisual:FindFirstChild("LinesFrame") :: Frame

	if not gridVisual then
		warn("GridVisual not found.")
		return
	end

	LinesFrame.Visible = false
end

return PlotGrid
