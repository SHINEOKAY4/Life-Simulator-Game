--!strict
-- ServerScriptService/Server/Classes/PlotState/Walls.lua
local Walls = {}

type Facing = "North" | "East" | "South" | "West"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

function Walls.attach(PlotState)
	local function edgeOfCell(facing: string, cellX: number, cellZ: number): ("Horizontal" | "Vertical", number, number)
		if facing == "North" then
			return "Horizontal", cellX, cellZ
		elseif facing == "South" then
			return "Horizontal", cellX, cellZ + 1
		elseif facing == "West" then
			return "Vertical", cellX, cellZ
		else
			return "Vertical", cellX + 1, cellZ
		end
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

	function PlotState:CanPlaceWall(
		cellX: number,
		cellZ: number,
		facing: Facing,
		requiresFloorOnBothSides: boolean?
	): boolean
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
			if not self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] then
				return false
			end
			if requiresFloorOnBothSides then
				if edgeZ >= 2 and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ - 1)] then
					return false
				end
				if edgeZ <= self.Grid.Rows and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
					return false
				end
			end
		else
			if not self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] then
				return false
			end
			if requiresFloorOnBothSides then
				if edgeX >= 2 and not self.FloorFilled[self.Grid:CellToIndex(edgeX - 1, edgeZ)] then
					return false
				end
				if edgeX <= self.Grid.Columns and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
					return false
				end
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
		requiresFloorOnBothSides: boolean?
	): boolean
		if not self:CanPlaceWall(cellX, cellZ, facing, requiresFloorOnBothSides) then
			return false
		end

		local alignment, edgeX, edgeZ = edgeOfCell(facing, cellX, cellZ)
		if alignment == "Horizontal" then
			self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] = false
		else
			self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] = false
		end

		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Wall")
		if self.Save.PlacedObjects[key] then
			if alignment == "Horizontal" then
				self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] = true
			else
				self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] = true
			end
			return false
		end

		self.Save.PlacedObjects[key] = {
			id = objectId,
			cellX = cellX,
			cellZ = cellZ,
			facing = facing,
		}
		return true
	end

	local function validateFloorRequirement(self, alignment: "Horizontal" | "Vertical", edgeX: number, edgeZ: number)
		if alignment == "Horizontal" then
			if edgeZ >= 2 and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ - 1)] then
				return false
			end
			if edgeZ <= self.Grid.Rows and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
				return false
			end
		else
			if edgeX >= 2 and not self.FloorFilled[self.Grid:CellToIndex(edgeX - 1, edgeZ)] then
				return false
			end
			if edgeX <= self.Grid.Columns and not self.FloorFilled[self.Grid:CellToIndex(edgeX, edgeZ)] then
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
		replaceableTag: string?
	): (string?, string?)
		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Wall")
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
			local alignment, edgeX, edgeZ = edgeOfCell(facing, cellX, cellZ)
			local direction: "Horizontal" | "Vertical" = if alignment == "Horizontal" then "Horizontal" else "Vertical"
			if not validateFloorRequirement(self, direction, edgeX, edgeZ) then
				return nil, "Requires floor on both sides"
			end
		end

		local previousId = saved.id
		saved.id = objectId
		saved.Metadata = saved.Metadata or {}
		saved.Metadata.PreviousId = previousId
		saved.Metadata.ReplaceableTag = replaceableTag
		saved.Metadata.RequiresFloorOnBothSides = requiresFloorOnBothSides == true
		self.Save.PlacedObjects[key] = saved
		return previousId, nil
	end

	function PlotState:RemoveWall(
		cellX: number,
		cellZ: number,
		facing: Facing
	): { removedId: string, restoredId: string? }?
		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Wall")
		local saved = self.Save.PlacedObjects[key]
		if not saved then
			return nil
		end

		local removedId = saved.id
		local metadata = saved.Metadata
		if metadata and metadata.PreviousId then
			saved.id = metadata.PreviousId
			local savedMutable: any = saved
			savedMutable.Metadata = nil
			self.Save.PlacedObjects[key] = saved
			return {
				removedId = removedId,
				restoredId = saved.id,
			}
		end

		local alignment, edgeX, edgeZ = edgeOfCell(facing, cellX, cellZ)
		if alignment == "Horizontal" then
			self.EdgeFreeHorizontal[self:HorizontalEdgeIndex(edgeX, edgeZ)] = true
		else
			self.EdgeFreeVertical[self:VerticalEdgeIndex(edgeX, edgeZ)] = true
		end

		self.Save.PlacedObjects[key] = nil
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
		toF: Facing
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

		local fromKey = self:PlacementKeyForType(fromX, fromZ, fromF, "Wall")
		local saved = self.Save.PlacedObjects[fromKey]
		if not saved or saved.id ~= itemId then
			return false, ("Wall '%s' not found at (%d, %d) facing %s"):format(itemId, fromX, fromZ, tostring(fromF))
		end

		local toKey = self:PlacementKeyForType(toX, toZ, toF, "Wall")
		if fromKey == toKey then
			return true, nil
		end

		local existing = self.Save.PlacedObjects[toKey]
		if existing and existing ~= saved then
			return false,
				("Destination already holds item '%s' at (%d, %d) facing %s"):format(existing.id, toX, toZ, toF)
		end

		local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
			self.Grid:FootprintChunkRange(toX, toZ, 1, 1, toF, self.ChunkSizeInCells)
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

		local toAlignment, toEdgeX, toEdgeZ = edgeOfCell(toF, toX, toZ)
		local targetIsHorizontal = toAlignment == "Horizontal"
		local toIndex: number
		if targetIsHorizontal then
			toIndex = self:HorizontalEdgeIndex(toEdgeX, toEdgeZ)
		else
			toIndex = self:VerticalEdgeIndex(toEdgeX, toEdgeZ)
		end

		if requiresFloor then
			if targetIsHorizontal then
				if toEdgeZ >= 2 and not self.FloorFilled[self.Grid:CellToIndex(toEdgeX, toEdgeZ - 1)] then
					return false, "Requires floor on both sides of wall"
				end
				if toEdgeZ <= self.Grid.Rows and not self.FloorFilled[self.Grid:CellToIndex(toEdgeX, toEdgeZ)] then
					return false, "Requires floor on both sides of wall"
				end
			else
				if toEdgeX >= 2 and not self.FloorFilled[self.Grid:CellToIndex(toEdgeX - 1, toEdgeZ)] then
					return false, "Requires floor on both sides of wall"
				end
				if toEdgeX <= self.Grid.Columns and not self.FloorFilled[self.Grid:CellToIndex(toEdgeX, toEdgeZ)] then
					return false, "Requires floor on both sides of wall"
				end
			end
		end

		local edgeFree
		if targetIsHorizontal then
			edgeFree = self.EdgeFreeHorizontal[toIndex]
		else
			edgeFree = self.EdgeFreeVertical[toIndex]
		end

		if not edgeFree and existing ~= saved then
			return false, "Destination edge is already occupied"
		end

		local fromAlignment, fromEdgeX, fromEdgeZ = edgeOfCell(fromF, fromX, fromZ)
		local fromIndex: number
		if fromAlignment == "Horizontal" then
			fromIndex = self:HorizontalEdgeIndex(fromEdgeX, fromEdgeZ)
			self.EdgeFreeHorizontal[fromIndex] = true
		else
			fromIndex = self:VerticalEdgeIndex(fromEdgeX, fromEdgeZ)
			self.EdgeFreeVertical[fromIndex] = true
		end

		if targetIsHorizontal then
			self.EdgeFreeHorizontal[toIndex] = false
		else
			self.EdgeFreeVertical[toIndex] = false
		end

		self.Save.PlacedObjects[fromKey] = nil
		saved.cellX = toX
		saved.cellZ = toZ
		saved.facing = toF
		self.Save.PlacedObjects[toKey] = saved

		return true, nil
	end

	function PlotState:RotateWall(itemId: string, fromKey: string, toFacing: Facing): (boolean, string?)
		local desiredFacing: Facing = PlacementKey.NormalizeFacing(toFacing)
		local parseOk, parsedCellX, parsedCellZ, parsedFacing, parsedType = pcall(PlacementKey.ParseWithType, fromKey)
		if not parseOk then
			local parseErr = parsedCellX
			return false, ("Invalid placement key '%s': %s"):format(fromKey, tostring(parseErr))
		end

		local cellX = parsedCellX :: number
		local cellZ = parsedCellZ :: number
		local currentFacing = PlacementKey.NormalizeFacing(parsedFacing :: Facing)
		local keyType = parsedType or "Wall"

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

		return self:MoveWall(itemId, cellX, cellZ, currentFacing, cellX, cellZ, desiredFacing)
	end
end

return Walls
