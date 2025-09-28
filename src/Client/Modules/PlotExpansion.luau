--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotExpansion.luau

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotContext = PlayerGui:WaitForChild("PlotContext")
local camera = Workspace.CurrentCamera :: Camera

local PlotExpansion = {}
local Connection: RBXScriptConnection? = nil
local IsActive = false

function PlotExpansion.Init()
	PlotContext.ToggleExpansion.Pressed:Connect(function()
		if PlotFinder.IsWithinBounds(Player) then
			if IsActive then
				IsActive = false
				PlotExpansion.Hide()
			else
				IsActive = true
				PlotExpansion.Show()
			end
		end
	end)
end

function PlotExpansion.Show()
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	local container = plotModel:FindFirstChild("Container") :: Folder
	local covers = plotModel:FindFirstChild("Covers") :: Folder

	if not covers or not container then
		return
	end

	local priceTag = container:FindFirstChild("PriceTag") :: BillboardGui
	local priceLabel = priceTag and priceTag:FindFirstChild("Label") :: TextLabel
	local highlight = container:FindFirstChild("Highlight") :: Highlight
	local activeCover = nil :: BasePart?
	local accumulatedTime = 0

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { covers }
	params.IgnoreWater = true
	params.RespectCanCollide = false

	Connection = RunService.PostSimulation:Connect(function(deltaTime)
		--#TODO: Hovering over cover parts for effects (Undecided still design wise)
		--#TODO: Check adjacent covers for expansion possibility
		--#TODO: PlotStateStore is now implemented therefore we can now finish the todo for this module
		--#TODO: Buying expansion functionality

		accumulatedTime += deltaTime
		if accumulatedTime >= 0.5 then
			accumulatedTime = 0
			if not PlotFinder.IsWithinBounds(Player) then
				PlotExpansion.Hide()
				IsActive = false
				return
			end
		end

		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
		local newCover = nil

		if result and result.Instance and result.Instance:IsA("BasePart") then
			newCover = result.Instance
		end
		if newCover == activeCover then
			return
		end

		if not newCover then
			highlight.Adornee = nil
			priceTag.Adornee = covers
			activeCover = nil
		end

		if newCover.Transparency == 1 then
			highlight.Adornee = nil
			priceTag.Adornee = covers
			activeCover = nil
			return
		end

		priceTag.Adornee = newCover
		highlight.Adornee = newCover
		priceLabel.Text = "$" .. "400" --#TODO: Change to actual price from PlotStateStore
		activeCover = newCover
	end)
end

function PlotExpansion.Hide()
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	local container = plotModel:FindFirstChild("Container") :: Folder
	local covers = plotModel:FindFirstChild("Covers") :: Folder

	local priceTag = container:FindFirstChild("PriceTag") :: BillboardGui
	local highlight = container:FindFirstChild("Highlight") :: Highlight

	highlight.Adornee = nil
	priceTag.Adornee = covers
end

return PlotExpansion
