--!strict

local PlotSerializationUtils = {}

local function valueType(value)
	local typeofFn = typeof
	if typeofFn then
		return typeofFn(value)
	end
	return type(value)
end

function PlotSerializationUtils.CloneMetadata(value)
	if valueType(value) ~= "table" then
		return value
	end

	local result = {}
	for key, entry in pairs(value) do
		result[key] = PlotSerializationUtils.CloneMetadata(entry)
	end

	return result
end

function PlotSerializationUtils.ClonePosition(value)
	if valueType(value) == "table" then
		local xValue = value.X or value.x
		local yValue = value.Y or value.y
		local zValue = value.Z or value.z
		if valueType(xValue) == "number" and valueType(yValue) == "number" and valueType(zValue) == "number" then
			return {
				X = xValue,
				Y = yValue,
				Z = zValue,
			}
		end
	elseif valueType(value) == "Vector3" then
		return {
			X = value.X,
			Y = value.Y,
			Z = value.Z,
		}
	end

	return {
		X = 0,
		Y = 0,
		Z = 0,
	}
end

function PlotSerializationUtils.FlattenPlacedObjects(
	map,
	defaultLevel,
	findItemById
)
	local keys = {}
	for key in pairs(map) do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local result = {}
	local outIndex = 1
	for index = 1, #keys do
		local saved = map[keys[index]]
		if saved then
			local spec = nil
			if saved.id and findItemById then
				spec = findItemById(saved.id)
			end
			local metadata = saved.Metadata
			local metadataClone = nil
			if metadata ~= nil then
				metadataClone = PlotSerializationUtils.CloneMetadata(metadata)
			end
			local widthCells = metadata and (metadata.WidthCells or metadata.widthCells)
			if not widthCells or widthCells <= 0 then
				if spec then
					widthCells = spec.WidthCells or spec.Width or 1
				else
					widthCells = 1
				end
			end
			local depthCells = metadata and (metadata.DepthCells or metadata.depthCells)
			if not depthCells or depthCells <= 0 then
				if spec then
					depthCells = spec.DepthCells or spec.Depth or 1
				else
					depthCells = 1
				end
			end
			local facing = saved.facing or "North"
			local levelValue = defaultLevel
			if valueType(saved.yLevel) == "number" then
				levelValue = saved.yLevel
			end
			result[outIndex] = {
				id = saved.id,
				cellX = saved.cellX,
				cellZ = saved.cellZ,
				facing = facing,
				WidthCells = widthCells,
				DepthCells = depthCells,
				Metadata = metadataClone,
				Level = levelValue,
			}
			outIndex = outIndex + 1
		end
	end

	return result
end

function PlotSerializationUtils.FlattenSurfaceMounts(map)
	local keys = {}
	for key in pairs(map) do
		keys[#keys + 1] = key
	end
	table.sort(keys)

	local result = {}
	local outIndex = 1
	for index = 1, #keys do
		local key = keys[index]
		local saved = map[key]
		if saved and valueType(saved) == "table" and valueType(saved.id) == "string" then
			local metadataClone = saved.Metadata and PlotSerializationUtils.CloneMetadata(saved.Metadata) or nil
			result[outIndex] = {
				key = key,
				id = saved.id,
				parentKey = saved.parentKey,
				LocalPosition = PlotSerializationUtils.ClonePosition(saved.LocalPosition),
				LocalRotationY = valueType(saved.LocalRotationY) == "number" and saved.LocalRotationY or 0,
				Metadata = metadataClone,
			}
			outIndex = outIndex + 1
		end
	end

	return result
end

return PlotSerializationUtils
