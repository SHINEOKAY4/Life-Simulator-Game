--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)

type Facing = string

local Renderer = {}

local YawFromFacing = PlacementHelpers.GetYawFromFacing
local GetFlatAlignedCFrame = PlacementHelpers.GetFlatAlignedCFrame
local GetRotationOnly = PlacementHelpers.GetRotation
local GetPivotRotation = PlacementHelpers.GetPivotRotation
local GetLiftAlongDirection = PlacementHelpers.GetLiftAlongDirection

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

	local anchorCFrame = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing)
	local startCFrame = grid:CellToWorldEdgeCenterCFrame(span.StartCellX, span.StartCellZ, facing)
	local endCFrame = grid:CellToWorldEdgeCenterCFrame(span.EndCellX, span.EndCellZ, facing)
	local centerPosition = (startCFrame.Position + endCFrame.Position) * 0.5
	local orientation =
		CFrame.fromMatrix(centerPosition, anchorCFrame.RightVector, anchorCFrame.UpVector, anchorCFrame.LookVector)
	model:PivotTo(orientation * CFrame.new(0, lift, 0))
end

function Renderer.PreviewFloor(
	model: Model,
	grid: any,
	surface: BasePart,
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
)
	local center = grid:FootprintCenterCFrame(cellX, cellZ, widthCells, depthCells, facing)
	local aligned = alignToSurface(center, surface)
	model:PivotTo(aligned)
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
	spec: any?
)
	local width = widthCells or 1
	local depth = depthCells or 1
	local lift = spec and spec.HeightStuds or 12

	if width == 1 and depth == 1 then
		local base = grid:CellToWorldCenterCFrame(cellX, cellZ, lift)
		local aligned = alignToSurface(base, surface)
		local yaw = CFrame.Angles(0, YawFromFacing(facing :: any), 0)
		model:PivotTo(aligned * yaw)
	else
		local center = grid:FootprintCenterCFrame(cellX, cellZ, width, depth, facing)
		local aligned = alignToSurface(center, surface)
		local yaw = CFrame.Angles(0, YawFromFacing(facing :: any), 0)
		local liftedPosition = aligned.Position + surface.CFrame.UpVector * lift
		model:PivotTo(CFrame.new(liftedPosition) * GetRotationOnly(aligned) * yaw)
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
	lift: number,
	pivotRotation: CFrame
)
	local center = grid:FootprintCenterCFrame(cellX, cellZ, widthCells, depthCells, facing)
	local flatAligned = GetFlatAlignedCFrame(surface, center.Position)
	local baseRotation = GetRotationOnly(flatAligned)
	local yaw = CFrame.Angles(0, YawFromFacing(facing :: any), 0)
	local orientation = baseRotation * yaw * pivotRotation
	local liftedPosition = center.Position + surface.CFrame.UpVector * lift

	model:PivotTo(CFrame.new(liftedPosition) * orientation)
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
	model:PivotTo(previewCFrame * pivotRotation)
end

return Renderer
