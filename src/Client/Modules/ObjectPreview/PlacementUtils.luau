--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

type Facing = string

export type MoveOriginInfo = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: Facing,
	PlacementType: string,
	WidthCells: number?,
	DepthCells: number?,
	Level: number?,
}

local PlacementUtils = {}

local function resolveDimensions(entry: any, itemSpec: any?): (number?, number?)
	local width = entry.width or entry.Width or entry.widthCells or entry.WidthCells
	local depth = entry.depth or entry.Depth or entry.depthCells or entry.DepthCells

	local metadata = entry.Metadata
	if metadata then
		width = width or metadata.WidthCells or metadata.widthCells or metadata.Width or metadata.width
		depth = depth or metadata.DepthCells or metadata.depthCells or metadata.Depth or metadata.depth
	end

	if itemSpec then
		width = width or itemSpec.WidthCells or itemSpec.Width
		depth = depth or itemSpec.DepthCells or itemSpec.Depth
	end

	return width, depth
end

function PlacementUtils.ResolvePlacementEntry(entry: any): (any?, string, number, number, Facing, number)
	local itemId = entry.id or entry.Id or entry.ItemId
	local itemSpec = if itemId then ItemFinder.FindItemById(itemId) else nil
	local placementType = (itemSpec and (itemSpec.PlacementType or itemSpec.Type)) or "CellObject"

	local width, depth = resolveDimensions(entry, itemSpec)
	local entryFacing: Facing = entry.facing or entry.Facing or "North"
	local entryLevelValue = entry.Level or entry.level or entry.LevelIndex or entry.yLevel
	local entryLevel = 0
	if entryLevelValue ~= nil then
		local numericLevel = tonumber(entryLevelValue)
		if numericLevel then
			if numericLevel < 0 then
				numericLevel = 0
			end
			entryLevel = math.floor(numericLevel + 0.5)
		end
	end

	if placementType == "Floor" then
		width = width or (itemSpec and (itemSpec.WidthCells or itemSpec.Width)) or 1
		depth = depth or (itemSpec and (itemSpec.DepthCells or itemSpec.Depth)) or 1
		entryFacing = "North"
	elseif placementType == "Wall" then
		width, depth = 1, 1
	else
		width = width or (itemSpec and (itemSpec.WidthCells or itemSpec.Width)) or 1
		depth = depth or (itemSpec and (itemSpec.DepthCells or itemSpec.Depth)) or 1
	end

	return itemSpec, placementType, width or 1, depth or 1, entryFacing, entryLevel
end

local function anyCellOverlap(firstCells: { number }, secondCells: { number }): boolean
	for _, firstCellIndex in firstCells do
		for _, secondCellIndex in secondCells do
			if firstCellIndex == secondCellIndex then
				return true
			end
		end
	end
	return false
end

function PlacementUtils.PreviewKindFromItem(
	itemId: string
): "CellObject" | "Floor" | "Wall" | "Roof" | "WallMounted" | "SurfaceMounted"
	local item = ItemFinder.FindItemById(itemId)
	local itemType = item and item.PlacementType or "CellObject"

	if itemType == "Floor" then
		return "Floor"
	elseif itemType == "Wall" then
		return "Wall"
	elseif itemType == "Roof" then
		return "Roof"
	elseif itemType == "WallMounted" then
		return "WallMounted"
	elseif itemType == "SurfaceMounted" then
		return "SurfaceMounted"
	end

	return "CellObject"
end

function PlacementUtils.GetItemFootprintCells(itemId: string): (number, number)
	local item = ItemFinder.FindItemById(itemId)
	local widthCells = item and item.WidthCells or 1
	local depthCells = item and item.DepthCells or 1
	return widthCells, depthCells
end

function PlacementUtils.IsFootprintUnlockedWithChecker(
	grid: any,
	chunkSize: number,
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing,
	isChunkUnlocked: (number, number) -> boolean
): boolean
	local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
		grid:FootprintChunkRange(cellX, cellZ, widthCells, depthCells, facing, chunkSize)
	for chunkZ = minChunkZ, maxChunkZ do
		for chunkX = minChunkX, maxChunkX do
			if not isChunkUnlocked(chunkX, chunkZ) then
				return false
			end
		end
	end
	return true
end

function PlacementUtils.MatchesIgnorePlacement(
	entry: any,
	placementType: string,
	facingValue: Facing,
	ignorePlacement: MoveOriginInfo?
): boolean
	if not ignorePlacement then
		return false
	end

	if placementType ~= ignorePlacement.PlacementType then
		return false
	end

	local normalizedFacing = PlacementKey.NormalizeFacing(facingValue :: any) :: Facing
	local ignoreFacing = PlacementKey.NormalizeFacing(ignorePlacement.Facing :: any) :: Facing
	if normalizedFacing ~= ignoreFacing then
		return false
	end

	if entry.cellX ~= ignorePlacement.CellX or entry.cellZ ~= ignorePlacement.CellZ then
		return false
	end

	local entryLevelValue = entry.Level or entry.level or entry.LevelIndex or entry.yLevel
	local ignoreLevel = ignorePlacement.Level
	if ignoreLevel ~= nil then
		local numericLevel = if entryLevelValue ~= nil then tonumber(entryLevelValue) else nil
		if numericLevel then
			numericLevel = math.floor(numericLevel + 0.5)
		end
		if numericLevel == nil or numericLevel ~= ignoreLevel then
			return false
		end
	end

	local entryId = entry.id or entry.Id or entry.ItemId
	return entryId == ignorePlacement.ItemId
end

function PlacementUtils.PopulateCellMapForType(
	grid: any,
	placed: any,
	placementType: string,
	target: { [number]: boolean },
	ignorePlacement: MoveOriginInfo?,
	activeLevel: number?
): { [number]: boolean }
	table.clear(target)
	if not placed then
		return target
	end

	for _, placedEntry in pairs(placed) do
		local _, entryPlacementType, width, depth, facingValue, entryLevel =
			PlacementUtils.ResolvePlacementEntry(placedEntry)
		if activeLevel ~= nil and entryLevel ~= activeLevel then
			continue
		end
		if placementType == entryPlacementType then
			if
				not PlacementUtils.MatchesIgnorePlacement(placedEntry, entryPlacementType, facingValue, ignorePlacement)
			then
				local cells =
					grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, facingValue)
				for _, cellIndex in cells do
					target[cellIndex] = true
				end
			end
		end
	end

	return target
end

local function shouldSkipEntry(
	entry: any,
	placementType: string,
	facingValue: Facing,
	ignorePlacement: MoveOriginInfo?
): boolean
	return PlacementUtils.MatchesIgnorePlacement(entry, placementType, facingValue, ignorePlacement)
end

function PlacementUtils.IsCellOccupiedForPreview(
	grid: any,
	previewKind: "CellObject" | "Floor" | "Roof" | "WallMounted" | "SurfaceMounted",
	cellX: number,
	cellZ: number,
	baseWidthCells: number,
	baseDepthCells: number,
	facing: Facing,
	placed: any,
	ignorePlacement: MoveOriginInfo?,
	activeLevel: number?
): boolean
	if not placed or next(placed) == nil then
		return false
	end

	local footprintFacing = if previewKind == "Floor" then "North" else facing
	local myCells = grid:ClippedFootprintCells(cellX, cellZ, baseWidthCells, baseDepthCells, footprintFacing)

	for _, placedEntry in pairs(placed) do
		local _, placementType, width, depth, facingValue, entryLevel =
			PlacementUtils.ResolvePlacementEntry(placedEntry)
		if activeLevel ~= nil and entryLevel ~= activeLevel then
			continue
		end
		if previewKind == "Floor" then
			if
				placementType == "Floor"
				and not shouldSkipEntry(placedEntry, placementType, facingValue, ignorePlacement)
			then
				local otherCells =
					grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, "North")
				if anyCellOverlap(myCells, otherCells) then
					return true
				end
			end
		elseif previewKind == "CellObject" then
			if
				placementType == "CellObject"
				and not shouldSkipEntry(placedEntry, placementType, facingValue, ignorePlacement)
			then
				local otherCells =
					grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, facingValue)
				if anyCellOverlap(myCells, otherCells) then
					return true
				end
			end
		elseif previewKind == "WallMounted" then
			if
				placementType == "WallMounted"
				and not shouldSkipEntry(placedEntry, placementType, facingValue, ignorePlacement)
			then
				local otherCells =
					grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, facingValue)
				if anyCellOverlap(myCells, otherCells) then
					return true
				end
			end
		elseif previewKind == "Roof" then
			if
				placementType == "Roof"
				and not shouldSkipEntry(placedEntry, placementType, facingValue, ignorePlacement)
			then
				local otherCells =
					grid:ClippedFootprintCells(placedEntry.cellX, placedEntry.cellZ, width, depth, facingValue)
				if anyCellOverlap(myCells, otherCells) then
					return true
				end
			end
		end
	end

	return false
end

return PlacementUtils
