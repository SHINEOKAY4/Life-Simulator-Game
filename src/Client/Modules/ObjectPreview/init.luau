--!strict

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementBehavior = require(ReplicatedStorage.Shared.Utilities.PlacementBehavior)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)
local PlotStateStore = require(script.Parent.Parent:WaitForChild("ClientStores"):WaitForChild("PlotStateStore"))
local CutawayViewController = require(script.Parent:WaitForChild("CutawayViewController"))

local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)

local MarkerPool = require(script:WaitForChild("MarkerPool"))
local PlacementUtils = require(script:WaitForChild("PlacementUtils"))
local FloorPreview = require(script:WaitForChild("FloorPreview"))
local RoofPreview = require(script:WaitForChild("RoofPreview"))
local WallStripPreview = require(script:WaitForChild("WallStripPreview"))
local WallConstraints = require(script:WaitForChild("WallConstraints"))
local Renderer = require(script:WaitForChild("Renderer"))
local PlacementCostDisplay = require(script.Parent:WaitForChild("PlacementCostDisplay"))
local GetYawFromFacing = PlacementHelpers.GetYawFromFacing
local Types = require(script:WaitForChild("Types"))
local PoseCache = require(script:WaitForChild("PoseCache"))
local CeilingPreviewState = require(script:WaitForChild("CeilingPreviewState"))
local WindowPreviewController = require(script:WaitForChild("WindowPreviewController"))

type PreviewFacing = Types.PreviewFacing
type PreviewKind = Types.PreviewKind
type PreviewPose = Types.PreviewPose
type WallMountPose = Types.WallMountPose
type SurfaceMountPose = Types.SurfaceMountPose
type CeilingMountPose = Types.CeilingMountPose
type WindowCutoutPose = Types.WindowCutoutPose
type PoseCacheComparable = Types.PoseCacheComparable
type PoseCacheSnapshot = Types.PoseCacheSnapshot
type WindowCutoutConfig = Renderer.WindowCutoutConfig
type MoveOriginInfo = PlacementUtils.MoveOriginInfo
export type Facing = PreviewFacing
export type FloorSelectionInfo = FloorPreview.FloorSelectionInfo
type FloorUpdateResult = FloorPreview.FloorUpdateResult
export type RoofSelectionInfo = RoofPreview.RoofSelectionInfo
type RoofUpdateResult = RoofPreview.RoofUpdateResult
export type WallStripSelectionInfo = WallStripPreview.WallStripSelectionInfo

type WallMountedPreviewResult = {
	CanPlace: boolean,
	ReferenceCellX: number,
	ReferenceCellZ: number,
	AttachedFacing: PreviewFacing,
	WorldPosition: Vector3,
	WallNormal: Vector3,
	HeightOffset: number,
}

local findWallModel: (Instance?) -> Model?
local extractWallPose: (Model?) -> (number?, number?, PreviewFacing?)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local PreviewContext = InputContextsFolder:WaitForChild("PreviewContext")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local PreviewHighlight = AssetsFolder.VisualTools:WaitForChild("PreviewHighlight") :: Highlight

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local objectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled") :: BoolValue

local storedPromptServiceEnabled: boolean? = nil
local proximityPromptsSuppressed = false
local CeilingCutawaySuppressed = false
local CEILING_CUTAWAY_SOURCE = "CeilingPreview"

-- Temporarily disable proximity prompts so preview input keys do not trigger world interactions.

local function suppressProximityPrompts()
	if proximityPromptsSuppressed then
		return
	end
	storedPromptServiceEnabled = ProximityPromptService.Enabled
	proximityPromptsSuppressed = true
	ProximityPromptService.Enabled = false
end

local function restoreProximityPrompts()
	if not proximityPromptsSuppressed then
		return
	end
	proximityPromptsSuppressed = false
	local desiredState = storedPromptServiceEnabled
	if desiredState == nil then
		desiredState = true
	end
	ProximityPromptService.Enabled = desiredState
	storedPromptServiceEnabled = nil
end

local function disableCutawayForCeiling()
	if CeilingCutawaySuppressed then
		return
	end
	CeilingCutawaySuppressed = true
	CutawayViewController.Request(CEILING_CUTAWAY_SOURCE, {
		Priority = 64,
		TargetLevel = PlotStateStore.GetMaxLevel(),
		HidePlacementTypes = {
			Wall = false,
			Roof = false,
			Ceiling = false,
			Floor = false,
			CellObject = false,
		},
	})
end

local function restoreCutawayAfterCeiling()
	if not CeilingCutawaySuppressed then
		return
	end
	CeilingCutawaySuppressed = false
	CutawayViewController.Release(CEILING_CUTAWAY_SOURCE)
end

local Camera = workspace.CurrentCamera

local ObjectPreview = {}

local Connection: RBXScriptConnection? = nil
local SelectedItem: Model? = nil
local CurrentItemId: string? = nil
local CurrentItemSpec: any? = nil
local CurrentKind: PreviewKind = "CellObject"
local CurrentFacing: PreviewFacing = "North"
local CurrentPivotRotation: CFrame = CFrame.identity

local LastLevel: number? = nil
local LastLevelHeight: number? = nil

local MoveOriginSignature: MoveOriginInfo? = nil
local MoveHoldActive = false
local MoveHoldMousePosition: Vector2? = nil
local MOUSE_MOVE_RELEASE_THRESHOLD = 2

local FloorSupportMap: { [number]: boolean } = {}
local WallStripPlacementHandler: ((WallStripSelectionInfo) -> ())? = nil
local RoofPlacementHandler: ((RoofSelectionInfo) -> ())? = nil
local LastPrimaryMouseDown = false
local CurrentWallMountPose: WallMountPose? = nil
local CurrentSurfaceMountPose: SurfaceMountPose? = nil
local CurrentCeilingMountPose: CeilingMountPose? = nil

local PLACEABLE_FILL = Color3.fromRGB(159, 234, 159)
local PLACEABLE_OUTLINE = Color3.fromRGB(137, 255, 119)
local BLOCKED_FILL = Color3.fromRGB(219, 136, 136)
local BLOCKED_OUTLINE = Color3.fromRGB(255, 85, 85)
local SURFACE_LOCAL_EPSILON = 1e-3

local function resetFloorState(shouldReleasePreviewPart: boolean?)
	FloorPreview.Clear()
	if shouldReleasePreviewPart then
		FloorPreview.ReleasePreviewPart()
	end
	LastPrimaryMouseDown = false
	PlacementCostDisplay.Hide()
end

local function resetRoofState(shouldReleasePreviewPart: boolean?)
	RoofPreview.Clear()
	if shouldReleasePreviewPart then
		RoofPreview.ReleasePreviewPart()
	end
	LastPrimaryMouseDown = false
	PlacementCostDisplay.Hide()
end

local function computeIgnorePlacement(): MoveOriginInfo?
	return MoveOriginSignature
end

local function updateFacing(newFacing: PreviewFacing)
	if CurrentFacing == newFacing then
		return
	end
	CurrentFacing = newFacing
	PoseCache.Reset()
end

local function applyModelPhysicsOverrides(model: Model)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false
		end
	end
end

local CARDINAL_ROTATION_ORDER: { PreviewFacing } = { "North", "East", "South", "West" }
local CARDINAL_ROTATION_INDEX: { [PreviewFacing]: number } = {
	North = 1,
	East = 2,
	South = 3,
	West = 4,
}

local WALL_ROTATION_ORDER: { PreviewFacing } = { "North", "NorthEast", "East", "South", "West", "NorthWest" }
local WALL_ROTATION_INDEX: { [PreviewFacing]: number } = {
	North = 1,
	NorthEast = 2,
	East = 3,
	South = 4,
	West = 5,
	NorthWest = 6,
}

local function allowsDiagonalForCurrentWall(): boolean
	if CurrentKind ~= "Wall" then
		return false
	end

	local spec = CurrentItemSpec
	if typeof(spec) ~= "table" then
		return false
	end

	local placementType = spec.PlacementType or spec.Type
	if placementType ~= "Wall" then
		return false
	end

	if spec.RequiresExistingWall == true then
		return false
	end

	if spec.AllowDiagonalWalls == false or spec.AllowDiagonalWallStrips == false then
		return false
	end

	local allowedFacing = spec.Facing
	if typeof(allowedFacing) == "table" then
		local hasDiagonalFacing = false
		for _, facing in allowedFacing do
			if facing == "NorthEast" or facing == "SouthEast" or facing == "NorthWest" or facing == "SouthWest" then
				hasDiagonalFacing = true
				break
			end
		end
		if not hasDiagonalFacing then
			return false
		end
	end

	return true
end

local function rotationSequenceForCurrent(): ({ PreviewFacing }, { [PreviewFacing]: number })
	if allowsDiagonalForCurrentWall() then
		return WALL_ROTATION_ORDER, WALL_ROTATION_INDEX
	end
	return CARDINAL_ROTATION_ORDER, CARDINAL_ROTATION_INDEX
end

local function rotateFacing(step: number)
	if CurrentKind == "Ceiling" then
		CeilingPreviewState.Rotate(step)
		return
	end
	local sequence, indexMap = rotationSequenceForCurrent()
	local count = #sequence
	if count == 0 then
		return
	end

	local currentFacing = CurrentFacing
	local index = indexMap[currentFacing]
	if not index then
		local fallback = sequence[1]
		if not fallback then
			return
		end
		currentFacing = fallback
		index = indexMap[fallback] or 1
		updateFacing(fallback)
	end

	local newIndex = ((index - 1 + step) % count) + 1
	local newFacing = sequence[newIndex]
	if newFacing and newFacing ~= currentFacing then
		updateFacing(newFacing)
	end
end

local function shouldSkipPose(pose: PoseCacheComparable): boolean
	return PoseCache.ShouldSkip(CurrentKind, pose, SURFACE_LOCAL_EPSILON)
end

local function updatePoseCache(pose: PoseCacheComparable)
	PoseCache.Update(CurrentKind, pose)
end

local function getPoseSnapshot(): PoseCacheSnapshot
	return PoseCache.GetSnapshot()
end

local function isWindowVariant(spec: any?): boolean
	return WindowPreviewController.IsWindowSpec(spec)
end

local function hideWindowPreviewModel()
	if not isWindowVariant(CurrentItemSpec) then
		return
	end
	WindowPreviewController.HideModel(SelectedItem, PreviewHighlight)
end

local function showWindowPreviewModel()
	if not isWindowVariant(CurrentItemSpec) then
		return
	end
	WindowPreviewController.ShowModel(SelectedItem, PreviewHighlight)
end

local function clearWindowPreview()
	WindowPreviewController.Clear(SelectedItem, PreviewHighlight)
end

local function computeLift(spec: any?, model: Model, surface: BasePart): number
	local surfaceUp = surface.CFrame.UpVector
	local baseLift = Renderer.GetLiftAlongSurface(model, surfaceUp)
	local extraLift = 0
	if typeof(spec) == "table" then
		local offset = spec.SurfaceOffsetStuds
		if typeof(offset) == "number" then
			extraLift = offset
		end
	end
	return baseLift + extraLift
end

local function withMarkerPool(render: () -> ())
	MarkerPool.BeginFrame()
	render()
end

local function isMouseHoldBroken(currentPosition: Vector2): boolean
	local origin = MoveHoldMousePosition
	if not origin then
		MoveHoldMousePosition = currentPosition
		return false
	end
	return (currentPosition - origin).Magnitude > MOUSE_MOVE_RELEASE_THRESHOLD
end

function ObjectPreview.Init()
	objectPreviewEnabled.Changed:Connect(function()
		if objectPreviewEnabled.Value then
			suppressProximityPrompts()
			return
		end
		restoreProximityPrompts()
	end)

	if objectPreviewEnabled.Value then
		suppressProximityPrompts()
	end

	PreviewContext.RotateLeft.Pressed:Connect(function()
		rotateFacing(1)
	end)

	PreviewContext.RotateRight.Pressed:Connect(function()
		rotateFacing(-1)
	end)

	PreviewContext.CancelPreview.Pressed:Connect(function()
		ObjectPreview.ClearPreview()
	end)

	UserInputService.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		LastPrimaryMouseDown = false
		if WallStripPreview.IsDragInProgress() then
			local summary = WallStripPreview.GetSelectionSummary()
			if not summary then
				summary = WallStripPreview.GetFallbackSummary()
			end
			local handler = WallStripPlacementHandler
			WallStripPreview.Clear()
			if summary and handler and summary.CanPlace then
				handler(summary)
			end
			return
		end
		if RoofPreview.IsDragInProgress() then
			local summary = RoofPreview.GetSelectionSummary()
			resetRoofState()
			if summary and summary.ItemId then
				local handler = RoofPlacementHandler
				if handler and summary.CanPlace then
					handler(summary)
				end
			end
			return
		end
		if not FloorPreview.IsDragInProgress() then
			return
		end

		local summary = FloorPreview.GetSelectionSummary()
		resetFloorState()
		if not summary or not summary.ItemId then
			return
		end

		local handler = FloorPreview.GetPlacementHandler()
		if handler and summary.CanPlace then
			handler(summary)
		end
	end)
end

local function buildRaycastParams(surface: BasePart, container: Instance?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	if container then
		params.FilterDescendantsInstances = { surface, container }
	else
		params.FilterDescendantsInstances = { surface }
	end
	params.IgnoreWater = true
	return params
end

local function buildWallRaycastParams(container: Instance?): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.IgnoreWater = true
	if container then
		params.FilterDescendantsInstances = { container }
	else
		params.FilterDescendantsInstances = {}
	end
	return params
end

local function ensureFloorPreviewPrepared(kind: PreviewKind, model: Model, baseWidth: number, baseDepth: number)
	if kind == "Floor" then
		FloorPreview.Prepare(model, baseWidth, baseDepth)
		resetRoofState(true)
	elseif kind == "Roof" then
		RoofPreview.Prepare(model, baseWidth, baseDepth)
		resetFloorState(true)
	else
		resetFloorState(true)
		resetRoofState(true)
	end
end

local function renderFloorPreview(
	model: Model,
	grid: any,
	surface: BasePart,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	placed,
	ignorePlacement: PlacementUtils.MoveOriginInfo?,
	itemId: string?,
	activeLevel: number,
	levelHeight: number
)
	local result = FloorPreview.Update({
		model = model,
		grid = grid,
		surface = surface,
		chunkSize = chunkSize,
		cellX = cellX,
		cellZ = cellZ,
		itemId = itemId,
		placed = placed,
		ignorePlacement = ignorePlacement,
		isChunkUnlocked = PlotStateStore.IsChunkUnlocked,
		level = activeLevel,
		levelHeight = levelHeight,
	}) :: FloorUpdateResult?
	if result then
		PreviewHighlight.FillColor = result.fillColor
		PreviewHighlight.OutlineColor = result.outlineColor
		local summary = result.summary
		if summary and typeof(itemId) == "string" then
			local summaryLevelHeight = PlotStateStore.GetLevelHeight(summary.Level)
			local widthCells = summary.WidthCells or (summary.MaxCellX - summary.MinCellX + 1)
			local depthCells = summary.DepthCells or (summary.MaxCellZ - summary.MinCellZ + 1)
			local centerCFrame =
				grid:FootprintCenterCFrame(summary.MinCellX, summary.MinCellZ, widthCells, depthCells, "North")
			centerCFrame = centerCFrame * CFrame.new(0, summaryLevelHeight, 0)
			local upVector = surface.CFrame.UpVector
			local maxDimension = math.max(widthCells, depthCells)
			local heightOffset = 1.75 + math.max(0, maxDimension - 1) * 0.35
			local worldPosition = centerCFrame.Position + upVector * heightOffset
			PlacementCostDisplay.UpdateFloor(itemId, summary.CellCount, result.canPlace, worldPosition)
		else
			PlacementCostDisplay.Hide()
		end
	else
		PlacementCostDisplay.Hide()
	end
end

local function previewWall(
	model: Model,
	grid: any,
	cellX: number,
	cellZ: number,
	facing: PreviewFacing,
	levelHeight: number,
	lift: number,
	span: WallStripSelectionInfo?
)
	Renderer.PreviewWall(model, grid, cellX, cellZ, facing, levelHeight, lift, span)
end

local function previewRoof(
	model: Model,
	grid: any,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	facing: PreviewFacing,
	widthCells: number,
	depthCells: number,
	levelHeight: number,
	spec: any?
)
	Renderer.PreviewRoof(model, grid, surface, cellX, cellZ, widthCells, depthCells, facing, levelHeight, spec)
end

local function previewCellObject(
	model: Model,
	grid: any,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	facing: PreviewFacing,
	widthCells: number,
	depthCells: number,
	levelHeight: number,
	lift: number
)
	Renderer.PreviewCellObject(
		model,
		grid,
		surface,
		cellX,
		cellZ,
		facing,
		widthCells,
		depthCells,
		levelHeight,
		lift,
		CurrentPivotRotation
	)
end

local function surfaceTopOrigin(surface: BasePart): Vector3
	return surface.CFrame.Position + surface.CFrame.UpVector * (surface.Size.Y * 0.5)
end

local function computeHeightOffset(surface: BasePart, point: Vector3): number
	local surfaceUp = surface.CFrame.UpVector
	local topOrigin = surfaceTopOrigin(surface)
	return (point - topOrigin):Dot(surfaceUp)
end

local function adjustPointToHeight(surface: BasePart, point: Vector3, targetHeight: number): Vector3
	local surfaceUp = surface.CFrame.UpVector
	local currentHeight = computeHeightOffset(surface, point)
	return point + surfaceUp * (targetHeight - currentHeight)
end

local function normalFromFacing(facing: PreviewFacing): Vector3
	if facing == "North" then
		return Vector3.new(0, 0, -1)
	elseif facing == "South" then
		return Vector3.new(0, 0, 1)
	elseif facing == "East" then
		return Vector3.new(1, 0, 0)
	elseif facing == "West" then
		return Vector3.new(-1, 0, 0)
	elseif facing == "NorthEast" then
		return Vector3.new(1, 0, -1).Unit
	elseif facing == "SouthEast" then
		return Vector3.new(1, 0, 1).Unit
	elseif facing == "SouthWest" then
		return Vector3.new(-1, 0, 1).Unit
	elseif facing == "NorthWest" then
		return Vector3.new(-1, 0, -1).Unit
	end
	return Vector3.new(0, 0, -1)
end

local function isDiagonalFacing(facing: PreviewFacing): boolean
	return facing == "NorthEast" or facing == "SouthEast" or facing == "SouthWest" or facing == "NorthWest"
end

local function extractNumber(source: any, key: string): number?
	if typeof(source) ~= "table" then
		return nil
	end

	local value = source[key]
	if typeof(value) == "number" then
		return value
	end

	return nil
end

local function resolveWallDimensionsFromSpec(spec: any?): (number, number, number, number, number)
	local defaultWidth = 4
	local defaultHeight = 12
	local defaultThickness = 0.5
	local defaultDiagonalMultiplier = math.sqrt(2)
	local defaultMinFrame = 0.2

	if typeof(spec) ~= "table" then
		return defaultWidth, defaultHeight, defaultThickness, defaultDiagonalMultiplier, defaultMinFrame
	end

	local dims = spec.WallDimensions
	if typeof(dims) ~= "table" then
		return defaultWidth, defaultHeight, defaultThickness, defaultDiagonalMultiplier, defaultMinFrame
	end

	local width = typeof(dims.NominalWidth) == "number" and dims.NominalWidth or defaultWidth
	local height = typeof(dims.NominalHeight) == "number" and dims.NominalHeight or defaultHeight
	local thickness = typeof(dims.NominalThickness) == "number" and dims.NominalThickness or defaultThickness
	local diagonalMultiplier = typeof(dims.DiagonalLengthMultiplier) == "number" and dims.DiagonalLengthMultiplier
		or defaultDiagonalMultiplier
	local minFrame = typeof(dims.MinFrameThickness) == "number" and dims.MinFrameThickness or defaultMinFrame

	return width, height, thickness, diagonalMultiplier, minFrame
end

local function validateExistingWallReplacement(
	cellX: number,
	cellZ: number,
	facing: PreviewFacing,
	spec: any?,
	placed: any?,
	ignorePlacement: MoveOriginInfo?,
	level: number?
): (boolean, string?, any?, any?, boolean)
	if typeof(spec) ~= "table" or spec.RequiresExistingWall ~= true then
		return true, nil, nil, nil, false
	end

	local placementKey = PlacementKey.ForPlacementType(cellX, cellZ, facing :: any, "Wall", level)
	local occupant = placed and placed[placementKey]
	if not occupant then
		return false, "Requires an existing wall", nil, nil, false
	end

	local occupantCheckId = occupant.id
	local occupantSpec = occupantCheckId and ItemFinder.FindItemById(occupantCheckId) or nil

	local occupantMatchesOrigin = false
	if ignorePlacement then
		local sameId = occupant.id == ignorePlacement.ItemId
		local sameCell = occupant.cellX == ignorePlacement.CellX and occupant.cellZ == ignorePlacement.CellZ
		local sameFacing = PlacementKey.NormalizeFacing(occupant.facing) == ignorePlacement.Facing
		local ignoreLevel = ignorePlacement.Level
		local occupantLevel = if typeof(occupant.Level) == "number" then occupant.Level else nil
		local sameLevel = if ignoreLevel ~= nil then occupantLevel == ignoreLevel else true
		occupantMatchesOrigin = sameId and sameCell and sameFacing and sameLevel
	end

	if occupantMatchesOrigin then
		return true, nil, occupant, occupantSpec, true
	end

	if isWindowVariant(spec) then
		local occupantMetadata = typeof(occupant.Metadata) == "table" and occupant.Metadata or nil
		local hasExistingWindow = false
		if occupantMetadata then
			hasExistingWindow = typeof(occupantMetadata.WindowCutoutData) == "table"
			if not hasExistingWindow then
				local originalMetadata = occupantMetadata.OriginalWallMetadata
				if typeof(originalMetadata) == "table" and typeof(originalMetadata.WindowCutoutData) == "table" then
					hasExistingWindow = true
				end
			end
		end

		if hasExistingWindow then
			return false, "Wall already has a window installed", occupant, occupantSpec, false
		end
	end

	if occupantSpec and occupantSpec.RequiresExistingWall == true then
		local previousId = occupant.Metadata and occupant.Metadata.PreviousId
		if typeof(previousId) == "string" and previousId ~= "" then
			occupantCheckId = previousId
			occupantSpec = ItemFinder.FindItemById(previousId)
		end
	end

	local canReplace = occupantSpec ~= nil and occupantSpec.PlacementType == "Wall"
	if canReplace and spec.ReplaceableWallTag then
		canReplace = ItemFinder.HasTag(occupantCheckId, spec.ReplaceableWallTag)
	end

	if not canReplace then
		return false, "Wall cannot host this item", occupant, occupantSpec, false
	end

	return true, nil, occupant, occupantSpec, false
end

local function computeWallMountedPreview(
	result: RaycastResult,
	grid: any,
	surface: BasePart,
	chunkSize: number,
	placed: any,
	ignorePlacement: MoveOriginInfo?
): WallMountedPreviewResult?
	local itemSpec = CurrentItemSpec
	if typeof(itemSpec) ~= "table" then
		return nil
	end

	local wallModel = findWallModel(result.Instance)
	if not wallModel then
		return nil
	end

	local wallCellX, wallCellZ, wallFacing = extractWallPose(wallModel)
	if not wallCellX or not wallCellZ or not wallFacing then
		return nil
	end

	local mountConfig = itemSpec.WallMountConfig
	if typeof(mountConfig) ~= "table" then
		return nil
	end

	local minHeight = mountConfig.MinHeight or 0
	local maxHeight = mountConfig.MaxHeight or (minHeight + 10)
	if maxHeight < minHeight then
		maxHeight = minHeight
	end

	local desiredHeight = computeHeightOffset(surface, result.Position)
	local clampedHeight = math.clamp(desiredHeight, minHeight, maxHeight)
	local adjustedPoint = adjustPointToHeight(surface, result.Position, clampedHeight)

	local wallNormal = result.Normal
	if wallNormal.Magnitude < 1e-3 then
		wallNormal = normalFromFacing(wallFacing)
	end
	local canonical = normalFromFacing(wallFacing)
	if canonical.Magnitude > 1e-3 then
		if canonical:Dot(wallNormal) < 0 then
			canonical = -canonical
		end
		wallNormal = canonical.Unit
	else
		wallNormal = wallNormal.Unit
	end

	local offsetFromWall = mountConfig.OffsetFromWall
	if typeof(offsetFromWall) ~= "number" then
		offsetFromWall = 0.1
	end
	local finalPosition = adjustedPoint + wallNormal * offsetFromWall

	local chunkX, chunkZ = grid:CellToChunk(wallCellX, wallCellZ, chunkSize)
	local isUnlocked = PlotStateStore.IsChunkUnlocked(chunkX, chunkZ)

	local canPlace = isUnlocked
	local ignoreKey: string? = nil
	if ignorePlacement then
		local ignoreFacing = PlacementKey.NormalizeFacing(ignorePlacement.Facing :: any)
		local ignorePlacementType = ignorePlacement.PlacementKeyType or ignorePlacement.PlacementType
		ignoreKey = PlacementKey.ForPlacementType(
			ignorePlacement.CellX,
			ignorePlacement.CellZ,
			ignoreFacing :: any,
			ignorePlacementType,
			ignorePlacement.Level
		)
	end

	if canPlace and mountConfig.CollisionCheck ~= false and placed then
		local visualSize = mountConfig.VisualSize
		if typeof(visualSize) ~= "Vector3" then
			visualSize = Vector3.new(2, 2, 0.5)
		end
		local spacingRadius = math.max(0.5, (visualSize.X + visualSize.Z) * 0.5)
		for key, entry in pairs(placed) do
			local spec = entry.id and ItemFinder.FindItemById(entry.id) or nil
			if spec and (spec.PlacementType or spec.Type) == "WallMounted" then
				if ignoreKey and key == ignoreKey then
					continue
				end
				local metadata = entry.Metadata
				local wallData = metadata and metadata.WallMountData
				if wallData then
					local attachedFacing = wallData.AttachedFacing or wallData.Face or wallData.Facing
					local sameFacing = attachedFacing == wallFacing
					local sameCell = wallData.ReferenceCellX == wallCellX and wallData.ReferenceCellZ == wallCellZ
					if sameFacing and sameCell then
						local existingPos = wallData.WorldPosition
						if typeof(existingPos) == "Vector3" then
							if (existingPos - finalPosition).Magnitude < spacingRadius then
								canPlace = false
								break
							end
						end
					end
				end
			end
		end
	end

	return {
		CanPlace = canPlace,
		ReferenceCellX = wallCellX,
		ReferenceCellZ = wallCellZ,
		AttachedFacing = wallFacing,
		WorldPosition = finalPosition,
		WallNormal = wallNormal,
		HeightOffset = clampedHeight,
	}
end

local function computeWindowCutoutPose(
	wallModel: Model,
	cellX: number,
	cellZ: number,
	facing: PreviewFacing,
	hitPosition: Vector3,
	spec: any?,
	occupantEntry: any?,
	occupantSpec: any?,
	occupantMatchesOrigin: boolean?
): WindowCutoutPose?
	if typeof(spec) ~= "table" then
		return nil
	end

	local config = spec.WindowCutoutConfig :: WindowCutoutConfig?
	if typeof(config) ~= "table" then
		return nil
	end

	local wallPart = wallModel.PrimaryPart or wallModel:FindFirstChildWhichIsA("BasePart")
	if not wallPart then
		return nil
	end

	local wallNormal = wallPart.CFrame.LookVector
	local facingNormal = normalFromFacing(facing)
	if wallNormal:Dot(facingNormal) < 0 then
		wallNormal = -wallNormal
	end

	local wallUp = wallPart.CFrame.UpVector
	if wallUp.Magnitude < 1e-3 then
		wallUp = Vector3.new(0, 1, 0)
	end

	local partSize = wallPart.Size
	local partWidth = partSize.X
	local partHeight = partSize.Y
	local partThickness = partSize.Z

	local occupantMetadata = occupantEntry and occupantEntry.Metadata
	local baseMetadata = nil
	local existingWindowData = nil
	if typeof(occupantMetadata) == "table" then
		if typeof(occupantMetadata.WindowCutoutData) == "table" then
			existingWindowData = occupantMetadata.WindowCutoutData
		end
		if typeof(occupantMetadata.OriginalWallMetadata) == "table" then
			baseMetadata = occupantMetadata.OriginalWallMetadata
		else
			baseMetadata = occupantMetadata
		end
	end

	local fallbackWidth, fallbackHeight, fallbackThickness, fallbackDiagonal, fallbackMinFrame =
		resolveWallDimensionsFromSpec(occupantSpec)

	local wallWidth = extractNumber(baseMetadata, "WallSizeX") or fallbackWidth
	local wallHeight = extractNumber(baseMetadata, "WallSizeY") or fallbackHeight
	local wallThickness = extractNumber(baseMetadata, "WallSizeZ") or fallbackThickness
	if wallWidth <= 0 then
		wallWidth = partWidth
	end
	if wallHeight <= 0 then
		wallHeight = partHeight
	end
	if wallThickness <= 0 then
		wallThickness = partThickness
	end

	local diagonalMultiplierValue = extractNumber(baseMetadata, "DiagonalLengthMultiplier") or fallbackDiagonal
	local diagonalMultiplier = if diagonalMultiplierValue and diagonalMultiplierValue > 0
		then diagonalMultiplierValue
		else math.sqrt(2)

	local effectiveWallWidthSource = extractNumber(baseMetadata, "EffectiveWallWidth")
	local effectiveWallWidth: number
	if typeof(effectiveWallWidthSource) == "number" and effectiveWallWidthSource > 0 then
		effectiveWallWidth = effectiveWallWidthSource
	else
		effectiveWallWidth = wallWidth
		if isDiagonalFacing(facing) then
			effectiveWallWidth = wallWidth * diagonalMultiplier
		end
	end

	local minFrameBaseValue = extractNumber(baseMetadata, "MinFrameThickness") or fallbackMinFrame
	local minFrameBase = if minFrameBaseValue and minFrameBaseValue > 0 then minFrameBaseValue else 0.2

	local configMinFrame = typeof(config.MinFrameThickness) == "number" and config.MinFrameThickness or nil
	local minFrameThickness = math.max(minFrameBase, configMinFrame or minFrameBase)

	local maxFrameThickness: number
	if typeof(config.MaxFrameThickness) == "number" and config.MaxFrameThickness > 0 then
		maxFrameThickness = math.max(config.MaxFrameThickness, minFrameThickness)
	else
		maxFrameThickness = math.max(minFrameThickness * 2, effectiveWallWidth * 0.5)
	end

	local useExistingCutout = occupantMatchesOrigin == true and typeof(existingWindowData) == "table"
	local frameRatio = typeof(config.FrameThicknessRatio) == "number" and math.max(config.FrameThicknessRatio, 0) or nil
	local frameThickness = if useExistingCutout and typeof(existingWindowData.FrameThickness) == "number"
		then existingWindowData.FrameThickness
		elseif frameRatio and frameRatio > 0 then wallWidth * frameRatio
		else (typeof(config.FrameThickness) == "number" and config.FrameThickness or minFrameThickness)
	frameThickness = math.clamp(frameThickness, minFrameThickness, math.max(minFrameThickness, maxFrameThickness))
	frameThickness = math.min(frameThickness, math.max(effectiveWallWidth * 0.5 - 0.01, minFrameThickness))

	local minCutoutWidthBase = typeof(config.MinCutoutWidth) == "number" and config.MinCutoutWidth or 0
	local minCutoutWidth = math.max(frameThickness * 2, minCutoutWidthBase)
	local maxCutoutWidth: number
	if typeof(config.MaxCutoutWidth) == "number" and config.MaxCutoutWidth > 0 then
		maxCutoutWidth = math.max(config.MaxCutoutWidth, minCutoutWidth)
	else
		maxCutoutWidth = math.max(effectiveWallWidth - frameThickness * 2, minCutoutWidth)
	end
	local widthRatio = typeof(config.CutoutWidthRatio) == "number" and math.max(config.CutoutWidthRatio, 0) or nil
	local desiredCutoutWidth = if useExistingCutout and typeof(existingWindowData.CutoutWidth) == "number"
		then existingWindowData.CutoutWidth
		elseif typeof(config.CutoutWidth) == "number" and config.CutoutWidth > 0 then config.CutoutWidth
		else effectiveWallWidth * (widthRatio and widthRatio > 0 and widthRatio or 0.7)
	local cutoutWidth = math.clamp(desiredCutoutWidth, minCutoutWidth, math.max(minCutoutWidth, maxCutoutWidth))
	cutoutWidth = math.min(cutoutWidth, effectiveWallWidth - frameThickness * 2)
	if cutoutWidth < frameThickness * 2 then
		cutoutWidth = frameThickness * 2
	end

	local minCutoutHeightBase = typeof(config.MinCutoutHeight) == "number" and config.MinCutoutHeight or 0
	local minCutoutHeight = math.max(frameThickness * 2, minCutoutHeightBase)
	local maxCutoutHeight: number
	if typeof(config.MaxCutoutHeight) == "number" and config.MaxCutoutHeight > 0 then
		maxCutoutHeight = math.max(config.MaxCutoutHeight, minCutoutHeight)
	else
		maxCutoutHeight = math.max(wallHeight - frameThickness * 2, minCutoutHeight)
	end
	local heightRatio = typeof(config.CutoutHeightRatio) == "number" and math.max(config.CutoutHeightRatio, 0) or nil
	local desiredCutoutHeight = if useExistingCutout and typeof(existingWindowData.CutoutHeight) == "number"
		then existingWindowData.CutoutHeight
		elseif typeof(config.CutoutHeight) == "number" and config.CutoutHeight > 0 then config.CutoutHeight
		else wallHeight * (heightRatio and heightRatio > 0 and heightRatio or 0.6)
	local cutoutHeight = math.clamp(desiredCutoutHeight, minCutoutHeight, math.max(minCutoutHeight, maxCutoutHeight))
	cutoutHeight = math.min(cutoutHeight, wallHeight - frameThickness * 2)
	if cutoutHeight < frameThickness * 2 then
		cutoutHeight = frameThickness * 2
	end

	local wallBottom = wallPart.CFrame.Position - wallUp * (wallHeight * 0.5)
	local rawHeight = (hitPosition - wallBottom):Dot(wallUp)
	if typeof(rawHeight) ~= "number" or rawHeight ~= rawHeight then
		rawHeight = 0
	end

	local halfCutoutHeight = cutoutHeight * 0.5
	local minCenter =
		math.max(halfCutoutHeight, typeof(config.MinHeight) == "number" and config.MinHeight or halfCutoutHeight)
	local maxCenter = math.min(
		wallHeight - halfCutoutHeight,
		typeof(config.MaxHeight) == "number" and config.MaxHeight or wallHeight - halfCutoutHeight
	)
	if maxCenter < minCenter then
		maxCenter = minCenter
	end

	local defaultCenterValue: number
	if useExistingCutout and typeof(existingWindowData.HeightOffset) == "number" then
		defaultCenterValue = math.clamp(existingWindowData.HeightOffset, minCenter, maxCenter)
	elseif typeof(config.DefaultHeightRatio) == "number" and config.DefaultHeightRatio > 0 then
		defaultCenterValue = math.clamp(wallHeight * config.DefaultHeightRatio, minCenter, maxCenter)
	elseif typeof(config.DefaultHeight) == "number" then
		defaultCenterValue = math.clamp(config.DefaultHeight, minCenter, maxCenter)
	else
		defaultCenterValue = math.clamp(wallHeight * 0.5, minCenter, maxCenter)
	end

	if rawHeight <= 0 then
		rawHeight = defaultCenterValue
	end

	local allowVertical = config.AllowVerticalSliding ~= false
	local resolvedHeight = if allowVertical then math.clamp(rawHeight, minCenter, maxCenter) else defaultCenterValue

	local localCenterY = resolvedHeight - wallHeight * 0.5

	local offsetFromWall = if useExistingCutout and typeof(existingWindowData.OffsetFromWall) == "number"
		then existingWindowData.OffsetFromWall
		elseif typeof(config.OffsetFromWall) == "number" then config.OffsetFromWall
		else 0

	local wallCenter = wallPart.CFrame.Position
	local worldCenter = wallCenter + wallUp.Unit * localCenterY + wallNormal.Unit * offsetFromWall

	return {
		WorldPosition = worldCenter,
		WallNormal = wallNormal.Unit,
		WallUp = wallUp.Unit,
		WallCenter = wallCenter,
		WallCellX = cellX,
		WallCellZ = cellZ,
		AttachedFacing = facing,
		HeightOffset = resolvedHeight,
		CutoutWidth = cutoutWidth,
		CutoutHeight = cutoutHeight,
		WallHeight = wallHeight,
		WallWidth = wallWidth,
		WallThickness = wallThickness,
		LocalCenterY = localCenterY,
		FrameThickness = frameThickness,
		OffsetFromWall = offsetFromWall,
		EffectiveWallWidth = effectiveWallWidth,
	}
end

local function updateHighlightForResult(canPlace: boolean)
	PreviewHighlight.FillColor = if canPlace then PLACEABLE_FILL else BLOCKED_FILL
	PreviewHighlight.OutlineColor = if canPlace then PLACEABLE_OUTLINE else BLOCKED_OUTLINE
end

local function handleRaycastMiss(kind: PreviewKind, isWindowItem: boolean)
	if WindowPreviewController.GetPose() then
		clearWindowPreview()
	end
	if isWindowItem then
		hideWindowPreviewModel()
	end

	if kind == "WallMounted" then
		CurrentWallMountPose = nil
	elseif kind == "SurfaceMounted" then
		CurrentSurfaceMountPose = nil
	elseif kind == "Ceiling" then
		CurrentCeilingMountPose = nil
	end

	updateHighlightForResult(false)
	PlacementCostDisplay.Hide()
end

type DragController = (kind: PreviewKind, cellX: number, cellZ: number) -> ()

local function beginFloorDrag(_: PreviewKind, cellX: number, cellZ: number)
	if CurrentItemId then
		FloorPreview.TryBeginDrag(CurrentKind, CurrentItemId, cellX, cellZ, true)
	end
end

local function beginRoofDrag(_: PreviewKind, cellX: number, cellZ: number)
	if CurrentItemId then
		RoofPreview.TryBeginDrag(CurrentKind, CurrentItemId, cellX, cellZ, true)
	end
end

local DragControllers: { [PreviewKind]: DragController } = {
	Floor = beginFloorDrag,
	Roof = beginRoofDrag,
}

local DragInProgressCheck: { [PreviewKind]: () -> boolean } = {
	Floor = FloorPreview.IsDragInProgress,
	Roof = RoofPreview.IsDragInProgress,
}

local function tryBeginCurrentDrag(kind: PreviewKind, cellX: number, cellZ: number, isMouseDown: boolean)
	if not isMouseDown or LastPrimaryMouseDown then
		return
	end
	if not CurrentItemId then
		return
	end
	local beginDrag = DragControllers[kind]
	if not beginDrag then
		return
	end
	local isDragging = DragInProgressCheck[kind]
	if isDragging and isDragging() then
		return
	end
	beginDrag(kind, cellX, cellZ)
end

type DefaultPreviewArgs = {
	model: Model,
	grid: any,
	surface: BasePart,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	baseWidthCells: number,
	baseDepthCells: number,
	previewFacing: PreviewFacing,
	resolvedPreviewKind: PreviewKind,
	placed: any,
	ignorePlacement: MoveOriginInfo?,
	activeLevel: number,
	levelHeight: number,
	lift: number,
}

local function processWindowVariant(
	model: Model,
	surface: BasePart,
	wallModelForWindow: Model?,
	resolvedPose: WindowCutoutPose,
	itemSpec: any?
): boolean
	if not wallModelForWindow then
		handleRaycastMiss("Wall", true)
		return false
	end

	local wallPart = wallModelForWindow.PrimaryPart or wallModelForWindow:FindFirstChildWhichIsA("BasePart")
	if not wallPart then
		handleRaycastMiss("Wall", true)
		return false
	end

	local rendered = WindowPreviewController.RenderOnWall({
		model = model,
		wallPart = wallPart,
		pose = resolvedPose,
		windowConfig = (itemSpec and itemSpec.WindowCutoutConfig) or nil,
		pivotRotation = CurrentPivotRotation,
		highlight = PreviewHighlight,
	})
	if not rendered then
		handleRaycastMiss("Wall", true)
		return false
	end

	showWindowPreviewModel()
	updateHighlightForResult(true)
	local upVector = surface.CFrame.UpVector
	PlacementCostDisplay.UpdateWall(CurrentItemId or "", 1, true, resolvedPose.WorldPosition + upVector * 2)
	return true
end

local function processWallMountedPreview(model: Model, surface: BasePart, wallPreview: WallMountedPreviewResult)
	CurrentWallMountPose = {
		WorldPosition = wallPreview.WorldPosition,
		WallNormal = wallPreview.WallNormal,
		WallCellX = wallPreview.ReferenceCellX,
		WallCellZ = wallPreview.ReferenceCellZ,
		AttachedFacing = wallPreview.AttachedFacing,
		HeightOffset = wallPreview.HeightOffset,
		ReferenceCellX = wallPreview.ReferenceCellX,
		ReferenceCellZ = wallPreview.ReferenceCellZ,
	}

	local upVector = surface.CFrame.UpVector
	Renderer.PreviewWallMounted(
		model,
		wallPreview.WorldPosition,
		wallPreview.WallNormal,
		upVector,
		CurrentPivotRotation
	)
	updateHighlightForResult(wallPreview.CanPlace)
	PlacementCostDisplay.UpdateWallMounted(
		CurrentItemId or "",
		1,
		wallPreview.CanPlace,
		wallPreview.WorldPosition + upVector * 2
	)
end

local function processSurfaceMountedPreview(model: Model, surfaceMountPose: SurfaceMountPose, surfaceMountParent: Model)
	CurrentSurfaceMountPose = surfaceMountPose

	Renderer.PreviewSurfaceMount(
		model,
		surfaceMountParent,
		surfaceMountPose.LocalPosition,
		surfaceMountPose.LocalRotationY,
		CurrentPivotRotation
	)
	local parentPivot = surfaceMountParent:GetPivot()
	local parentUp = parentPivot.UpVector
	if parentUp.Magnitude < 1e-3 then
		parentUp = Vector3.new(0, 1, 0)
	else
		parentUp = parentUp.Unit
	end
	updateHighlightForResult(surfaceMountPose.CanPlace)
	PlacementCostDisplay.UpdateSurfaceMounted(
		CurrentItemId or "",
		1,
		surfaceMountPose.CanPlace,
		surfaceMountPose.WorldPosition + parentUp * 2
	)
end

local function processCeilingPreview(model: Model, surface: BasePart, ceilingMountPose: CeilingMountPose)
	CurrentCeilingMountPose = ceilingMountPose
	local upVector = surface.CFrame.UpVector
	Renderer.PreviewCeilingMounted(
		model,
		ceilingMountPose.WorldPosition,
		ceilingMountPose.CeilingNormal,
		upVector,
		ceilingMountPose.RotationY,
		CurrentPivotRotation
	)
	updateHighlightForResult(ceilingMountPose.CanPlace)
	PlacementCostDisplay.UpdateCeiling(
		CurrentItemId or "",
		1,
		ceilingMountPose.CanPlace,
		ceilingMountPose.WorldPosition + upVector * 2
	)
end

local function processRoofDragPreview(
	model: Model,
	grid: any,
	surface: BasePart,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	placed,
	ignorePlacement: MoveOriginInfo?,
	activeLevel: number
): boolean
	local roofResult = RoofPreview.Update({
		model = model,
		grid = grid,
		surface = surface,
		chunkSize = chunkSize,
		cellX = cellX,
		cellZ = cellZ,
		itemId = CurrentItemId,
		spec = CurrentItemSpec,
		placed = placed,
		ignorePlacement = ignorePlacement,
		isChunkUnlocked = PlotStateStore.IsChunkUnlocked,
		level = activeLevel,
	}) :: RoofUpdateResult?
	if roofResult then
		PreviewHighlight.FillColor = roofResult.fillColor
		PreviewHighlight.OutlineColor = roofResult.outlineColor
		local summary = roofResult.summary
		if summary and typeof(CurrentItemId) == "string" then
			local gridWidth = summary.WidthCells or (summary.MaxCellX - summary.MinCellX + 1)
			local gridDepth = summary.DepthCells or (summary.MaxCellZ - summary.MinCellZ + 1)
			local summaryLevel = (summary :: any).Level
			local summaryLevelHeight = PlotStateStore.GetLevelHeight(summaryLevel)
			local centerCFrame =
				grid:FootprintCenterCFrame(summary.MinCellX, summary.MinCellZ, gridWidth, gridDepth, "North")
			centerCFrame = centerCFrame * CFrame.new(0, summaryLevelHeight, 0)
			local upVector = surface.CFrame.UpVector
			local heightStuds = BuildConstants.RoofLiftStuds or 12
			if typeof(CurrentItemSpec) == "table" then
				local specHeight = (CurrentItemSpec :: any).HeightStuds
				if typeof(specHeight) == "number" then
					heightStuds = specHeight
				end
			end
			local maxDimension = math.max(gridWidth, gridDepth)
			local heightOffset = math.max(0, heightStuds) + 2.25 + math.max(0, maxDimension - 1) * 0.25
			local worldPosition = centerCFrame.Position + upVector * heightOffset
			PlacementCostDisplay.UpdateRoof(CurrentItemId, summary.CellCount, roofResult.canPlace, worldPosition)
		else
			PlacementCostDisplay.Hide()
		end
	else
		PlacementCostDisplay.Hide()
	end
	return roofResult ~= nil
end

local function renderDefaultPreview(args: DefaultPreviewArgs)
	local model = args.model
	local grid = args.grid
	local surface = args.surface
	local chunkSize = args.chunkSize
	local cellX = args.cellX
	local cellZ = args.cellZ
	local baseWidthCells = args.baseWidthCells
	local baseDepthCells = args.baseDepthCells
	local previewFacing = args.previewFacing
	local resolvedPreviewKind = args.resolvedPreviewKind
	local placed = args.placed
	local ignorePlacement = args.ignorePlacement
	local activeLevel = args.activeLevel
	local levelHeight = args.levelHeight
	local lift = args.lift

	withMarkerPool(function()
		local isUnlocked = PlacementUtils.IsFootprintUnlockedWithChecker(
			grid,
			chunkSize,
			cellX,
			cellZ,
			baseWidthCells,
			baseDepthCells,
			previewFacing,
			PlotStateStore.IsChunkUnlocked
		)
		local blocked = false
		local previewAllowsStacking = PlacementBehavior.allowsStacking(CurrentItemSpec)
		if resolvedPreviewKind == "CellObject" then
			blocked = PlacementUtils.IsCellOccupiedForPreview(
				grid,
				"CellObject",
				cellX,
				cellZ,
				baseWidthCells,
				baseDepthCells,
				previewFacing,
				placed,
				ignorePlacement,
				activeLevel,
				previewAllowsStacking
			)
		elseif resolvedPreviewKind == "Roof" then
			blocked = PlacementUtils.IsCellOccupiedForPreview(
				grid,
				"Roof",
				cellX,
				cellZ,
				baseWidthCells,
				baseDepthCells,
				previewFacing,
				placed,
				ignorePlacement,
				activeLevel,
				false
			)
		end
		local wallEdgeOccupant: string? = nil

		if resolvedPreviewKind == "Wall" or resolvedPreviewKind == "CellObject" then
			WallConstraints.Populate(grid, placed, ignorePlacement, activeLevel)
		end

		if resolvedPreviewKind == "Wall" and WallStripPreview.IsDragInProgress() then
			local stripResult = WallStripPreview.Update({
				grid = grid,
				chunkSize = chunkSize,
				placed = placed,
				itemId = CurrentItemId,
				spec = CurrentItemSpec,
				currentCellX = cellX,
				currentCellZ = cellZ,
				facing = previewFacing,
				isChunkUnlocked = PlotStateStore.IsChunkUnlocked,
				level = activeLevel,
			})
			if stripResult then
				updateHighlightForResult(stripResult.canPlace)
				local highlightCells = stripResult.highlightCells
				MarkerPool.RenderFootprintMarkers(
					grid,
					surface,
					highlightCells,
					stripResult.canPlace,
					"Wall",
					levelHeight
				)
				local summary = stripResult.summary
				if summary then
					local summaryLevelHeight = PlotStateStore.GetLevelHeight(summary.Level)
					if typeof(CurrentItemId) == "string" then
						local startCFrame = grid:CellToWorldEdgeCenterCFrame(
							summary.StartCellX,
							summary.StartCellZ,
							summary.Facing,
							summaryLevelHeight
						)
						local endCFrame = grid:CellToWorldEdgeCenterCFrame(
							summary.EndCellX,
							summary.EndCellZ,
							summary.Facing,
							summaryLevelHeight
						)
						local midpoint = (startCFrame.Position + endCFrame.Position) * 0.5
						local upVector = surface.CFrame.UpVector
						local heightOffset = 2.75 + math.max(0, summary.SegmentCount - 1) * 0.15
						local worldPosition = midpoint + upVector * heightOffset
						PlacementCostDisplay.UpdateWall(
							CurrentItemId,
							summary.SegmentCount,
							stripResult.canPlace,
							worldPosition
						)
					else
						PlacementCostDisplay.Hide()
					end
					previewWall(
						model,
						grid,
						summary.AnchorCellX,
						summary.AnchorCellZ,
						summary.Facing,
						summaryLevelHeight,
						lift,
						summary
					)
				else
					PlacementCostDisplay.Hide()
					previewWall(model, grid, cellX, cellZ, previewFacing, levelHeight, lift)
				end
				return
			end
			PlacementCostDisplay.Hide()
		end

		if resolvedPreviewKind == "Wall" then
			PlacementCostDisplay.Hide()
		end

		if resolvedPreviewKind == "Wall" then
			wallEdgeOccupant = WallConstraints.GetEdgeOccupant(cellX, cellZ, previewFacing)
			if wallEdgeOccupant == WallConstraints.EdgeKind.Interior then
				blocked = true
			end

			local spec = CurrentItemSpec
			if spec and spec.RequiresExistingWall then
				local placementKey =
					PlacementKey.ForPlacementType(cellX, cellZ, previewFacing :: any, "Wall", activeLevel)
				local occupant = placed and placed[placementKey]
				if not occupant then
					blocked = true
				else
					local occupantMatchesOrigin = false
					if ignorePlacement then
						local sameId = occupant.id == ignorePlacement.ItemId
						local sameCell = occupant.cellX == ignorePlacement.CellX
							and occupant.cellZ == ignorePlacement.CellZ
						local sameFacing = PlacementKey.NormalizeFacing(occupant.facing) == ignorePlacement.Facing
						local ignoreLevel = ignorePlacement.Level
						local occupantLevel = if typeof(occupant.Level) == "number" then occupant.Level else nil
						local sameLevel = if ignoreLevel ~= nil then occupantLevel == ignoreLevel else true
						occupantMatchesOrigin = sameId and sameCell and sameFacing and sameLevel
					end

					if not occupantMatchesOrigin then
						local occupantCheckId = occupant.id
						local occupantSpec = occupantCheckId and ItemFinder.FindItemById(occupantCheckId) or nil
						if occupantSpec and occupantSpec.RequiresExistingWall == true then
							local previousId = occupant.Metadata and occupant.Metadata.PreviousId
							if typeof(previousId) == "string" and previousId ~= "" then
								occupantCheckId = previousId
								occupantSpec = ItemFinder.FindItemById(previousId)
							end
						end

						local canReplace = occupantSpec ~= nil and occupantSpec.PlacementType == "Wall"
						if canReplace and spec.ReplaceableWallTag then
							canReplace = ItemFinder.HasTag(occupantCheckId, spec.ReplaceableWallTag)
						end
						if not canReplace then
							blocked = true
						end
					end
				end
			elseif wallEdgeOccupant == WallConstraints.EdgeKind.Wall then
				blocked = true
			end
		end

		if resolvedPreviewKind == "CellObject" then
			local minCellX, minCellZ, maxCellX, maxCellZ =
				grid:FootprintBounds(cellX, cellZ, baseWidthCells, baseDepthCells, CurrentFacing)
			if WallConstraints.HasInteriorEdgeBetweenCells(minCellX, minCellZ, maxCellX, maxCellZ) then
				blocked = true
			end
		end

		local missingFloorSupport = false
		if resolvedPreviewKind == "Roof" then
			local spec = CurrentItemSpec
			local requiresFloor = spec ~= nil and spec.Rules ~= nil and spec.Rules.RequiresFloorUnderAllCells == true
			if requiresFloor then
				PlacementUtils.PopulateCellMapForType(
					grid,
					placed,
					"Floor",
					FloorSupportMap,
					ignorePlacement,
					activeLevel
				)
				local cells = grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, CurrentFacing)
				for _, index in cells do
					if not FloorSupportMap[index] then
						missingFloorSupport = true
						break
					end
				end
			end
		end

		local canPlace = isUnlocked and not blocked and not missingFloorSupport

		if resolvedPreviewKind == "Wall" then
			previewWall(model, grid, cellX, cellZ, previewFacing, levelHeight, lift)
		elseif resolvedPreviewKind == "Roof" then
			previewRoof(
				model,
				grid,
				surface,
				cellX,
				cellZ,
				previewFacing,
				baseWidthCells,
				baseDepthCells,
				levelHeight,
				CurrentItemSpec
			)
		else
			previewCellObject(
				model,
				grid,
				surface,
				cellX,
				cellZ,
				previewFacing,
				baseWidthCells,
				baseDepthCells,
				levelHeight,
				lift
			)
		end

		updateHighlightForResult(canPlace)

		local cells = grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, previewFacing)
		local markerKind: "CellObject" | "Floor" | "Roof" | "Wall" = if resolvedPreviewKind == "WallMounted"
			then "CellObject"
			else resolvedPreviewKind :: "CellObject" | "Floor" | "Roof" | "Wall"
		MarkerPool.RenderFootprintMarkers(grid, surface, cells, canPlace, markerKind, levelHeight)
	end)
end

findWallModel = function(hit: Instance?): Model?
	if not hit then
		return nil
	end

	local ancestor = hit:FindFirstAncestorWhichIsA("Model")
	while ancestor do
		local itemIdAttr = ancestor:GetAttribute("ItemId")
		if typeof(itemIdAttr) == "string" and itemIdAttr ~= "" then
			local spec = ItemFinder.FindItemById(itemIdAttr)
			if spec and (spec.PlacementType or spec.Type or "CellObject") == "Wall" then
				return ancestor
			end
		end

		local parent = ancestor.Parent
		if not parent then
			break
		end
		ancestor = parent:FindFirstAncestorWhichIsA("Model")
	end

	return nil
end

extractWallPose = function(model: Model?): (number?, number?, PreviewFacing?)
	if not model then
		return nil, nil, nil
	end

	local cellXAttr = model:GetAttribute("CellX")
	local cellZAttr = model:GetAttribute("CellZ")
	local facingAttr = model:GetAttribute("Facing")

	local cellX = if typeof(cellXAttr) == "number" then cellXAttr else nil
	local cellZ = if typeof(cellZAttr) == "number" then cellZAttr else nil
	local facing = nil
	if typeof(facingAttr) == "string" and facingAttr ~= "" then
		local normalized = PlacementKey.NormalizeFacing(facingAttr :: any)
		facing = normalized :: any
	end

	return cellX, cellZ, facing
end

local function findSurfaceMountParent(hit: Instance?, container: Instance?): Model?
	if not hit or not container then
		return nil
	end

	local current: Instance? = hit
	while current and current ~= container do
		if current:IsA("Model") then
			local placementTypeAttr = current:GetAttribute("PlacementType")
			if typeof(placementTypeAttr) == "string" and placementTypeAttr ~= "" then
				if placementTypeAttr == "SurfaceMounted" then
					local parentKeyAttr = current:GetAttribute("ParentPlacementKey")
					if typeof(parentKeyAttr) == "string" and parentKeyAttr ~= "" then
						local parentModel = container:FindFirstChild(parentKeyAttr)
						if parentModel and parentModel:IsA("Model") then
							return parentModel
						end
					end
				else
					return current
				end
			end
		end
		current = current.Parent
	end

	return nil
end

local function computeSurfaceMountPreview(
	result: RaycastResult,
	parentModel: Model,
	snapshot: any,
	pivotRotation: CFrame,
	facing: PreviewFacing
): SurfaceMountPose?
	local placementKeyAttr = parentModel:GetAttribute("PlacementKey")
	local parentKey = if typeof(placementKeyAttr) == "string" and placementKeyAttr ~= ""
		then placementKeyAttr
		else parentModel.Name
	if typeof(parentKey) ~= "string" or parentKey == "" then
		return nil
	end

	local placedItems = snapshot and snapshot.PlacedItems or nil
	local parentEntry = placedItems and placedItems[parentKey] or nil
	local parentCellXValue = parentEntry and parentEntry.cellX or parentModel:GetAttribute("CellX")
	local parentCellZValue = parentEntry and parentEntry.cellZ or parentModel:GetAttribute("CellZ")
	local parentFacingValue = parentEntry and parentEntry.facing or parentModel:GetAttribute("Facing")

	local parentPivot = parentModel:GetPivot()
	local localPosition = parentPivot:PointToObjectSpace(result.Position)
	if math.abs(localPosition.X) > 512 or math.abs(localPosition.Y) > 512 or math.abs(localPosition.Z) > 512 then
		return nil
	end

	local rotationY = GetYawFromFacing(facing :: any)
	local offset = CFrame.new(localPosition) * CFrame.Angles(0, rotationY, 0)
	local finalCFrame = parentPivot * offset * pivotRotation

	local normalizedParentFacing: PreviewFacing? = nil
	if typeof(parentFacingValue) == "string" and parentFacingValue ~= "" then
		normalizedParentFacing = PlacementKey.NormalizeFacing(parentFacingValue :: any) :: PreviewFacing
	end

	local pose: SurfaceMountPose = {
		ParentKey = parentKey,
		LocalPosition = localPosition,
		LocalRotationY = rotationY,
		WorldPosition = finalCFrame.Position,
		ParentCellX = if typeof(parentCellXValue) == "number" then parentCellXValue else nil,
		ParentCellZ = if typeof(parentCellZValue) == "number" then parentCellZValue else nil,
		ParentFacing = normalizedParentFacing,
		CanPlace = parentEntry ~= nil,
	}

	return pose
end

function ObjectPreview.RenderPreview(itemId: string, initialFacing: PreviewFacing?)
	ObjectPreview.ClearPreview()

	local sourceModel = ItemFinder.ResolveItemModel(itemId)
	if not sourceModel then
		warn("Item model not found for ID: " .. itemId)
		return
	end

	CurrentItemSpec = ItemFinder.FindItemById(itemId)
	local isWindowItem = isWindowVariant(CurrentItemSpec)

	if not PlotStateStore.IsReady() then
		warn("PlotStateStore is not ready.")
		return
	end

	local grid = PlotStateStore.GetGrid()
	local surface = PlotStateStore.GetSurface()

	if not grid or not surface then
		warn("Plot grid or surface not available.")
		return
	end

	local plotParent = surface.Parent
	if not plotParent or not plotParent:IsA("Model") then
		warn("Plot surface parent is missing or not a Model.")
		return
	end

	local plotModel = plotParent :: Model
	local containerFolder = plotModel:FindFirstChild("Container") :: Folder?
	if not containerFolder then
		warn("Plot container not found for preview.")
		return
	end

	local derivedPreviewKind = PlacementUtils.PreviewKindFromItem(itemId)

	local itemModel: Model = sourceModel:Clone()
	if derivedPreviewKind == "Wall" then
		if itemModel:GetAttribute("PreviewApplyWallScaling") == nil then
			itemModel:SetAttribute("PreviewApplyWallScaling", true)
		end
	end

	CurrentPivotRotation = Renderer.GetPivotRotation(itemModel)
	local lift = computeLift(CurrentItemSpec, itemModel, surface)
	local chunkSize = PlotStateStore.GetStateSnapshot().ChunkInfo.ChunkSizeInCells

	PreviewHighlight.Adornee = itemModel
	itemModel.Parent = containerFolder
	SelectedItem = itemModel
	if isWindowItem then
		hideWindowPreviewModel()
	end
	objectPreviewEnabled.Value = true
	suppressProximityPrompts()
	PreviewContext.CancelPreview.Enabled = true

	applyModelPhysicsOverrides(itemModel)

	local raycastParams = buildRaycastParams(surface, containerFolder)
	local wallRaycastParams = buildWallRaycastParams(containerFolder)

	CurrentFacing = initialFacing or "North"

	local resolvedPreviewKind: PreviewKind
	if
		derivedPreviewKind == "CellObject"
		or derivedPreviewKind == "Floor"
		or derivedPreviewKind == "Wall"
		or derivedPreviewKind == "Roof"
		or derivedPreviewKind == "WallMounted"
		or derivedPreviewKind == "SurfaceMounted"
		or derivedPreviewKind == "Ceiling"
	then
		resolvedPreviewKind = derivedPreviewKind
	else
		resolvedPreviewKind = "CellObject"
	end
	local baseWidthCells, baseDepthCells = PlacementUtils.GetItemFootprintCells(itemId)

	CurrentItemId = itemId
	CurrentKind = resolvedPreviewKind
	if resolvedPreviewKind == "Ceiling" then
		disableCutawayForCeiling()
		CeilingPreviewState.Initialize(CurrentItemSpec)
	else
		restoreCutawayAfterCeiling()
		CeilingPreviewState.Reset()
	end
	local sequenceForCurrent, indexForCurrent = rotationSequenceForCurrent()
	if sequenceForCurrent[1] and not indexForCurrent[CurrentFacing] then
		updateFacing(sequenceForCurrent[1])
	end

	ensureFloorPreviewPrepared(resolvedPreviewKind, itemModel, baseWidthCells, baseDepthCells)

	PreviewContext.RotateLeft.Enabled = (resolvedPreviewKind ~= "Floor")
	PreviewContext.RotateRight.Enabled = (resolvedPreviewKind ~= "Floor")

	Connection = RunService.PreRender:Connect(function(deltaTime)
		Renderer.SetFrameDelta(deltaTime)
		local model = SelectedItem
		if not model then
			return
		end

		local mouse = UserInputService:GetMouseLocation()
		if MoveHoldActive then
			if isMouseHoldBroken(mouse) then
				MoveHoldActive = false
				MoveHoldMousePosition = nil
			end
		else
			MoveHoldMousePosition = nil
		end

		local ray = Camera:ViewportPointToRay(mouse.X, mouse.Y)
		local activeParams = if resolvedPreviewKind == "WallMounted" then wallRaycastParams else raycastParams
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 2048, activeParams)
		local rejectedCeilingHit = false
		if result and resolvedPreviewKind == "Ceiling" then
			local plotUp = surface.CFrame.UpVector
			local downwardAlignment = result.Normal:Dot(-plotUp.Unit)
			if downwardAlignment < 0.5 then
				rejectedCeilingHit = true
			end
		end
		if not result or rejectedCeilingHit then
			handleRaycastMiss(resolvedPreviewKind, isWindowItem)
			return
		end

		local isInside, computedCellX, computedCellZ = grid:WorldPointToCell(result.Position)
		local cellX: number
		local cellZ: number
		local wallMountPosition: Vector3? = nil
		local hitWallModel: Model? = nil
		if isInside then
			cellX = computedCellX
			cellZ = computedCellZ
		else
			cellX, cellZ = grid:WorldPointToClampedCell(result.Position)
		end

		local resolvedFacing: PreviewFacing = CurrentFacing
		local itemSpec = CurrentItemSpec
		local requiresExistingWall = itemSpec
			and (itemSpec.PlacementType or itemSpec.Type) == "Wall"
			and itemSpec.RequiresExistingWall == true

		if requiresExistingWall then
			local wallModel = findWallModel(result.Instance)
			if wallModel then
				hitWallModel = wallModel
				local wallCellX, wallCellZ, wallFacing = extractWallPose(wallModel)
				if wallCellX and wallCellZ and wallFacing then
					cellX = wallCellX
					cellZ = wallCellZ
					resolvedFacing = wallFacing
				end
			end
		end

		if MoveHoldActive and MoveOriginSignature then
			cellX = MoveOriginSignature.CellX
			cellZ = MoveOriginSignature.CellZ
			if typeof(MoveOriginSignature.Facing) == "string" and MoveOriginSignature.Facing ~= "" then
				resolvedFacing = MoveOriginSignature.Facing
			end
		end

		local snapshot = PlotStateStore.GetStateSnapshot()
		local placed = snapshot.PlacedItems
		local ignorePlacement = computeIgnorePlacement()
		local activeLevel = PlotStateStore.GetActiveLevel()
		local levelHeight = PlotStateStore.GetLevelHeight(activeLevel)
		LastLevel = activeLevel
		LastLevelHeight = levelHeight

		resolvedFacing = PlacementKey.NormalizeFacing(resolvedFacing :: any)
		local isMouseDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		tryBeginCurrentDrag(CurrentKind, cellX, cellZ, isMouseDown)
		LastPrimaryMouseDown = isMouseDown

		local wallPreview: WallMountedPreviewResult? = nil
		if resolvedPreviewKind == "WallMounted" then
			wallPreview = computeWallMountedPreview(result, grid, surface, chunkSize, placed, ignorePlacement)
			if not wallPreview then
				handleRaycastMiss(resolvedPreviewKind, isWindowItem)
				return
			end
			cellX = wallPreview.ReferenceCellX
			cellZ = wallPreview.ReferenceCellZ
			resolvedFacing = wallPreview.AttachedFacing
			wallMountPosition = wallPreview.WorldPosition
		end

		local surfaceMountPose: SurfaceMountPose? = nil
		local surfaceMountParent: Model? = nil
		if resolvedPreviewKind == "SurfaceMounted" then
			local parentModel = findSurfaceMountParent(result.Instance, containerFolder)
			if not parentModel then
				handleRaycastMiss(resolvedPreviewKind, isWindowItem)
				return
			end

			surfaceMountParent = parentModel
			surfaceMountPose =
				computeSurfaceMountPreview(result, parentModel, snapshot, CurrentPivotRotation, CurrentFacing)
			if not surfaceMountPose then
				handleRaycastMiss(resolvedPreviewKind, isWindowItem)
				return
			end

			if surfaceMountPose.ParentCellX and surfaceMountPose.ParentCellZ then
				cellX = surfaceMountPose.ParentCellX
				cellZ = surfaceMountPose.ParentCellZ
			end
		end

		local ceilingMountPose: CeilingMountPose? = nil
		if resolvedPreviewKind == "Ceiling" then
			ceilingMountPose = CeilingPreviewState.ComputePose(
				grid,
				surface,
				result,
				cellX,
				cellZ,
				resolvedFacing,
				activeLevel,
				snapshot
			)
			if not ceilingMountPose then
				CurrentCeilingMountPose = nil
				updateHighlightForResult(false)
				PlacementCostDisplay.Hide()
				return
			end
		end

		local windowVariantActive = isWindowItem and resolvedPreviewKind == "Wall"

		if not windowVariantActive and WindowPreviewController.GetPose() then
			clearWindowPreview()
		end

		local windowPose: WindowCutoutPose? = nil
		if windowVariantActive then
			local wallModelForWindow = hitWallModel or findWallModel(result.Instance)
			if not wallModelForWindow then
				clearWindowPreview()
				updateHighlightForResult(false)
				PlacementCostDisplay.Hide()
				return
			end
			hitWallModel = wallModelForWindow

			local canReplace, _, occupantEntry, occupantSpec, occupantMatchesOrigin = validateExistingWallReplacement(
				cellX,
				cellZ,
				resolvedFacing,
				itemSpec,
				placed,
				ignorePlacement,
				activeLevel
			)
			if not canReplace then
				clearWindowPreview()
				updateHighlightForResult(false)
				PlacementCostDisplay.Hide()
				return
			end

			local computedPose = computeWindowCutoutPose(
				wallModelForWindow,
				cellX,
				cellZ,
				resolvedFacing,
				result.Position,
				itemSpec,
				occupantEntry,
				occupantSpec,
				occupantMatchesOrigin
			)
			if not computedPose then
				clearWindowPreview()
				updateHighlightForResult(false)
				PlacementCostDisplay.Hide()
				return
			end

			local resolvedPose = computedPose :: WindowCutoutPose
			windowPose = resolvedPose
			if occupantEntry and occupantSpec and occupantSpec.RequiresExistingWall == true then
				resolvedPose.HeightOffset = math.clamp(
					resolvedPose.HeightOffset,
					resolvedPose.CutoutHeight * 0.5,
					resolvedPose.WallHeight - resolvedPose.CutoutHeight * 0.5
				)
			end
		end

		local windowHeightOffset = windowPose and windowPose.HeightOffset or nil

		local surfaceParentKeyForCache = surfaceMountPose and surfaceMountPose.ParentKey or nil
		local surfaceLocalPositionForCache = surfaceMountPose and surfaceMountPose.LocalPosition or nil
		local ceilingDropForCache = ceilingMountPose and ceilingMountPose.DropStuds or nil
		local ceilingRotationForCache = ceilingMountPose and ceilingMountPose.RotationY or nil

		local poseInfo: PoseCacheComparable = {
			cellX = cellX,
			cellZ = cellZ,
			facing = resolvedFacing,
			wallPosition = wallMountPosition,
			windowHeightOffset = windowHeightOffset,
			surfaceParentKey = surfaceParentKeyForCache,
			surfaceLocalPosition = surfaceLocalPositionForCache,
			ceilingDrop = ceilingDropForCache,
			ceilingRotation = ceilingRotationForCache,
		}

		if shouldSkipPose(poseInfo) then
			Renderer.StepModel(model)
			return
		end

		updatePoseCache(poseInfo)
		CurrentFacing = resolvedFacing

		if windowVariantActive and windowPose then
			local success = processWindowVariant(
				model,
				surface,
				hitWallModel or findWallModel(result.Instance),
				windowPose :: WindowCutoutPose,
				itemSpec
			)
			if not success then
				return
			end
			return
		end

		if resolvedPreviewKind == "WallMounted" and wallPreview then
			processWallMountedPreview(model, surface, wallPreview)
			return
		end

		if resolvedPreviewKind == "SurfaceMounted" and surfaceMountPose and surfaceMountParent then
			processSurfaceMountedPreview(model, surfaceMountPose, surfaceMountParent)
			return
		end

		if resolvedPreviewKind == "Ceiling" then
			if ceilingMountPose then
				processCeilingPreview(model, surface, ceilingMountPose)
			else
				CurrentCeilingMountPose = nil
				PlacementCostDisplay.Hide()
				updateHighlightForResult(false)
			end
			return
		end

		if resolvedPreviewKind == "Floor" then
			renderFloorPreview(
				model,
				grid,
				surface,
				chunkSize,
				cellX,
				cellZ,
				placed,
				ignorePlacement,
				CurrentItemId,
				activeLevel,
				levelHeight
			)
			return
		end

		if resolvedPreviewKind == "Roof" and RoofPreview.IsDragInProgress() then
			local handled = processRoofDragPreview(
				model,
				grid,
				surface,
				chunkSize,
				cellX,
				cellZ,
				placed,
				ignorePlacement,
				activeLevel
			)
			if handled then
				return
			end
		end

		if resolvedPreviewKind == "Roof" then
			PlacementCostDisplay.Hide()
		end

		renderDefaultPreview({
			model = model,
			grid = grid,
			surface = surface,
			chunkSize = chunkSize,
			cellX = cellX,
			cellZ = cellZ,
			baseWidthCells = baseWidthCells,
			baseDepthCells = baseDepthCells,
			previewFacing = CurrentFacing,
			resolvedPreviewKind = resolvedPreviewKind,
			placed = placed,
			ignorePlacement = ignorePlacement,
			activeLevel = activeLevel,
			levelHeight = levelHeight,
			lift = lift,
		})
	end)
end

function ObjectPreview.ClearPreview()
	PreviewContext.RotateLeft.Enabled = false
	PreviewContext.RotateRight.Enabled = false
	PreviewContext.CancelPreview.Enabled = false
	objectPreviewEnabled.Value = false
	restoreProximityPrompts()
	MarkerPool.Clear()
	resetFloorState(true)
	resetRoofState(true)
	WallStripPreview.Clear()
	clearWindowPreview()

	if SelectedItem then
		PreviewHighlight.Adornee = nil
		Renderer.ClearModel(SelectedItem)
		SelectedItem:Destroy()
		SelectedItem = nil
	end

	PlacementCostDisplay.Hide()

	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	PoseCache.Reset()
	CurrentItemId = nil
	CurrentItemSpec = nil
	CurrentPivotRotation = CFrame.identity
	MoveOriginSignature = nil
	MoveHoldActive = false
	MoveHoldMousePosition = nil
	LastPrimaryMouseDown = false
	CurrentWallMountPose = nil
	CurrentSurfaceMountPose = nil
	CurrentCeilingMountPose = nil
	CeilingPreviewState.Reset()
	restoreCutawayAfterCeiling()
end

function ObjectPreview.GetCurrentPose(): PreviewPose?
	if not CurrentItemId then
		return nil
	end

	local poseLevel = LastLevel or PlotStateStore.GetActiveLevel()
	local poseLevelHeight = LastLevelHeight or PlotStateStore.GetLevelHeight(poseLevel)
	local originSignature = MoveOriginSignature
	local poseSnapshot = getPoseSnapshot()
	local cachedCellX = poseSnapshot.cellX
	local cachedCellZ = poseSnapshot.cellZ
	local windowPose = WindowPreviewController.GetPose()

	if CurrentKind == "SurfaceMounted" then
		if not CurrentSurfaceMountPose then
			return nil
		end

		local targetCellX = CurrentSurfaceMountPose.ParentCellX or cachedCellX
		local targetCellZ = CurrentSurfaceMountPose.ParentCellZ or cachedCellZ
		if not targetCellX or not targetCellZ then
			return nil
		end

		return {
			ItemId = CurrentItemId,
			CellX = targetCellX,
			CellZ = targetCellZ,
			Facing = CurrentFacing,
			Kind = CurrentKind,
			WallMount = nil,
			WindowCutout = windowPose,
			SurfaceMount = CurrentSurfaceMountPose,
			CeilingMount = CurrentCeilingMountPose,
			Level = poseLevel,
			LevelHeight = poseLevelHeight,
		}
	end

	if (not cachedCellX or not cachedCellZ) and originSignature then
		local originCellX = originSignature.CellX
		local originCellZ = originSignature.CellZ
		if typeof(originCellX) == "number" and typeof(originCellZ) == "number" then
			local originFacing = originSignature.Facing
			local resolvedFacing = if typeof(originFacing) == "string" and originFacing ~= ""
				then originFacing
				else CurrentFacing
			local originLevel = originSignature.Level
			local fallbackLevel = if typeof(originLevel) == "number" then originLevel else poseLevel
			local fallbackLevelHeight = PlotStateStore.GetLevelHeight(fallbackLevel)
			return {
				ItemId = CurrentItemId,
				CellX = originCellX,
				CellZ = originCellZ,
				Facing = resolvedFacing,
				Kind = CurrentKind,
				WallMount = CurrentWallMountPose,
				WindowCutout = windowPose,
				SurfaceMount = CurrentSurfaceMountPose,
				CeilingMount = CurrentCeilingMountPose,
				Level = fallbackLevel,
				LevelHeight = fallbackLevelHeight,
			}
		end
	end

	if not cachedCellX or not cachedCellZ then
		return nil
	end

	return {
		ItemId = CurrentItemId,
		CellX = cachedCellX,
		CellZ = cachedCellZ,
		Facing = CurrentFacing,
		Kind = CurrentKind,
		WallMount = CurrentWallMountPose,
		WindowCutout = windowPose,
		SurfaceMount = CurrentSurfaceMountPose,
		CeilingMount = CurrentCeilingMountPose,
		Level = poseLevel,
		LevelHeight = poseLevelHeight,
	}
end

function ObjectPreview.SetFloorPlacementHandler(handler: ((FloorSelectionInfo) -> ())?)
	FloorPreview.SetPlacementHandler(handler)
end

function ObjectPreview.SetWallStripPlacementHandler(handler: ((WallStripSelectionInfo) -> ())?)
	WallStripPlacementHandler = handler
end

function ObjectPreview.SetRoofPlacementHandler(handler: ((RoofSelectionInfo) -> ())?)
	RoofPlacementHandler = handler
end

function ObjectPreview.TryBeginFloorDrag(): boolean
	if CurrentKind ~= "Floor" then
		return false
	end
	if FloorPreview.IsDragInProgress() then
		return true
	end
	local poseSnapshot = getPoseSnapshot()
	local cachedCellX = poseSnapshot.cellX
	local cachedCellZ = poseSnapshot.cellZ
	if not CurrentItemId or not cachedCellX or not cachedCellZ then
		return false
	end
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		return false
	end
	return FloorPreview.TryBeginDrag(CurrentKind, CurrentItemId, cachedCellX, cachedCellZ, true)
end

function ObjectPreview.IsFloorDragInProgress(): boolean
	return FloorPreview.IsDragInProgress()
end

function ObjectPreview.GetFloorSelectionSummary(): FloorSelectionInfo?
	return FloorPreview.GetSelectionSummary()
end

function ObjectPreview.TryBeginWallStripDrag(): boolean
	if CurrentKind ~= "Wall" then
		return false
	end
	if WallStripPreview.IsDragInProgress() then
		return true
	end
	if not CurrentItemId or not CurrentItemSpec then
		return false
	end
	if CurrentItemSpec.RequiresExistingWall == true then
		return false
	end
	local poseSnapshot = getPoseSnapshot()
	local cachedCellX = poseSnapshot.cellX
	local cachedCellZ = poseSnapshot.cellZ
	if not cachedCellX or not cachedCellZ then
		return false
	end
	local isPressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	if not isPressed then
		return false
	end

	return WallStripPreview.TryBeginDrag({
		itemId = CurrentItemId,
		anchorCellX = cachedCellX,
		anchorCellZ = cachedCellZ,
		facing = CurrentFacing,
		spec = CurrentItemSpec,
		isMousePressed = isPressed,
	})
end

function ObjectPreview.IsWallStripDragInProgress(): boolean
	return WallStripPreview.IsDragInProgress()
end

function ObjectPreview.GetWallStripSelectionSummary(): WallStripSelectionInfo?
	return WallStripPreview.GetSelectionSummary()
end

function ObjectPreview.TryBeginRoofDrag(): boolean
	if CurrentKind ~= "Roof" then
		return false
	end
	if RoofPreview.IsDragInProgress() then
		return true
	end
	local poseSnapshot = getPoseSnapshot()
	local cachedCellX = poseSnapshot.cellX
	local cachedCellZ = poseSnapshot.cellZ
	if not CurrentItemId or not cachedCellX or not cachedCellZ then
		return false
	end
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		return false
	end
	return RoofPreview.TryBeginDrag(CurrentKind, CurrentItemId, cachedCellX, cachedCellZ, true)
end

function ObjectPreview.IsRoofDragInProgress(): boolean
	return RoofPreview.IsDragInProgress()
end

function ObjectPreview.GetRoofSelectionSummary(): RoofSelectionInfo?
	return RoofPreview.GetSelectionSummary()
end

function ObjectPreview.SetMoveOrigin(originInfo: {
	ItemId: string?,
	CellX: number?,
	CellZ: number?,
	Facing: PreviewFacing?,
	WidthCells: number?,
	DepthCells: number?,
	Level: number?,
}?)
	if not originInfo then
		MoveOriginSignature = nil
		MoveHoldActive = false
		MoveHoldMousePosition = nil
		return
	end

	local itemId = originInfo.ItemId
	local cellX = originInfo.CellX
	local cellZ = originInfo.CellZ
	if not itemId or cellX == nil or cellZ == nil then
		MoveOriginSignature = nil
		return
	end

	local widthCells = originInfo.WidthCells
	local depthCells = originInfo.DepthCells
	if typeof(widthCells) ~= "number" then
		widthCells = tonumber(widthCells)
	end
	if typeof(depthCells) ~= "number" then
		depthCells = tonumber(depthCells)
	end

	local entry = {
		id = itemId,
		cellX = cellX,
		cellZ = cellZ,
		facing = originInfo.Facing,
	}
	if typeof(widthCells) == "number" and widthCells > 0 then
		entry.widthCells = widthCells
		entry.WidthCells = widthCells
	end
	if typeof(depthCells) == "number" and depthCells > 0 then
		entry.depthCells = depthCells
		entry.DepthCells = depthCells
	end
	if typeof(originInfo.Level) == "number" then
		entry.Level = originInfo.Level
		entry.level = originInfo.Level
	end

	local itemSpec, placementType, resolvedWidth, resolvedDepth, resolvedFacing =
		PlacementUtils.ResolvePlacementEntry(entry)
	local placementKeyType = PlacementBehavior.getPlacementKeyLabel(itemSpec)

	local resolvedLevel = nil
	if typeof(originInfo.Level) == "number" then
		resolvedLevel = math.floor(originInfo.Level + 0.5)
	end

	MoveOriginSignature = {
		ItemId = itemId,
		CellX = cellX,
		CellZ = cellZ,
		Facing = tostring(PlacementKey.NormalizeFacing(resolvedFacing :: any)),
		PlacementType = placementType,
		PlacementKeyType = placementKeyType,
		WidthCells = if typeof(widthCells) == "number" and widthCells > 0 then widthCells else resolvedWidth,
		DepthCells = if typeof(depthCells) == "number" and depthCells > 0 then depthCells else resolvedDepth,
		Level = resolvedLevel,
	}

	MoveHoldActive = true
	MoveHoldMousePosition = UserInputService:GetMouseLocation()
end

return ObjectPreview
