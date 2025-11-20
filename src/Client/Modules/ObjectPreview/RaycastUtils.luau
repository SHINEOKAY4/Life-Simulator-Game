--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)

local RaycastUtils = {}

export type PreviewFacing = PlacementHelpers.PreviewFacing

function RaycastUtils.BuildRaycastParams(surface: BasePart, container: Instance?): RaycastParams
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

function RaycastUtils.BuildWallRaycastParams(container: Instance?): RaycastParams
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

function RaycastUtils.FindWallModel(hit: Instance?): Model?
	if not hit then
		return nil
	end

	local ancestor = hit:FindFirstAncestorWhichIsA("Model")
	while ancestor do
		if ancestor:GetAttribute("PlacementType") == "Wall" then
			return ancestor
		end
		local parent = ancestor.Parent
		if not parent then
			break
		end
		ancestor = parent:FindFirstAncestorWhichIsA("Model")
	end

	return nil
end

function RaycastUtils.ExtractWallPose(model: Model?): (number?, number?, PreviewFacing?)
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

function RaycastUtils.FindSurfaceMountParent(hit: Instance?, container: Instance?): Model?
	if not hit or not container then
		return nil
	end

	local current: Instance? = hit
	while current and current ~= container do
		if current:IsA("Model") then
			local pType = current:GetAttribute("PlacementType")
			if pType == "CellObject" or pType == "Wall" or pType == "Roof" or pType == "Floor" then
				return current
			end
		end
		current = current.Parent
	end

	return nil
end

function RaycastUtils.NormalFromFacing(facing: PreviewFacing): Vector3
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

function RaycastUtils.IsDiagonalFacing(facing: PreviewFacing): boolean
	return facing == "NorthEast" or facing == "SouthEast" or facing == "SouthWest" or facing == "NorthWest"
end

return RaycastUtils
