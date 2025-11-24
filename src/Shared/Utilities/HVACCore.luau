--!strict
-- Unified HVAC & Temperature utilities - single source of truth

local HVACCore = {}

-- Constants
export type FacingOffset = { dx: number, dz: number }

HVACCore.FACING_OFFSETS = {
	North = { dx = 0, dz = -1 } :: FacingOffset,
	South = { dx = 0, dz = 1 } :: FacingOffset,
	East = { dx = 1, dz = 0 } :: FacingOffset,
	West = { dx = -1, dz = 0 } :: FacingOffset,
}

-- Get adjacent cell coordinates based on facing direction
function HVACCore.GetAdjacentCell(cellX: number, cellZ: number, facing: string?): (number, number)
	if not facing then
		return cellX, cellZ
	end

	local offset = HVACCore.FACING_OFFSETS[facing]
	if not offset then
		return cellX, cellZ
	end

	return cellX + offset.dx, cellZ + offset.dz
end

-- Check if object is wall-mounted (needs adjacent cell lookup)
function HVACCore.IsWallMounted(placementType: string?): boolean
	return placementType == "WallMounted" or placementType == "Wall"
end

-- Extract HVAC stats from item spec
export type HVACStats = {
	Heating: number,
	Cooling: number,
	Lighting: number,
	HeaterTarget: number?,
	CoolerTarget: number?,
}

function HVACCore.ExtractHVACStats(spec: any): HVACStats
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

	return {
		Heating = heating,
		Cooling = cooling,
		Lighting = lighting,
		HeaterTarget = heaterTarget,
		CoolerTarget = coolerTarget,
	}
end

-- Check if object is powered and active
function HVACCore.IsObjectActive(spec: any, objectData: any): boolean
	-- Check Power
	local requiresPower = spec.RequiresPower
	local isPowered = objectData.Metadata and objectData.Metadata.IsPowered
	local hasPower = not requiresPower or isPowered

	-- Check Manual Switch
	local isOn = true
	if objectData.Metadata and objectData.Metadata.IsOn ~= nil then
		isOn = objectData.Metadata.IsOn
	end

	return hasPower and isOn
end

-- Check if spec is a thermostat
function HVACCore.IsThermostat(spec: any): boolean
	return spec.Name == "Thermostat" or (spec.Tags and table.find(spec.Tags, "Control"))
end

-- Temperature conversion utilities
function HVACCore.CelsiusToFahrenheit(celsius: number): number
	return (celsius * 9 / 5) + 32
end

function HVACCore.FahrenheitToCelsius(fahrenheit: number): number
	return (fahrenheit - 32) * 5 / 9
end

-- Get color for temperature display
function HVACCore.GetTemperatureColor(tempF: number): Color3
	if tempF < 60 then
		return Color3.fromRGB(150, 200, 255) -- Cold blue
	elseif tempF > 82 then
		return Color3.fromRGB(255, 150, 150) -- Hot red
	else
		return Color3.fromRGB(255, 255, 255) -- Normal white
	end
end

return HVACCore
