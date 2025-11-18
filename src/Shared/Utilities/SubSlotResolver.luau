--!strict

local PlacementHelpers = require(script.Parent.PlacementHelpers)

export type SubSlotRecord = {
	Id: string,
	OffsetCellX: number,
	OffsetCellY: number,
	OffsetCellZ: number,
	OffsetStudsX: number,
	OffsetStudsY: number,
	OffsetStudsZ: number,
	Label: string?,
}

local SubSlotResolver = {}

local function getConfig(spec: { [string]: any }?): { [string]: any }?
	if typeof(spec) ~= "table" then
		return nil
	end
	local slotsConfig = spec.SubSlots
	if typeof(slotsConfig) ~= "table" then
		return nil
	end
	return slotsConfig
end

local function getSlotsArray(config: { [string]: any }): { { [string]: any } }
	local slots = config.Slots
	if typeof(slots) == "table" then
		if #slots > 0 then
			return slots
		end
		local result = {}
		for _, entry in pairs(slots) do
			if typeof(entry) == "table" then
				result[#result + 1] = entry
			end
		end
		return result
	end
	return {}
end

local function resolveOffset(component: any, defaultValue: number): number
	if typeof(component) == "number" then
		return component
	end
	return defaultValue
end

local function coerceSlot(entry: { [string]: any }): SubSlotRecord?
	local slotId = entry.Id or entry.id or entry.Name or entry.name
	if typeof(slotId) ~= "string" or slotId == "" then
		return nil
	end

	local offsetCell = entry.OffsetCell or entry.CellOffset or entry.GridOffset
	local offsetStuds = entry.OffsetStuds or entry.StudOffset or entry.WorldOffset

	local offsetCellX = 0
	local offsetCellY = 0
	local offsetCellZ = 0
	if typeof(offsetCell) == "table" then
		offsetCellX = resolveOffset(offsetCell.X or offsetCell.x, 0)
		offsetCellY = resolveOffset(offsetCell.Y or offsetCell.y, 0)
		offsetCellZ = resolveOffset(offsetCell.Z or offsetCell.z, 0)
	end

	local offsetStudsX = 0
	local offsetStudsY = 0
	local offsetStudsZ = 0
	if typeof(offsetStuds) == "table" then
		offsetStudsX = resolveOffset(offsetStuds.X or offsetStuds.x, 0)
		offsetStudsY = resolveOffset(offsetStuds.Y or offsetStuds.y, 0)
		offsetStudsZ = resolveOffset(offsetStuds.Z or offsetStuds.z, 0)
	end

	return {
		Id = slotId,
		OffsetCellX = offsetCellX,
		OffsetCellY = offsetCellY,
		OffsetCellZ = offsetCellZ,
		OffsetStudsX = offsetStudsX,
		OffsetStudsY = offsetStudsY,
		OffsetStudsZ = offsetStudsZ,
		Label = entry.Label or entry.label,
	}
end

local function buildSlotLookup(config: { [string]: any }): { [string]: SubSlotRecord }
	local lookup: { [string]: SubSlotRecord } = {}
	local slots = getSlotsArray(config)
	for _, entry in ipairs(slots) do
		if typeof(entry) == "table" then
			local normalized = coerceSlot(entry)
			if normalized then
				lookup[normalized.Id] = normalized
			end
		end
	end
	return lookup
end

local function getSlotLookup(spec: { [string]: any }?): { [string]: SubSlotRecord }
	local config = getConfig(spec)
	if not config then
		return {}
	end
	if config._CachedLookup then
		return config._CachedLookup
	end
	local lookup = buildSlotLookup(config)
	config._CachedLookup = lookup
	return lookup
end

function SubSlotResolver.UsesSubSlots(spec: { [string]: any }?): boolean
	local config = getConfig(spec)
	if not config then
		return false
	end
	local lookup = getSlotLookup(spec)
	return next(lookup) ~= nil
end

function SubSlotResolver.GetSlotCount(spec: { [string]: any }?): number
	local lookup = getSlotLookup(spec)
	local count = 0
	for _ in pairs(lookup) do
		count += 1
	end
	return count
end

local function resolveDefaultId(spec: { [string]: any }?, lookup: { [string]: SubSlotRecord }): string?
	local config = getConfig(spec)
	if not config then
		return nil
	end
	local defaultId = config.DefaultId or config.Default or config.DefaultSlot or config.DefaultSlotId
	if typeof(defaultId) == "string" and defaultId ~= "" and lookup[defaultId] then
		return defaultId
	end
	for _, record in pairs(lookup) do
		return record.Id
	end
	return nil
end

function SubSlotResolver.GetDefaultSlotId(spec: { [string]: any }?): string?
	local lookup = getSlotLookup(spec)
	return resolveDefaultId(spec, lookup)
end

function SubSlotResolver.NormalizeSlotId(spec: { [string]: any }?, candidateId: string?): string?
	if not candidateId or candidateId == "" then
		return SubSlotResolver.GetDefaultSlotId(spec)
	end
	local lookup = getSlotLookup(spec)
	if lookup[candidateId] then
		return candidateId
	end
	return SubSlotResolver.GetDefaultSlotId(spec)
end

function SubSlotResolver.ResolveSavedSlotId(metadata: { [string]: any }?, spec: { [string]: any }?): string?
	if typeof(metadata) ~= "table" then
		return SubSlotResolver.GetDefaultSlotId(spec)
	end
	local candidate = metadata.SubSlotId or metadata.subSlotId
	if typeof(candidate) ~= "string" then
		candidate = nil
	end
	return SubSlotResolver.NormalizeSlotId(spec, candidate)
end

function SubSlotResolver.GetGroupId(spec: { [string]: any }?): string?
	local config = getConfig(spec)
	if not config then
		return nil
	end
	local groupId = config.Group or config.GroupId
	if not groupId and typeof(spec) == "table" then
		groupId = spec.SubSlotGroup
	end
	if typeof(groupId) == "string" and groupId ~= "" then
		return groupId
	end
	return nil
end

function SubSlotResolver.AllowsMixing(spec: { [string]: any }?): boolean
	local config = getConfig(spec)
	if not config then
		return false
	end
	local allow = config.AllowMixing
	if typeof(allow) == "boolean" then
		return allow
	end
	local rules = (typeof(spec) == "table" and spec.Rules) or nil
	if typeof(rules) == "table" then
		local rulesAllow = rules.AllowSubSlotMixing
		if typeof(rulesAllow) == "boolean" then
			return rulesAllow
		end
	end
	return false
end

function SubSlotResolver.CanItemsShare(specA: { [string]: any }?, specB: { [string]: any }?): boolean
	if not SubSlotResolver.UsesSubSlots(specA) or not SubSlotResolver.UsesSubSlots(specB) then
		return false
	end
	local groupA = SubSlotResolver.GetGroupId(specA)
	local groupB = SubSlotResolver.GetGroupId(specB)
	if groupA and groupB and groupA == groupB then
		return true
	end
	if not groupA or not groupB then
		return SubSlotResolver.AllowsMixing(specA) and SubSlotResolver.AllowsMixing(specB)
	end
	return false
end

local function rotateVectorAroundY(vector: Vector3, yaw: number): Vector3
	local cosYaw = math.cos(yaw)
	local sinYaw = math.sin(yaw)
	local x = vector.X * cosYaw - vector.Z * sinYaw
	local z = vector.X * sinYaw + vector.Z * cosYaw
	return Vector3.new(x, vector.Y, z)
end

function SubSlotResolver.ResolveOffset(
	spec: { [string]: any }?,
	slotId: string?,
	cellSize: number,
	facing: string?
): Vector3
	local lookup = getSlotLookup(spec)
	if not next(lookup) then
		return Vector3.new()
	end
	local resolvedId = SubSlotResolver.NormalizeSlotId(spec, slotId)
	if not resolvedId then
		return Vector3.new()
	end
	local record = lookup[resolvedId]
	if not record then
		return Vector3.new()
	end

	local offsetX = record.OffsetStudsX + record.OffsetCellX * cellSize
	local offsetY = record.OffsetStudsY + record.OffsetCellY * cellSize
	local offsetZ = record.OffsetStudsZ + record.OffsetCellZ * cellSize

	local baseOffset = Vector3.new(offsetX, offsetY, offsetZ)
	if not facing then
		return baseOffset
	end
	local yaw = PlacementHelpers.GetYawFromFacing(facing :: any)
	return rotateVectorAroundY(baseOffset, yaw)
end

local function computeBaseOffset(record: SubSlotRecord, cellSize: number): Vector3
	local offsetX = record.OffsetStudsX + record.OffsetCellX * cellSize
	local offsetY = record.OffsetStudsY + record.OffsetCellY * cellSize
	local offsetZ = record.OffsetStudsZ + record.OffsetCellZ * cellSize
	return Vector3.new(offsetX, offsetY, offsetZ)
end

function SubSlotResolver.IterateSlots(spec: { [string]: any }?, cellSize: number): ({ SubSlotRecord }, { Vector3 })
	local lookup = getSlotLookup(spec)
	local records: { SubSlotRecord } = {}
	local offsets: { Vector3 } = {}
	local keys: { string } = {}
	for id in pairs(lookup) do
		keys[#keys + 1] = id
	end
	table.sort(keys)
	for index = 1, #keys do
		local record = lookup[keys[index]]
		records[index] = record
		offsets[index] = computeBaseOffset(record, cellSize)
	end
	return records, offsets
end

function SubSlotResolver.FindNearestSlot(
	spec: { [string]: any }?,
	cellSize: number,
	localOffset: Vector3,
	facing: string?
): string?
	local lookup = getSlotLookup(spec)
	if not next(lookup) then
		return nil
	end
	local yaw = PlacementHelpers.GetYawFromFacing(facing :: any)
	local inverseYaw = -yaw
	local rotatedOffset = rotateVectorAroundY(localOffset, inverseYaw)

	local nearestId: string? = nil
	local nearestDistance = math.huge
	for _, record in pairs(lookup) do
		local baseOffset = computeBaseOffset(record, cellSize)
		local dx = rotatedOffset.X - baseOffset.X
		local dz = rotatedOffset.Z - baseOffset.Z
		local distance = dx * dx + dz * dz
		if distance < nearestDistance then
			nearestDistance = distance
			nearestId = record.Id
		end
	end

	return nearestId or SubSlotResolver.GetDefaultSlotId(spec)
end

return SubSlotResolver
