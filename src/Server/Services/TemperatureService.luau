--!strict
-- ServerScriptService/Server/Services/TemperatureService.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local Packets = require(ReplicatedStorage.Network.TemperaturePackets)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local HVACCore = require(ReplicatedStorage.Shared.Utilities.HVACCore)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local WeatherService = require(ServerScriptService.Server.Services.WeatherService)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local _InsulationConstants = require(ReplicatedStorage.Shared.Configurations.InsulationConstants)

local TemperatureService = {}

function TemperatureService.Init()
	-- Update temperature every 1 second
	WorldUpdate.Subscribe("TemperatureUpdate", 1.0, function(dt)
		TemperatureService:Update(dt)
	end)

	Packets.SetTargetTemp.OnServerEvent:Connect(function(player, args)
		local plotState = PlotService.GetState(player)
		if not plotState then
			return
		end

		local x = args.X
		local z = args.Z
		local level = args.Level
		local targetTemp = args.TargetTemp

		local foundKey = nil
		local foundObj = nil
		for key, obj in pairs(plotState.Save.PlacedObjects) do
			if obj.cellX == x and obj.cellZ == z and plotState:NormalizeLevel(obj.yLevel) == level then
				local spec = ItemFinder.FindItemById(obj.id)
				if spec and HVACCore.IsThermostat(spec) then
					foundKey = key
					foundObj = obj
					break
				end
			end
		end

		if foundKey then
			local obj = plotState.Save.PlacedObjects[foundKey]
			if not obj.Metadata then
				obj.Metadata = {}
			end
			local metadata = obj.Metadata :: { [string]: any }
			metadata.TargetTemp = targetTemp

			-- Update Model Attribute
			local model = WorldPlacer.GetPlacementModel(player, foundKey)
			if model then
				model:SetAttribute("TargetTemp", targetTemp)
			end

			-- Update Room Target WITHOUT Invalidating Cache (preserves CurrentTemperature)
			local room = plotState:GetRoomAt(x, z, level)

			-- If not found directly, try adjacent based on facing (WallMounted logic)
			if not room and foundObj then
				local adjX, adjZ = HVACCore.GetAdjacentCell(x, z, foundObj.facing)
				room = plotState:GetRoomAt(adjX, adjZ, level)
			end

			if room then
				local r = room :: any
				r.HeaterTarget = targetTemp
				r.CoolerTarget = targetTemp
			end
		end
	end)

	Packets.GetRoomDetails.OnServerInvoke = function(player, args)
		local plotState = PlotService.GetState(player)
		if not plotState then
			return { MinTemp = 20, MaxTemp = 20, CurrentTemp = 20 }
		end

		local x = args.X
		local z = args.Z
		local level = args.Level

		-- Find the object to determine facing if needed
		local foundObj = nil
		for _, obj in pairs(plotState.Save.PlacedObjects) do
			if obj.cellX == x and obj.cellZ == z and plotState:NormalizeLevel(obj.yLevel) == level then
				local spec = ItemFinder.FindItemById(obj.id)
				if spec and HVACCore.IsThermostat(spec) then
					foundObj = obj
					break
				end
			end
		end

		local room = plotState:GetRoomAt(x, z, level)

		-- If not found directly, try adjacent based on facing (WallMounted logic)
		if not room and foundObj then
			local adjX, adjZ = HVACCore.GetAdjacentCell(x, z, foundObj.facing)
			room = plotState:GetRoomAt(adjX, adjZ, level)
		end

		if room then
			local ambient = WeatherService.GetCurrentTemperature()
			local insulation = math.max(room.InsulationScore, 0.01)

			local maxTemp = ambient + (room.HeatingPower / insulation)
			local minTemp = ambient - (room.CoolingPower / insulation)

			return {
				MinTemp = minTemp,
				MaxTemp = maxTemp,
				CurrentTemp = room.CurrentTemperature,
			}
		end

		return { MinTemp = 20, MaxTemp = 20, CurrentTemp = 20 }
	end
end

function TemperatureService:Update(dt: number)
	for _, player in ipairs(Players:GetPlayers()) do
		local plotState = PlotService.GetState(player)
		if plotState then
			-- Get plot model to set attributes on
			local plotIndexValue = player:GetAttribute("OwnedPlotIndex")
			if typeof(plotIndexValue) ~= "number" then
				continue
			end

			local plotModel = PlotFinder.FindPlot(plotIndexValue)
			if not plotModel then
				continue
			end

			local minLevel = plotState.DefaultLevel or 0
			local maxLevel = plotState.MaxFloorLevel or 3

			for level = minLevel, maxLevel do
				local rooms = plotState:GetRoomsForLevel(level)

				for _, room in ipairs(rooms) do
					-- Only track temperature for enclosed rooms (rooms with walls)
					if room.IsEnclosed then
						self:UpdateRoomTemperature(room, dt)

						-- Replicate temperature via plot model attribute using room key
						-- Format: "Temp_<level>_<roomId>" e.g. "Temp_0_1"
						local attributeName = string.format("Temp_%d_%d", level, room.Id)
						plotModel:SetAttribute(attributeName, room.CurrentTemperature)
					end
				end
			end
		end
	end
end

function TemperatureService:UpdateRoomTemperature(room: any, dt: number)
	local ambient = WeatherService.GetCurrentTemperature()
	local insulation = room.InsulationScore
	local heatingCap = room.HeatingPower
	local coolingCap = room.CoolingPower
	local current = room.CurrentTemperature

	-- Physics Constants
	local THERMAL_MASS_PER_CELL = 50 -- Joules/Degree (Arbitrary unit to tune speed)

	-- Clamp InsulationScore (Conductance) to a minimum to avoid perfect insulation
	local conductance = math.max(insulation, 0.05)
	local thermalMass = math.max(room.CellCount, 1) * THERMAL_MASS_PER_CELL

	-- Thermostat Logic (Smart Control)
	local activeHeating = 0
	local activeCooling = 0
	local threshold = 0.5 -- Degrees hysteresis

	-- Calculate heat loss at current temp to determine needed power
	-- Loss = U * (T_in - T_out)
	-- Positive result means heat is leaving the room (Room is hotter than ambient)
	-- Negative result means heat is entering the room (Room is colder than ambient)
	local currentHeatLoss = conductance * (current - ambient)

	if heatingCap > 0 then
		local target = room.HeaterTarget or 21
		if current < target - threshold then
			-- Full power if below threshold
			activeHeating = heatingCap
		elseif current < target + threshold then
			-- Proportional control or maintain
			-- We need to counteract the heat loss to maintain temp
			-- PowerNeeded = Loss
			-- If Loss is positive (heat leaving), we need heat.
			if currentHeatLoss > 0 then
				activeHeating = math.min(heatingCap, currentHeatLoss)
			end
		end
	end

	if coolingCap > 0 then
		local target = room.CoolerTarget or 21
		if current > target + threshold then
			-- Full power
			activeCooling = coolingCap
		elseif current > target - threshold then
			-- Maintain
			-- If Loss is negative (heat entering), we need cooling.
			-- Cooling power is removed energy, so we treat it as positive value in calculation but subtract it
			if currentHeatLoss < 0 then
				-- currentHeatLoss is negative (e.g. -50). We need 50 cooling.
				activeCooling = math.min(coolingCap, -currentHeatLoss)
			end
		end
	end

	local netPower = activeHeating - activeCooling

	-- Physics Update: dT/dt = (Power_in - Power_out) / ThermalMass
	-- Power_in = netPower
	-- Power_out = Conductance * (T_current - T_ambient)

	local heatFlow = netPower - conductance * (current - ambient)
	local deltaTemp = (heatFlow / thermalMass) * dt

	room.CurrentTemperature += deltaTemp
end

return TemperatureService
