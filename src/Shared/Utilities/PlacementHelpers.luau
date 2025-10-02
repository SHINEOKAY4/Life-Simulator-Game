--!strict
-- ReplicatedStorage/Shared/Utilities/PlacementHelpers.lua
-- Shared helper utilities for placement math used by both client previews and server placement.

export type Facing = "North" | "East" | "South" | "West"

local PlacementHelpers = {}
PlacementHelpers.__index = PlacementHelpers

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
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local pivotCFrame = model:GetPivot()
	local pivotLocal = bboxCFrame:PointToObjectSpace(pivotCFrame.Position)
	return (bboxSize.Y * 0.5) + pivotLocal.Y
end

return PlacementHelpers
