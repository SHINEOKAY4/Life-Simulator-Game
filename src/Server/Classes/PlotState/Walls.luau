--!strict
-- ServerScriptService/Server/Classes/PlotState/Walls.lua
local Walls = {}

type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

type EdgeAlignment = "Horizontal" | "Vertical" | "DiagonalForward" | "DiagonalBackward"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

function Walls.attach(PlotState)
	local function edgeOfCell(facing: string, cellX: number, cellZ: number): (EdgeAlignment, number, number)
		local resolved = PlacementKey.NormalizeFacing(facing :: any)
		if resolved == "North" then
			return "Horizontal", cellX, cellZ
		elseif resolved == "South" then
			return "Horizontal", cellX, cellZ + 1
		elseif resolved == "West" then
			return "Vertical", cellX, cellZ
		elseif resolved == "East" then
			return "Vertical", cellX + 1, cellZ
		elseif resolved == "NorthEast" then
			return "DiagonalForward", cellX, cellZ
		elseif resolved == "NorthWest" then
			return "DiagonalBackward", cellX, cellZ
		end

		error(("Unsupported facing '%s' for wall edge"):format(tostring(facing)))
	end

	function PlotState:EdgeOfCell(cellX: number, cellZ: number, facing: Facing)
		return edgeOfCell(facing, cellX, cellZ)
	end

	function PlotState:HorizontalEdgeIndex(edgeX: number, edgeZ: number): number
		assert(edgeX >= 1 and edgeX <= self.HorizontalEdgeColumns, "Horizontal edge x out of bounds")
		assert(edgeZ >= 1 and edgeZ <= self.HorizontalEdgeRows, "Horizontal edge z out of bounds")
		return (edgeZ - 1) * self.HorizontalEdgeColumns + edgeX
	end

	function PlotState:VerticalEdgeIndex(edgeX: number, edgeZ: number): number
		assert(edgeX >= 1 and edgeX <= self.VerticalEdgeColumns, "Vertical edge x out of bounds")
		assert(edgeZ >= 1 and edgeZ <= self.VerticalEdgeRows, "Vertical edge z out of bounds")
		return (edgeZ - 1) * self.VerticalEdgeColumns + edgeX
	end

	function PlotState:DiagonalForwardEdgeIndex(edgeX: number, edgeZ: number): number
		assert(edgeX >= 1 and edgeX <= self.DiagonalForwardEdgeColumns, "Diagonal forward edge x out of bounds")
		assert(edgeZ >= 1 and edgeZ <= self.DiagonalForwardEdgeRows, "Diagonal forward edge z out of bounds")
		return (edgeZ - 1) * self.DiagonalForwardEdgeColumns + edgeX
	end

	function PlotState:DiagonalBackwardEdgeIndex(edgeX: number, edgeZ: number): number
		assert(edgeX >= 1 and edgeX <= self.DiagonalBackwardEdgeColumns, "Diagonal backward edge x out of bounds")
		assert(edgeZ >= 1 and edgeZ <= self.DiagonalBackwardEdgeRows, "Diagonal backward edge z out of bounds")
		return (edgeZ - 1) * self.DiagonalBackwardEdgeColumns + edgeX
	end

	function PlotState:CanPlaceWall(
		cellX: number,
		cellZ: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?,
		yLevel: number?
	): boolean
		local level = self:NormalizeLevel(yLevel)
		local horizontalEdges = self:GetEdgeFreeHorizontalForLevel(level)
		local verticalEdges = self:GetEdgeFreeVerticalForLevel(level)
		local diagForwardEdges = self:GetEdgeFreeDiagonalForwardForLevel(level)
		local diagBackwardEdges = self:GetEdgeFreeDiagonalBackwardForLevel(level)
		local occupancy = self:GetCellFreeForLevel(level)
		local floorFilled = self:GetFloorFilledForLevel(level)
		local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
			self.Grid:FootprintChunkRange(cellX, cellZ, 1, 1, facing, self.ChunkSizeInCells)

		for checkChunkZ = minChunkZ, maxChunkZ do
			for checkChunkX = minChunkX, maxChunkX do
				if not self:IsChunkUnlocked(checkChunkX, checkChunkZ) then
					return false
				end
			end
		end

		local alignment, edgeX, edgeZ = edgeOfCell(facing, cellX, cellZ)

		if alignment == "Horizontal" then
			if not horizontalEdges[self:HorizontalEdgeIndex(edgeX, edgeZ)] then
				return false
			end
			if requiresFloorOnBothSides then
				if edgeZ >= 2 and not floorFilled[self.Grid:CellToIndex(edgeX, edgeZ - 1)] then
					return false
				end
				if edgeZ <= self.Grid.Rows and not floorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
					return false
				end
			end
		elseif alignment == "Vertical" then
			if not verticalEdges[self:VerticalEdgeIndex(edgeX, edgeZ)] then
				return false
			end
			if requiresFloorOnBothSides then
				if edgeX >= 2 and not floorFilled[self.Grid:CellToIndex(edgeX - 1, edgeZ)] then
					return false
				end
				if edgeX <= self.Grid.Columns and not floorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
					return false
				end
			end
		elseif alignment == "DiagonalForward" then
			if edgeX < 1 or edgeX > self.DiagonalForwardEdgeColumns then
				return false
			end
			if edgeZ < 1 or edgeZ > self.DiagonalForwardEdgeRows then
				return false
			end
			local cellIndex = self.Grid:CellToIndex(cellX, cellZ)
			if not occupancy[cellIndex] then
				return false
			end
			if not diagForwardEdges[self:DiagonalForwardEdgeIndex(edgeX, edgeZ)] then
				return false
			end
			if requiresFloorOnBothSides then
				return false
			end
		elseif alignment == "DiagonalBackward" then
			if edgeX < 1 or edgeX > self.DiagonalBackwardEdgeColumns then
				return false
			end
			if edgeZ < 1 or edgeZ > self.DiagonalBackwardEdgeRows then
				return false
			end
			local cellIndex = self.Grid:CellToIndex(cellX, cellZ)
			if not occupancy[cellIndex] then
				return false
			end
			if not diagBackwardEdges[self:DiagonalBackwardEdgeIndex(edgeX, edgeZ)] then
				return false
			end
			if requiresFloorOnBothSides then
				return false
			end
		end

		return true
	end

	function PlotState:PlaceWall(
		objectId: string,
		cellX: number,
		cellZ: number,
		_widthCells: number,
		_depthCells: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?,
		metadata: { [string]: any }?,
		yLevel: number?
	): boolean
		local resolvedFacing = PlacementKey.NormalizeFacing(facing)
		local level = self:NormalizeLevel(yLevel)
		if not self:CanPlaceWall(cellX, cellZ, resolvedFacing, requiresFloorOnBothSides, level) then
			return false
		end

		local alignment, edgeX, edgeZ = edgeOfCell(resolvedFacing, cellX, cellZ)
		local horizontalEdges = self:GetEdgeFreeHorizontalForLevel(level)
		local verticalEdges = self:GetEdgeFreeVerticalForLevel(level)
		local diagForwardEdges = self:GetEdgeFreeDiagonalForwardForLevel(level)
		local diagBackwardEdges = self:GetEdgeFreeDiagonalBackwardForLevel(level)
		local occupancy = self:GetCellFreeForLevel(level)
		if alignment == "Horizontal" then
			horizontalEdges[self:HorizontalEdgeIndex(edgeX, edgeZ)] = false
		elseif alignment == "Vertical" then
			verticalEdges[self:VerticalEdgeIndex(edgeX, edgeZ)] = false
		elseif alignment == "DiagonalForward" then
			diagForwardEdges[self:DiagonalForwardEdgeIndex(edgeX, edgeZ)] = false
		elseif alignment == "DiagonalBackward" then
			diagBackwardEdges[self:DiagonalBackwardEdgeIndex(edgeX, edgeZ)] = false
		end

		if alignment == "DiagonalForward" or alignment == "DiagonalBackward" then
			occupancy[self.Grid:CellToIndex(cellX, cellZ)] = false
		end

		local key = self:PlacementKeyForType(cellX, cellZ, resolvedFacing, "Wall", level)
		if self.Save.PlacedObjects[key] then
			if alignment == "Horizontal" then
				horizontalEdges[self:HorizontalEdgeIndex(edgeX, edgeZ)] = true
			elseif alignment == "Vertical" then
				verticalEdges[self:VerticalEdgeIndex(edgeX, edgeZ)] = true
			elseif alignment == "DiagonalForward" then
				diagForwardEdges[self:DiagonalForwardEdgeIndex(edgeX, edgeZ)] = true
				occupancy[self.Grid:CellToIndex(cellX, cellZ)] = true
			elseif alignment == "DiagonalBackward" then
				diagBackwardEdges[self:DiagonalBackwardEdgeIndex(edgeX, edgeZ)] = true
				occupancy[self.Grid:CellToIndex(cellX, cellZ)] = true
			end

			if alignment == "DiagonalForward" or alignment == "DiagonalBackward" then
				occupancy[self.Grid:CellToIndex(cellX, cellZ)] = true
			end
			return false
		end

		local metadataCopy = nil
		if typeof(metadata) == "table" then
			metadataCopy = table.clone(metadata)
		end

		self.Save.PlacedObjects[key] = {
			id = objectId,
			cellX = cellX,
			cellZ = cellZ,
			facing = resolvedFacing,
			yLevel = level,
			Metadata = metadataCopy,
		}
		return true
	end

	local function validateFloorRequirement(
		self,
		alignment: "Horizontal" | "Vertical",
		edgeX: number,
		edgeZ: number,
		floorFilled: { [number]: boolean }
	)
		if alignment == "Horizontal" then
			if edgeZ >= 2 and not floorFilled[self.Grid:CellToIndex(edgeX, edgeZ - 1)] then
				return false
			end
			if edgeZ <= self.Grid.Rows and not floorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
				return false
			end
		else
			if edgeX >= 2 and not floorFilled[self.Grid:CellToIndex(edgeX - 1, edgeZ)] then
				return false
			end
			if edgeX <= self.Grid.Columns and not floorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
				return false
			end
		end
		return true
	end

	function PlotState:ReplaceWallSegment(
		objectId: string,
		cellX: number,
		cellZ: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?,
		replaceableTag: string?,
		yLevel: number?
	): (string?, string?)
		local resolvedFacing = PlacementKey.NormalizeFacing(facing)
		local level = self:NormalizeLevel(yLevel)
		local key = self:PlacementKeyForType(cellX, cellZ, resolvedFacing, "Wall", level)
		local saved = self.Save.PlacedObjects[key]
		if not saved then
			return nil, "No existing wall to replace"
		end

		local spec = ItemFinder.FindItemById(saved.id)
		if not spec or spec.PlacementType ~= "Wall" then
			return nil, "Existing item is not replaceable"
		end

		if replaceableTag and not ItemFinder.HasTag(saved.id, replaceableTag) then
			return nil, "Wall cannot host this door"
		end

		if requiresFloorOnBothSides then
			local alignment, edgeX, edgeZ = edgeOfCell(resolvedFacing, cellX, cellZ)
			if alignment == "Horizontal" then
				local floors = self:GetFloorFilledForLevel(level)
				if not validateFloorRequirement(self, "Horizontal", edgeX, edgeZ, floors) then
					return nil, "Requires floor on both sides"
				end
			elseif alignment == "Vertical" then
				local floors = self:GetFloorFilledForLevel(level)
				if not validateFloorRequirement(self, "Vertical", edgeX, edgeZ, floors) then
					return nil, "Requires floor on both sides"
				end
			else
				return nil, "Diagonal walls cannot enforce floor support"
			end
		end

		local previousId = saved.id
		saved.id = objectId
		saved.Metadata = saved.Metadata or {}
		saved.Metadata.PreviousId = previousId
		saved.Metadata.ReplaceableTag = replaceableTag
		saved.Metadata.RequiresFloorOnBothSides = requiresFloorOnBothSides == true
		saved.yLevel = level
		self.Save.PlacedObjects[key] = saved
		return previousId, nil
	end

	function PlotState:RemoveWall(
		cellX: number,
		cellZ: number,
		facing: Facing,
		yLevel: number?
	): { removedId: string, restoredId: string? }?
		local level = self:NormalizeLevel(yLevel)
		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Wall", level)
		local saved = self.Save.PlacedObjects[key]
		if not saved then
			return nil
		end

		local resolvedFacing = PlacementKey.NormalizeFacing(facing)
		local removedId = saved.id
		local metadata = saved.Metadata
		if metadata and metadata.PreviousId then
			saved.id = metadata.PreviousId
			local savedMutable: any = saved
			savedMutable.Metadata = nil
			savedMutable.yLevel = level
			self.Save.PlacedObjects[key] = saved
			return {
				removedId = removedId,
				restoredId = saved.id,
			}
		end

		local alignment, edgeX, edgeZ = edgeOfCell(resolvedFacing, cellX, cellZ)
		local horizontalEdges = self:GetEdgeFreeHorizontalForLevel(level)
		local verticalEdges = self:GetEdgeFreeVerticalForLevel(level)
		local diagForwardEdges = self:GetEdgeFreeDiagonalForwardForLevel(level)
		local diagBackwardEdges = self:GetEdgeFreeDiagonalBackwardForLevel(level)
		local occupancy = self:GetCellFreeForLevel(level)
		if alignment == "Horizontal" then
			horizontalEdges[self:HorizontalEdgeIndex(edgeX, edgeZ)] = true
		elseif alignment == "Vertical" then
			verticalEdges[self:VerticalEdgeIndex(edgeX, edgeZ)] = true
		elseif alignment == "DiagonalForward" then
			diagForwardEdges[self:DiagonalForwardEdgeIndex(edgeX, edgeZ)] = true
		elseif alignment == "DiagonalBackward" then
			diagBackwardEdges[self:DiagonalBackwardEdgeIndex(edgeX, edgeZ)] = true
		end

		self.Save.PlacedObjects[key] = nil
		if alignment == "DiagonalForward" or alignment == "DiagonalBackward" then
			occupancy[self.Grid:CellToIndex(cellX, cellZ)] = true
		end
		return {
			removedId = removedId,
		}
	end

	function PlotState:MoveWall(
		itemId: string,
		fromX: number,
		fromZ: number,
		fromF: Facing,
		toX: number,
		toZ: number,
		toF: Facing,
		fromLevel: number?,
		toLevel: number?
	): (boolean, string?)
		local spec = ItemFinder.FindItemById(itemId)
		if not spec then
			return false, ("Unknown catalog item '%s'"):format(itemId)
		end

		if spec.PlacementType ~= "Wall" then
			return false,
				("Item '%s' of type '%s' cannot be moved as wall"):format(itemId, tostring(spec.PlacementType))
		end

		if spec.RequiresExistingWall == true then
			return false, "Door segments cannot be moved"
		end

		local requiresFloor = spec.RequiresFloorOnBothSides == true

		local resolvedFromFacing = PlacementKey.NormalizeFacing(fromF)
		local resolvedToFacing = PlacementKey.NormalizeFacing(toF)
		local resolvedFromLevel = self:NormalizeLevel(fromLevel)
		local resolvedToLevel = self:NormalizeLevel(toLevel)

		local fromKey = self:PlacementKeyForType(fromX, fromZ, resolvedFromFacing, "Wall", resolvedFromLevel)
		local saved = self.Save.PlacedObjects[fromKey]
		if not saved or saved.id ~= itemId then
			return false, ("Wall '%s' not found at (%d, %d) facing %s"):format(itemId, fromX, fromZ, tostring(fromF))
		end

		local toKey = self:PlacementKeyForType(toX, toZ, resolvedToFacing, "Wall", resolvedToLevel)
		if fromKey == toKey then
			return true, nil
		end

		local existing = self.Save.PlacedObjects[toKey]
		if existing and existing ~= saved then
			return false,
				("Destination already holds item '%s' at (%d, %d) facing %s"):format(
					existing.id,
					toX,
					toZ,
					resolvedToFacing
				)
		end

		local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
			self.Grid:FootprintChunkRange(toX, toZ, 1, 1, resolvedToFacing, self.ChunkSizeInCells)
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

		local toAlignment, toEdgeX, toEdgeZ = edgeOfCell(resolvedToFacing, toX, toZ)
		local toHorizontalEdges = self:GetEdgeFreeHorizontalForLevel(resolvedToLevel)
		local toVerticalEdges = self:GetEdgeFreeVerticalForLevel(resolvedToLevel)
		local toDiagForwardEdges = self:GetEdgeFreeDiagonalForwardForLevel(resolvedToLevel)
		local toDiagBackwardEdges = self:GetEdgeFreeDiagonalBackwardForLevel(resolvedToLevel)
		local toOccupancy = self:GetCellFreeForLevel(resolvedToLevel)
		local toIndex: number
		local targetEdgeFree: boolean
		if toAlignment == "Horizontal" then
			toIndex = self:HorizontalEdgeIndex(toEdgeX, toEdgeZ)
			targetEdgeFree = toHorizontalEdges[toIndex]
		elseif toAlignment == "Vertical" then
			toIndex = self:VerticalEdgeIndex(toEdgeX, toEdgeZ)
			targetEdgeFree = toVerticalEdges[toIndex]
		elseif toAlignment == "DiagonalForward" then
			if toEdgeX < 1 or toEdgeX > self.DiagonalForwardEdgeColumns then
				return false, "Destination diagonal outside bounds"
			end
			if toEdgeZ < 1 or toEdgeZ > self.DiagonalForwardEdgeRows then
				return false, "Destination diagonal outside bounds"
			end
			toIndex = self:DiagonalForwardEdgeIndex(toEdgeX, toEdgeZ)
			targetEdgeFree = toDiagForwardEdges[toIndex]
			if not toOccupancy[self.Grid:CellToIndex(toX, toZ)] then
				return false, "Destination cell is occupied"
			end
		else -- DiagonalBackward
			if toEdgeX < 1 or toEdgeX > self.DiagonalBackwardEdgeColumns then
				return false, "Destination diagonal outside bounds"
			end
			if toEdgeZ < 1 or toEdgeZ > self.DiagonalBackwardEdgeRows then
				return false, "Destination diagonal outside bounds"
			end
			toIndex = self:DiagonalBackwardEdgeIndex(toEdgeX, toEdgeZ)
			targetEdgeFree = toDiagBackwardEdges[toIndex]
			if not toOccupancy[self.Grid:CellToIndex(toX, toZ)] then
				return false, "Destination cell is occupied"
			end
		end

		if requiresFloor then
			local toFloors = self:GetFloorFilledForLevel(resolvedToLevel)
			if toAlignment == "Horizontal" then
				if toEdgeZ >= 2 and not toFloors[self.Grid:CellToIndex(toEdgeX, toEdgeZ - 1)] then
					return false, "Requires floor on both sides of wall"
				end
				if toEdgeZ <= self.Grid.Rows and not toFloors[self.Grid:CellToIndex(toEdgeX, toEdgeZ)] then
					return false, "Requires floor on both sides of wall"
				end
			elseif toAlignment == "Vertical" then
				if toEdgeX >= 2 and not toFloors[self.Grid:CellToIndex(toEdgeX - 1, toEdgeZ)] then
					return false, "Requires floor on both sides of wall"
				end
				if toEdgeX <= self.Grid.Columns and not toFloors[self.Grid:CellToIndex(toEdgeX, toEdgeZ)] then
					return false, "Requires floor on both sides of wall"
				end
			else
				return false, "Requires floor on both sides of wall"
			end
		end

		if not targetEdgeFree and existing ~= saved then
			return false, "Destination edge is already occupied"
		end

		local fromAlignment, fromEdgeX, fromEdgeZ = edgeOfCell(resolvedFromFacing, fromX, fromZ)
		local fromHorizontalEdges = self:GetEdgeFreeHorizontalForLevel(resolvedFromLevel)
		local fromVerticalEdges = self:GetEdgeFreeVerticalForLevel(resolvedFromLevel)
		local fromDiagForwardEdges = self:GetEdgeFreeDiagonalForwardForLevel(resolvedFromLevel)
		local fromDiagBackwardEdges = self:GetEdgeFreeDiagonalBackwardForLevel(resolvedFromLevel)
		local fromOccupancy = self:GetCellFreeForLevel(resolvedFromLevel)
		if fromAlignment == "Horizontal" then
			fromHorizontalEdges[self:HorizontalEdgeIndex(fromEdgeX, fromEdgeZ)] = true
		elseif fromAlignment == "Vertical" then
			fromVerticalEdges[self:VerticalEdgeIndex(fromEdgeX, fromEdgeZ)] = true
		elseif fromAlignment == "DiagonalForward" then
			fromDiagForwardEdges[self:DiagonalForwardEdgeIndex(fromEdgeX, fromEdgeZ)] = true
			fromOccupancy[self.Grid:CellToIndex(fromX, fromZ)] = true
		elseif fromAlignment == "DiagonalBackward" then
			fromDiagBackwardEdges[self:DiagonalBackwardEdgeIndex(fromEdgeX, fromEdgeZ)] = true
			fromOccupancy[self.Grid:CellToIndex(fromX, fromZ)] = true
		end

		if toAlignment == "Horizontal" then
			toHorizontalEdges[toIndex] = false
		elseif toAlignment == "Vertical" then
			toVerticalEdges[toIndex] = false
		elseif toAlignment == "DiagonalForward" then
			toDiagForwardEdges[toIndex] = false
			toOccupancy[self.Grid:CellToIndex(toX, toZ)] = false
		elseif toAlignment == "DiagonalBackward" then
			toDiagBackwardEdges[toIndex] = false
			toOccupancy[self.Grid:CellToIndex(toX, toZ)] = false
		end

		self.Save.PlacedObjects[fromKey] = nil
		saved.cellX = toX
		saved.cellZ = toZ
		saved.facing = resolvedToFacing
		saved.yLevel = resolvedToLevel
		self.Save.PlacedObjects[toKey] = saved

		return true, nil
	end

	function PlotState:RotateWall(itemId: string, fromKey: string, toFacing: Facing): (boolean, string?)
		local desiredFacing: Facing = PlacementKey.NormalizeFacing(toFacing)
		local parseOk, parsedCellX, parsedCellZ, parsedFacing, parsedType, parsedLevel =
			pcall(PlacementKey.ParseWithType, fromKey)
		if not parseOk then
			local parseErr = parsedCellX
			return false, ("Invalid placement key '%s': %s"):format(fromKey, tostring(parseErr))
		end

		local cellX = parsedCellX :: number
		local cellZ = parsedCellZ :: number
		local currentFacing = PlacementKey.NormalizeFacing(parsedFacing :: Facing)
		local keyType = parsedType or "Wall"
		local level = if typeof(parsedLevel) == "number" then parsedLevel else self.DefaultLevel

		if keyType ~= "Wall" then
			return false, ("Placement key type '%s' does not match Wall rotation"):format(tostring(parsedType))
		end

		local saved = self.Save.PlacedObjects[fromKey]
		if not saved then
			return false, "Wall not found at key"
		end

		if saved.id ~= itemId then
			return false, ("Key holds '%s' instead of '%s'"):format(saved.id, itemId)
		end

		if currentFacing == desiredFacing then
			return true, nil
		end

		local spec = ItemFinder.FindItemById(itemId)
		if not spec then
			return false, ("Unknown catalog item '%s'"):format(itemId)
		end

		if spec.RequiresExistingWall == true then
			return false, "Door segments cannot be rotated"
		end

		local allowedFacing = spec.Facing :: { Facing }?
		if allowedFacing and #allowedFacing > 0 and not table.find(allowedFacing, desiredFacing) then
			return false, "Invalid facing for this item"
		end

		return self:MoveWall(itemId, cellX, cellZ, currentFacing, cellX, cellZ, desiredFacing, level, level)
	end
end

return Walls
