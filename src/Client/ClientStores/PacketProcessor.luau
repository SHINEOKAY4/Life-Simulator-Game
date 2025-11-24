--!strict
-- Client/ClientStores/PacketProcessor.luau
-- Centralized packet data normalization and processing

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementBehavior = require(ReplicatedStorage.Shared.Utilities.PlacementBehavior)
local DataNormalization = require(script.Parent.DataNormalization)

local PacketProcessor = {}

type PlacedItemEntry = {
	id: string,
	cellX: number,
	cellZ: number,
	facing: string,
	WidthCells: number,
	DepthCells: number,
	Metadata: any,
	Level: number,
	PlacementType: string,
	PlacementKeyType: string,
}

local function resolveItemDimensions(entry: any, spec: any?): (number, number)
	local entryTable = entry :: any
	local widthCells = entryTable.WidthCells or entryTable.widthCells
	local depthCells = entryTable.DepthCells or entryTable.depthCells
	if not widthCells or widthCells <= 0 then
		widthCells = spec and (spec.WidthCells or spec.Width) or 1
	end
	if not depthCells or depthCells <= 0 then
		depthCells = spec and (spec.DepthCells or spec.Depth) or 1
	end
	return widthCells, depthCells
end

function PacketProcessor.NormalizePlacedItem(entry: any, defaultLevel: number): PlacedItemEntry?
	if not entry or not entry.id then
		return nil
	end

	local facing = entry.facing or "North"
	local spec = ItemFinder.FindItemById(entry.id)
	local metadata = DataNormalization.NormalizeMetadata(entry.Metadata)
	local widthCells, depthCells = resolveItemDimensions(entry, spec)

	local levelValue = entry.Level or entry.level or defaultLevel
	local numericLevel = tonumber(levelValue)
	if numericLevel then
		numericLevel = math.floor(numericLevel + 0.5)
		if numericLevel < defaultLevel then
			numericLevel = defaultLevel
		end
		levelValue = numericLevel
	else
		levelValue = defaultLevel
	end

	local placementType = spec and (spec.PlacementType or spec.Type) or "CellObject"
	local subSlotId = if metadata then metadata.SubSlotId or metadata.subSlotId else nil
	local placementKeyType = PlacementBehavior.getPlacementKeyLabelForSubSlot(spec, subSlotId)

	return {
		id = entry.id,
		cellX = entry.cellX,
		cellZ = entry.cellZ,
		facing = facing,
		WidthCells = widthCells,
		DepthCells = depthCells,
		Metadata = metadata,
		Level = levelValue,
		PlacementType = placementType,
		PlacementKeyType = placementKeyType,
	}
end

function PacketProcessor.GeneratePlacementKey(item: PlacedItemEntry): string
	return PlacementKey.ForPlacementType(item.cellX, item.cellZ, item.facing :: any, item.PlacementKeyType, item.Level)
end

function PacketProcessor.NormalizePlacedItemsArray(items: any, defaultLevel: number): { [string]: PlacedItemEntry }
	local placedMap = {}
	if not items then
		return placedMap
	end

	for _, entry in ipairs(items) do
		local normalized = PacketProcessor.NormalizePlacedItem(entry, defaultLevel)
		if normalized then
			local key = PacketProcessor.GeneratePlacementKey(normalized)
			placedMap[key] = normalized
		end
	end

	return placedMap
end

function PacketProcessor.ApplyPlacementDelta(
	currentPlacedItems: { [string]: any },
	delta: any,
	defaultLevel: number
): (string?, boolean)
	if not delta or not delta.Item then
		return nil, false
	end

	local itemId = delta.Item.ItemId or delta.Item.Id or delta.Item.id
	if not itemId then
		return nil, false
	end

	local facing = delta.Item.Facing or "North"
	local spec = ItemFinder.FindItemById(itemId)
	local placementType = spec and (spec.PlacementType or spec.Type) or "CellObject"

	local metadata = DataNormalization.NormalizeMetadata(delta.Item.Metadata)
	local deltaSubSlotId = delta.Item.SubSlotId or delta.Item.subSlotId
	if typeof(deltaSubSlotId) == "string" and deltaSubSlotId ~= "" then
		if metadata == nil then
			metadata = {}
		end
		metadata.SubSlotId = deltaSubSlotId
	end

	local subSlotId = if metadata then metadata.SubSlotId or metadata.subSlotId else nil
	local placementKeyType = PlacementBehavior.getPlacementKeyLabelForSubSlot(spec, subSlotId)

	local widthCells, depthCells = resolveItemDimensions(delta.Item, spec)

	local levelValue = delta.Item.Level or delta.Item.level or defaultLevel
	local numericLevel = tonumber(levelValue)
	if numericLevel then
		numericLevel = math.floor(numericLevel + 0.5)
		if numericLevel < 0 then
			numericLevel = 0
		end
		levelValue = numericLevel
	else
		levelValue = defaultLevel
	end

	local keyValue = delta.Item.PlacementKey or delta.Item.placementKey
	local key = if typeof(keyValue) == "string" and keyValue ~= ""
		then keyValue
		else PlacementKey.ForPlacementType(
			delta.Item.CellX,
			delta.Item.CellZ,
			facing,
			placementKeyType,
			levelValue
		)

	if delta.Action == "Removed" then
		currentPlacedItems[key] = nil
		return key, true
	end

	if delta.Action ~= "Placed" and delta.Action ~= "Updated" then
		return nil, false
	end

	currentPlacedItems[key] = {
		id = itemId,
		cellX = delta.Item.CellX,
		cellZ = delta.Item.CellZ,
		facing = facing,
		WidthCells = widthCells,
		DepthCells = depthCells,
		Metadata = metadata,
		Level = levelValue,
		PlacementType = placementType,
		PlacementKeyType = placementKeyType,
	}

	return key, true
end

return PacketProcessor
