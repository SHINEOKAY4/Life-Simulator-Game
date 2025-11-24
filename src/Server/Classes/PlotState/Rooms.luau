--!strict
-- ServerScriptService/Server/Classes/PlotState/Rooms.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local InsulationConstants = require(ReplicatedStorage.Shared.Configurations.InsulationConstants)
local FloodFillCore = require(ReplicatedStorage.Shared.Utilities.FloodFillCore)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local HVACCore = require(ReplicatedStorage.Shared.Utilities.HVACCore)
local WeatherService = require(ServerScriptService.Server.Services.WeatherService)

local Rooms = {}

local REQUIRED_ROOM_DIM = 5
local REQUIRED_ROOM_CELLS = REQUIRED_ROOM_DIM * REQUIRED_ROOM_DIM
local DEFAULT_TENANT_CAPACITY_PER_ROOM = 1 -- Base occupants per tenant-ready room (gamepasses can override per player)

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

local function computeRoomKey(level: number, minX: number, minZ: number): string
	return ("%d:%d:%d"):format(level, minX, minZ)
end

local function meetsMinimumRoomSize(room: any): boolean
	local width = room.MaxX - room.MinX + 1
	local depth = room.MaxZ - room.MinZ + 1
	return width >= REQUIRED_ROOM_DIM and depth >= REQUIRED_ROOM_DIM and room.CellCount >= REQUIRED_ROOM_CELLS
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
	horizontalEdges: { [number]: boolean },
	verticalEdges: { [number]: boolean }
): boolean
	for x = room.MinX, room.MaxX do
		local northIdx = self:HorizontalEdgeIndex(x, room.MinZ)
		local southIdx = self:HorizontalEdgeIndex(x, room.MaxZ + 1)
		if horizontalEdges[northIdx] ~= false or horizontalEdges[southIdx] ~= false then
			return false
		end
	end
	for z = room.MinZ, room.MaxZ do
		local westIdx = self:VerticalEdgeIndex(room.MinX, z)
		local eastIdx = self:VerticalEdgeIndex(room.MaxX + 1, z)
		if verticalEdges[westIdx] ~= false or verticalEdges[eastIdx] ~= false then
			return false
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
	if limitingDim < REQUIRED_ROOM_DIM then
		return 0
	end
	local segments = math.floor(limitingDim / REQUIRED_ROOM_DIM)
	if segments <= 0 then
		return 0
	end
	-- Each 5-cell band on the limiting axis allows two tenants (two beds).
	return segments * 2
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
	end

	function PlotState:GetRoomsForLevel(yLevel: number?): { Room }
		local level = self:NormalizeLevel(yLevel)
		self.RoomCache = self.RoomCache or {}

		if self.RoomCache[level] then
			return self.RoomCache[level].Rooms
		end

		return self:RecalculateRooms(level)
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

		local floorFilled = self:GetFloorFilledForLevel(level)
		local horizontalEdges = self:GetEdgeFreeHorizontalForLevel(level)
		local verticalEdges = self:GetEdgeFreeVerticalForLevel(level)
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

			local loss = InsulationConstants.BaseWallLoss
			local spec = ItemFinder.FindItemById(saved.id)
			if spec and spec.Tags and table.find(spec.Tags, "Glass") then
				loss = InsulationConstants.GlassWallLoss
			end

			if spec and spec.WallVariant == "Door" then
				loss = InsulationConstants.DoorLoss
			elseif spec and spec.WallVariant == "Window" then
				loss = InsulationConstants.WindowLoss
			end

			return loss
		end

		-- Edge checker function for FloodFillCore
		local function isEdgeBlocked(cx: number, cz: number, direction: string): boolean
			if direction == "North" then
				local edgeIdx = self:HorizontalEdgeIndex(cx, cz)
				return not horizontalEdges[edgeIdx] -- true if wall exists (edge not free)
			elseif direction == "South" then
				local edgeIdx = self:HorizontalEdgeIndex(cx, cz + 1)
				return not horizontalEdges[edgeIdx]
			elseif direction == "West" then
				local edgeIdx = self:VerticalEdgeIndex(cx, cz)
				return not verticalEdges[edgeIdx]
			elseif direction == "East" then
				local edgeIdx = self:VerticalEdgeIndex(cx + 1, cz)
				return not verticalEdges[edgeIdx]
			end
			return true
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

				-- Check all 4 walls
				local directions = {
					{
						facing = "North",
						nx = cx,
						nz = cz - 1,
						edgeCheck = function()
							local edgeIdx = self:HorizontalEdgeIndex(cx, cz)
							return horizontalEdges[edgeIdx]
						end,
					},
					{
						facing = "South",
						nx = cx,
						nz = cz + 1,
						edgeCheck = function()
							local edgeIdx = self:HorizontalEdgeIndex(cx, cz + 1)
							return horizontalEdges[edgeIdx]
						end,
					},
					{
						facing = "West",
						nx = cx - 1,
						nz = cz,
						edgeCheck = function()
							local edgeIdx = self:VerticalEdgeIndex(cx, cz)
							return verticalEdges[edgeIdx]
						end,
					},
					{
						facing = "East",
						nx = cx + 1,
						nz = cz,
						edgeCheck = function()
							local edgeIdx = self:VerticalEdgeIndex(cx + 1, cz)
							return verticalEdges[edgeIdx]
						end,
					},
				}

				for _, dir in ipairs(directions) do
					local neighborX = dir.nx
					local neighborZ = dir.nz
					local isEdgeFree = dir.edgeCheck()

					-- Check if neighbor is within bounds and has floor
					local hasNeighborFloor = neighborX >= 1
						and neighborX <= columns
						and neighborZ >= 1
						and neighborZ <= rows
						and floorFilled[self.Grid:CellToIndex(neighborX, neighborZ)]

					if not isEdgeFree then
						-- Wall exists
						totalHeatLoss += getWallInsulation(cx, cz, dir.facing)
					elseif not hasNeighborFloor then
						-- Edge of floor, open air
						totalHeatLoss += InsulationConstants.OpenAirLoss
					end
					-- If neighbor has floor and edge is free, it's same room - no loss
				end

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
			currentRoom.RoomKey = computeRoomKey(level, currentRoom.MinX, currentRoom.MinZ)
			currentRoom.IsEnclosed = isPerimeterEnclosed(self, currentRoom, horizontalEdges, verticalEdges)
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
					local bedLimitedCapacity = math.min(sizeCapacity, room.BedCount)
					room.TenantCapacity = math.min(bedLimitedCapacity, DEFAULT_TENANT_CAPACITY_PER_ROOM)
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

		-- DEBUG: Print found rooms
		print(string.format("[Rooms] Recalculated level %d. Found %d rooms.", level, #rooms))
		for _, r in ipairs(rooms) do
			print(
				string.format(
					"  Room %d (%s): %dx%d cells (X:%d-%d, Z:%d-%d) Cells=%d Enclosed=%s Bed=%s",
					r.Id,
					r.RoomKey,
					r.WidthCells,
					r.DepthCells,
					r.MinX,
					r.MaxX,
					r.MinZ,
					r.MaxZ,
					r.CellCount,
					tostring(r.IsEnclosed),
					tostring(r.HasBed)
				)
			)
		end

		return rooms
	end
end

return Rooms
