--!strict
-- ReplicatedStorage/Client/Modules/PlotBuilder.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ObjectPreview = require(script.Parent.ObjectPreview)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local SoundtrackManager = require(script.Parent.SoundtrackManager)
local PlacementCelebration = require(script.Parent.PlacementCelebration)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotBuilderGui = PlayerGui:WaitForChild("PlotBuilderGui")
local PlotBuilderMain = PlotBuilderGui.Main

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local BuildContext = InputContextsFolder:WaitForChild("BuildContext")
local ToggleBuildModeAction = BuildContext.ToggleBuildMode
local PlacePreviewAction = BuildContext.PlacePreview

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled")
local ObjectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled")
local JobSelectionUIEnabled = ActiveQueryFolder:FindFirstChild("JobSelectionUIEnabled") :: BoolValue

type Facing = ObjectPreview.Facing
type WallStripSelectionInfo = ObjectPreview.WallStripSelectionInfo
type RoofSelectionInfo = ObjectPreview.RoofSelectionInfo
type PreviewPose = ObjectPreview.PreviewPose

local PlotBuilder = {}
local INPUT_DEBOUNCE_SECONDS = 0.25
local PREVIEW_RESTORE_DELAY = 0.6

local previewRestoreToken = 0

local function cancelPendingPreviewRestore()
	previewRestoreToken += 1
end

local function temporarilyHidePreviewForPlacement(pose: PreviewPose)
	if pose.Kind ~= "CellObject" then
		return
	end

	local itemId = pose.ItemId
	local facing = pose.Facing
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end

	cancelPendingPreviewRestore()
	local token = previewRestoreToken
	local wasEnabled = PlacePreviewAction.Enabled

	ObjectPreview.ClearPreview()
	PlacePreviewAction.Enabled = false

	task.delay(PREVIEW_RESTORE_DELAY, function()
		if previewRestoreToken ~= token then
			return
		end

		if PlotBuilderEnabled.Value ~= true then
			return
		end

		if PlotBuilderMain.Visible ~= true then
			return
		end

		if ObjectPreviewEnabled.Value ~= true then
			return
		end

		if
			JobSelectionUIEnabled.Value == true
			or PlotExpansionEnabled.Value == true
			or ObjectSelectorEnabled.Value == true
		then
			return
		end

		ObjectPreview.RenderPreview(itemId, facing :: Facing)
		PlacePreviewAction.Enabled = wasEnabled
	end)
end

local function computeFootprintPosition(
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: string
): Vector3?
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return nil
	end
	local ok, cframe = pcall(function()
		return grid:FootprintCenterCFrame(cellX, cellZ, widthCells, depthCells, facing)
	end)
	if not ok then
		return nil
	end
	return (cframe :: CFrame).Position
end

local function computeCellObjectPosition(itemId: string?, cellX: number, cellZ: number, facing: string): Vector3?
	local widthCells = 1
	local depthCells = 1
	if typeof(itemId) == "string" then
		local spec = ItemFinder.FindItemById(itemId)
		if spec then
			widthCells = spec.WidthCells or spec.Width or widthCells
			depthCells = spec.DepthCells or spec.Depth or depthCells
		end
	end
	return computeFootprintPosition(cellX, cellZ, widthCells, depthCells, facing)
end

local function computeAreaPlacementPosition(
	startCellX: number,
	startCellZ: number,
	endCellX: number,
	endCellZ: number,
	widthCells: number?,
	depthCells: number?,
	facing: string?
): Vector3?
	local anchorCellX = math.min(startCellX, endCellX)
	local anchorCellZ = math.min(startCellZ, endCellZ)
	local resolvedWidth = widthCells or math.abs(endCellX - startCellX) + 1
	local resolvedDepth = depthCells or math.abs(endCellZ - startCellZ) + 1
	return computeFootprintPosition(anchorCellX, anchorCellZ, resolvedWidth, resolvedDepth, facing or "North")
end

local function computeWallStripPosition(selection: WallStripSelectionInfo): Vector3?
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return nil
	end
	local facing = selection.Facing
	local minCellX = math.min(selection.StartCellX, selection.EndCellX)
	local minCellZ = math.min(selection.StartCellZ, selection.EndCellZ)
	local maxCellX = math.max(selection.StartCellX, selection.EndCellX)
	local maxCellZ = math.max(selection.StartCellZ, selection.EndCellZ)

	local okStart, startCFrame = pcall(function()
		return grid:CellToWorldEdgeCenterCFrame(minCellX, minCellZ, facing)
	end)
	if not okStart then
		return nil
	end
	local startPosition = (startCFrame :: CFrame).Position

	if minCellX == maxCellX and minCellZ == maxCellZ then
		return startPosition
	end

	local okEnd, endCFrame = pcall(function()
		return grid:CellToWorldEdgeCenterCFrame(maxCellX, maxCellZ, facing)
	end)
	if okEnd then
		local endPosition = (endCFrame :: CFrame).Position
		return (startPosition + endPosition) * 0.5
	end

	return startPosition
end

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

	ObjectPreview.SetRoofPlacementHandler(function(selection)
		PlotBuilder.PlaceRoofSelection(selection)
	end)

	ObjectSelectorEnabled.Changed:Connect(function()
		if ObjectSelectorEnabled.Value and PlotBuilderEnabled.Value then
			PlotBuilder.Hide()
		end
	end)

	ObjectPreviewEnabled.Changed:Connect(function()
		-- if objectpreview is cancelled and plotbuilder is active, re-show plotbuilder and disable placing preview control
		if not ObjectPreviewEnabled.Value and PlotBuilderEnabled.Value then
			PlacePreviewAction.Enabled = false
			PlotBuilder.Show()
		end
	end)

	ToggleBuildModeAction.Pressed:Connect(function()
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

	PlacePreviewAction.Pressed:Connect(function()
		runDebounced("PlacePreview", function()
			if ObjectPreview.TryBeginFloorDrag() then
				return
			end
			if ObjectPreview.TryBeginRoofDrag() then
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
	PlotBuilderMain.Visible = true
	PlotFinder.StartTracking(Player)
end

function PlotBuilder.Hide()
	PlotBuilderEnabled.Value = false
	PlotBuilderMain.Visible = false
	PlotBuilder.RemovePreview()
end

function PlotBuilder.PreviewSelected(itemId: string, initialFacing: string?)
	cancelPendingPreviewRestore()
	ObjectPreview.RenderPreview(itemId, initialFacing :: Facing?)
	PlacePreviewAction.Enabled = true
end

function PlotBuilder.RemovePreview()
	cancelPendingPreviewRestore()
	ObjectPreview.ClearPreview()
	PlacePreviewAction.Enabled = false
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
	elseif pose.Kind == "Roof" then
		if ObjectPreview.IsRoofDragInProgress() then
			return
		end
		local roofSelection = ObjectPreview.GetRoofSelectionSummary()
		if roofSelection and roofSelection.CanPlace then
			PlotBuilder.PlaceRoofSelection(roofSelection)
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
		warn("Placement failed: " .. (message or "unknown reason"))
		local failurePosition = computeCellObjectPosition(pose.ItemId, pose.CellX, pose.CellZ, pose.Facing)
		PlacementCelebration.ShowFailure(failurePosition, pose.ItemId, message)
		return
	end

	SoundtrackManager.PlayPlacementSuccess()
	PlacementCelebration.CellObjectSuccess(pose.ItemId, pose.CellX, pose.CellZ, pose.Facing)
	temporarilyHidePreviewForPlacement(pose)

	-- Optional: keep previewing for batch placement; or call RemovePreview()
end

function PlotBuilder.PlaceFloorSelection(selection: any)
	if typeof(selection) ~= "table" or selection.CanPlace ~= true then
		return
	end

	local itemId = selection.ItemId
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end

	local startX = selection.AnchorCellX
	local startZ = selection.AnchorCellZ
	local endX = selection.CurrentCellX
	local endZ = selection.CurrentCellZ

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

	local widthCells = selection.WidthCells
	local depthCells = selection.DepthCells

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

	local placementPosition = computeAreaPlacementPosition(startX, startZ, endX, endZ, widthCells, depthCells, "North")

	if success then
		SoundtrackManager.PlayPlacementSuccess()
		PlacementCelebration.ShowSuccess(placementPosition, itemId)
		PlacementCelebration.CelebrateFloorArea(itemId, minCellX, minCellZ, widthCells, depthCells)
	else
		warn("Placement failed: " .. (message or "unknown reason"))
		PlacementCelebration.ShowFailure(placementPosition, itemId, message)
	end
end

function PlotBuilder.PlaceWallStrip(selection: WallStripSelectionInfo)
	if typeof(selection) ~= "table" or selection.CanPlace ~= true then
		return
	end

	local itemId = selection.ItemId
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end

	local startCellX = selection.StartCellX
	local endCellX = selection.EndCellX
	local startCellZ = selection.StartCellZ
	local endCellZ = selection.EndCellZ
	local facing = selection.Facing
	local orientation = selection.Orientation

	if
		typeof(startCellX) ~= "number"
		or typeof(endCellX) ~= "number"
		or typeof(startCellZ) ~= "number"
		or typeof(endCellZ) ~= "number"
	then
		return
	end

	if typeof(facing) ~= "string" or facing == "" then
		return
	end

	if orientation ~= "Horizontal" and orientation ~= "Vertical" then
		return
	end

	if
		(orientation == "Horizontal" and startCellZ ~= endCellZ)
		or (orientation == "Vertical" and startCellX ~= endCellX)
	then
		return
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

	local placementPosition = computeWallStripPosition(selection)

	if success then
		SoundtrackManager.PlayPlacementSuccess()
		PlacementCelebration.ShowSuccess(placementPosition, itemId)
		PlacementCelebration.CelebrateWallStrip(itemId, startCellX, endCellX, startCellZ, endCellZ, facing, orientation)
	else
		warn("Placement failed: " .. (message or "unknown reason"))
		PlacementCelebration.ShowFailure(placementPosition, itemId, message)
	end
end

function PlotBuilder.PlaceRoofSelection(selection: RoofSelectionInfo)
	if typeof(selection) ~= "table" or selection.CanPlace ~= true then
		return
	end

	local itemId = selection.ItemId
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end

	local startX = selection.AnchorCellX
	local startZ = selection.AnchorCellZ
	local endX = selection.CurrentCellX
	local endZ = selection.CurrentCellZ

	if
		typeof(startX) ~= "number"
		or typeof(startZ) ~= "number"
		or typeof(endX) ~= "number"
		or typeof(endZ) ~= "number"
	then
		return
	end

	local success, message = Packets.PlaceRoofAreaRequest:Fire({
		ItemId = itemId,
		StartCellX = startX,
		StartCellZ = startZ,
		EndCellX = endX,
		EndCellZ = endZ,
	})

	local placementPosition =
		computeAreaPlacementPosition(startX, startZ, endX, endZ, selection.WidthCells, selection.DepthCells, "North")

	if not success then
		warn("Placement failed: " .. (message or "unknown reason"))
		PlacementCelebration.ShowFailure(placementPosition, itemId, message)
		return
	end

	SoundtrackManager.PlayPlacementSuccess()
	PlacementCelebration.ShowSuccess(placementPosition, itemId)
end

--#TODO: More functions for rotating, selecting already placed items, deleting placed items, etc.
return PlotBuilder
