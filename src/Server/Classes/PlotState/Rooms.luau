--!strict
-- ServerScriptService/Server/Classes/PlotState/Rooms.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local InsulationConstants = require(ReplicatedStorage.Shared.Configurations.InsulationConstants)
local FloodFillCore = require(ReplicatedStorage.Shared.Utilities.FloodFillCore)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local HVACCore = require(ReplicatedStorage.Shared.Utilities.HVACCore)
local RoomCore = require(ReplicatedStorage.Shared.Utilities.RoomCore)
local WeatherService = require(ServerScriptService.Server.Services.WeatherService)
local PlacementPackets = require(ReplicatedStorage.Network.PlacementPackets)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local Rooms = {}

local function hasTag(spec: { [string]: any }?, targetTag: string): boolean
	if not spec then
		return false
	end
	local tags = spec.Tags
	if typeof(tags) ~= "table" then
		return false
	end
	for _, tagName in ipairs(tags) do
		if tagName == targetTag then
			return true
		end
	end
	return false
end

local function meetsMinimumRoomSize(room: any): boolean
	local width = room.MaxX - room.MinX + 1
	local depth = room.MaxZ - room.MinZ + 1
	return width >= RoomCore.MIN_TENANT_ROOM_DIM
		and depth >= RoomCore.MIN_TENANT_ROOM_DIM
		and room.CellCount >= RoomCore.MIN_TENANT_ROOM_CELLS
end

type BedPlacement = {
	PrimaryIndex: number?,
	Indices: { number },
}

local function collectBedPlacements(self: any, level: number): { BedPlacement }
	local placements: { BedPlacement } = {}
	for _, objectData in pairs(self.Save.PlacedObjects) do
		if self:NormalizeLevel(objectData.yLevel) ~= level then
			continue
		end
		local spec = ItemFinder.FindItemById(objectData.id)
		if not hasTag(spec, "Bed") then
			continue
		end
		local metadata = objectData.Metadata
		local width = if metadata
				and typeof(metadata.WidthCells) == "number"
				and metadata.WidthCells > 0
			then metadata.WidthCells
			else (spec and (spec.WidthCells or spec.Width)) or 1
		local depth = if metadata
				and typeof(metadata.DepthCells) == "number"
				and metadata.DepthCells > 0
			then metadata.DepthCells
			else (spec and (spec.DepthCells or spec.Depth)) or 1
		width = math.max(1, math.floor(width + 0.5))
		depth = math.max(1, math.floor(depth + 0.5))
		local facing = objectData.facing or "North"
		local indices = self.Grid:FootprintCells(objectData.cellX, objectData.cellZ, width, depth, facing)
		if #indices > 0 then
			placements[#placements + 1] = {
				PrimaryIndex = indices[1],
				Indices = indices,
			}
		end
	end
	return placements
end

local function buildBedCountsForRooms(
	bedPlacements: { BedPlacement },
	cellMap: { [number]: Room }
): { [number]: number }
	local counts: { [number]: number } = {}
	for _, placement in ipairs(bedPlacements) do
		local room = nil
		if placement.PrimaryIndex then
			room = cellMap[placement.PrimaryIndex]
		end
		if not room then
			for _, cellIndex in ipairs(placement.Indices) do
				room = cellMap[cellIndex]
				if room then
					break
				end
			end
		end
		if room then
			local roomId = room.Id
			counts[roomId] = (counts[roomId] or 0) + 1
		end
	end
	return counts
end

local function isPerimeterEnclosed(
	self: any,
	room: any,
	isEdgeBlocked: (cellX: number, cellZ: number, direction: string) -> boolean,
	columns: number,
	rows: number
): boolean
	local cellSet: { [number]: boolean } = {}
	for _, cellIndex in ipairs(room.Cells) do
		cellSet[cellIndex] = true
	end

	for _, cellIndex in ipairs(room.Cells) do
		local cx = ((cellIndex - 1) % columns) + 1
		local cz = math.floor((cellIndex - 1) / columns) + 1

		local neighbors = {
			{ dir = "North", nx = cx, nz = cz - 1 },
			{ dir = "South", nx = cx, nz = cz + 1 },
			{ dir = "West", nx = cx - 1, nz = cz },
			{ dir = "East", nx = cx + 1, nz = cz },
		}

		for _, neighbor in ipairs(neighbors) do
			local nx = neighbor.nx
			local nz = neighbor.nz
			local neighborIndex: number? = nil
			if nx >= 1 and nx <= columns and nz >= 1 and nz <= rows then
				neighborIndex = self.Grid:CellToIndex(nx, nz)
			end
			if not neighborIndex or not cellSet[neighborIndex] then
				if not isEdgeBlocked(cx, cz, neighbor.dir) then
					warn(
						string.format(
							"[Rooms] Gap for room %s at cell (%d,%d) facing %s -> neighbor (%s,%s)",
							tostring(room.RoomKey or room.Id),
							cx,
							cz,
							neighbor.dir,
							if neighborIndex then tostring(nx) else "out",
							if neighborIndex then tostring(nz) else "of"
						)
					)
					return false
				end
			end
		end
	end

	return true
end

export type Room = {
	Id: number,
	Level: number,
	Cells: { number },
	CellCount: number,
	MinX: number,
	MinZ: number,
	MaxX: number,
	MaxZ: number,
	WidthCells: number,
	DepthCells: number,
	RoomKey: string,
	InsulationScore: number,
	HeatingPower: number,
	CoolingPower: number,
	HeaterTarget: number?,
	CoolerTarget: number?,
	ThermostatTarget: number?,
	CurrentTemperature: number,
	LightingScore: number,
	HasBed: boolean,
	BedCount: number,
	IsEnclosed: boolean,
	IsTenantRoom: boolean,
	TenantCapacity: number,
}

local function calculateRoomCapacity(room: Room): number
	local limitingDim = math.min(room.WidthCells, room.DepthCells)
	-- Must meet minimum room size
	if limitingDim < RoomCore.MIN_TENANT_ROOM_DIM then
		return 0
	end

	-- Scale capacity based on total room area
	-- 32 cells per tenant (8x8 room = 64 cells = 2 tenants)
	local cellCount = room.CellCount
	local capacity = math.floor(cellCount / 32)
	return math.max(1, capacity) -- At least 1 tenant if room meets minimum size
end

type RoomCacheEntry = {
	Rooms: { Room },
	CellMap: { [number]: Room },
}

function Rooms.attach(PlotState: any)
	function PlotState:InvalidateRooms(yLevel: number?)
		local level = self:NormalizeLevel(yLevel)
		if self.RoomCache then
			self.RoomCache[level] = nil
		end

		-- Trigger room recalculation and send to client
		self:RecalculateRooms(level)
	end

	function PlotState:GetRoomsForLevel(yLevel: number?): { Room }
		local level = self:NormalizeLevel(yLevel)
		self.RoomCache = self.RoomCache or {}

		if self.RoomCache[level] then
			return self.RoomCache[level].Rooms
		end

		return self:RecalculateRooms(level)
	end

	-- Send minimal room data to client for replication
	local function sendRoomDataToClient(player: Player?, level: number, rooms: { Room })
		if not player or not player:IsA("Player") then
			return
		end

		local minimalRooms = {}
		for _, room in ipairs(rooms) do
			table.insert(minimalRooms, {
				Id = room.Id,
				RoomKey = room.RoomKey,
				MinCellX = room.MinX,
				MaxCellX = room.MaxX,
				MinCellZ = room.MinZ,
				MaxCellZ = room.MaxZ,
				CellIndices = room.Cells,
				IsEnclosed = room.IsEnclosed,
			})
		end

		PlacementPackets.RoomDataSync:FireClient(player, {
			Level = level,
			Rooms = minimalRooms,
		})
	end

	function PlotState:GetRoomAt(cellX: number, cellZ: number, yLevel: number?): Room?
		local level = self:NormalizeLevel(yLevel)

		-- Ensure cache exists
		if not self.RoomCache or not self.RoomCache[level] then
			self:RecalculateRooms(level)
		end

		local cache = self.RoomCache[level]
		local index = self.Grid:CellToIndex(cellX, cellZ)
		return cache.CellMap[index]
	end

	function PlotState:UpdateRoomStats(yLevel: number?)
		local level = self:NormalizeLevel(yLevel)
		if not self.RoomCache or not self.RoomCache[level] then
			return
		end

		local cache = self.RoomCache[level]
		local rooms = cache.Rooms
		local cellMap = cache.CellMap

		-- Reset stats
		for _, room in ipairs(rooms) do
			room.HeatingPower = 0
			room.CoolingPower = 0
			room.LightingScore = 0
			room.HeaterTarget = nil
			room.CoolerTarget = nil
			room.ThermostatTarget = nil
		end

		-- Re-assign HVAC power to rooms
		for _, objectData in pairs(self.Save.PlacedObjects) do
			if self:NormalizeLevel(objectData.yLevel) == level then
				local spec = ItemFinder.FindItemById(objectData.id)
				if spec then
					local stats = HVACCore.ExtractHVACStats(spec)
					if stats.Heating > 0 or stats.Cooling > 0 or stats.Lighting > 0 then
						if HVACCore.IsObjectActive(spec, objectData) then
							local cellX, cellZ = objectData.cellX, objectData.cellZ
							local pType = objectData.placementType or spec.PlacementType
							if HVACCore.IsWallMounted(pType) then
								cellX, cellZ = HVACCore.GetAdjacentCell(cellX, cellZ, objectData.facing)
							end

							local cellIndex = self.Grid:CellToIndex(cellX, cellZ)
							local room = cellMap[cellIndex]

							if room then
								room.HeatingPower += stats.Heating
								room.CoolingPower += stats.Cooling
								room.LightingScore += stats.Lighting

								if stats.HeaterTarget then
									if not room.HeaterTarget or stats.HeaterTarget > room.HeaterTarget then
										room.HeaterTarget = stats.HeaterTarget
									end
								end

								if stats.CoolerTarget then
									if not room.CoolerTarget or stats.CoolerTarget < room.CoolerTarget then
										room.CoolerTarget = stats.CoolerTarget
									end
								end
							end
						end
					end

					-- Thermostat Logic
					if HVACCore.IsThermostat(spec) then
						local cellX, cellZ = objectData.cellX, objectData.cellZ
						local pType = objectData.placementType or spec.PlacementType
						if HVACCore.IsWallMounted(pType) then
							cellX, cellZ = HVACCore.GetAdjacentCell(cellX, cellZ, objectData.facing)
						end

						local cellIndex = self.Grid:CellToIndex(cellX, cellZ)
						local room = cellMap[cellIndex]

						if room and objectData.Metadata and objectData.Metadata.TargetTemp then
							room.ThermostatTarget = objectData.Metadata.TargetTemp
						end
					end
				end
			end
		end

		-- Apply Thermostat Overrides
		for _, room in ipairs(rooms) do
			if room.ThermostatTarget then
				room.HeaterTarget = room.ThermostatTarget
				room.CoolerTarget = room.ThermostatTarget
			end
		end
	end

	function PlotState:RecalculateRooms(yLevel: number?): { Room }
		local level = self:NormalizeLevel(yLevel)

		local grid = self.Grid
		local columns = grid.Columns
		local rows = grid.Rows

		local baseFloorFilled = self:GetFloorFilledForLevel(level)
		local horizontalEdges = self:GetEdgeFreeHorizontalForLevel(level)
		local verticalEdges = self:GetEdgeFreeVerticalForLevel(level)

		local diagonalFacingDirections = {
			NorthEast = { "North", "East" },
			SouthEast = { "South", "East" },
			SouthWest = { "South", "West" },
			NorthWest = { "North", "West" },
		}

		local oppositeDirection = {
			North = "South",
			South = "North",
			East = "West",
			West = "East",
		}

		local function resolveWallLoss(spec: { [string]: any }?): number
			if not spec then
				return InsulationConstants.BaseWallLoss
			end
			local loss = if hasTag(spec, "Glass")
				then InsulationConstants.GlassWallLoss
				else InsulationConstants.BaseWallLoss
			if spec.WallVariant == "Door" then
				return InsulationConstants.DoorLoss
			elseif spec.WallVariant == "Window" then
				return InsulationConstants.WindowLoss
			end
			return loss
		end

		-- Track diagonal walls by cell so both flood fill and heat loss honor their blocked edges.
		local diagonalHeatLossByCell: { [number]: { [string]: number } } = {}
		for _, saved in pairs(self.Save.PlacedObjects) do
			if typeof(saved) == "table" then
				local savedLevel = self:NormalizeLevel(saved.yLevel)
				if savedLevel == level and typeof(saved.cellX) == "number" and typeof(saved.cellZ) == "number" then
					local resolvedFacing = PlacementKey.NormalizeFacing(saved.facing :: any)
					local directions = diagonalFacingDirections[resolvedFacing :: any]
					if directions then
						local spec = ItemFinder.FindItemById(saved.id)
						local cellIndex = grid:CellToIndex(saved.cellX, saved.cellZ)
						diagonalHeatLossByCell[cellIndex] = diagonalHeatLossByCell[cellIndex] or {}
						local loss = resolveWallLoss(spec)
						for _, direction in ipairs(directions) do
							diagonalHeatLossByCell[cellIndex][direction] = loss
						end
					end
				end
			end
		end

		local floorFilled = baseFloorFilled
		if next(diagonalHeatLossByCell) then
			floorFilled = table.clone(baseFloorFilled)
			-- Diagonal walls consume their anchor cells; exclude them from flood fill to avoid phantom rooms.
			for cellIndex in pairs(diagonalHeatLossByCell) do
				floorFilled[cellIndex] = false
			end
		end

		local function getDiagonalHeatLoss(cellX: number, cellZ: number, direction: string): number?
			if cellX < 1 or cellX > columns or cellZ < 1 or cellZ > rows then
				return nil
			end
			local index = grid:CellToIndex(cellX, cellZ)
			local byDirection = diagonalHeatLossByCell[index]
			if byDirection then
				local loss = byDirection[direction]
				if loss then
					return loss
				end
			end
			-- Treat any adjacency that touches a diagonal wall cell as closed for enclosure checks.
			local neighborX = cellX
			local neighborZ = cellZ
			if direction == "North" then
				neighborZ -= 1
			elseif direction == "South" then
				neighborZ += 1
			elseif direction == "West" then
				neighborX -= 1
			elseif direction == "East" then
				neighborX += 1
			end
			if neighborX < 1 or neighborX > columns or neighborZ < 1 or neighborZ > rows then
				return nil
			end
			local neighborIndex = grid:CellToIndex(neighborX, neighborZ)
			local neighborDirections = diagonalHeatLossByCell[neighborIndex]
			if neighborDirections then
				return neighborDirections[oppositeDirection[direction]]
			end
			return nil
		end

		local function edgeBlockedByDiagonal(cellX: number, cellZ: number, direction: string): boolean
			local index = grid:CellToIndex(cellX, cellZ)
			local byDirection = diagonalHeatLossByCell[index]
			if byDirection and byDirection[direction] then
				return true
			end

			local neighborX = cellX
			local neighborZ = cellZ
			if direction == "North" then
				neighborZ -= 1
			elseif direction == "South" then
				neighborZ += 1
			elseif direction == "West" then
				neighborX -= 1
			elseif direction == "East" then
				neighborX += 1
			end

			if neighborX < 1 or neighborX > columns or neighborZ < 1 or neighborZ > rows then
				return false
			end

			local neighborIndex = grid:CellToIndex(neighborX, neighborZ)
			local neighborDirections = diagonalHeatLossByCell[neighborIndex]
			-- If the neighbor has any diagonal wall, treat the edge as blocked for enclosure purposes
			-- since diagonal wall cells are excluded from flood fill
			if neighborDirections ~= nil then
				return true
			end
			return false
		end

		local bedPlacements = collectBedPlacements(self, level)

		local rooms = {}
		local cellMap = {}
		local roomIdCounter = 0

		-- Helper function for wall heat loss calculation
		local function getWallInsulation(cellX: number, cellZ: number, facing: string): number
			local key = self:PlacementKeyForType(cellX, cellZ, facing, "Wall", level)
			local saved = self.Save.PlacedObjects[key]
			if not saved then
				return InsulationConstants.OpenAirLoss
			end
			local spec = ItemFinder.FindItemById(saved.id)
			return resolveWallLoss(spec)
		end

		-- Edge checker function for FloodFillCore
		local function isEdgeBlocked(cx: number, cz: number, direction: string): boolean
			if direction == "North" then
				local edgeIdx = self:HorizontalEdgeIndex(cx, cz)
				if not horizontalEdges[edgeIdx] then
					return true
				end
			elseif direction == "South" then
				local edgeIdx = self:HorizontalEdgeIndex(cx, cz + 1)
				if not horizontalEdges[edgeIdx] then
					return true
				end
			elseif direction == "West" then
				local edgeIdx = self:VerticalEdgeIndex(cx, cz)
				if not verticalEdges[edgeIdx] then
					return true
				end
			elseif direction == "East" then
				local edgeIdx = self:VerticalEdgeIndex(cx + 1, cz)
				if not verticalEdges[edgeIdx] then
					return true
				end
			end
			return edgeBlockedByDiagonal(cx, cz, direction)
		end

		-- Use FloodFillCore to find all room areas
		local areas = FloodFillCore.FindAllAreas(columns, rows, floorFilled, isEdgeBlocked, nil)

		-- Convert areas to Room objects with heat loss calculation
		for _, area in ipairs(areas) do
			roomIdCounter += 1
			local currentRoom: Room = {
				Id = roomIdCounter,
				Level = level,
				Cells = area.Cells,
				CellCount = area.CellCount,
				MinX = area.MinX,
				MaxX = area.MaxX,
				MinZ = area.MinZ,
				MaxZ = area.MaxZ,
				WidthCells = 0,
				DepthCells = 0,
				RoomKey = "",
				InsulationScore = 0,
				HeatingPower = 0,
				CoolingPower = 0,
				CurrentTemperature = WeatherService.GetCurrentTemperature(),
				LightingScore = 0,
				HeaterTarget = nil,
				CoolerTarget = nil,
				ThermostatTarget = nil,
				HasBed = false,
				BedCount = 0,
				IsEnclosed = false,
				IsTenantRoom = false,
				TenantCapacity = 0,
			}

			-- Map cells to room
			for _, cellIndex in ipairs(area.Cells) do
				cellMap[cellIndex] = currentRoom
			end

			-- Calculate heat loss for this room
			local totalHeatLoss = 0
			for _, cellIndex in ipairs(area.Cells) do
				local cx = ((cellIndex - 1) % columns) + 1
				local cz = math.floor((cellIndex - 1) / columns) + 1

				local function applyEdgeLoss(
					direction: string,
					neighborX: number,
					neighborZ: number,
					hasCardinalWall: boolean
				)
					local neighborHasFloor = neighborX >= 1
						and neighborX <= columns
						and neighborZ >= 1
						and neighborZ <= rows
						and floorFilled[self.Grid:CellToIndex(neighborX, neighborZ)]
					local diagonalLoss = getDiagonalHeatLoss(cx, cz, direction)
					if hasCardinalWall then
						totalHeatLoss += getWallInsulation(cx, cz, direction)
					elseif diagonalLoss then
						totalHeatLoss += diagonalLoss
					elseif not neighborHasFloor then
						totalHeatLoss += InsulationConstants.OpenAirLoss
					end
				end

				applyEdgeLoss("North", cx, cz - 1, not horizontalEdges[self:HorizontalEdgeIndex(cx, cz)])
				applyEdgeLoss("South", cx, cz + 1, not horizontalEdges[self:HorizontalEdgeIndex(cx, cz + 1)])
				applyEdgeLoss("West", cx - 1, cz, not verticalEdges[self:VerticalEdgeIndex(cx, cz)])
				applyEdgeLoss("East", cx + 1, cz, not verticalEdges[self:VerticalEdgeIndex(cx + 1, cz)])

				-- Vertical heat loss (up/down)
				if self:HasFloorAtCell(level + 1, cx, cz) then
					totalHeatLoss += InsulationConstants.FloorLoss
				elseif self:HasRoofCoverage(level, cx, cz) then
					totalHeatLoss += InsulationConstants.RoofLoss
				else
					totalHeatLoss += InsulationConstants.OpenAirLoss
				end
				totalHeatLoss += InsulationConstants.FloorLoss -- Down
			end

			currentRoom.InsulationScore = totalHeatLoss
			local widthCells = currentRoom.MaxX - currentRoom.MinX + 1
			local depthCells = currentRoom.MaxZ - currentRoom.MinZ + 1
			currentRoom.WidthCells = widthCells
			currentRoom.DepthCells = depthCells
			-- Use room ID to guarantee uniqueness across all rooms
			currentRoom.RoomKey = string.format("%d:%d", level, roomIdCounter)
			currentRoom.IsEnclosed = isPerimeterEnclosed(self, currentRoom, isEdgeBlocked, columns, rows)
			table.insert(rooms, currentRoom)
		end

		local bedCountsByRoom = buildBedCountsForRooms(bedPlacements, cellMap)
		for _, room in ipairs(rooms) do
			room.BedCount = bedCountsByRoom[room.Id] or 0
			room.HasBed = room.BedCount > 0
			local meetsMinimum = meetsMinimumRoomSize(room)
			room.IsTenantRoom = meetsMinimum and room.HasBed and room.IsEnclosed
			if room.IsTenantRoom then
				local sizeCapacity = calculateRoomCapacity(room)
				if sizeCapacity > 0 and room.BedCount > 0 then
					-- Capacity scales with room size, limited only by bed count
					room.TenantCapacity = math.min(sizeCapacity, room.BedCount)
				else
					room.TenantCapacity = 0
				end
			else
				room.TenantCapacity = 0
			end
		end

		self.RoomCache = self.RoomCache or {}
		self.RoomCache[level] = {
			Rooms = rooms,
			CellMap = cellMap,
		}

		self:UpdateRoomStats(level)

		-- Send minimal room data to client
		if self.Owner and self.Owner:IsA("Player") then
			sendRoomDataToClient(self.Owner, level, rooms)
		end

		return rooms
	end
end

return Rooms
