--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local Renderer = require(script.Parent.Renderer)
local Types = require(script.Parent.Types)

local MountLogic = {}

type PreviewFacing = Types.PreviewFacing
type SurfaceMountPose = Types.SurfaceMountPose

function MountLogic.SurfaceTopOrigin(surface: BasePart): Vector3
	return surface.CFrame.Position + surface.CFrame.UpVector * (surface.Size.Y * 0.5)
end

function MountLogic.ComputeHeightOffset(surface: BasePart, point: Vector3): number
	local surfaceUp = surface.CFrame.UpVector
	local topOrigin = MountLogic.SurfaceTopOrigin(surface)
	return (point - topOrigin):Dot(surfaceUp)
end

function MountLogic.AdjustPointToHeight(surface: BasePart, point: Vector3, targetHeight: number): Vector3
	local surfaceUp = surface.CFrame.UpVector
	local currentHeight = MountLogic.ComputeHeightOffset(surface, point)
	return point + surfaceUp * (targetHeight - currentHeight)
end

function MountLogic.ComputeLift(spec: any?, model: Model, surface: BasePart): number
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

function MountLogic.ComputeSurfaceMountPreview(
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

	local rotationY = PlacementHelpers.GetYawFromFacing(facing :: any)
	local offset = CFrame.new(localPosition) * CFrame.Angles(0, rotationY, 0)
	local finalCFrame = parentPivot * offset * pivotRotation

	local normalizedParentFacing: PreviewFacing? = nil
	if typeof(parentFacingValue) == "string" and parentFacingValue ~= "" then
		normalizedParentFacing = PlacementKey.NormalizeFacing(parentFacingValue :: any) :: PreviewFacing
	end

	local pose: SurfaceMountPose = {
		CanPlace = true, -- Validation happens externally or later
		ParentKey = parentKey,
		ParentCellX = if typeof(parentCellXValue) == "number" then parentCellXValue else 0,
		ParentCellZ = if typeof(parentCellZValue) == "number" then parentCellZValue else 0,
		ParentFacing = normalizedParentFacing,
		LocalPosition = localPosition,
		LocalRotationY = rotationY,
		WorldPosition = finalCFrame.Position,
	}

	return pose
end

return MountLogic
