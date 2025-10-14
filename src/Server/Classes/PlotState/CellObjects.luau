--!strict
-- ServerScriptService/Server/Classes/PlotState/CellObjects.lua

type Facing = "North" | "East" | "South" | "West"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local CellObjects = {}

local function normalizeDimension(value: number?): number
	return tonumber(value) or 1
end

function CellObjects.attach(PlotState)
	local function setInteriorEdgesFree(
		self,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing,
		isFree: boolean
	)
		local normalizedWidth = normalizeDimension(widthCells)
		local normalizedDepth = normalizeDimension(depthCells)
		local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
			self.Grid:FootprintBounds(anchorX, anchorZ, normalizedWidth, normalizedDepth, facing)
		local rotatedWidth = maxCellX - minCellX
		local rotatedDepth = maxCellZ - minCellZ

		if rotatedWidth >= 1 then
			for cellZ = minCellZ, maxCellZ do
				for cellX = minCellX, maxCellX - 1 do
					local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, "East")
					if alignment == "Vertical" then
						self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] = isFree
					end
				end
			end
		end

		if rotatedDepth >= 1 then
			for cellZ = minCellZ, maxCellZ - 1 do
				for cellX = minCellX, maxCellX do
					local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, "South")
					if alignment == "Horizontal" then
						self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] = isFree
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
		isFree: boolean
	)
		setInteriorEdgesFree(self, anchorX, anchorZ, widthCells, depthCells, facing, isFree)
	end

	function PlotState:IsCellBuildable(cellX: number, cellZ: number): boolean
		if not self.Grid:IsCellInBounds(cellX, cellZ) then
			return false
		end

		local chunkX, chunkZ = self.Grid:CellToChunk(cellX, cellZ, self.ChunkSizeInCells)
		if not self:IsChunkUnlocked(chunkX, chunkZ) then
			return false
		end

		return self.CellFree[self.Grid:CellToIndex(cellX, cellZ)] == true
	end

	function PlotState:CanPlace(
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	): boolean
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
		for i = 1, #cellIndices do
			if not self.CellFree[cellIndices[i]] then
				return false
			end
		end

		local minCellX: number, minCellZ: number, maxCellX: number, maxCellZ: number =
			self.Grid:FootprintBounds(anchorX, anchorZ, widthCells, depthCells, facing)
		local rotatedWidth = maxCellX - minCellX + 1
		local rotatedDepth = maxCellZ - minCellZ + 1

		if rotatedWidth > 1 then
			for cellZ = minCellZ, maxCellZ do
				for cellX = minCellX, maxCellX - 1 do
					local alignment, edgeX, edgeZ = self:EdgeOfCell(cellX, cellZ, "East")
					if alignment == "Vertical" then
						local edgeIndex = self:VerticalEdgeIndex(edgeX, edgeZ)
						if not self.EdgeFreeVertical[edgeIndex] then
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
						if not self.EdgeFreeHorizontal[edgeIndex] then
							return false
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
		facing: Facing
	): boolean
		if not self:CanPlace(anchorX, anchorZ, widthCells, depthCells, facing) then
			return false
		end

		local cellIndices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
		for i = 1, #cellIndices do
			self.CellFree[cellIndices[i]] = false
		end

		self:SetFootprintInteriorEdgesFree(anchorX, anchorZ, widthCells, depthCells, facing, false)

		return true
	end

	function PlotState:FreeFootprint(
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	)
		local cellIndices = self.Grid:FootprintCells(anchorX, anchorZ, widthCells, depthCells, facing)
		for i = 1, #cellIndices do
			self.CellFree[cellIndices[i]] = true
		end

		self:SetFootprintInteriorEdgesFree(anchorX, anchorZ, widthCells, depthCells, facing, true)
	end

	function PlotState:Place(
		objectId: string,
		anchorX: number,
		anchorZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	): boolean
		if not self:ReserveFootprint(anchorX, anchorZ, widthCells, depthCells, facing) then
			return false
		end

		local key = self:PlacementKeyForType(anchorX, anchorZ, facing, "CellObject")
		if self.Save.PlacedObjects[key] then
			self:FreeFootprint(anchorX, anchorZ, widthCells, depthCells, facing)
			return false
		end

		self.Save.PlacedObjects[key] = {
			id = objectId,
			cellX = anchorX,
			cellZ = anchorZ,
			facing = facing,
		}
		return true, key
	end

	function PlotState:RemoveCellObject(cellX: number, cellZ: number, width: number, depth: number, facing: Facing)
		local normalizedWidth = normalizeDimension(width)
		local normalizedDepth = normalizeDimension(depth)
		local indices = self.Grid:FootprintCells(cellX, cellZ, normalizedWidth, normalizedDepth, facing)
		for i = 1, #indices do
			self.CellFree[indices[i]] = true
		end
		self:SetFootprintInteriorEdgesFree(cellX, cellZ, normalizedWidth, normalizedDepth, facing, true)

		local key = self:PlacementKeyForType(cellX, cellZ, facing, "CellObject")
		local saved = self.Save.PlacedObjects[key]
		if saved then
			local spec = ItemFinder.FindItemById(saved.id)
			assert(spec, ("Unknown catalog item '%s'"):format(saved.id))
			local placementType = spec.PlacementType
			local specWidth = spec.WidthCells
			local specDepth = spec.DepthCells
			local objFacing = saved.facing or "North"
			if
				placementType == "CellObject"
				and saved.cellX == cellX
				and saved.cellZ == cellZ
				and specWidth == normalizedWidth
				and specDepth == normalizedDepth
				and objFacing == facing
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
		toF: Facing
	): (boolean, string?)
		local spec = ItemFinder.FindItemById(itemId)
		assert(spec, ("Unknown catalog item '%s'"):format(itemId))
		local placementType = spec.PlacementType
		if placementType ~= "CellObject" then
			return false, ("Item '%s' of type '%s' cannot be moved"):format(itemId, placementType)
		end
		local width = spec.WidthCells
		local depth = spec.DepthCells

		local fromKey = self:PlacementKeyForType(fromX, fromZ, fromF, "CellObject")
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

		local okFrom, fromCells = pcall(function()
			return self.Grid:FootprintCells(fromX, fromZ, width, depth, fromF)
		end)
		local fromCellsArray: { number }
		if okFrom then
			fromCellsArray = fromCells :: { number }
		else
			return false, ("Source footprint invalid: %s"):format(fromCells)
		end

		local okTo, toCells = pcall(function()
			return self.Grid:FootprintCells(toX, toZ, width, depth, toF)
		end)
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
		for _, index in fromCellsArray do
			fromCellSet[index] = true
		end

		for _, index in toCellsArray do
			if not self.CellFree[index] and not fromCellSet[index] then
				local blockX, blockZ = self.Grid:IndexToCell(index)
				return false, ("Cell (%d, %d) is already occupied"):format(blockX, blockZ)
			end
		end

		local toKey = self:PlacementKeyForType(toX, toZ, toF, "CellObject")
		local existing = self.Save.PlacedObjects[toKey]
		if existing and existing ~= saved then
			return false, ("Destination already has item '%s' at (%d, %d) facing %s"):format(existing.id, toX, toZ, toF)
		end

		self:FreeFootprint(fromX, fromZ, width, depth, fromF)
		if not self:ReserveFootprint(toX, toZ, width, depth, toF) then
			self:ReserveFootprint(fromX, fromZ, width, depth, fromF)
			return false, "Failed to reserve destination footprint"
		end

		self.Save.PlacedObjects[fromKey] = nil
		saved.cellX = toX
		saved.cellZ = toZ
		saved.facing = toF
		self.Save.PlacedObjects[toKey] = saved
		return true, nil
	end

	function PlotState:RotateCellObject(itemId: string, fromKey: string, toFacing: Facing): (boolean, string?)
		local targetFacing: Facing = PlacementKey.NormalizeFacing(toFacing)
		local okParse, parsedCellX, parsedCellZ, parsedFacing, parsedType = pcall(PlacementKey.ParseWithType, fromKey)
		if not okParse then
			local parseErr = parsedCellX
			return false, ("Invalid placement key '%s': %s"):format(fromKey, tostring(parseErr))
		end

		local cellX = parsedCellX :: number
		local cellZ = parsedCellZ :: number
		local currentFacing = PlacementKey.NormalizeFacing(parsedFacing :: Facing)
		local keyType = parsedType or "CellObject"

		if keyType ~= "CellObject" then
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

		return self:MoveCellObject(itemId, cellX, cellZ, currentFacing, cellX, cellZ, targetFacing)
	end
end

return CellObjects
