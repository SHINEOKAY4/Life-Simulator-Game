--!strict
-- ReplicatedStorage/Client/Modules/PlotBuilder.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ObjectPreview = require(script.Parent.ObjectPreview)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotBuilderGui = PlayerGui:WaitForChild("PlotBuilderGui")

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local BuildContext = InputContextsFolder:WaitForChild("BuildContext")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled")
local ObjectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled")

type Facing = ObjectPreview.Facing
local PlotBuilder = {}

function PlotBuilder.Init()
	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value and PlotBuilderEnabled.Value then
			PlotBuilder.Hide()
		end
	end)

	ObjectPreview.SetFloorPlacementHandler(function(selection)
		PlotBuilder.PlaceFloorSelection(selection)
	end)

	ObjectSelectorEnabled.Changed:Connect(function()
		if ObjectSelectorEnabled.Value and PlotBuilderEnabled.Value then
			PlotBuilder.Hide()
		end
	end)

	ObjectPreviewEnabled.Changed:Connect(function()
		-- if objectpreview is cancelled and plotbuilder is active, re-show plotbuilder and disable placing preview control
		if not ObjectPreviewEnabled.Value and PlotBuilderEnabled.Value then
			BuildContext.PlacePreview.Enabled = false
			PlotBuilder.Show()
		end
	end)

	BuildContext.ToggleBuildMode.Pressed:Connect(function()
		local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
		if not plotIndex then
			warn("Player does not own a plot.")
			return
		end
		if PlotFinder.IsWithinBounds(Player) then
			if PlotBuilderEnabled.Value then
				PlotBuilder.Hide()
			else
				PlotBuilder.Show()
			end
		end
	end)

	BuildContext.PlacePreview.Pressed:Connect(function()
		if ObjectPreview.TryBeginFloorDrag() then
			return
		end
		PlotBuilder.PlaceSelectedPreview()
	end)

	Player:GetAttributeChangedSignal("WithinPlot"):Connect(function()
		local IsWithinBounds = Player:GetAttribute("WithinPlot")
		if not IsWithinBounds then
			PlotBuilder.Hide()
		end
	end)
end

function PlotBuilder.Show()
	PlotBuilderEnabled.Value = true
	PlotBuilderGui.Main.Visible = PlotBuilderEnabled.Value
	PlotFinder.StartTracking(Player)
end

function PlotBuilder.Hide()
	PlotBuilderEnabled.Value = false
	PlotBuilderGui.Main.Visible = PlotBuilderEnabled.Value

	PlotBuilder.RemovePreview()
end

function PlotBuilder.PreviewSelected(itemId: string, initialFacing: string?)
	ObjectPreview.RenderPreview(itemId, initialFacing :: Facing?)
	BuildContext.PlacePreview.Enabled = true
end

function PlotBuilder.RemovePreview()
	ObjectPreview.ClearPreview()
	BuildContext.PlacePreview.Enabled = false
end

function PlotBuilder.PlaceSelectedPreview()
	-- Packets.PlaceRequest:Fire(itemId, cellX, cellZ, facing):Response(boolean, string long) -- shape of payload

	local pose = ObjectPreview.GetCurrentPose()
	if not pose then
		warn("No preview pose available.")
		return
	end

	if pose.Kind == "Floor" then
		if ObjectPreview.IsFloorDragInProgress() then
			return
		end
		local floorSelection = ObjectPreview.GetFloorSelectionSummary()
		if not floorSelection or not floorSelection.CanPlace then
			return
		end
		PlotBuilder.PlaceFloorSelection(floorSelection)
		return
	end

	local success, message = Packets.PlaceRequest:Fire({
		ItemId = pose.ItemId,
		CellX = pose.CellX,
		CellZ = pose.CellZ,
		Facing = pose.Facing,
	})

	if not success then
		warn("Placement failed: " .. message)
	end

	-- Optional: keep previewing for batch placement; or call RemovePreview()
end

function PlotBuilder.PlaceFloorSelection(selection: any)
	if typeof(selection) ~= "table" then
		return
	end

	local itemId = selection.ItemId
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end

	if selection.CanPlace ~= true then
		return
	end

	local startX = selection.AnchorCellX
	local startZ = selection.AnchorCellZ
	local endX = selection.CurrentCellX
	local endZ = selection.CurrentCellZ
	local widthCells = selection.WidthCells
	local depthCells = selection.DepthCells

	if
		typeof(startX) ~= "number"
		or typeof(startZ) ~= "number"
		or typeof(endX) ~= "number"
		or typeof(endZ) ~= "number"
	then
		return
	end

	local minCellX = math.min(startX, endX)
	local minCellZ = math.min(startZ, endZ)
	local maxCellX = math.max(startX, endX)
	local maxCellZ = math.max(startZ, endZ)

	if typeof(widthCells) ~= "number" then
		widthCells = maxCellX - minCellX + 1
	end

	if typeof(depthCells) ~= "number" then
		depthCells = maxCellZ - minCellZ + 1
	end

	local success, message = Packets.PlaceFloorAreaRequest:Fire({
		ItemId = itemId,
		StartCellX = startX,
		StartCellZ = startZ,
		EndCellX = endX,
		EndCellZ = endZ,
		WidthCells = widthCells,
		DepthCells = depthCells,
	})

	if not success then
		warn("Placement failed: " .. message)
	end
end

--#TODO: More functions for rotating, selecting already placed items, deleting placed items, etc.
return PlotBuilder
