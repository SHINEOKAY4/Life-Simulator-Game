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

local function alignToSurface(base: CFrame, surface: BasePart): CFrame
	return CFrame.lookAt(base.Position, base.Position + surface.CFrame.LookVector, surface.CFrame.UpVector)
end

function Renderer.GetPivotRotation(model: Model): CFrame
	return GetPivotRotation(model)
end

function Renderer.GetLiftAlongSurface(model: Model, surfaceUp: Vector3): number
	return GetLiftAlongDirection(model, surfaceUp)
end

function Renderer.PreviewWall(model: Model, grid: any, cellX: number, cellZ: number, facing: Facing, lift: number)
	local edgeCFrame = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing)
	model:PivotTo(edgeCFrame * CFrame.new(0, lift, 0))
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
	facing: Facing,
	lift: number
)
	local base = grid:CellToWorldCenterCFrame(cellX, cellZ, lift)
	local aligned = alignToSurface(base, surface)
	local yaw = CFrame.Angles(0, YawFromFacing(facing :: any), 0)
	model:PivotTo(aligned * yaw)
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

return Renderer
