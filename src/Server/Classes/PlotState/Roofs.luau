--!strict
-- ServerScriptService/Server/Classes/PlotState/Roofs.lua
local Roofs = {}

type Facing = "North" | "East" | "South" | "West"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local function normalize(value: number?): number
	return tonumber(value) or 1
end

function Roofs.attach(PlotState)
	function PlotState:CanPlaceRoof(
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	): boolean
		local minX, minZ, maxX, maxZ =
			self.Grid:FootprintChunkRange(cellX, cellZ, widthCells, depthCells, facing, self.ChunkSizeInCells)
		for cz = minZ, maxZ do
			for cx = minX, maxX do
				if not self:IsChunkUnlocked(cx, cz) then
					return false
				end
			end
		end

		local indices = self.Grid:FootprintCells(cellX, cellZ, widthCells, depthCells, facing)
		for i = 1, #indices do
			if self.RoofFilled[indices[i]] then
				return false
			end
		end

		return true
	end

	function PlotState:PlaceRoof(
		objectId: string,
		cellX: number,
		cellZ: number,
		widthCells: number,
		depthCells: number,
		facing: Facing
	): boolean
		if not self:CanPlaceRoof(cellX, cellZ, widthCells, depthCells, facing) then
			return false
		end

		local indices = self.Grid:FootprintCells(cellX, cellZ, widthCells, depthCells, facing)
		for i = 1, #indices do
			self.RoofFilled[indices[i]] = true
		end

		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Roof")
		if self.Save.PlacedObjects[key] then
			for i = 1, #indices do
				self.RoofFilled[indices[i]] = false
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

	function PlotState:RemoveRoof(cellX: number, cellZ: number, width: number, depth: number, facing: Facing)
		local normalizedWidth = normalize(width)
		local normalizedDepth = normalize(depth)
		local indices = self.Grid:FootprintCells(cellX, cellZ, normalizedWidth, normalizedDepth, facing)
		for i = 1, #indices do
			self.RoofFilled[indices[i]] = false
		end

		local key = self:PlacementKeyForType(cellX, cellZ, facing, "Roof")
		local saved = self.Save.PlacedObjects[key]
		if saved then
			local spec = ItemFinder.FindItemById(saved.id)
			assert(spec, ("Unknown catalog item '%s'"):format(saved.id))
			local placementType = spec.PlacementType
			local specWidth = spec.WidthCells
			local specDepth = spec.DepthCells
			local objFacing = saved.facing or "North"
			if
				placementType == "Roof"
				and specWidth == normalizedWidth
				and specDepth == normalizedDepth
				and objFacing == facing
			then
				self.Save.PlacedObjects[key] = nil
			end
		end
	end

	function PlotState:MoveRoof(
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

		if spec.PlacementType ~= "Roof" then
			return false,
				("Item '%s' of type '%s' cannot be moved as roof"):format(itemId, tostring(spec.PlacementType))
		end

		local width = spec.WidthCells or spec.Width or 1
		local depth = spec.DepthCells or spec.Depth or 1

		local fromKey = self:PlacementKeyForType(fromX, fromZ, fromF, "Roof")
		local saved = self.Save.PlacedObjects[fromKey]
		if not saved or saved.id ~= itemId then
			return false, ("Roof '%s' not found at (%d, %d) facing %s"):format(itemId, fromX, fromZ, tostring(fromF))
		end

		local toKey = self:PlacementKeyForType(toX, toZ, toF, "Roof")
		local existing = self.Save.PlacedObjects[toKey]
		if existing and existing ~= saved then
			return false,
				("Destination already holds item '%s' at (%d, %d) facing %s"):format(existing.id, toX, toZ, toF)
		end

		local minChunkX, minChunkZ, maxChunkX, maxChunkZ =
			self.Grid:FootprintChunkRange(toX, toZ, width, depth, toF, self.ChunkSizeInCells)
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

		local okFrom, fromCellsResult = pcall(function()
			return self.Grid:FootprintCells(fromX, fromZ, width, depth, fromF)
		end)
		if not okFrom then
			return false, ("Source footprint invalid: %s"):format(tostring(fromCellsResult))
		end
		local fromCells = fromCellsResult :: { number }

		local okTo, toCellsResult = pcall(function()
			return self.Grid:FootprintCells(toX, toZ, width, depth, toF)
		end)
		if not okTo then
			return false, ("Destination footprint invalid: %s"):format(tostring(toCellsResult))
		end
		local toCells = toCellsResult :: { number }

		local fromCellSet: { [number]: boolean } = {}
		for _, index in fromCells do
			fromCellSet[index] = true
		end

		for _, index in toCells do
			if self.RoofFilled[index] and not fromCellSet[index] then
				local blockX, blockZ = self.Grid:IndexToCell(index)
				return false, ("Roof already placed at (%d, %d)"):format(blockX, blockZ)
			end
		end

		for _, index in fromCells do
			self.RoofFilled[index] = false
		end
		for _, index in toCells do
			self.RoofFilled[index] = true
		end

		self.Save.PlacedObjects[fromKey] = nil
		saved.cellX = toX
		saved.cellZ = toZ
		saved.facing = toF
		self.Save.PlacedObjects[toKey] = saved

		return true, nil
	end

	function PlotState:RotateRoof(itemId: string, fromKey: string, toFacing: Facing): (boolean, string?)
		local desiredFacing: Facing = PlacementKey.NormalizeFacing(toFacing)
		local parseOk, parsedCellX, parsedCellZ, parsedFacing, parsedType = pcall(PlacementKey.ParseWithType, fromKey)
		if not parseOk then
			local parseErr = parsedCellX
			return false, ("Invalid placement key '%s': %s"):format(fromKey, tostring(parseErr))
		end

		local cellX = parsedCellX :: number
		local cellZ = parsedCellZ :: number
		local currentFacing = PlacementKey.NormalizeFacing(parsedFacing :: Facing)
		local keyType = parsedType or "Roof"

		if keyType ~= "Roof" then
			return false, ("Placement key type '%s' does not match Roof rotation"):format(tostring(parsedType))
		end

		local saved = self.Save.PlacedObjects[fromKey]
		if not saved then
			return false, "Roof not found at key"
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

		local allowedFacing = spec.Facing :: { Facing }?
		if allowedFacing and #allowedFacing > 0 and not table.find(allowedFacing, desiredFacing) then
			return false, "Invalid facing for this item"
		end

		return self:MoveRoof(itemId, cellX, cellZ, currentFacing, cellX, cellZ, desiredFacing)
	end
end

return Roofs
