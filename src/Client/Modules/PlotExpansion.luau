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
local ToggleExpansionAction = PlotContext.ToggleExpansion
local ToggleClickPurchaseAction = PlotContext.ToggleClickPurchase

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local VisualToolsFolder = AssetsFolder.VisualTools
local ChunkHighlight = VisualToolsFolder:WaitForChild("ChunkHighlight") :: Highlight
local PriceTag = VisualToolsFolder:WaitForChild("PriceTag") :: BillboardGui
local PriceLabel = PriceTag:FindFirstChild("Label") :: TextLabel

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled")
local JobSelectionUIEnabled = ActiveQueryFolder:FindFirstChild("JobSelectionUIEnabled") :: BoolValue

local camera = Workspace.CurrentCamera :: Camera

local PlotExpansion = {}
local INPUT_DEBOUNCE_SECONDS = 0.25

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("PlotExpansion/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, Player.UserId)
end

local Connection: RBXScriptConnection? = nil
local _HoveredCover: BasePart? = nil

local function ClearEffects()
	_HoveredCover = nil
	ChunkHighlight.Adornee = nil
	PriceTag.Adornee = VisualToolsFolder
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

	ToggleExpansionAction.Pressed:Connect(function()
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

	ToggleClickPurchaseAction.Pressed:Connect(function()
		runDebounced("Purchase", function()
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
	ToggleClickPurchaseAction.Enabled = true
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder
	local container = plotModel and plotModel:FindFirstChild("Container") :: Folder
	PriceTag.Enabled = true
	PriceTag.Parent = container

	local params = BuildParams(coversFolder)
	PlotFinder.StartTracking(Player)

	Connection = RunService.PreRender:Connect(function(_deltaTime)
		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

		if not result or not result.Instance or not result.Instance:IsA("BasePart") then
			ClearEffects()
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
		ChunkHighlight.Adornee = hitCover
		PriceTag.Adornee = hitCover
		PriceLabel.Text = if not success then message else "$" .. "400" -- #TODO: pricing logic
		ChunkHighlight.FillColor = if success then Color3.fromRGB(0, 255, 0) else Color3.fromRGB(255, 0, 0)
		ChunkHighlight.OutlineColor = if success then Color3.fromRGB(0, 100, 0) else Color3.fromRGB(100, 0, 0)
	end)
end

function PlotExpansion.Hide()
	PlotExpansionEnabled.Value = false
	ToggleClickPurchaseAction.Enabled = false
	PriceTag.Parent = VisualToolsFolder
	PriceTag.Enabled = false
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	ClearEffects()
end

return PlotExpansion
