--!strict
-- Client/ClientStores/DataNormalization.luau
-- Centralized data normalization and type coercion utilities

local DataNormalization = {}

function DataNormalization.DeepClone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, entry in pairs(value) do
		result[key] = DataNormalization.DeepClone(entry)
	end

	return result
end

function DataNormalization.CoerceVector3(value: any): Vector3?
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) ~= "table" then
		return nil
	end

	local valueTable = value :: any
	local xValue = valueTable.X or valueTable.x
	local yValue = valueTable.Y or valueTable.y
	local zValue = valueTable.Z or valueTable.z
	if typeof(xValue) ~= "number" or typeof(yValue) ~= "number" or typeof(zValue) ~= "number" then
		return nil
	end
	return Vector3.new(xValue, yValue, zValue)
end

function DataNormalization.NormalizeMetadata(metadata: any): any
	if metadata == nil then
		return nil
	end

	if typeof(metadata) ~= "table" then
		return metadata
	end

	local cloned = DataNormalization.DeepClone(metadata)
	local wallData = cloned.WallMountData
	if typeof(wallData) == "table" then
		local convertedPosition = DataNormalization.CoerceVector3(wallData.WorldPosition)
		if convertedPosition then
			wallData.WorldPosition = convertedPosition
		end
		local convertedNormal = DataNormalization.CoerceVector3(wallData.WallNormal)
		if convertedNormal then
			if convertedNormal.Magnitude > 1e-3 then
				wallData.WallNormal = convertedNormal.Unit
			else
				wallData.WallNormal = Vector3.new(0, 0, -1)
			end
		end
	end

	return cloned
end

function DataNormalization.NormalizeSurfaceMountEntry(entry: any): any
	if typeof(entry) ~= "table" then
		return nil
	end

	local keyValue = entry.Key or entry.key
	if typeof(keyValue) ~= "string" or keyValue == "" then
		return nil
	end

	local itemIdValue = entry.ItemId or entry.Id or entry.id
	if typeof(itemIdValue) ~= "string" or itemIdValue == "" then
		return nil
	end

	local parentKeyValue = entry.ParentKey or entry.parentKey or ""
	if typeof(parentKeyValue) ~= "string" then
		parentKeyValue = ""
	end

	local localPosition = DataNormalization.CoerceVector3(entry.LocalPosition) or Vector3.new()
	local rotationValue = entry.LocalRotationY
	local rotationY = if typeof(rotationValue) == "number" then rotationValue else 0
	local metadata = DataNormalization.NormalizeMetadata(entry.Metadata)

	return {
		key = keyValue,
		id = itemIdValue,
		parentKey = parentKeyValue,
		LocalPosition = localPosition,
		LocalRotationY = rotationY,
		Metadata = metadata,
	}
end

function DataNormalization.CopyNumberArray(source: { number }?): { number }
	local result: { number } = {}
	if not source then
		return result
	end
	for index = 1, #source do
		result[index] = source[index]
	end
	return result
end

function DataNormalization.CloneBooleanMap(source: { [string]: boolean }?): { [string]: boolean }
	local result = {}
	if not source then
		return result
	end
	for key, value in pairs(source) do
		if value == true then
			result[key] = true
		end
	end
	return result
end

function DataNormalization.BooleanMapsEqual(left: { [string]: boolean }?, right: { [string]: boolean }?): boolean
	if left == right then
		return true
	end
	if not left then
		if not right then
			return true
		end
		for _, value in pairs(right) do
			if value == true then
				return false
			end
		end
		return true
	end
	if not right then
		for _, value in pairs(left) do
			if value == true then
				return false
			end
		end
		return true
	end
	for key, value in pairs(left) do
		if (right[key] or false) ~= (value == true) then
			return false
		end
	end
	for key, value in pairs(right) do
		if (left[key] or false) ~= (value == true) then
			return false
		end
	end
	return true
end

return DataNormalization
