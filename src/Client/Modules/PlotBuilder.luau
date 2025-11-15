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
local SurfacePalette = require(ReplicatedStorage.Shared.Configurations.Build.SurfacePalette)
local CutawayViewController = require(script.Parent.CutawayViewController)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotBuilderGui = PlayerGui:WaitForChild("PlotBuilderGui")
local PlotBuilderMain = PlotBuilderGui.Main

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local BuildContext = InputContextsFolder:WaitForChild("BuildContext")
local FloorContext = InputContextsFolder:WaitForChild("FloorContext")
local ToggleBuildModeAction = BuildContext.ToggleBuildMode
local PlacePreviewAction = BuildContext.PlacePreview

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled")
local ObjectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled")

type Facing = ObjectPreview.Facing
type WallStripSelectionInfo = ObjectPreview.WallStripSelectionInfo
type RoofSelectionInfo = ObjectPreview.RoofSelectionInfo
type PreviewPose = ObjectPreview.PreviewPose

local PlotBuilder = {}
local INPUT_DEBOUNCE_SECONDS = 0.25
local PREVIEW_RESTORE_DELAY = 0.6
local DEFAULT_BUILD_CONTEXT_PRIORITY = BuildContext.Priority or 0
local PREVIEW_SUPPRESSED_PRIORITY = DEFAULT_BUILD_CONTEXT_PRIORITY - 1
local DEFAULT_FLOOR_CONTEXT_PRIORITY = FloorContext.Priority or (DEFAULT_BUILD_CONTEXT_PRIORITY + 1)
local FLOOR_INPUT_SUPPRESS_SECONDS = 0.12
local BUILDER_CUTAWAY_SOURCE = "PlotBuilder"

local previewRestoreToken = 0
local floorInputSuppressUntil = 0

local function syncInputContextPriorities()
	if not ObjectPreviewEnabled then
		return
	end

	local previewActive = ObjectPreviewEnabled.Value == true
	if previewActive then
		BuildContext.Priority = PREVIEW_SUPPRESSED_PRIORITY
		FloorContext.Priority = math.max(DEFAULT_FLOOR_CONTEXT_PRIORITY, PREVIEW_SUPPRESSED_PRIORITY + 1)
	else
		BuildContext.Priority = DEFAULT_BUILD_CONTEXT_PRIORITY
		FloorContext.Priority = DEFAULT_FLOOR_CONTEXT_PRIORITY
	end
end

local function refreshCutawayForBuilder()
	if not PlotBuilderEnabled then
		return
	end
	if PlotBuilderEnabled.Value then
		CutawayViewController.Request(BUILDER_CUTAWAY_SOURCE, {
			Priority = 20,
			TargetLevel = PlotStateStore.GetActiveLevel(),
		})
	else
		CutawayViewController.Release(BUILDER_CUTAWAY_SOURCE)
	end
end

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

		if PlotExpansionEnabled.Value == true or ObjectSelectorEnabled.Value == true then
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
	facing: string,
	level: number?
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
	local levelHeight = PlotStateStore.GetLevelHeight(level)
	return (cframe :: CFrame).Position + Vector3.new(0, levelHeight, 0)
end

local function resolveDefaultSurfaceId(itemId: string?): string
	if typeof(itemId) ~= "string" or itemId == "" then
		return ""
	end
	local spec = ItemFinder.FindItemById(itemId :: string)
	if not spec then
		return ""
	end
	local resolved = SurfacePalette.ResolveForPlacement(spec, nil)
	if typeof(resolved) == "string" then
		return resolved
	end
	return ""
end

local function computeCellObjectPosition(
	itemId: string?,
	cellX: number,
	cellZ: number,
	facing: string,
	level: number?
): Vector3?
	local widthCells = 1
	local depthCells = 1
	if typeof(itemId) == "string" then
		local spec = ItemFinder.FindItemById(itemId)
		if spec then
			widthCells = spec.WidthCells or spec.Width or widthCells
			depthCells = spec.DepthCells or spec.Depth or depthCells
		end
	end
	return computeFootprintPosition(cellX, cellZ, widthCells, depthCells, facing, level)
end

local function computeAreaPlacementPosition(
	startCellX: number,
	startCellZ: number,
	endCellX: number,
	endCellZ: number,
	widthCells: number?,
	depthCells: number?,
	facing: string?,
	level: number?
): Vector3?
	local anchorCellX = math.min(startCellX, endCellX)
	local anchorCellZ = math.min(startCellZ, endCellZ)
	local resolvedWidth = widthCells or math.abs(endCellX - startCellX) + 1
	local resolvedDepth = depthCells or math.abs(endCellZ - startCellZ) + 1
	return computeFootprintPosition(anchorCellX, anchorCellZ, resolvedWidth, resolvedDepth, facing or "North", level)
end

local function computeWallStripPosition(selection: WallStripSelectionInfo, level: number?): Vector3?
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return nil
	end
	local facing = selection.Facing
	local levelHeight = PlotStateStore.GetLevelHeight(level)
	local okStart, startCFrame = pcall(function()
		return grid:CellToWorldEdgeCenterCFrame(selection.StartCellX, selection.StartCellZ, facing, levelHeight)
	end)
	if not okStart then
		return nil
	end
	local startPosition = (startCFrame :: CFrame).Position

	if selection.StartCellX == selection.EndCellX and selection.StartCellZ == selection.EndCellZ then
		return startPosition
	end

	local okEnd, endCFrame = pcall(function()
		return grid:CellToWorldEdgeCenterCFrame(selection.EndCellX, selection.EndCellZ, facing, levelHeight)
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
	if PlotBuilderEnabled then
		PlotBuilderEnabled.Changed:Connect(refreshCutawayForBuilder)
	end

	PlotStateStore.OnActiveLevelChanged(function()
		if PlotBuilderEnabled and PlotBuilderEnabled.Value then
			refreshCutawayForBuilder()
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
		syncInputContextPriorities()
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
			if floorInputSuppressUntil > os.clock() then
				return
			end
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

	syncInputContextPriorities()
	refreshCutawayForBuilder()
end

function PlotBuilder.Show()
	PlotBuilderEnabled.Value = true
	PlotBuilderMain.Visible = true
	PlotFinder.StartTracking(Player)
	refreshCutawayForBuilder()
end

function PlotBuilder.Hide()
	PlotBuilderEnabled.Value = false
	PlotBuilderMain.Visible = false
	PlotBuilder.RemovePreview()
	refreshCutawayForBuilder()
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

	if floorInputSuppressUntil > os.clock() then
		return
	end

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
	elseif pose.Kind == "SurfaceMounted" then
		local surfacePose = pose.SurfaceMount
		if not surfacePose or surfacePose.CanPlace ~= true then
			return
		end
		local parentKey = surfacePose.ParentKey
		if typeof(parentKey) ~= "string" or parentKey == "" then
			warn("Surface mount parent key missing for placement")
			return
		end
		local localPosition = surfacePose.LocalPosition
		local success, message = Packets.PlaceSurfaceMountRequest:Fire({
			ItemId = pose.ItemId,
			ParentKey = parentKey,
			LocalPosX = localPosition.X,
			LocalPosY = localPosition.Y,
			LocalPosZ = localPosition.Z,
			LocalRotationY = surfacePose.LocalRotationY,
			Metadata = nil,
		})
		if not success then
			warn("Surface mount placement failed: " .. (message or "unknown reason"))
			local failurePosition = surfacePose.WorldPosition
			PlacementCelebration.ShowFailure(failurePosition, pose.ItemId, message)
			return
		end
		SoundtrackManager.PlayPlacementSuccess()
		PlacementCelebration.ShowSuccess(surfacePose.WorldPosition, pose.ItemId)
		return
	end

	local wallPose = pose.WallMount
	local windowPose = pose.WindowCutout
	local cellX = pose.CellX
	local cellZ = pose.CellZ
	if typeof(cellX) ~= "number" or typeof(cellZ) ~= "number" then
		warn("Placement pose is missing cell coordinates for item " .. tostring(pose.ItemId))
		return
	end
	local poseLevel = if typeof(pose.Level) == "number" then pose.Level else PlotStateStore.GetActiveLevel()
	local success, message = Packets.PlaceRequest:Fire({
		ItemId = pose.ItemId,
		CellX = cellX,
		CellZ = cellZ,
		Facing = pose.Facing,
		Level = poseLevel,
		SurfaceId = resolveDefaultSurfaceId(pose.ItemId),
		WallMountEnabled = pose.Kind == "WallMounted" and wallPose ~= nil,
		WallMountCellX = wallPose and wallPose.ReferenceCellX or cellX,
		WallMountCellZ = wallPose and wallPose.ReferenceCellZ or cellZ,
		WallMountFacing = wallPose and wallPose.AttachedFacing or pose.Facing,
		WallMountHeightOffset = wallPose and wallPose.HeightOffset or 0,
		WallMountPosX = wallPose and wallPose.WorldPosition.X or 0,
		WallMountPosY = wallPose and wallPose.WorldPosition.Y or 0,
		WallMountPosZ = wallPose and wallPose.WorldPosition.Z or 0,
		WallMountNormalX = wallPose and wallPose.WallNormal.X or 0,
		WallMountNormalY = wallPose and wallPose.WallNormal.Y or 0,
		WallMountNormalZ = wallPose and wallPose.WallNormal.Z or -1,
		WindowEnabled = pose.Kind == "Wall" and windowPose ~= nil,
		WindowHeightOffset = windowPose and windowPose.HeightOffset or 0,
	})

	if not success then
		warn("Placement failed: " .. (message or "unknown reason"))
		local failurePosition = if pose.Kind == "WallMounted" and wallPose
			then wallPose.WorldPosition
			else computeCellObjectPosition(pose.ItemId, cellX, cellZ, pose.Facing, poseLevel)
		PlacementCelebration.ShowFailure(failurePosition, pose.ItemId, message)
		return
	end

	SoundtrackManager.PlayPlacementSuccess()
	PlacementCelebration.CellObjectSuccess(pose.ItemId, cellX, cellZ, pose.Facing, poseLevel)
	temporarilyHidePreviewForPlacement(pose)

	-- Optional: keep previewing for batch placement; or call RemovePreview()
end

function PlotBuilder.RegisterFloorInput()
	floorInputSuppressUntil = os.clock() + FLOOR_INPUT_SUPPRESS_SECONDS
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

	local selectionLevelValue = (selection :: any).Level
	local level = if typeof(selectionLevelValue) == "number"
		then selectionLevelValue
		else PlotStateStore.GetActiveLevel()

	local success, message = Packets.PlaceFloorAreaRequest:Fire({
		ItemId = itemId,
		StartCellX = startX,
		StartCellZ = startZ,
		EndCellX = endX,
		EndCellZ = endZ,
		WidthCells = widthCells,
		DepthCells = depthCells,
		Level = level,
		SurfaceId = resolveDefaultSurfaceId(itemId),
	})

	local placementPosition =
		computeAreaPlacementPosition(startX, startZ, endX, endZ, widthCells, depthCells, "North", level)

	if success then
		SoundtrackManager.PlayPlacementSuccess()
		PlacementCelebration.ShowSuccess(placementPosition, itemId)
		PlacementCelebration.CelebrateFloorArea(itemId, minCellX, minCellZ, widthCells, depthCells, level)
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

	local isDiagonalForward = orientation == "DiagonalForward"
	local isDiagonalBackward = orientation == "DiagonalBackward"
	local isDiagonal = isDiagonalForward or isDiagonalBackward

	if orientation ~= "Horizontal" and orientation ~= "Vertical" and not isDiagonal then
		return
	end

	if orientation == "Horizontal" and startCellZ ~= endCellZ then
		return
	end

	if orientation == "Vertical" and startCellX ~= endCellX then
		return
	end

	if isDiagonal then
		local deltaX = endCellX - startCellX
		local deltaZ = endCellZ - startCellZ
		if math.abs(deltaX) ~= math.abs(deltaZ) then
			return
		end
		if deltaX ~= 0 or deltaZ ~= 0 then
			local product = deltaX * deltaZ
			if isDiagonalForward and product < 0 then
				return
			end
			if isDiagonalBackward and product > 0 then
				return
			end
		end
	end

	local selectionLevelValue = (selection :: any).Level
	local level = if typeof(selectionLevelValue) == "number"
		then selectionLevelValue
		else PlotStateStore.GetActiveLevel()

	local success, message = Packets.PlaceWallStripRequest:Fire({
		ItemId = itemId,
		Facing = facing,
		Orientation = orientation,
		StartCellX = startCellX,
		StartCellZ = startCellZ,
		EndCellX = endCellX,
		EndCellZ = endCellZ,
		Level = level,
		SurfaceId = resolveDefaultSurfaceId(itemId),
	})

	local placementPosition = computeWallStripPosition(selection, level)

	if success then
		SoundtrackManager.PlayPlacementSuccess()
		PlacementCelebration.ShowSuccess(placementPosition, itemId)
		PlacementCelebration.CelebrateWallStrip(
			itemId,
			startCellX,
			endCellX,
			startCellZ,
			endCellZ,
			facing,
			orientation,
			level
		)
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

	local selectionLevelValue = (selection :: any).Level
	local level = if typeof(selectionLevelValue) == "number"
		then selectionLevelValue
		else PlotStateStore.GetActiveLevel()

	local success, message = Packets.PlaceRoofAreaRequest:Fire({
		ItemId = itemId,
		StartCellX = startX,
		StartCellZ = startZ,
		EndCellX = endX,
		EndCellZ = endZ,
		Level = level,
	})

	local placementPosition = computeAreaPlacementPosition(
		startX,
		startZ,
		endX,
		endZ,
		selection.WidthCells,
		selection.DepthCells,
		"North",
		level
	)

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
