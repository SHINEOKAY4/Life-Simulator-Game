--!strict
-- ServerScriptService/Server/Classes/PlotState/Floors.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local Floors = {}

type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

local function defaultFacing(facing: Facing?): Facing
	return facing or "North"
end

local function resolveDimension(value: any, fallback: number): number
	if typeof(value) == "number" and value > 0 then
		return math.max(1, math.floor(value + 0.5))
	end
	return fallback
end

local function resolveFootprint(objectData: any, spec: any)
	local metadata = objectData.Metadata
	local width = resolveDimension(
		metadata and metadata.WidthCells,
		resolveDimension(spec and (spec.WidthCells or spec.Width), 1)
	)
	local depth = resolveDimension(
		metadata and metadata.DepthCells,
		resolveDimension(spec and (spec.DepthCells or spec.Depth), 1)
	)
	local facing = defaultFacing(objectData.facing)
	return width, depth, facing
end

local function buildFloorAnchorCache(self: any, level: number)
	local cache: { [number]: string } = {}
	for key, objectData in pairs(self.Save.PlacedObjects) do
		if self:NormalizeLevel(objectData.yLevel) ~= level then
			continue
		end
		local spec = ItemFinder.FindItemById(objectData.id)
		if not spec then
			continue
		end
		local placementType = spec.PlacementType or spec.Type or "CellObject"
		if placementType ~= "Floor" then
			continue
		end
		local width, depth, facing = resolveFootprint(objectData, spec)
		local indices = self.Grid:FootprintCells(objectData.cellX, objectData.cellZ, width, depth, facing)
		for _, index in ipairs(indices) do
			cache[index] = key
		end
	end
	self.FloorAnchorCacheByLevel[level] = cache
	return cache
end

function Floors.attach(PlotState)
	function PlotState:InvalidateFloorAnchors(yLevel: number?)
		if not self.FloorAnchorCacheByLevel then
			return
		end
		if yLevel == nil then
			table.clear(self.FloorAnchorCacheByLevel)
			return
		end
		self.FloorAnchorCacheByLevel[self:NormalizeLevel(yLevel)] = nil
	end

	function PlotState:GetFloorPlacementKey(cellX: number, cellZ: number, yLevel: number?): string?
		local level = self:NormalizeLevel(yLevel)
		self.FloorAnchorCacheByLevel = self.FloorAnchorCacheByLevel or {}
		local cache = self.FloorAnchorCacheByLevel[level]
		if not cache then
			cache = buildFloorAnchorCache(self, level)
		end
		local index = self.Grid:CellToIndex(cellX, cellZ)
		return cache[index]
	end

	function PlotState:HasFloorAtCell(yLevel: number?, cellX: number, cellZ: number): boolean
		local level = self:NormalizeLevel(yLevel)
		local index = self.Grid:CellToIndex(cellX, cellZ)
		local levelFloors = self:GetFloorFilledForLevel(level)
		return levelFloors[index] == true
	end

	function PlotState:HasFloorUnderFootprint(
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?
	): boolean
		local levelFloors = self:GetFloorFilledForLevel(yLevel)
		local indices = self.Grid:FootprintCells(cellX, cellZ, widthCells, depthCells, facing)
		for i = 1, #indices do
			if not levelFloors[indices[i]] then
				return false
			end
		end
		return true
	end

	function PlotState:AnyFloorInFootprint(
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing?,
		yLevel: number?
	): boolean
		local level = self:NormalizeLevel(yLevel)
		local indices = self.Grid:FootprintCells(cellX, cellZ, widthCells, depthCells, defaultFacing(facing))
		local levelFloors = self:GetFloorFilledForLevel(level)
		for i = 1, #indices do
			if levelFloors[indices[i]] then
				return true
			end
		end
		return false
	end

	function PlotState:CanPlaceFloor(
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?,
		yLevel: number?
	): boolean
		local w = widthCells or 1
		local d = depthCells or 1
		local f = defaultFacing(facing)
		local level = self:NormalizeLevel(yLevel)

		if w < 1 or d < 1 then
			return false
		end

		local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
			self.Grid:FootprintBounds(cellX, cellZ, w, d, f)
		if minCellX < 1 or minCellZ < 1 or maxCellX > self.Grid.Columns or maxCellZ > self.Grid.Rows then
			return false
		end

		local minChunkX: number, minChunkZ: number, maxChunkX: number, maxChunkZ: number =
			self.Grid:FootprintChunkRange(cellX, cellZ, w, d, f, self.ChunkSizeInCells)
		for chunkZ = minChunkZ, maxChunkZ do
			for chunkX = minChunkX, maxChunkX do
				if not self:IsChunkUnlocked(chunkX, chunkZ) then
					return false
				end
			end
		end

		local indices = self.Grid:FootprintCells(cellX, cellZ, w, d, f)
		local levelFloors = self:GetFloorFilledForLevel(level)
		for i = 1, #indices do
			local index = indices[i]
			if levelFloors[index] then
				return false
			end
		end

		return true
	end

	function PlotState:PlaceFloor(
		id: string,
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?,
		yLevel: number?,
		metadataOverride: { [string]: any }?
	): boolean
		local w = widthCells or 1
		local d = depthCells or 1
		local f = defaultFacing(facing)
		local level = self:NormalizeLevel(yLevel)

		if not self:CanPlaceFloor(cellX, cellZ, w, d, f, level) then
			return false
		end

		local indices = self.Grid:FootprintCells(cellX, cellZ, w, d, f)
		local levelFloors = self:GetFloorFilledForLevel(level)
		for i = 1, #indices do
			levelFloors[indices[i]] = true
		end

		local key = self:PlacementKeyForType(cellX, cellZ, f, "Floor", level)
		if self.Save.PlacedObjects[key] then
			for i = 1, #indices do
				levelFloors[indices[i]] = false
			end
			return false
		end

		local metadata: { [string]: any }
		if typeof(metadataOverride) == "table" then
			metadata = table.clone(metadataOverride)
		else
			metadata = {}
		end
		if typeof(metadata.WidthCells) ~= "number" then
			metadata.WidthCells = w
		end
		if typeof(metadata.DepthCells) ~= "number" then
			metadata.DepthCells = d
		end

		self.Save.PlacedObjects[key] = {
			id = id,
			cellX = cellX,
			cellZ = cellZ,
			facing = f,
			yLevel = level,
			Metadata = metadata,
		}
		self:InvalidateFloorAnchors(level)
		if self.InvalidateRooms then
			self:InvalidateRooms(level)
		end
		return true
	end

	function PlotState:RemoveFloor(
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?,
		yLevel: number?
	)
		local f = defaultFacing(facing)
		local resolvedWidth = widthCells
		local resolvedDepth = depthCells
		local level = self:NormalizeLevel(yLevel)

		local placementKey = self:PlacementKeyForType(cellX, cellZ, f, "Floor", level)
		local saved = self.Save.PlacedObjects[placementKey]
		local spec = saved and ItemFinder.FindItemById(saved.id) or nil
		local metadata = saved and saved.Metadata or nil

		if spec then
			if metadata and typeof(metadata.WidthCells) == "number" then
				resolvedWidth = resolvedWidth or metadata.WidthCells
			end
			if metadata and typeof(metadata.DepthCells) == "number" then
				resolvedDepth = resolvedDepth or metadata.DepthCells
			end
			resolvedWidth = resolvedWidth or spec.WidthCells or spec.Width or 1
			resolvedDepth = resolvedDepth or spec.DepthCells or spec.Depth or 1
		end

		local w = resolvedWidth or 1
		local d = resolvedDepth or 1
		local indices = self.Grid:FootprintCells(cellX, cellZ, w, d, f)
		local levelFloors = self:GetFloorFilledForLevel(level)
		for i = 1, #indices do
			levelFloors[indices[i]] = false
		end

		if saved then
			self.Save.PlacedObjects[placementKey] = nil
		end
		self:InvalidateFloorAnchors(level)
		if self.InvalidateRooms then
			self:InvalidateRooms(level)
		end
	end

	function PlotState:MoveFloor(
		itemId: string,
		fromX: number,
		fromZ: number,
		toX: number,
		toZ: number,
		fromLevel: number?,
		toLevel: number?
	): (boolean, string?)
		local spec = ItemFinder.FindItemById(itemId)
		if not spec then
			return false, ("Unknown catalog item '%s'"):format(itemId)
		end

		if spec.PlacementType ~= "Floor" then
			return false,
				("Item '%s' of type '%s' cannot be moved as floor"):format(itemId, tostring(spec.PlacementType))
		end

		local facing: Facing = "North"
		local resolvedFromLevel = self:NormalizeLevel(fromLevel)
		local resolvedToLevel = self:NormalizeLevel(toLevel)
		local fromKey = self:PlacementKeyForType(fromX, fromZ, facing, "Floor", resolvedFromLevel)
		local saved = self.Save.PlacedObjects[fromKey]
		if not saved or saved.id ~= itemId then
			return false, ("Floor '%s' not found at (%d, %d)"):format(itemId, fromX, fromZ)
		end

		local metadata = saved.Metadata
		local width = metadata and metadata.WidthCells or spec.WidthCells or spec.Width or 1
		local depth = metadata and metadata.DepthCells or spec.DepthCells or spec.Depth or 1

		local toKey = self:PlacementKeyForType(toX, toZ, facing, "Floor", resolvedToLevel)
		if fromKey == toKey then
			return true, nil
		end

		local existing = self.Save.PlacedObjects[toKey]
		if existing and existing ~= saved then
			return false, ("Destination already holds item '%s' at (%d, %d)"):format(existing.id, toX, toZ)
		end

		local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
			self.Grid:FootprintBounds(toX, toZ, width, depth, facing)
		if minCellX < 1 or minCellZ < 1 or maxCellX > self.Grid.Columns or maxCellZ > self.Grid.Rows then
			return false, "Destination is out of plot bounds"
		end

		local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
			self.Grid:FootprintChunkRange(toX, toZ, width, depth, facing, self.ChunkSizeInCells)
		for cz = minChunkZ, maxChunkZ do
			for cx = minChunkX, maxChunkX do
				if not self:IsChunkInBounds(cx, cz) then
					return false, ("Destination chunk (%d, %d) is outside plot bounds"):format(cx, cz)
				end
				if not self:IsChunkUnlocked(cx, cz) then
					return false, ("Destination chunk (%d, %d) is locked"):format(cx, cz)
				end
			end
		end

		local okFrom, fromCellsResult = pcall(self.Grid.FootprintCells, self.Grid, fromX, fromZ, width, depth, facing)
		if not okFrom then
			return false, ("Source footprint invalid: %s"):format(tostring(fromCellsResult))
		end
		local fromCells = fromCellsResult :: { number }

		local okTo, toCellsResult = pcall(self.Grid.FootprintCells, self.Grid, toX, toZ, width, depth, facing)
		if not okTo then
			return false, ("Destination footprint invalid: %s"):format(tostring(toCellsResult))
		end
		local toCells = toCellsResult :: { number }

		local fromCellSet: { [number]: boolean } = {}
		local allowSharedCells = resolvedFromLevel == resolvedToLevel
		if allowSharedCells then
			for _, index in fromCells do
				fromCellSet[index] = true
			end
		end

		local toFloors = self:GetFloorFilledForLevel(resolvedToLevel)
		for _, index in toCells do
			if toFloors[index] and not fromCellSet[index] then
				local blockX, blockZ = self.Grid:IndexToCell(index)
				return false, ("Floor already placed at (%d, %d)"):format(blockX, blockZ)
			end
		end

		local fromFloors = self:GetFloorFilledForLevel(resolvedFromLevel)
		for _, index in fromCells do
			fromFloors[index] = false
		end
		for _, index in toCells do
			toFloors[index] = true
		end

		self.Save.PlacedObjects[fromKey] = nil
		saved.cellX = toX
		saved.cellZ = toZ
		saved.facing = facing
		saved.yLevel = resolvedToLevel
		local savedMetadata = saved.Metadata
		if savedMetadata then
			savedMetadata.WidthCells = width
			savedMetadata.DepthCells = depth
		else
			saved.Metadata = {
				WidthCells = width,
				DepthCells = depth,
			}
		end
		self.Save.PlacedObjects[toKey] = saved
		self:InvalidateFloorAnchors(resolvedFromLevel)
		self:InvalidateFloorAnchors(resolvedToLevel)

		if self.InvalidateRooms then
			self:InvalidateRooms(resolvedFromLevel)
			if resolvedFromLevel ~= resolvedToLevel then
				self:InvalidateRooms(resolvedToLevel)
			end
		end

		return true, nil
	end

	function PlotState:RotateFloor()
		-- Floors do not have facing, so rotation is a no-op
		return true, nil
	end
end

return Floors
