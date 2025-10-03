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

local PlotBuilder = {}

function PlotBuilder.Init()
	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value and PlotBuilderEnabled.Value then
			PlotBuilder.Hide()
		end
	end)

	ObjectSelectorEnabled.Changed:Connect(function()
		if ObjectSelectorEnabled.Value and PlotBuilderEnabled.Value then
			PlotBuilder.Hide()
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

function PlotBuilder.PreviewSelected(itemId: string)
	ObjectPreview.RenderPreview(itemId)
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

--#TODO: More functions for rotating, selecting already placed items, deleting placed items, etc.
return PlotBuilder
