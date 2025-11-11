--!strict
-- ReplicatedStorage/Shared/Utilities/PlacementHelpers.lua
-- Shared helper utilities for placement math used by both client previews and server placement.

export type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

local PlacementHelpers = {}
PlacementHelpers.__index = PlacementHelpers

local DEFAULT_FORWARD = Vector3.new(0, 0, -1)
local WORLD_UP = Vector3.new(0, 1, 0)

--[=[
	Converts a cardinal facing value into a yaw rotation in radians.
	@within PlacementHelpers

	@param facing Facing -- The cardinal direction to convert.
	@return number -- The yaw angle, in radians, matching the facing.
]=]
function PlacementHelpers.GetYawFromFacing(facing: Facing): number
	if facing == "East" then
		return math.rad(90)
	elseif facing == "South" then
		return math.rad(180)
	elseif facing == "West" then
		return math.rad(270)
	elseif facing == "NorthEast" or facing == "SouthWest" then
		return math.rad(45)
	elseif facing == "NorthWest" or facing == "SouthEast" then
		return math.rad(315)
	end
	return 0
end

--[=[
	Computes how far a model's pivot must be lifted so its lowest point sits on a surface.
	@within PlacementHelpers

	@param model Model -- The model to measure.
	@return number -- The vertical offset from the pivot to the model's lowest point.
]=]
function PlacementHelpers.GetLiftFromPivotToBottom(model: Model): number
	return PlacementHelpers.GetLiftAlongDirection(model, Vector3.yAxis)
end

function PlacementHelpers.GetLiftAlongDirection(model: Model, direction: Vector3): number
	local directionMagnitude = direction.Magnitude
	if directionMagnitude < 1e-3 then
		return 0
	end

	local unitDirection = direction / directionMagnitude
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local pivotPosition = model:GetPivot().Position
	local halfSize = bboxSize * 0.5
	local minProjection = math.huge

	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local cornerOffset = Vector3.new(halfSize.X * sx, halfSize.Y * sy, halfSize.Z * sz)
				local cornerWorld = bboxCFrame * cornerOffset
				local projection = unitDirection:Dot(cornerWorld - pivotPosition)
				if projection < minProjection then
					minProjection = projection
				end
			end
		end
	end

	if minProjection >= 0 then
		return 0
	end

	return -minProjection
end

--[=[
	Builds a CFrame at the given position that keeps the model upright (no roll or pitch)
	while aligning its forward direction with the provided surface's horizontal orientation.
	Falls back to world -Z if the surface lacks a usable horizontal forward vector.
	@within PlacementHelpers

	@param surface BasePart? -- The surface whose horizontal orientation should be mirrored.
	@param position Vector3 -- The world position for the resulting CFrame.
	@return CFrame -- A CFrame positioned at `position` with only yaw rotation applied.
]=]
function PlacementHelpers.GetFlatAlignedCFrame(surface: BasePart?, position: Vector3): CFrame
	if surface then
		local surfaceCFrame = surface.CFrame
		local forward = Vector3.new(surfaceCFrame.LookVector.X, 0, surfaceCFrame.LookVector.Z)
		if forward.Magnitude < 1e-3 then
			local right = surfaceCFrame.RightVector
			forward = Vector3.new(right.X, 0, right.Z)
		end
		if forward.Magnitude > 1e-3 then
			forward = forward.Unit
			return CFrame.lookAt(position, position + forward, WORLD_UP)
		end
	end

	return CFrame.lookAt(position, position + DEFAULT_FORWARD, WORLD_UP)
end

function PlacementHelpers.GetRotation(cf: CFrame): CFrame
	return cf - cf.Position
end

function PlacementHelpers.GetPivotRotation(model: Model): CFrame
	local pivot = model:GetPivot()
	if typeof(pivot) ~= "CFrame" then
		return CFrame.identity
	end
	return pivot - pivot.Position
end

return PlacementHelpers
