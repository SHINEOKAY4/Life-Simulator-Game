--!strict
-- ReplicatedStorage/Client/Modules/PlotBuilder.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ObjectPreview = require(script.Parent.ObjectPreview)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

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
local JobSelectionUIEnabled = ActiveQueryFolder:FindFirstChild("JobSelectionUIEnabled") :: BoolValue

type Facing = ObjectPreview.Facing
type WallStripSelectionInfo = ObjectPreview.WallStripSelectionInfo
local PlotBuilder = {}
local INPUT_DEBOUNCE_SECONDS = 0.25

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("PlotBuilder/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, Player.UserId)
end

function PlotBuilder.Init()
	JobSelectionUIEnabled.Changed:Connect(function()
		if JobSelectionUIEnabled.Value and PlotBuilderEnabled.Value then
			PlotBuilder.Hide()
		end
	end)
	PlotExpansionEnabled.Changed:Connect(function()
		if PlotExpansionEnabled.Value and PlotBuilderEnabled.Value then
			PlotBuilder.Hide()
		end
	end)

	ObjectPreview.SetFloorPlacementHandler(function(selection)
		PlotBuilder.PlaceFloorSelection(selection)
	end)

	ObjectPreview.SetWallStripPlacementHandler(function(selection)
		PlotBuilder.PlaceWallStrip(selection)
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
		runDebounced("Toggle", function()
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
	end)

	BuildContext.PlacePreview.Pressed:Connect(function()
		runDebounced("PlacePreview", function()
			if ObjectPreview.TryBeginFloorDrag() then
				return
			end
			if ObjectPreview.TryBeginWallStripDrag() then
				return
			end
			PlotBuilder.PlaceSelectedPreview()
		end)
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
	elseif pose.Kind == "Wall" then
		if ObjectPreview.IsWallStripDragInProgress() then
			return
		end
		local wallSelection = ObjectPreview.GetWallStripSelectionSummary()
		if wallSelection and wallSelection.CanPlace then
			PlotBuilder.PlaceWallStrip(wallSelection)
			return
		end
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

function PlotBuilder.PlaceWallStrip(selection: WallStripSelectionInfo)
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

	local startCellX = selection.StartCellX
	local endCellX = selection.EndCellX
	local startCellZ = selection.StartCellZ
	local endCellZ = selection.EndCellZ
	local facing = selection.Facing
	local orientation = selection.Orientation

	if typeof(startCellX) ~= "number" or typeof(endCellX) ~= "number" then
		return
	end
	if typeof(startCellZ) ~= "number" or typeof(endCellZ) ~= "number" then
		return
	end
	if typeof(facing) ~= "string" or facing == "" then
		return
	end
	if orientation ~= "Horizontal" and orientation ~= "Vertical" then
		return
	end

	if orientation == "Horizontal" then
		if startCellZ ~= endCellZ then
			return
		end
	else
		if startCellX ~= endCellX then
			return
		end
	end

	local success, message = Packets.PlaceWallStripRequest:Fire({
		ItemId = itemId,
		Facing = facing,
		Orientation = orientation,
		StartCellX = startCellX,
		StartCellZ = startCellZ,
		EndCellX = endCellX,
		EndCellZ = endCellZ,
	})

	if not success then
		warn("Placement failed: " .. message)
	end
end

return PlotBuilder
