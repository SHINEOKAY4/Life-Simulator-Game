--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)
local WindowWallFill = require(ReplicatedStorage.Shared.Utilities.WindowWallFill)

type Facing = string

local Renderer = {}

local DEFAULT_FRAME_DELTA = 1 / 60
local SMOOTH_SNAP_SPEED = 18
local MIN_BLEND_ALPHA = 0.12
local POSITION_SNAP_EPSILON = 1e-3
local ORIENTATION_SNAP_EPSILON = 1e-3

local lastFrameDelta = DEFAULT_FRAME_DELTA

type SmoothEntry = {
	current: CFrame,
	target: CFrame,
}

local smoothEntries = setmetatable({}, { __mode = "k" }) :: { [Model]: SmoothEntry }

local function computeBlendAlpha(): number
	local dt = lastFrameDelta
	if dt <= 0 then
		dt = DEFAULT_FRAME_DELTA
	end
	local alpha = 1 - math.exp(-SMOOTH_SNAP_SPEED * dt)
	if alpha < MIN_BLEND_ALPHA then
		alpha = MIN_BLEND_ALPHA
	elseif alpha > 1 then
		alpha = 1
	end
	return alpha
end

local function getSmoothEntry(model: Model, default: CFrame?): SmoothEntry
	local entry = smoothEntries[model]
	if entry then
		return entry
	end
	local initial = default or model:GetPivot()
	entry = {
		current = initial,
		target = initial,
	}
	smoothEntries[model] = entry
	return entry
end

local function isOrientationClose(a: CFrame, b: CFrame): boolean
	local dot = (a.RightVector:Dot(b.RightVector) + a.UpVector:Dot(b.UpVector) + a.LookVector:Dot(b.LookVector)) / 3
	return (1 - dot) <= ORIENTATION_SNAP_EPSILON
end

local function isPoseClose(a: CFrame, b: CFrame): boolean
	if (a.Position - b.Position).Magnitude > POSITION_SNAP_EPSILON then
		return false
	end
	return isOrientationClose(a, b)
end

local function blendToward(model: Model, entry: SmoothEntry, target: CFrame)
	local blended = entry.current:Lerp(target, computeBlendAlpha())
	if isPoseClose(blended, target) then
		blended = target
	end
	entry.current = blended
	entry.target = target
	model:PivotTo(blended)
end

local function applySmoothPivot(model: Model, target: CFrame, skipSmoothing: boolean?)
	local entry = getSmoothEntry(model, target)

	if skipSmoothing == true then
		-- Some placement previews (wall/floor/ceiling planes) must snap instantly to avoid stretching artifacts.
		entry.current = target
		entry.target = target
		model:PivotTo(target)
		return
	end

	if isPoseClose(entry.current, target) then
		entry.current = target
		entry.target = target
		model:PivotTo(target)
		return
	end
	blendToward(model, entry, target)
end

function Renderer.StepModel(model: Model)
	local entry = smoothEntries[model]
	if not entry then
		return
	end
	local target = entry.target
	local current = entry.current
	if not target or not current then
		return
	end
	if isPoseClose(current, target) then
		if current ~= target then
			entry.current = target
			model:PivotTo(target)
		end
		return
	end
	blendToward(model, entry, target)
end

function Renderer.ClearModel(model: Model?)
	if not model then
		return
	end
	smoothEntries[model] = nil
end

function Renderer.SetFrameDelta(deltaTime: number?)
	if typeof(deltaTime) == "number" and deltaTime > 0 then
		lastFrameDelta = deltaTime
	else
		lastFrameDelta = DEFAULT_FRAME_DELTA
	end
end

local YawFromFacing = PlacementHelpers.GetYawFromFacing
local GetFlatAlignedCFrame = PlacementHelpers.GetFlatAlignedCFrame
local GetRotationOnly = PlacementHelpers.GetRotation
local GetPivotRotation = PlacementHelpers.GetPivotRotation
local GetLiftAlongDirection = PlacementHelpers.GetLiftAlongDirection
local GetCeilingAttachmentAxes = PlacementHelpers.GetCeilingAttachmentAxes

export type WindowCutoutConfig = {
	CutoutWidth: number?,
	CutoutHeight: number?,
	OffsetFromWall: number?,
	FrameThickness: number?,
	FrameThicknessRatio: number?,
	MinFrameThickness: number?,
	MaxFrameThickness: number?,
	MinCutoutWidth: number?,
	MaxCutoutWidth: number?,
	CutoutWidthRatio: number?,
	MinCutoutHeight: number?,
	MaxCutoutHeight: number?,
	CutoutHeightRatio: number?,
	DefaultHeightRatio: number?,
	MinHeight: number?,
	MaxHeight: number?,
	DefaultHeight: number?,
	AllowVerticalSliding: boolean?,
	PreserveModelThickness: boolean?,
}

export type WindowCutoutPose = {
	WorldPosition: Vector3,
	WallNormal: Vector3,
	WallUp: Vector3,
	WallCellX: number?,
	WallCellZ: number?,
	AttachedFacing: Facing?,
	WallCenter: Vector3,
	WallHeight: number,
	WallWidth: number,
	WallThickness: number,
	HeightOffset: number,
	CutoutWidth: number,
	CutoutHeight: number,
	LocalCenterY: number,
	FrameThickness: number,
	OffsetFromWall: number,
	EffectiveWallWidth: number,
}

export type WindowPreviewVisual = {
	WallPart: BasePart,
	OriginalTransparencyModifier: number,
	Segments: { BasePart },
	Container: Folder?,
}

type WallSpanInfo = {
	StartCellX: number,
	EndCellX: number,
	StartCellZ: number,
	EndCellZ: number,
	SegmentCount: number,
}

local function alignToSurface(base: CFrame, surface: BasePart): CFrame
	return CFrame.lookAt(base.Position, base.Position + surface.CFrame.LookVector, surface.CFrame.UpVector)
end

function Renderer.GetPivotRotation(model: Model): CFrame
	return GetPivotRotation(model)
end

function Renderer.GetLiftAlongSurface(model: Model, surfaceUp: Vector3): number
	return GetLiftAlongDirection(model, surfaceUp)
end

local function ensureWallPreviewAttributes(part: BasePart, cellSize: number)
	if part:GetAttribute("PreviewLengthAxis") then
		return
	end

	local size = part.Size
	local axis = "X"
	if math.abs(size.Z - cellSize) < math.abs(size.X - cellSize) then
		axis = "Z"
	end

	part:SetAttribute("PreviewLengthAxis", axis)
	part:SetAttribute("PreviewBaseHeight", size.Y)
	if axis == "X" then
		part:SetAttribute("PreviewBaseLength", size.X)
		part:SetAttribute("PreviewBaseThickness", size.Z)
	else
		part:SetAttribute("PreviewBaseLength", size.Z)
		part:SetAttribute("PreviewBaseThickness", size.X)
	end
end

local function applyWallPreviewScaling(part: BasePart, cellSize: number, span: WallSpanInfo?, facing: Facing)
	ensureWallPreviewAttributes(part, cellSize)

	local axis = part:GetAttribute("PreviewLengthAxis") :: string? or "X"
	local baseHeight = part:GetAttribute("PreviewBaseHeight") :: number? or part.Size.Y
	if BuildConstants.FloorHeightStuds then
		baseHeight = BuildConstants.FloorHeightStuds
	end

	local baseThickness = part:GetAttribute("PreviewBaseThickness") :: number?
		or (axis == "X" and part.Size.Z or part.Size.X)
	local segmentCount = if span and span.SegmentCount and span.SegmentCount > 0 then span.SegmentCount else 1
	local lengthMultiplier = 1
	if facing == "NorthEast" or facing == "SouthEast" or facing == "NorthWest" or facing == "SouthWest" then
		lengthMultiplier = math.sqrt(2)
	end
	local targetLength = segmentCount * cellSize * lengthMultiplier

	if axis == "X" then
		part.Size = Vector3.new(targetLength, baseHeight, baseThickness)
	else
		part.Size = Vector3.new(baseThickness, baseHeight, targetLength)
	end
end

local function computeWallSpan(span: WallSpanInfo?, cellX: number, cellZ: number): WallSpanInfo
	if span then
		local segmentCount = if span.SegmentCount > 0 then span.SegmentCount else 1
		return {
			StartCellX = span.StartCellX,
			EndCellX = span.EndCellX,
			StartCellZ = span.StartCellZ,
			EndCellZ = span.EndCellZ,
			SegmentCount = segmentCount,
		}
	end

	return {
		StartCellX = cellX,
		EndCellX = cellX,
		StartCellZ = cellZ,
		EndCellZ = cellZ,
		SegmentCount = 1,
	}
end

function Renderer.PreviewWall(
	model: Model,
	grid: any,
	cellX: number,
	cellZ: number,
	facing: Facing,
	levelHeight: number?,
	lift: number,
	spanInfo: WallSpanInfo?
)
	local span = computeWallSpan(spanInfo, cellX, cellZ)
	local scalingAttribute = model:GetAttribute("PreviewApplyWallScaling")
	local shouldApplyScaling = scalingAttribute == nil or scalingAttribute == true

	if shouldApplyScaling then
		local rootPart: BasePart? = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
		if rootPart then
			applyWallPreviewScaling(rootPart, grid.CellSize, span, facing)
		end
	end

	local resolvedLevelHeight = if typeof(levelHeight) == "number" then levelHeight else 0
	local anchorCFrame = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing, resolvedLevelHeight)
	local startCFrame = grid:CellToWorldEdgeCenterCFrame(span.StartCellX, span.StartCellZ, facing, resolvedLevelHeight)
	local endCFrame = grid:CellToWorldEdgeCenterCFrame(span.EndCellX, span.EndCellZ, facing, resolvedLevelHeight)
	local centerPosition = (startCFrame.Position + endCFrame.Position) * 0.5
	local orientation =
		CFrame.fromMatrix(centerPosition, anchorCFrame.RightVector, anchorCFrame.UpVector, anchorCFrame.LookVector)
	applySmoothPivot(model, orientation * CFrame.new(0, lift, 0), true)
end

function Renderer.PreviewFloor(
	model: Model,
	grid: any,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing,
	levelHeight: number?
)
	local center = grid:FootprintCenterCFrame(cellX, cellZ, widthCells, depthCells, facing)
	if typeof(levelHeight) == "number" and levelHeight ~= 0 then
		center = center * CFrame.new(0, levelHeight, 0)
	end
	local aligned = alignToSurface(center, surface)
	applySmoothPivot(model, aligned, true)
end

function Renderer.PreviewRoof(
	model: Model,
	grid: any,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	widthCells: number?,
	depthCells: number?,
	facing: Facing,
	levelHeight: number?,
	spec: any?
)
	local width = widthCells or 1
	local depth = depthCells or 1
	local resolvedLevelHeight = if typeof(levelHeight) == "number" then levelHeight else 0
	local baseRoofLift = BuildConstants.RoofLiftStuds or 12
	local roofLift = baseRoofLift
	if spec and typeof(spec.HeightStuds) == "number" then
		roofLift = spec.HeightStuds
	end

	if width == 1 and depth == 1 then
		local totalOffset = resolvedLevelHeight + roofLift
		local base = grid:CellToWorldCenterCFrame(cellX, cellZ, totalOffset)
		local aligned = alignToSurface(base, surface)
		local yaw = CFrame.Angles(0, YawFromFacing(facing :: any), 0)
		applySmoothPivot(model, aligned * yaw)
	else
		local center = grid:FootprintCenterCFrame(cellX, cellZ, width, depth, facing)
		center = center * CFrame.new(0, resolvedLevelHeight, 0)
		local aligned = alignToSurface(center, surface)
		local yaw = CFrame.Angles(0, YawFromFacing(facing :: any), 0)
		local liftedPosition = aligned.Position + surface.CFrame.UpVector * roofLift
		applySmoothPivot(model, CFrame.new(liftedPosition) * GetRotationOnly(aligned) * yaw)
	end
end

function Renderer.PreviewCellObject(
	model: Model,
	grid: any,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	facing: Facing,
	widthCells: number,
	depthCells: number,
	levelHeight: number?,
	lift: number,
	pivotRotation: CFrame,
	subSlotOffset: Vector3?
)
	local center = grid:FootprintCenterCFrame(cellX, cellZ, widthCells, depthCells, facing)
	local resolvedLevelHeight = if typeof(levelHeight) == "number" then levelHeight else 0
	if resolvedLevelHeight ~= 0 then
		center = center * CFrame.new(0, resolvedLevelHeight, 0)
	end
	local flatAligned = GetFlatAlignedCFrame(surface, center.Position)
	local baseRotation = GetRotationOnly(flatAligned)
	local yaw = CFrame.Angles(0, YawFromFacing(facing :: any), 0)
	local orientation = baseRotation * yaw * pivotRotation
	local offset = if subSlotOffset then subSlotOffset else Vector3.new()
	local liftedPosition = center.Position + offset + surface.CFrame.UpVector * lift

	applySmoothPivot(model, CFrame.new(liftedPosition) * orientation)
end

function Renderer.PreviewWallMounted(
	model: Model,
	worldPosition: Vector3,
	wallNormal: Vector3,
	upVector: Vector3,
	pivotRotation: CFrame
)
	local forward = (-wallNormal).Unit
	local safeUp = if upVector.Magnitude > 1e-3 then upVector.Unit else Vector3.new(0, 1, 0)
	local previewCFrame = CFrame.lookAt(worldPosition, worldPosition + forward, safeUp)
	applySmoothPivot(model, previewCFrame * pivotRotation)
end

function Renderer.PreviewSurfaceMount(
	model: Model,
	parentModel: Model,
	localPosition: Vector3,
	rotationY: number,
	pivotRotation: CFrame
)
	local parentPivot = parentModel:GetPivot()
	local offset = CFrame.new(localPosition) * CFrame.Angles(0, rotationY, 0)
	applySmoothPivot(model, parentPivot * offset * pivotRotation)
end

function Renderer.PreviewCeilingMounted(
	model: Model,
	worldPosition: Vector3,
	ceilingNormal: Vector3,
	upVector: Vector3,
	rotationY: number,
	pivotRotation: CFrame
)
	local resolvedNormal = ceilingNormal
	if resolvedNormal.Magnitude < 1e-3 then
		resolvedNormal = Vector3.new(0, -1, 0)
	else
		resolvedNormal = resolvedNormal.Unit
	end
	local right, attachmentUp, forward = GetCeilingAttachmentAxes(resolvedNormal, upVector)
	local baseCFrame = CFrame.fromMatrix(worldPosition, right, attachmentUp, -forward)
	local aroundAxis = CFrame.fromAxisAngle(resolvedNormal, rotationY)
	applySmoothPivot(model, baseCFrame * aroundAxis * pivotRotation, true)
end

local WINDOW_PREVIEW_SEGMENT_NAME = "_PreviewWindowSegment"
local WINDOW_PREVIEW_CONTAINER_NAME = "_WindowPreviewCutout"

local function buildBasis(wallNormal: Vector3, wallUp: Vector3): (Vector3, Vector3, Vector3)
	local forward = (-wallNormal).Unit
	local up = wallUp
	if up.Magnitude < 1e-3 or math.abs(up:Dot(forward)) > 0.98 then
		up = Vector3.new(0, 1, 0)
		if math.abs(up:Dot(forward)) > 0.98 then
			up = Vector3.new(0, 0, 1)
		end
	end
	local right = forward:Cross(up)
	if right.Magnitude < 1e-3 then
		right = Vector3.new(1, 0, 0)
	end
	right = right.Unit
	up = right:Cross(forward).Unit
	forward = forward.Unit
	return right, up, forward
end

local function createPreviewSegment(parent: Instance, size: Vector3, cf: CFrame, template: BasePart): BasePart
	local part = Instance.new("Part")
	part.Name = WINDOW_PREVIEW_SEGMENT_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.CastShadow = true
	part.Material = template.Material
	part.Color = template.Color
	part.Transparency = template.Transparency
	part.Reflectance = template.Reflectance
	part.CFrame = cf
	part.Size = size
	part.Parent = parent
	return part
end

function Renderer.PreviewWindowOnWall(
	windowModel: Model,
	wallPart: BasePart?,
	pose: WindowCutoutPose,
	config: WindowCutoutConfig?,
	pivotRotation: CFrame
): WindowPreviewVisual?
	if not wallPart then
		return nil
	end

	local frameThickness = pose.FrameThickness
	if frameThickness <= 0.01 then
		if config and typeof(config.FrameThickness) == "number" and config.FrameThickness > 0 then
			frameThickness = config.FrameThickness
		else
			frameThickness = 0.2
		end
	end

	local wallThickness = pose.WallThickness
	if not wallThickness or wallThickness <= 1e-3 then
		wallThickness = wallPart.Size.Z
	end
	if wallThickness < 0.05 then
		wallThickness = 0.05
	end

	local wallWidth = pose.WallWidth
	if not wallWidth or wallWidth <= 1e-3 then
		wallWidth = wallPart.Size.X
	end
	if wallWidth < frameThickness * 2 then
		wallWidth = frameThickness * 2
	end

	local effectiveWallWidth = wallWidth
	if pose.EffectiveWallWidth and pose.EffectiveWallWidth > 1e-3 then
		effectiveWallWidth = math.max(pose.EffectiveWallWidth, wallWidth)
	end

	local heightOffset = pose.HeightOffset
	if not heightOffset or heightOffset <= 0 then
		heightOffset = pose.WallHeight * 0.5
	end

	local offsetFromWall = pose.OffsetFromWall or 0
	local rightVector, upVector, forwardVector = buildBasis(pose.WallNormal, pose.WallUp)
	local outwardVector = -forwardVector
	local edgePosition = pose.WorldPosition - upVector * heightOffset - outwardVector * offsetFromWall

	local visualOverride = {
		Size = wallPart.Size,
		Material = wallPart.Material,
		Color = wallPart.Color,
		Transparency = wallPart.Transparency,
		Reflectance = wallPart.Reflectance,
	}

	local windowData = {
		FrameThickness = frameThickness,
		WallSizeX = wallWidth,
		WallSizeY = pose.WallHeight,
		WallSizeZ = wallThickness,
		EffectiveWallWidth = effectiveWallWidth,
		CutoutWidth = pose.CutoutWidth,
		CutoutHeight = pose.CutoutHeight,
		HeightOffset = heightOffset,
		OffsetFromWall = offsetFromWall,
		EdgePosition = edgePosition,
		EdgeUp = upVector,
		EdgeForward = outwardVector,
		EdgeRight = rightVector,
	}

	local solution = WindowWallFill.ComputeSegments(windowModel, windowData, nil, visualOverride)
	if not solution then
		return nil
	end

	local geometry = solution.Geometry
	local adjustedWidth = math.max(geometry.WallWidth, frameThickness * 2)

	local rootPart = windowModel.PrimaryPart or windowModel:FindFirstChildWhichIsA("BasePart")
	if rootPart then
		ensureWallPreviewAttributes(rootPart, math.max(adjustedWidth, 0.1))
		local axis = rootPart:GetAttribute("PreviewLengthAxis") :: string? or "X"
		local baseHeightAttr = rootPart:GetAttribute("PreviewBaseHeight")
		local baseThicknessAttr = rootPart:GetAttribute("PreviewBaseThickness")

		local baseHeight = rootPart.Size.Y
		if typeof(baseHeightAttr) == "number" and baseHeightAttr > 0 then
			baseHeight = baseHeightAttr
		end

		local baseThickness
		if axis == "X" then
			baseThickness = rootPart.Size.Z
		else
			baseThickness = rootPart.Size.X
		end
		if typeof(baseThicknessAttr) == "number" and baseThicknessAttr > 0 then
			baseThickness = baseThicknessAttr
		end

		if axis == "X" then
			rootPart.Size = Vector3.new(adjustedWidth, baseHeight, baseThickness)
		else
			rootPart.Size = Vector3.new(baseThickness, baseHeight, adjustedWidth)
		end
	end

	local segmentContainer = Instance.new("Folder")
	segmentContainer.Name = WINDOW_PREVIEW_CONTAINER_NAME
	segmentContainer.Parent = wallPart

	local originalModifier = wallPart.LocalTransparencyModifier
	wallPart.LocalTransparencyModifier = 1

	local segments: { BasePart } = {}
	local ok, err = pcall(function()
		for _, segment in solution.Segments do
			segments[#segments + 1] = createPreviewSegment(segmentContainer, segment.Size, segment.CFrame, wallPart)
		end
	end)
	if not ok then
		wallPart.LocalTransparencyModifier = originalModifier
		segmentContainer:Destroy()
		warn("[ObjectPreview] Failed to build window preview segments: " .. tostring(err))
		return nil
	end

	Renderer.PreviewWallMounted(windowModel, pose.WorldPosition, pose.WallNormal, upVector, pivotRotation)

	return {
		WallPart = wallPart,
		OriginalTransparencyModifier = originalModifier,
		Segments = segments,
		Container = segmentContainer,
	}
end

function Renderer.ClearWindowPreview(visual: WindowPreviewVisual?)
	if not visual then
		return
	end

	if visual.WallPart then
		visual.WallPart.LocalTransparencyModifier = visual.OriginalTransparencyModifier
	end

	for _, part in visual.Segments do
		if part and part.Parent then
			part:Destroy()
		end
	end

	if visual.Container and visual.Container.Parent then
		visual.Container:Destroy()
	end
end

return Renderer
