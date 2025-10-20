--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotExpansion.lua

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local PlotContext = InputContextsFolder:WaitForChild("PlotContext")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local ChunkHighlight = AssetsFolder.VisualTools:WaitForChild("ChunkHighlight") :: Highlight
local PriceTag = AssetsFolder.VisualTools:WaitForChild("PriceTag") :: BillboardGui
local PriceLabel = PriceTag:FindFirstChild("Label") :: TextLabel

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled")
local JobSelectionUIEnabled = ActiveQueryFolder:FindFirstChild("JobSelectionUIEnabled") :: BoolValue

local camera = Workspace.CurrentCamera :: Camera

local PlotExpansion = {}

local INPUT_DEBOUNCE_SECONDS = 0.25
local RAYCAST_DISTANCE_STUDS = 1000
local CHUNK_PRICE = 400
local SUCCESS_HIGHLIGHT_COLOR = Color3.fromRGB(0, 255, 0)
local SUCCESS_OUTLINE_COLOR = Color3.fromRGB(0, 100, 0)
local FAILURE_HIGHLIGHT_COLOR = Color3.fromRGB(255, 0, 0)
local FAILURE_OUTLINE_COLOR = Color3.fromRGB(100, 0, 0)

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("PlotExpansion/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, Player.UserId)
end

local renderConnection: RBXScriptConnection? = nil
local hoveredChunkCover: BasePart? = nil

local function clearVisualEffects()
	hoveredChunkCover = nil
	ChunkHighlight.Adornee = nil
	PriceTag.Adornee = AssetsFolder.VisualTools
end

local function createRaycastParameters(coversFolder: Folder): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { coversFolder }
	params.RespectCanCollide = false
	params.IgnoreWater = true
	return params
end

function PlotExpansion.Init()
	JobSelectionUIEnabled.Changed:Connect(function()
		if JobSelectionUIEnabled.Value and PlotExpansionEnabled.Value then
			PlotExpansion.Hide()
		end
	end)
	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value and PlotExpansionEnabled.Value then
			PlotExpansion.Hide()
		end
	end)

	ObjectSelectorEnabled.Changed:Connect(function()
		if ObjectSelectorEnabled.Value and PlotExpansionEnabled.Value then
			PlotExpansion.Hide()
		end
	end)

	PlotContext.ToggleExpansion.Pressed:Connect(function()
		runDebounced("Toggle", function()
			local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
			if not plotIndex then
				warn("Player does not own a plot.")
				return
			end

			if PlotFinder.IsWithinBounds(Player) then
				if PlotExpansionEnabled.Value then
					PlotExpansion.Hide()
				else
					PlotExpansion.Show()
				end
			end
		end)
	end)

	PlotContext.ToggleClickPurchase.Pressed:Connect(function()
		runDebounced("Purchase", function()
			local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
			local plotModel = PlotFinder.FindPlot(plotIndex)
			local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder

			local params = createRaycastParameters(coversFolder)
			local mouseLocation = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
			local result = Workspace:Raycast(ray.Origin, ray.Direction * RAYCAST_DISTANCE_STUDS, params)

			if not result or not result.Instance or not result.Instance:IsA("BasePart") then
				return
			end

			local hitCover = result.Instance
			if hitCover == hoveredChunkCover then
				local chunkX = hitCover:GetAttribute("ChunkX") :: number
				local chunkZ = hitCover:GetAttribute("ChunkZ") :: number
				local success, message = PlotStateStore.RequestPurchase(chunkX, chunkZ)
				print("Purchase result:", success, message)
			end
		end)
	end)

	Player:GetAttributeChangedSignal("WithinPlot"):Connect(function()
		local IsWithinBounds = Player:GetAttribute("WithinPlot")
		if not IsWithinBounds then
			PlotExpansion.Hide()
		end
	end)
end

function PlotExpansion.Show()
	PlotExpansionEnabled.Value = true
	PlotContext.ToggleClickPurchase.Enabled = true
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder
	local container = plotModel and plotModel:FindFirstChild("Container") :: Folder
	PriceTag.Enabled = true
	PriceTag.Parent = container

	local params = createRaycastParameters(coversFolder)
	PlotFinder.StartTracking(Player)

	renderConnection = RunService.PreRender:Connect(function(_deltaTime)
		local mouseLocation = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouseLocation.X, mouseLocation.Y)
		local result = Workspace:Raycast(ray.Origin, ray.Direction * RAYCAST_DISTANCE_STUDS, params)

		if not result or not result.Instance or not result.Instance:IsA("BasePart") then
			clearVisualEffects()
			return
		end

		local hitCover = result.Instance
		local chunkX = hitCover:GetAttribute("ChunkX") :: number
		local chunkZ = hitCover:GetAttribute("ChunkZ") :: number

		if hitCover == hoveredChunkCover then
			return
		end

		local canPurchase, message = PlotStateStore.CanPurchaseChunk(chunkX, chunkZ)
		hoveredChunkCover = hitCover
		ChunkHighlight.Adornee = hitCover
		PriceTag.Adornee = hitCover
		PriceLabel.Text = if not canPurchase then message else "$" .. tostring(CHUNK_PRICE)
		ChunkHighlight.FillColor = if canPurchase then SUCCESS_HIGHLIGHT_COLOR else FAILURE_HIGHLIGHT_COLOR
		ChunkHighlight.OutlineColor = if canPurchase then SUCCESS_OUTLINE_COLOR else FAILURE_OUTLINE_COLOR
	end)
end

function PlotExpansion.Hide()
	PlotExpansionEnabled.Value = false
	PlotContext.ToggleClickPurchase.Enabled = false
	PriceTag.Parent = AssetsFolder.VisualTools
	PriceTag.Enabled = false
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	clearVisualEffects()
end

return PlotExpansion
