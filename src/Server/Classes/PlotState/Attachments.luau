--!strict

type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

local Attachments = {}

local function cloneMetadata(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, entry in pairs(value) do
		copy[key] = cloneMetadata(entry)
	end

	return copy
end

local function validateChunkUnlocked(self, cellX: number, cellZ: number): boolean
	if not self.Grid:IsCellInBounds(cellX, cellZ) then
		return false
	end

	local chunkX, chunkZ = self.Grid:CellToChunk(cellX, cellZ, self.ChunkSizeInCells)
	if not self:IsChunkUnlocked(chunkX, chunkZ) then
		return false
	end

	return true
end

function Attachments.attach(PlotState)
	function PlotState:CanPlaceWallMounted(
		cellX: number,
		cellZ: number,
		facing: Facing,
		yLevel: number?
	): (boolean, string?)
		local level = self:NormalizeLevel(yLevel)
		if not validateChunkUnlocked(self, cellX, cellZ) then
			return false, "Chunk locked"
		end

		local wallKey = self:PlacementKeyForType(cellX, cellZ, facing, "Wall", level)
		if not self.Save.PlacedObjects[wallKey] then
			return false, "No supporting wall"
		end

		return true, nil
	end

	function PlotState:PlaceWallMounted(
		objectId: string,
		cellX: number,
		cellZ: number,
		facing: Facing,
		metadata: { [string]: any }?,
		yLevel: number?
	): (boolean, string?)
		local level = self:NormalizeLevel(yLevel)
		local canPlace, failureReason = self:CanPlaceWallMounted(cellX, cellZ, facing, level)
		if not canPlace then
			return false, failureReason
		end

		local key = self:PlacementKeyForType(cellX, cellZ, facing, "WallMounted", level)
		if self.Save.PlacedObjects[key] ~= nil then
			return false, "Wall already has attachment"
		end

		local clonedMetadata = if metadata then cloneMetadata(metadata) else nil

		self.Save.PlacedObjects[key] = {
			id = objectId,
			cellX = cellX,
			cellZ = cellZ,
			facing = facing,
			yLevel = level,
			Metadata = clonedMetadata,
		}

		return true, nil
	end

	function PlotState:RemoveWallMounted(cellX: number, cellZ: number, facing: Facing, yLevel: number?)
		local level = self:NormalizeLevel(yLevel)
		local key = self:PlacementKeyForType(cellX, cellZ, facing, "WallMounted", level)
		local saved = self.Save.PlacedObjects[key]
		self.Save.PlacedObjects[key] = nil
		return saved
	end

	local function hasCeilingSupport(self, cellX: number, cellZ: number, level: number): boolean
		local cellIndex = self.Grid:CellToIndex(cellX, cellZ)
		if not cellIndex then
			return false
		end
		local roofFilled = self:GetRoofFilledForLevel(level)
		if roofFilled[cellIndex] then
			return true
		end
		local aboveLevel = level + 1
		local maxLevelValue = if typeof(self.MaxLevel) == "number" then self.MaxLevel else aboveLevel
		if aboveLevel <= maxLevelValue then
			local floorFilled = self:GetFloorFilledForLevel(aboveLevel)
			if floorFilled[cellIndex] then
				return true
			end
		end
		return false
	end

	function PlotState:CanPlaceCeilingMounted(
		cellX: number,
		cellZ: number,
		facing: Facing,
		yLevel: number?
	): (boolean, string?)
		local level = self:NormalizeLevel(yLevel)
		if not validateChunkUnlocked(self, cellX, cellZ) then
			return false, "Chunk locked"
		end
		if not self.Grid:IsCellInBounds(cellX, cellZ) then
			return false, "Cell out of bounds"
		end
		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Ceiling", level)
		if self.Save.PlacedObjects[key] then
			return false, "Ceiling already has attachment"
		end
		if not hasCeilingSupport(self, cellX, cellZ, level) then
			return false, "No ceiling to attach to"
		end
		return true, nil
	end

	function PlotState:PlaceCeilingMounted(
		objectId: string,
		cellX: number,
		cellZ: number,
		facing: Facing,
		metadata: { [string]: any }?,
		yLevel: number?
	): (boolean, string?)
		local level = self:NormalizeLevel(yLevel)
		local canPlace, failureReason = self:CanPlaceCeilingMounted(cellX, cellZ, facing, level)
		if not canPlace then
			return false, failureReason
		end
		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Ceiling", level)
		local clonedMetadata = if metadata then cloneMetadata(metadata) else nil
		self.Save.PlacedObjects[key] = {
			id = objectId,
			cellX = cellX,
			cellZ = cellZ,
			facing = facing,
			yLevel = level,
			Metadata = clonedMetadata,
		}
		return true, nil
	end

	function PlotState:RemoveCeilingMounted(cellX: number, cellZ: number, facing: Facing, yLevel: number?)
		local level = self:NormalizeLevel(yLevel)
		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Ceiling", level)
		local saved = self.Save.PlacedObjects[key]
		self.Save.PlacedObjects[key] = nil
		return saved
	end
end

return Attachments
