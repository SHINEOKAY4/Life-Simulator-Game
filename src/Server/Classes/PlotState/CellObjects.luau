--!strict
-- ServerScriptService/Server/Classes/PlotState/CellObjects.lua

type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementBehavior = require(ReplicatedStorage.Shared.Utilities.PlacementBehavior)
local SubSlotResolver = require(ReplicatedStorage.Shared.Utilities.SubSlotResolver)

type PlacementOptions = {
	PlacementType: string?,
	IgnoreOccupancy: boolean?,
	Metadata: { [string]: any }?,
}

local CellObjects = {}

local function normalizeDimension(value: number?): number
	return tonumber(value) or 1
end

local function resolveFootprintSize(
	spec: { [string]: any }?,
	metadata: { [string]: any }?,
	fallbackWidth: number?,
	fallbackDepth: number?
): (number, number)
	local width = fallbackWidth
	local depth = fallbackDepth
	if typeof(metadata) == "table" then
		width = metadata.WidthCells or metadata.widthCells or metadata.Width or metadata.width or width
		depth = metadata.DepthCells or metadata.depthCells or metadata.Depth or metadata.depth or depth
	end
	if not width and spec then
		width = spec.WidthCells or spec.Width
	end
	if not depth and spec then
		depth = spec.DepthCells or spec.Depth
	end
	return normalizeDimension(width), normalizeDimension(depth)
end

local function buildCellSet(
	grid: any,
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): { [number]: boolean }?
	local ok, indices = pcall(grid.FootprintCells, grid, cellX, cellZ, widthCells, depthCells, facing)
	if not ok then
		return nil
	end
	local set: { [number]: boolean } = {}
	for _, index in indices do
		set[index] = true
	end
	return set
end

local function isOverlayPlacementType(label: string?): boolean
	if typeof(label) ~= "string" then
		return false
	end
	return string.find(label, "Overlay", 1, true) ~= nil
end

local function hasOverlayConflict(
	self,
	objectId: string,
	placementType: string,
	level: number,
	anchorX: number,
	anchorZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing,
	candidateMetadata: { [string]: any }?,
	excludeKey: string?
): boolean
	if not isOverlayPlacementType(placementType) then
		return false
	end

	local candidateSpec = ItemFinder.FindItemById(objectId)
	local candidateUsesSubSlots = candidateSpec ~= nil and SubSlotResolver.UsesSubSlots(candidateSpec)
	local candidateSlotId: string? = nil
	if candidateUsesSubSlots and candidateSpec then
		candidateSlotId = SubSlotResolver.ResolveSavedSlotId(candidateMetadata, candidateSpec)
	end

	local candidateSet = buildCellSet(self.Grid, anchorX, anchorZ, widthCells, depthCells, facing)
	if not candidateSet then
		return false
	end

	for key, saved in pairs(self.Save.PlacedObjects) do
		if key ~= excludeKey and saved and saved.id == objectId and isOverlayPlacementType(saved.placementType) then
			local savedLevel = saved.yLevel or self.DefaultLevel
			if savedLevel == level then
				local savedSpec = ItemFinder.FindItemById(saved.id)
				if savedSpec then
					local savedWidth, savedDepth =
						resolveFootprintSize(savedSpec, saved.Metadata, savedSpec.WidthCells, savedSpec.DepthCells)
					local savedFacing: Facing = PlacementKey.NormalizeFacing((saved.facing or "North") :: any)
					local savedCells =
						buildCellSet(self.Grid, saved.cellX, saved.cellZ, savedWidth, savedDepth, savedFacing)
					if savedCells then
						for index in pairs(candidateSet) do
							if savedCells[index] then
								if
									candidateUsesSubSlots
									and SubSlotResolver.UsesSubSlots(savedSpec)
									and SubSlotResolver.CanItemsShare(candidateSpec, savedSpec)
								then
									local existingSlotId = SubSlotResolver.ResolveSavedSlotId(saved.Metadata, savedSpec)
									if
										candidateSlotId ~= nil
										and existingSlotId ~= nil
										and candidateSlotId ~= existingSlotId
									then
										continue
									end
								end
								return true
							end
						end
					end
				end
			end
		end
	end

	return false
end

function CellObjects.attach(PlotState)
	local function setInteriorEdgesFree(
		self,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		isFree: boolean,
		yLevel: number?
	)
		local normalizedWidth = normalizeDimension(widthCells)
		local normalizedDepth = normalizeDimension(depthCells)
		local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
			self.Grid:FootprintBounds(anchorX, anchorZ, normalizedWidth, normalizedDepth, facing)
		local rotatedWidth = maxCellX - minCellX
		local rotatedDepth = maxCellZ - minCellZ
		local verticalEdges = self:GetEdgeFreeVerticalForLevel(yLevel)
		local horizontalEdges = self:GetEdgeFreeHorizontalForLevel(yLevel)

		if rotatedWidth >= 1 then
			for cellZ = minCellZ, maxCellZ do
				for cellX = minCellX, maxCellX - 1 do
					local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, "East")
					if alignment == "Vertical" then
						verticalEdges[self:VerticalEdgeIndex(edgeX, edgeZ)] = isFree
					end
				end
			end
		end

		if rotatedDepth >= 1 then
			for cellZ = minCellZ, maxCellZ - 1 do
				for cellX = minCellX, maxCellX do
					local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, "South")
					if alignment == "Horizontal" then
						horizontalEdges[self:HorizontalEdgeIndex(edgeX, edgeZ)] = isFree
					end
				end
			end
		end
	end

	-- Tracks edges covered by multi-cell objects so walls cannot slice through them.
	function PlotState:SetFootprintInteriorEdgesFree(
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		isFree: boolean,
		yLevel: number?
	)
		setInteriorEdgesFree(self, anchorX, anchorZ, widthCells, depthCells, facing, isFree, yLevel)
	end

	function PlotState:IsCellBuildable(cellX: number, cellZ: number, yLevel: number?): boolean
		if not self.Grid:IsCellInBounds(cellX, cellZ) then
			return false
		end

		local chunkX, chunkZ = self.Grid:CellToChunk(cellX, cellZ, self.ChunkSizeInCells)
		if not self:IsChunkUnlocked(chunkX, chunkZ) then
			return false
		end

		local occupancy = self:GetCellFreeForLevel(yLevel)
		return occupancy[self.Grid:CellToIndex(cellX, cellZ)] == true
	end

	function PlotState:CanPlace(
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?,
		options: PlacementOptions?
	): boolean
		local ignoreOccupancy = options ~= nil and options.IgnoreOccupancy == true
		local level = self:NormalizeLevel(yLevel)
		local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
			self.Grid:FootprintChunkRange(anchorX, anchorZ, widthCells, depthCells, facing, self.ChunkSizeInCells)
		for chunkZ = minChunkZ, maxChunkZ do
			for chunkX = minChunkX, maxChunkX do
				if not self:IsChunkUnlocked(chunkX, chunkZ) then
					return false
				end
			end
		end

		local cellIndices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
		local occupancy = self:GetCellFreeForLevel(level)
		for i = 1, #cellIndices do
			if not occupancy[cellIndices[i]] and not ignoreOccupancy then
				return false
			end
		end

		local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
			self.Grid:FootprintBounds(anchorX, anchorZ, widthCells, depthCells, facing)
		if not ignoreOccupancy then
			local rotatedWidth = maxCellX - minCellX + 1
			local rotatedDepth = maxCellZ - minCellZ + 1
			local verticalEdges = self:GetEdgeFreeVerticalForLevel(level)
			local horizontalEdges = self:GetEdgeFreeHorizontalForLevel(level)

			if rotatedWidth > 1 then
				for cellZ = minCellZ, maxCellZ do
					for cellX = minCellX, maxCellX - 1 do
						local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, "East")
						if alignment == "Vertical" then
							local edgeIndex = self:VerticalEdgeIndex(edgeX, edgeZ)
							if not verticalEdges[edgeIndex] then
								return false
							end
						end
					end
				end
			end

			if rotatedDepth > 1 then
				for cellZ = minCellZ, maxCellZ - 1 do
					for cellX = minCellX, maxCellX do
						local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, "South")
						if alignment == "Horizontal" then
							local edgeIndex = self:HorizontalEdgeIndex(edgeX, edgeZ)
							if not horizontalEdges[edgeIndex] then
								return false
							end
						end
					end
				end
			end
		end

		return true
	end

	function PlotState:ReserveFootprint(
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?,
		options: PlacementOptions?
	): boolean
		if not self:CanPlace(anchorX, anchorZ, widthCells, depthCells, facing, yLevel, options) then
			return false
		end

		local ignoreOccupancy = options ~= nil and options.IgnoreOccupancy == true
		if ignoreOccupancy then
			return true
		end

		local level = self:NormalizeLevel(yLevel)
		local cellIndices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
		local occupancy = self:GetCellFreeForLevel(level)
		for i = 1, #cellIndices do
			occupancy[cellIndices[i]] = false
		end

		self:SetFootprintInteriorEdgesFree(anchorX, anchorZ, widthCells, depthCells, facing, false, level)

		return true
	end

	function PlotState:FreeFootprint(
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?,
		options: PlacementOptions?
	)
		local ignoreOccupancy = options ~= nil and options.IgnoreOccupancy == true
		if ignoreOccupancy then
			return
		end
		local cellIndices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
		local level = self:NormalizeLevel(yLevel)
		local occupancy = self:GetCellFreeForLevel(level)
		for i = 1, #cellIndices do
			occupancy[cellIndices[i]] = true
		end

		self:SetFootprintInteriorEdgesFree(anchorX, anchorZ, widthCells, depthCells, facing, true, level)
	end

	function PlotState:Place(
		objectId: string,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		yLevel: number?,
		options: PlacementOptions?
	): (boolean, string?)
		local level = self:NormalizeLevel(yLevel)
		local resolvedWidth = normalizeDimension(widthCells)
		local resolvedDepth = normalizeDimension(depthCells)
		if not self:ReserveFootprint(anchorX, anchorZ, resolvedWidth, resolvedDepth, facing, level, options) then
			return false, nil
		end

		local placementType = if options ~= nil and typeof(options.PlacementType) == "string"
			then options.PlacementType :: string
			else "CellObject"
		local candidateMetadata = if options ~= nil then options.Metadata else nil
		local key = self:PlacementKeyForType(anchorX, anchorZ, facing, placementType, level)
		if self.Save.PlacedObjects[key] then
			self:FreeFootprint(anchorX, anchorZ, resolvedWidth, resolvedDepth, facing, level, options)
			return false, nil
		end

		if
			hasOverlayConflict(
				self,
				objectId,
				placementType,
				level,
				anchorX,
				anchorZ,
				resolvedWidth,
				resolvedDepth,
				facing,
				candidateMetadata,
				nil
			)
		then
			self:FreeFootprint(anchorX, anchorZ, resolvedWidth, resolvedDepth, facing, level, options)
			return false, nil
		end

		self.Save.PlacedObjects[key] = {
			id = objectId,
			cellX = anchorX,
			cellZ = anchorZ,
			facing = tostring(facing),
			yLevel = level,
			placementType = placementType,
			Metadata = if candidateMetadata ~= nil then table.clone(candidateMetadata) else nil,
		}
		return true, key
	end

	function PlotState:RemoveCellObject(
		cellX: number,
		cellZ: number,
		width: number,
		depth: number,
		facing: Facing,
		yLevel: number?,
		options: PlacementOptions?
	)
		local placementType = if options ~= nil and typeof(options.PlacementType) == "string"
			then options.PlacementType :: string
			else "CellObject"
		local ignoreOccupancy = options ~= nil and options.IgnoreOccupancy == true
		local normalizedWidth = normalizeDimension(width)
		local normalizedDepth = normalizeDimension(depth)
		if not ignoreOccupancy then
			local indices = self.Grid:FootprintCells(cellX, cellZ, normalizedWidth, normalizedDepth, facing)
			local level = self:NormalizeLevel(yLevel)
			local occupancy = self:GetCellFreeForLevel(level)
			for i = 1, #indices do
				occupancy[indices[i]] = true
			end
			self:SetFootprintInteriorEdgesFree(cellX, cellZ, normalizedWidth, normalizedDepth, facing, true, level)
		end

		local level = self:NormalizeLevel(yLevel)
		local key = self:PlacementKeyForType(cellX, cellZ, facing, placementType, level)
		local saved = self.Save.PlacedObjects[key]
		if saved then
			local spec = ItemFinder.FindItemById(saved.id)
			assert(spec, ("Unknown catalog item '%s'"):format(saved.id))
			local specPlacementType = spec.PlacementType or spec.Type or "CellObject"
			local specWidth = spec.WidthCells
			local specDepth = spec.DepthCells
			local objFacing = saved.facing or "North"
			if
				specPlacementType == "CellObject"
				and saved.cellX == cellX
				and saved.cellZ == cellZ
				and specWidth == normalizedWidth
				and specDepth == normalizedDepth
				and objFacing == facing
				and (saved.yLevel or self.DefaultLevel) == level
			then
				self.Save.PlacedObjects[key] = nil
			end
		end
	end

	function PlotState:MoveCellObject(
		itemId: string,
		fromX: number,
		fromZ: number,
		fromF: Facing,
		toX: number,
		toZ: number,
		toF: Facing,
		fromLevel: number?,
		toLevel: number?,
		options: PlacementOptions?
	): (boolean, string?)
		local spec = ItemFinder.FindItemById(itemId)
		assert(spec, ("Unknown catalog item '%s'"):format(itemId))
		local placementType = spec.PlacementType
		if placementType ~= "CellObject" then
			return false, ("Item '%s' of type '%s' cannot be moved"):format(itemId, placementType)
		end
		local width = normalizeDimension(spec.WidthCells)
		local depth = normalizeDimension(spec.DepthCells)

		local resolvedFromLevel = self:NormalizeLevel(fromLevel)
		local resolvedToLevel = self:NormalizeLevel(toLevel)
		local placementKeyType = if options ~= nil and typeof(options.PlacementType) == "string"
			then options.PlacementType :: string
			else PlacementBehavior.getPlacementKeyLabel(spec)
		local ignoreOccupancy = if options ~= nil and options.IgnoreOccupancy == true
			then true
			else PlacementBehavior.allowsStacking(spec)
		local fromKey = self:PlacementKeyForType(fromX, fromZ, fromF, placementKeyType, resolvedFromLevel)
		local saved = self.Save.PlacedObjects[fromKey]
		if not saved then
			return false, ("No item '%s' found at source (%d, %d) facing %s"):format(itemId, fromX, fromZ, fromF)
		end
		if saved.id ~= itemId then
			return false,
				("Source holds '%s' instead of '%s' at (%d, %d) facing %s"):format(
					saved.id,
					itemId,
					fromX,
					fromZ,
					fromF
				)
		end

		local okFrom, fromCells = pcall(self.Grid.FootprintCells, self.Grid, fromX, fromZ, width, depth, fromF)
		local fromCellsArray: { number }
		if okFrom then
			fromCellsArray = fromCells :: { number }
		else
			return false, ("Source footprint invalid: %s"):format(fromCells)
		end

		local okTo, toCells = pcall(self.Grid.FootprintCells, self.Grid, toX, toZ, width, depth, toF)
		local toCellsArray: { number }
		if okTo then
			toCellsArray = toCells :: { number }
		else
			return false, ("Destination footprint invalid: %s"):format(toCells)
		end

		local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
			self.Grid:FootprintChunkRange(toX, toZ, width, depth, toF, self.ChunkSizeInCells)
		for chunkZ = minChunkZ, maxChunkZ do
			for chunkX = minChunkX, maxChunkX do
				if not self:IsChunkInBounds(chunkX, chunkZ) then
					return false, ("Destination chunk (%d, %d) is outside plot bounds"):format(chunkX, chunkZ)
				end
				if not self:IsChunkUnlocked(chunkX, chunkZ) then
					return false, ("Destination chunk (%d, %d) is locked"):format(chunkX, chunkZ)
				end
			end
		end

		local fromCellSet: { [number]: boolean } = {}
		local allowSharedCells = resolvedFromLevel == resolvedToLevel
		if allowSharedCells then
			for _, index in fromCellsArray do
				fromCellSet[index] = true
			end
		end

		local toOccupancy = self:GetCellFreeForLevel(resolvedToLevel)
		for _, index in toCellsArray do
			if not ignoreOccupancy and not toOccupancy[index] and not fromCellSet[index] then
				local blockX, blockZ = self.Grid:IndexToCell(index)
				return false, ("Cell (%d, %d) is already occupied"):format(blockX, blockZ)
			end
		end

		local toKey = self:PlacementKeyForType(toX, toZ, toF, placementKeyType, resolvedToLevel)
		local existing = self.Save.PlacedObjects[toKey]
		if existing and existing ~= saved then
			return false, ("Destination already has item '%s' at (%d, %d) facing %s"):format(existing.id, toX, toZ, toF)
		end

		if
			hasOverlayConflict(
				self,
				itemId,
				placementKeyType,
				resolvedToLevel,
				toX,
				toZ,
				width,
				depth,
				toF,
				saved.Metadata,
				fromKey
			)
		then
			return false, "Cannot overlap identical overlays"
		end

		local moveOptions: PlacementOptions = {
			IgnoreOccupancy = ignoreOccupancy,
		}
		self:FreeFootprint(fromX, fromZ, width, depth, fromF, resolvedFromLevel, moveOptions)
		if not self:ReserveFootprint(toX, toZ, width, depth, toF, resolvedToLevel, moveOptions) then
			self:ReserveFootprint(fromX, fromZ, width, depth, fromF, resolvedFromLevel, moveOptions)
			return false, "Failed to reserve destination footprint"
		end

		self.Save.PlacedObjects[fromKey] = nil
		saved.cellX = toX
		saved.cellZ = toZ
		saved.facing = tostring(toF)
		saved.yLevel = resolvedToLevel
		saved.placementType = placementKeyType
		toKey = self:PlacementKeyForType(toX, toZ, toF, placementKeyType, resolvedToLevel)
		self.Save.PlacedObjects[toKey] = saved
		return true, nil
	end

	function PlotState:RotateCellObject(itemId: string, fromKey: string, toFacing: Facing): (boolean, string?)
		local targetFacing: Facing = PlacementKey.NormalizeFacing(toFacing)
		local okParse, parsedCellX, parsedCellZ, parsedFacing, parsedType, parsedLevel =
			pcall(PlacementKey.ParseWithType, fromKey)
		if not okParse then
			local parseErr = parsedCellX
			return false, ("Invalid placement key '%s': %s"):format(fromKey, tostring(parseErr))
		end

		local cellX = parsedCellX :: number
		local cellZ = parsedCellZ :: number
		local currentFacing = PlacementKey.NormalizeFacing(parsedFacing :: Facing)
		local keyType = parsedType or "CellObject"
		local level = if typeof(parsedLevel) == "number" then parsedLevel else self.DefaultLevel

		if keyType ~= "CellObject" and keyType ~= "Overlay" then
			return false, ("Placement key type '%s' does not match CellObject rotation"):format(tostring(parsedType))
		end

		local saved = self.Save.PlacedObjects[fromKey]
		if not saved then
			return false, "Item not found at key"
		end

		if saved.id ~= itemId then
			return false, ("Key holds '%s' instead of '%s'"):format(saved.id, itemId)
		end

		if currentFacing == targetFacing then
			return true, nil
		end

		local spec = ItemFinder.FindItemById(itemId)
		if not spec then
			return false, ("Unknown catalog item '%s'"):format(itemId)
		end

		local allowedFacing = spec.Facing :: { Facing }?
		if allowedFacing and #allowedFacing > 0 and not table.find(allowedFacing, targetFacing) then
			return false, "Invalid facing for this item"
		end

		local placementOptions: PlacementOptions = {
			PlacementType = saved.placementType,
			IgnoreOccupancy = PlacementBehavior.allowsStacking(spec),
			Metadata = saved.Metadata,
		}
		return self:MoveCellObject(
			itemId,
			cellX,
			cellZ,
			currentFacing,
			cellX,
			cellZ,
			targetFacing,
			level,
			level,
			placementOptions
		)
	end
end

return CellObjects
