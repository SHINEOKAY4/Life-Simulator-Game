--!strict
-- ServerScriptService/Server/Classes/PlotState/Rooms.lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local InsulationConstants = require(ReplicatedStorage.Shared.Configurations.InsulationConstants)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
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
					local heating = 0
					local cooling = 0
					local lighting = 0
					local heaterTarget = nil
					local coolerTarget = nil

					if spec.TemperatureConfig then
						local cfg = spec.TemperatureConfig
						local power = cfg.Power or 0
						if cfg.Type == "Heater" then
							heating = power
							heaterTarget = cfg.TargetTemp
						elseif cfg.Type == "Cooler" then
							cooling = power
							coolerTarget = cfg.TargetTemp
						end
					else
						-- Legacy/Fallback
						heating = spec.HeatingPower or (spec.Stats and spec.Stats.HeatingPower) or 0
						cooling = spec.CoolingPower or (spec.Stats and spec.Stats.CoolingPower) or 0
					end

					if spec.LightingConfig then
						lighting = spec.LightingConfig.Brightness or 1
					end

					if heating > 0 or cooling > 0 or lighting > 0 then
						-- Check Power
						local requiresPower = spec.RequiresPower
						local isPowered = objectData.Metadata and objectData.Metadata.IsPowered
						local hasPower = not requiresPower or isPowered

						-- Check Manual Switch
						local isOn = true
						if objectData.Metadata and objectData.Metadata.IsOn ~= nil then
							isOn = objectData.Metadata.IsOn
						end

						if hasPower and isOn then
							local cellIndex = self.Grid:CellToIndex(objectData.cellX, objectData.cellZ)
							local room = cellMap[cellIndex]

							-- Fix: WallMounted objects (like AC) are on the wall cell, which isn't "in" the room.
							-- Check the adjacent cell they are facing.
							local pType = objectData.placementType or spec.PlacementType
							if not room and (pType == "WallMounted" or pType == "Wall") then
								local f = objectData.facing
								local dx, dz = 0, 0
								if f == "North" then
									dz = -1
								elseif f == "South" then
									dz = 1
								elseif f == "East" then
									dx = 1
								elseif f == "West" then
									dx = -1
								end

								if dx ~= 0 or dz ~= 0 then
									local adjIndex = self.Grid:CellToIndex(objectData.cellX + dx, objectData.cellZ + dz)
									room = cellMap[adjIndex]
								end
							end

							if room then
								room.HeatingPower += heating
								room.CoolingPower += cooling
								room.LightingScore += lighting

								if heaterTarget then
									if not room.HeaterTarget or heaterTarget > room.HeaterTarget then
										room.HeaterTarget = heaterTarget
									end
								end

								if coolerTarget then
									if not room.CoolerTarget or coolerTarget < room.CoolerTarget then
										room.CoolerTarget = coolerTarget
									end
								end
							end
						end
					end

					-- Thermostat Logic
					if spec.Name == "Thermostat" or (spec.Tags and table.find(spec.Tags, "Control")) then
						local cellIndex = self.Grid:CellToIndex(objectData.cellX, objectData.cellZ)
						local room = cellMap[cellIndex]

						-- Handle WallMounted logic
						local pType = objectData.placementType or spec.PlacementType
						if not room and (pType == "WallMounted" or pType == "Wall") then
							local f = objectData.facing
							local dx, dz = 0, 0
							if f == "North" then
								dz = -1
							elseif f == "South" then
								dz = 1
							elseif f == "East" then
								dx = 1
							elseif f == "West" then
								dx = -1
							end
							if dx ~= 0 or dz ~= 0 then
								local adjIndex = self.Grid:CellToIndex(objectData.cellX + dx, objectData.cellZ + dz)
								room = cellMap[adjIndex]
							end
						end

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

		local visited = table.create(columns * rows, false)
		local rooms = {}
		local cellMap = {}

		local function getCellIndex(x: number, z: number)
			return (z - 1) * columns + x
		end

		local function getWallInsulation(cellX, cellZ, facing)
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

			-- Check for windows/doors (WallMounted objects)
			-- This is expensive if we iterate all objects.
			-- Optimization: WallMounted objects should be indexed by parent wall?
			-- Currently they are just PlacedObjects with "WallMounted" type.
			-- But they don't link to the wall explicitly in Save data structure (except maybe visually).
			-- Actually, WallMounted objects have a PlacementKey that matches the wall's location?
			-- No, WallMounted usually have their own position.
			-- Let's assume for V1 we just check the wall material.
			-- If we want to check windows, we need to know if there is a window at this location.
			-- Windows usually replace the wall or attach to it.
			-- If they replace (Door), the wall ID changes.

			if spec and spec.WallVariant == "Door" then
				loss = InsulationConstants.DoorLoss
			elseif spec and spec.WallVariant == "Window" then -- If windows are walls
				loss = InsulationConstants.WindowLoss
			end

			return loss
		end

		local roomIdCounter = 0

		for z = 1, rows do
			for x = 1, columns do
				local cellIndex = getCellIndex(x, z)

				-- Skip if no floor or already visited
				if not floorFilled[cellIndex] or visited[cellIndex] then
					continue
				end

				-- Start new room
				roomIdCounter += 1
				local currentRoom: Room = {
					Id = roomIdCounter,
					Level = level,
					Cells = {},
					CellCount = 0,
					MinX = x,
					MaxX = x,
					MinZ = z,
					MaxZ = z,
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

				local totalHeatLoss = 0
				local queue = { x, z } -- Interleaved x, z for performance (avoid table creation per node)
				local head = 1
				visited[cellIndex] = true

				while head <= #queue do
					local cx = queue[head]
					local cz = queue[head + 1]
					head += 2

					local cIndex = getCellIndex(cx, cz)

					table.insert(currentRoom.Cells, cIndex)
					currentRoom.CellCount += 1
					cellMap[cIndex] = currentRoom

					-- Update bounds
					if cx < currentRoom.MinX then
						currentRoom.MinX = cx
					end
					if cx > currentRoom.MaxX then
						currentRoom.MaxX = cx
					end
					if cz < currentRoom.MinZ then
						currentRoom.MinZ = cz
					end
					if cz > currentRoom.MaxZ then
						currentRoom.MaxZ = cz
					end

					-- Check Neighbors

					-- North (cz - 1)
					if cz > 1 then
						local nIndex = getCellIndex(cx, cz - 1)
						local edgeIdx = self:HorizontalEdgeIndex(cx, cz)
						local isEdgeFree = horizontalEdges[edgeIdx]

						if floorFilled[nIndex] then
							if isEdgeFree then
								if not visited[nIndex] then
									visited[nIndex] = true
									table.insert(queue, cx)
									table.insert(queue, cz - 1)
								end
							else
								-- Wall between rooms
								totalHeatLoss += getWallInsulation(cx, cz, "North")
							end
						else
							-- Edge of floor
							if not isEdgeFree then
								totalHeatLoss += getWallInsulation(cx, cz, "North")
							else
								totalHeatLoss += InsulationConstants.OpenAirLoss
							end
						end
					else
						-- Edge of grid
						local edgeIdx = self:HorizontalEdgeIndex(cx, cz)
						if not horizontalEdges[edgeIdx] then
							totalHeatLoss += getWallInsulation(cx, cz, "North")
						else
							totalHeatLoss += InsulationConstants.OpenAirLoss
						end
					end

					-- South (cz + 1)
					if cz < rows then
						local sIndex = getCellIndex(cx, cz + 1)
						local edgeIdx = self:HorizontalEdgeIndex(cx, cz + 1)
						local isEdgeFree = horizontalEdges[edgeIdx]

						if floorFilled[sIndex] then
							if isEdgeFree then
								if not visited[sIndex] then
									visited[sIndex] = true
									table.insert(queue, cx)
									table.insert(queue, cz + 1)
								end
							else
								totalHeatLoss += getWallInsulation(cx, cz, "South")
							end
						else
							if not isEdgeFree then
								totalHeatLoss += getWallInsulation(cx, cz, "South")
							else
								totalHeatLoss += InsulationConstants.OpenAirLoss
							end
						end
					else
						local edgeIdx = self:HorizontalEdgeIndex(cx, cz + 1)
						if not horizontalEdges[edgeIdx] then
							totalHeatLoss += getWallInsulation(cx, cz, "South")
						else
							totalHeatLoss += InsulationConstants.OpenAirLoss
						end
					end

					-- West (cx - 1)
					if cx > 1 then
						local wIndex = getCellIndex(cx - 1, cz)
						local edgeIdx = self:VerticalEdgeIndex(cx, cz)
						local isEdgeFree = verticalEdges[edgeIdx]

						if floorFilled[wIndex] then
							if isEdgeFree then
								if not visited[wIndex] then
									visited[wIndex] = true
									table.insert(queue, cx - 1)
									table.insert(queue, cz)
								end
							else
								totalHeatLoss += getWallInsulation(cx, cz, "West")
							end
						else
							if not isEdgeFree then
								totalHeatLoss += getWallInsulation(cx, cz, "West")
							else
								totalHeatLoss += InsulationConstants.OpenAirLoss
							end
						end
					else
						local edgeIdx = self:VerticalEdgeIndex(cx, cz)
						if not verticalEdges[edgeIdx] then
							totalHeatLoss += getWallInsulation(cx, cz, "West")
						else
							totalHeatLoss += InsulationConstants.OpenAirLoss
						end
					end

					-- East (cx + 1)
					if cx < columns then
						local eIndex = getCellIndex(cx + 1, cz)
						local edgeIdx = self:VerticalEdgeIndex(cx + 1, cz)
						local isEdgeFree = verticalEdges[edgeIdx]

						if floorFilled[eIndex] then
							if isEdgeFree then
								if not visited[eIndex] then
									visited[eIndex] = true
									table.insert(queue, cx + 1)
									table.insert(queue, cz)
								end
							else
								totalHeatLoss += getWallInsulation(cx, cz, "East")
							end
						else
							if not isEdgeFree then
								totalHeatLoss += getWallInsulation(cx, cz, "East")
							else
								totalHeatLoss += InsulationConstants.OpenAirLoss
							end
						end
					else
						local edgeIdx = self:VerticalEdgeIndex(cx + 1, cz)
						if not verticalEdges[edgeIdx] then
							totalHeatLoss += getWallInsulation(cx, cz, "East")
						else
							totalHeatLoss += InsulationConstants.OpenAirLoss
						end
					end

					-- Vertical Heat Loss
					-- Up
					if self:HasFloorAtCell(level + 1, cx, cz) then
						totalHeatLoss += InsulationConstants.FloorLoss
					elseif self:HasRoofCoverage(level, cx, cz) then
						totalHeatLoss += InsulationConstants.RoofLoss
					else
						totalHeatLoss += InsulationConstants.OpenAirLoss
					end

					-- Down
					totalHeatLoss += InsulationConstants.FloorLoss

					-- Check for HVAC objects in this cell
					-- Note: We skip HVAC scanning inside this loop for efficiency.
					-- We iterate PlacedObjects separately and assign them to rooms.
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

		return rooms
	end
end

return Rooms
