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
		if IsActive then
			PlotExpansion.Hide()
		else
			PlotExpansion.Show()
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
	local priceLabel = priceTag and priceTag:FindFirstChild("PriceLabel") :: TextLabel
	local highlight = container:FindFirstChild("Highlight") :: Highlight
	local activeCover = nil :: BasePart?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { covers }
	params.IgnoreWater = true
	params.RespectCanCollide = false

	Connection = RunService.PostSimulation:Connect(function()
		--#TODO: Hovering over cover parts for effects (Undecided still design wise)
		--#TODO: Check adjacent covers for expansion possibility
		--#TODO: PlotStateStore is now implemented therefore we can now finish the todo for this module
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 2000, params)
		local newCover: BasePart? = nil

		if result and result.Instance and result.Instance:IsA("BasePart") then
			newCover = result.Instance
		end
		if newCover == activeCover then
			return
		end

		if not newCover then
			highlight.Adornee = nil
			activeCover = nil
		end

		highlight.Adornee = newCover
		activeCover = newCover
	end)
end

function PlotExpansion.Hide()
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end
	--#TODO: Hide any UI elements
end

return PlotExpansion
