--!strict
-- ServerScriptService/Server/Classes/PlotState/Floors.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local Floors = {}

type Facing = "North" | "East" | "South" | "West"

local function defaultFacing(facing: Facing?): Facing
	return facing or "North"
end

function Floors.attach(PlotState)
	function PlotState:HasFloorUnderFootprint(
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	): boolean
		local indices = self.Grid:FootprintCells(cellX, cellZ, widthCells, depthCells, facing)
		for i = 1, #indices do
			if not self.FloorFilled[indices[i]] then
				return false
			end
		end
		return true
	end

	function PlotState:CanPlaceFloor(
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?
	): boolean
		local w = widthCells or 1
		local d = depthCells or 1
		local f = defaultFacing(facing)

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
		for i = 1, #indices do
			if self.FloorFilled[indices[i]] then
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
		facing: Facing?
	): boolean
		local w = widthCells or 1
		local d = depthCells or 1
		local f = defaultFacing(facing)

		if not self:CanPlaceFloor(cellX, cellZ, w, d, f) then
			return false
		end

		local indices = self.Grid:FootprintCells(cellX, cellZ, w, d, f)
		for i = 1, #indices do
			self.FloorFilled[indices[i]] = true
		end

		local key = self:PlacementKeyForType(cellX, cellZ, f, "Floor")
		if self.Save.PlacedObjects[key] then
			for i = 1, #indices do
				self.FloorFilled[indices[i]] = false
			end
			return false
		end

		self.Save.PlacedObjects[key] = {
			id = id,
			cellX = cellX,
			cellZ = cellZ,
			facing = f,
			Metadata = {
				WidthCells = w,
				DepthCells = d,
			},
		}
		return true
	end

	function PlotState:RemoveFloor(
		cellX: number,
		cellZ: number,
		widthCells: number?,
		depthCells: number?,
		facing: Facing?
	)
		local f = defaultFacing(facing)
		local resolvedWidth = widthCells
		local resolvedDepth = depthCells

		local placementKey = self:PlacementKeyForType(cellX, cellZ, f, "Floor")
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
		for i = 1, #indices do
			self.FloorFilled[indices[i]] = false
		end

		if saved then
			self.Save.PlacedObjects[placementKey] = nil
		end
	end

	function PlotState:MoveFloor(
		itemId: string,
		fromX: number,
		fromZ: number,
		toX: number,
		toZ: number
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
		local fromKey = self:PlacementKeyForType(fromX, fromZ, facing, "Floor")
		local saved = self.Save.PlacedObjects[fromKey]
		if not saved or saved.id ~= itemId then
			return false, ("Floor '%s' not found at (%d, %d)"):format(itemId, fromX, fromZ)
		end

		local metadata = saved.Metadata
		local width = metadata and metadata.WidthCells or spec.WidthCells or spec.Width or 1
		local depth = metadata and metadata.DepthCells or spec.DepthCells or spec.Depth or 1

		local toKey = self:PlacementKeyForType(toX, toZ, facing, "Floor")
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
		for _, index in fromCells do
			fromCellSet[index] = true
		end

		for _, index in toCells do
			if self.FloorFilled[index] and not fromCellSet[index] then
				local blockX, blockZ = self.Grid:IndexToCell(index)
				return false, ("Floor already placed at (%d, %d)"):format(blockX, blockZ)
			end
		end

		for _, index in fromCells do
			self.FloorFilled[index] = false
		end
		for _, index in toCells do
			self.FloorFilled[index] = true
		end

		self.Save.PlacedObjects[fromKey] = nil
		saved.cellX = toX
		saved.cellZ = toZ
		saved.facing = facing
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

		return true, nil
	end

	function PlotState:RotateFloor()
		-- Floors do not have facing, so rotation is a no-op
		return true, nil
	end
end

return Floors
