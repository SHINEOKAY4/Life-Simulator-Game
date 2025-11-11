--!strict

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlotStateStore = require(script.Parent.Parent:WaitForChild("ClientStores"):WaitForChild("PlotStateStore"))

local MarkerPool = require(script:WaitForChild("MarkerPool"))
local PlacementUtils = require(script:WaitForChild("PlacementUtils"))
local FloorPreview = require(script:WaitForChild("FloorPreview"))
local RoofPreview = require(script:WaitForChild("RoofPreview"))
local WallStripPreview = require(script:WaitForChild("WallStripPreview"))
local WallConstraints = require(script:WaitForChild("WallConstraints"))
local Renderer = require(script:WaitForChild("Renderer"))
local PlacementCostDisplay = require(script.Parent:WaitForChild("PlacementCostDisplay"))

type PreviewFacing = string
type PreviewKind = "CellObject" | "Floor" | "Wall" | "Roof" | "WallMounted"
type MoveOriginInfo = PlacementUtils.MoveOriginInfo
export type Facing = PreviewFacing
export type PreviewPose = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: PreviewFacing,
	Kind: PreviewKind,
	WallMount: WallMountPose?,
}
export type FloorSelectionInfo = FloorPreview.FloorSelectionInfo
type FloorUpdateResult = FloorPreview.FloorUpdateResult
export type RoofSelectionInfo = RoofPreview.RoofSelectionInfo
type RoofUpdateResult = RoofPreview.RoofUpdateResult
export type WallStripSelectionInfo = WallStripPreview.WallStripSelectionInfo

export type WallMountPose = {
	WorldPosition: Vector3,
	WallNormal: Vector3,
	WallCellX: number,
	WallCellZ: number,
	AttachedFacing: PreviewFacing,
	HeightOffset: number,
	ReferenceCellX: number,
	ReferenceCellZ: number,
}

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

-- Temporarily disable proximity prompts so preview input keys do not trigger world interactions.

local function suppressProximityPrompts()
	if proximityPromptsSuppressed then
		return
	end
	proximityPromptsSuppressed = true
	storedPromptServiceEnabled = ProximityPromptService.Enabled
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

local Camera = workspace.CurrentCamera

local ObjectPreview = {}

local Connection: RBXScriptConnection? = nil
local SelectedItem: Model? = nil
local CurrentItemId: string? = nil
local CurrentItemSpec: any? = nil
local CurrentKind: PreviewKind = "CellObject"
local CurrentFacing: PreviewFacing = "North"
local LastCellX: number? = nil
local LastCellZ: number? = nil
local LastFacing: PreviewFacing? = nil
local LastWallPosition: Vector3? = nil
local CurrentPivotRotation: CFrame = CFrame.identity

local MoveOriginSignature: MoveOriginInfo? = nil
local MoveHoldActive = false
local MoveHoldMousePosition: Vector2? = nil
local MOUSE_MOVE_RELEASE_THRESHOLD = 2

local FloorSupportMap: { [number]: boolean } = {}
local WallStripPlacementHandler: ((WallStripSelectionInfo) -> ())? = nil
local RoofPlacementHandler: ((RoofSelectionInfo) -> ())? = nil
local LastPrimaryMouseDown = false
local CurrentWallMountPose: WallMountPose? = nil

local PLACEABLE_FILL = Color3.fromRGB(159, 234, 159)
local PLACEABLE_OUTLINE = Color3.fromRGB(137, 255, 119)
local BLOCKED_FILL = Color3.fromRGB(219, 136, 136)
local BLOCKED_OUTLINE = Color3.fromRGB(255, 85, 85)

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
	CurrentFacing = newFacing
	LastFacing = nil
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

local function isSamePlacementPose(cellX: number, cellZ: number, facing: PreviewFacing, wallPosition: Vector3?): boolean
	if CurrentKind == "WallMounted" then
		if not wallPosition or not LastWallPosition then
			return false
		end
		if LastCellX ~= cellX or LastCellZ ~= cellZ or LastFacing ~= facing then
			return false
		end
		return (LastWallPosition - wallPosition).Magnitude < 0.05
	end

	return LastCellX == cellX and LastCellZ == cellZ and LastFacing == facing
end

local function updateLastPose(cellX: number, cellZ: number, facing: PreviewFacing, wallPosition: Vector3?)
	LastCellX = cellX
	LastCellZ = cellZ
	LastFacing = facing
	if CurrentKind == "WallMounted" then
		LastWallPosition = wallPosition
	else
		LastWallPosition = nil
	end
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
	itemId: string?
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
	}) :: FloorUpdateResult?
	if result then
		PreviewHighlight.FillColor = result.fillColor
		PreviewHighlight.OutlineColor = result.outlineColor
		local summary = result.summary
		if summary and typeof(itemId) == "string" then
			local widthCells = summary.WidthCells or (summary.MaxCellX - summary.MinCellX + 1)
			local depthCells = summary.DepthCells or (summary.MaxCellZ - summary.MinCellZ + 1)
			local centerCFrame =
				grid:FootprintCenterCFrame(summary.MinCellX, summary.MinCellZ, widthCells, depthCells, "North")
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
	lift: number,
	span: WallStripSelectionInfo?
)
	Renderer.PreviewWall(model, grid, cellX, cellZ, facing, lift, span)
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
	spec: any?
)
	Renderer.PreviewRoof(model, grid, surface, cellX, cellZ, widthCells, depthCells, facing, spec)
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
		ignoreKey = PlacementKey.ForPlacementType(
			ignorePlacement.CellX,
			ignorePlacement.CellZ,
			ignoreFacing :: any,
			ignorePlacement.PlacementType
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

local function updateHighlightForResult(canPlace: boolean)
	PreviewHighlight.FillColor = if canPlace then PLACEABLE_FILL else BLOCKED_FILL
	PreviewHighlight.OutlineColor = if canPlace then PLACEABLE_OUTLINE else BLOCKED_OUTLINE
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

function ObjectPreview.RenderPreview(itemId: string, initialFacing: PreviewFacing?)
	ObjectPreview.ClearPreview()

	local sourceModel = ItemFinder.ResolveItemModel(itemId)
	if not sourceModel then
		warn("Item model not found for ID: " .. itemId)
		return
	end

	CurrentItemSpec = ItemFinder.FindItemById(itemId)

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
	then
		resolvedPreviewKind = derivedPreviewKind
	else
		resolvedPreviewKind = "CellObject"
	end
	local baseWidthCells, baseDepthCells = PlacementUtils.GetItemFootprintCells(itemId)

	CurrentItemId = itemId
	CurrentKind = resolvedPreviewKind
	local sequenceForCurrent, indexForCurrent = rotationSequenceForCurrent()
	if sequenceForCurrent[1] and not indexForCurrent[CurrentFacing] then
		updateFacing(sequenceForCurrent[1])
	end

	ensureFloorPreviewPrepared(resolvedPreviewKind, itemModel, baseWidthCells, baseDepthCells)

	PreviewContext.RotateLeft.Enabled = (resolvedPreviewKind ~= "Floor")
	PreviewContext.RotateRight.Enabled = (resolvedPreviewKind ~= "Floor")

	Connection = RunService.PreRender:Connect(function()
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
		if not result then
			if resolvedPreviewKind == "WallMounted" then
				CurrentWallMountPose = nil
				updateHighlightForResult(false)
				PlacementCostDisplay.Hide()
			end
			return
		end

		local isInside, computedCellX, computedCellZ = grid:WorldPointToCell(result.Position)
		local cellX: number
		local cellZ: number
		local wallMountPosition: Vector3? = nil
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

		resolvedFacing = PlacementKey.NormalizeFacing(resolvedFacing :: any)
		local isMouseDown = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
		if CurrentKind == "Floor" and CurrentItemId then
			if isMouseDown and not LastPrimaryMouseDown then
				FloorPreview.TryBeginDrag(CurrentKind, CurrentItemId, cellX, cellZ, true)
			end
		elseif CurrentKind == "Roof" and CurrentItemId then
			if isMouseDown and not LastPrimaryMouseDown then
				RoofPreview.TryBeginDrag(CurrentKind, CurrentItemId, cellX, cellZ, true)
			end
		end
		LastPrimaryMouseDown = isMouseDown

		local wallPreview: WallMountedPreviewResult? = nil
		if resolvedPreviewKind == "WallMounted" then
			wallPreview = computeWallMountedPreview(result, grid, surface, chunkSize, placed, ignorePlacement)
			if not wallPreview then
				CurrentWallMountPose = nil
				updateHighlightForResult(false)
				PlacementCostDisplay.Hide()
				return
			end
			cellX = wallPreview.ReferenceCellX
			cellZ = wallPreview.ReferenceCellZ
			resolvedFacing = wallPreview.AttachedFacing
			wallMountPosition = wallPreview.WorldPosition
		end

		if isSamePlacementPose(cellX, cellZ, resolvedFacing, wallMountPosition) then
			return
		end

		updateLastPose(cellX, cellZ, resolvedFacing, wallMountPosition)
		CurrentFacing = resolvedFacing

		if resolvedPreviewKind == "WallMounted" and wallPreview then
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
			return
		end

		if resolvedPreviewKind == "Floor" then
			renderFloorPreview(model, grid, surface, chunkSize, cellX, cellZ, placed, ignorePlacement, CurrentItemId)
			return
		end

		if resolvedPreviewKind == "Roof" and RoofPreview.IsDragInProgress() then
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
			}) :: RoofUpdateResult?
			if roofResult then
				PreviewHighlight.FillColor = roofResult.fillColor
				PreviewHighlight.OutlineColor = roofResult.outlineColor
				local summary = roofResult.summary
				if summary and typeof(CurrentItemId) == "string" then
					local widthCells = summary.WidthCells or (summary.MaxCellX - summary.MinCellX + 1)
					local depthCells = summary.DepthCells or (summary.MaxCellZ - summary.MinCellZ + 1)
					local centerCFrame =
						grid:FootprintCenterCFrame(summary.MinCellX, summary.MinCellZ, widthCells, depthCells, "North")
					local upVector = surface.CFrame.UpVector
					local heightStuds = 0
					if typeof(CurrentItemSpec) == "table" then
						local specHeight = (CurrentItemSpec :: any).HeightStuds
						if typeof(specHeight) == "number" then
							heightStuds = specHeight
						end
					end
					local maxDimension = math.max(widthCells, depthCells)
					local heightOffset = math.max(0, heightStuds) + 2.25 + math.max(0, maxDimension - 1) * 0.25
					local worldPosition = centerCFrame.Position + upVector * heightOffset
					PlacementCostDisplay.UpdateRoof(
						CurrentItemId,
						summary.CellCount,
						roofResult.canPlace,
						worldPosition
					)
				else
					PlacementCostDisplay.Hide()
				end
			end
			return
		end

		if resolvedPreviewKind == "Roof" then
			PlacementCostDisplay.Hide()
		end

		withMarkerPool(function()
			local previewFacing = CurrentFacing
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
					ignorePlacement
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
					ignorePlacement
				)
			end
			local wallEdgeOccupant: string? = nil

			if resolvedPreviewKind == "Wall" or resolvedPreviewKind == "CellObject" then
				WallConstraints.Populate(grid, placed, ignorePlacement)
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
				})
				if stripResult then
					updateHighlightForResult(stripResult.canPlace)
					local highlightCells = stripResult.highlightCells
					MarkerPool.RenderFootprintMarkers(grid, surface, highlightCells, stripResult.canPlace, "Wall")
					local summary = stripResult.summary
					if summary then
						if typeof(CurrentItemId) == "string" then
							local startCFrame =
								grid:CellToWorldEdgeCenterCFrame(summary.StartCellX, summary.StartCellZ, summary.Facing)
							local endCFrame =
								grid:CellToWorldEdgeCenterCFrame(summary.EndCellX, summary.EndCellZ, summary.Facing)
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
							lift,
							summary
						)
					else
						PlacementCostDisplay.Hide()
						previewWall(model, grid, cellX, cellZ, previewFacing, lift)
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
					local placementKey = PlacementKey.ForPlacementType(cellX, cellZ, previewFacing :: any, "Wall")
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
							occupantMatchesOrigin = sameId and sameCell and sameFacing
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
				local requiresFloor = spec ~= nil
					and spec.Rules ~= nil
					and spec.Rules.RequiresFloorUnderAllCells == true
				if requiresFloor then
					PlacementUtils.PopulateCellMapForType(grid, placed, "Floor", FloorSupportMap, ignorePlacement)
					local cells =
						grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, CurrentFacing)
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
				previewWall(model, grid, cellX, cellZ, previewFacing, lift)
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
					lift
				)
			end

			updateHighlightForResult(canPlace)

			local cells = grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, previewFacing)
			local markerKind: "CellObject" | "Floor" | "Roof" | "Wall" = if resolvedPreviewKind == "WallMounted"
				then "CellObject"
				else resolvedPreviewKind :: "CellObject" | "Floor" | "Roof" | "Wall"
			MarkerPool.RenderFootprintMarkers(grid, surface, cells, canPlace, markerKind)
		end)
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

	if SelectedItem then
		PreviewHighlight.Adornee = nil
		SelectedItem:Destroy()
		SelectedItem = nil
	end

	PlacementCostDisplay.Hide()

	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	LastCellX = nil
	LastCellZ = nil
	LastFacing = nil
	LastWallPosition = nil
	CurrentItemId = nil
	CurrentItemSpec = nil
	CurrentPivotRotation = CFrame.identity
	MoveOriginSignature = nil
	MoveHoldActive = false
	MoveHoldMousePosition = nil
	LastPrimaryMouseDown = false
	CurrentWallMountPose = nil
end

function ObjectPreview.GetCurrentPose(): PreviewPose?
	if not CurrentItemId or not LastCellX or not LastCellZ then
		return nil
	end

	return {
		ItemId = CurrentItemId,
		CellX = LastCellX,
		CellZ = LastCellZ,
		Facing = CurrentFacing,
		Kind = CurrentKind,
		WallMount = CurrentWallMountPose,
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
	if not CurrentItemId or not LastCellX or not LastCellZ then
		return false
	end
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		return false
	end
	return FloorPreview.TryBeginDrag(CurrentKind, CurrentItemId, LastCellX, LastCellZ, true)
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
	if not LastCellX or not LastCellZ then
		return false
	end
	local isPressed = UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1)
	if not isPressed then
		return false
	end

	return WallStripPreview.TryBeginDrag({
		itemId = CurrentItemId,
		anchorCellX = LastCellX,
		anchorCellZ = LastCellZ,
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
	if not CurrentItemId or not LastCellX or not LastCellZ then
		return false
	end
	if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
		return false
	end
	return RoofPreview.TryBeginDrag(CurrentKind, CurrentItemId, LastCellX, LastCellZ, true)
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

	local _, placementType, resolvedWidth, resolvedDepth, resolvedFacing = PlacementUtils.ResolvePlacementEntry(entry)

	MoveOriginSignature = {
		ItemId = itemId,
		CellX = cellX,
		CellZ = cellZ,
		Facing = tostring(PlacementKey.NormalizeFacing(resolvedFacing :: any)),
		PlacementType = placementType,
		WidthCells = if typeof(widthCells) == "number" and widthCells > 0 then widthCells else resolvedWidth,
		DepthCells = if typeof(depthCells) == "number" and depthCells > 0 then depthCells else resolvedDepth,
	}

	MoveHoldActive = true
	MoveHoldMousePosition = UserInputService:GetMouseLocation()
end

return ObjectPreview
