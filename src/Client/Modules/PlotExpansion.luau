--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotExpansion.lua

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotContext = PlayerGui:WaitForChild("PlotContext")
local camera = Workspace.CurrentCamera :: Camera

local PlotExpansion = {}
local IsActive = false

local Connection: RBXScriptConnection? = nil
local _HoveredCover: BasePart? = nil

local function ClearEffects(priceTag: BillboardGui, highlight: Highlight, coversFolder: Folder)
	_HoveredCover = nil
	highlight.Adornee = nil
	priceTag.Adornee = coversFolder
end

local function BuildParams(coversFolder: Folder): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { coversFolder }
	params.RespectCanCollide = false
	params.IgnoreWater = true
	return params
end

function PlotExpansion.Init()
	PlotContext.ToggleExpansion.Pressed:Connect(function()
		local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
		if not plotIndex then
			warn("Player does not own a plot.")
			return
		end

		if PlotFinder.IsWithinBounds(Player) then
			if IsActive then
				PlotExpansion.Hide()
			else
				PlotExpansion.Show()
			end
		end
	end)

	PlotContext.ToggleClickPurchase.Pressed:Connect(function()
		print("ToggleClickPurchase pressed")
		local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
		local plotModel = PlotFinder.FindPlot(plotIndex)
		local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder

		local params = BuildParams(coversFolder)
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

		if not result or not result.Instance or not result.Instance:IsA("BasePart") then
			return
		end

		local hitCover = result.Instance
		if hitCover == _HoveredCover then
			local chunkX = hitCover:GetAttribute("ChunkX") :: number
			local chunkZ = hitCover:GetAttribute("ChunkZ") :: number
			local success, message = PlotStateStore.RequestPurchase(chunkX, chunkZ)
			if success then
				print("Toast notification UI implementation needed")
			end
			--#TODO: Toast notification for success/failure
			print("Purchase result:", success, message)
		end
	end)
end

function PlotExpansion.Show()
	IsActive = true
	PlotContext.ToggleClickPurchase.Enabled = true
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder
	local container = plotModel and plotModel:FindFirstChild("Container") :: Folder
	local priceTag = container and container:FindFirstChild("PriceTag") :: BillboardGui
	local priceLabel = priceTag and priceTag:FindFirstChild("Label") :: TextLabel
	local highlight = container and container:FindFirstChild("ChunkHighlight") :: Highlight
	local accumulatedTime = 0

	local params = BuildParams(coversFolder)

	Connection = RunService.PreRender:Connect(function(deltaTime)
		accumulatedTime += deltaTime
		if accumulatedTime >= 0.5 then
			accumulatedTime = 0
			if not PlotFinder.IsWithinBounds(Player) then
				PlotExpansion.Hide()
				return
			end
		end

		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

		if not result or not result.Instance or not result.Instance:IsA("BasePart") then
			ClearEffects(priceTag, highlight, coversFolder)
			return
		end

		local hitCover = result.Instance
		local chunkX = hitCover:GetAttribute("ChunkX") :: number
		local chunkZ = hitCover:GetAttribute("ChunkZ") :: number

		if hitCover == _HoveredCover then
			return
		end

		local success, message = PlotStateStore.CanPurchaseChunk(chunkX, chunkZ)
		--#TODO: Add Additional visual effects
		_HoveredCover = hitCover
		highlight.Adornee = hitCover
		priceTag.Adornee = hitCover
		priceLabel.Text = if not success then message else "$" .. "400" -- #TODO: pricing logic
		highlight.FillColor = if success then Color3.fromRGB(0, 255, 0) else Color3.fromRGB(255, 0, 0)
		highlight.OutlineColor = if success then Color3.fromRGB(0, 100, 0) else Color3.fromRGB(100, 0, 0)
	end)
end

function PlotExpansion.Hide()
	IsActive = false
	PlotContext.ToggleClickPurchase.Enabled = false

	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	_HoveredCover = nil

	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder
	local container = plotModel and plotModel:FindFirstChild("Container") :: Folder
	local priceTag = container and container:FindFirstChild("PriceTag") :: BillboardGui
	local highlight = container and container:FindFirstChild("ChunkHighlight") :: Highlight
	ClearEffects(priceTag, highlight, coversFolder)
end

return PlotExpansion
