--!strict
-- ReplicatedStorage/Shared/Utilities/PlacementKey.luau
-- Utility helpers to build and parse placement keys formed from cell coordinates and facing.

type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

local PlacementKey = {}

local DEFAULT_FACING: Facing = "North"
local DEFAULT_LEVEL = 0

local FacingAliases: { [string]: Facing } = {
	North = "North",
	East = "East",
	South = "South",
	West = "West",
	NorthEast = "NorthEast",
	SouthWest = "NorthEast",
	NorthWest = "NorthWest",
	SouthEast = "NorthWest",
}

local function normalizeLevel(level: number?): number
	local numeric = tonumber(level)
	if not numeric then
		return DEFAULT_LEVEL
	end
	numeric = math.floor(numeric + 0.5)
	if numeric < 0 then
		return DEFAULT_LEVEL
	end
	return numeric
end

local function normalizeFacing(facing: Facing?): Facing
	if facing == nil then
		return DEFAULT_FACING
	end

	local mapped = FacingAliases[tostring(facing)]
	if not mapped then
		error(("Invalid facing '%s' in placement key"):format(tostring(facing)))
	end

	return mapped :: Facing
end

local function sanitizePlacementType(label: string?): string
	if not label or label == "" then
		return "Generic"
	end
	return label:gsub(":", "-")
end

function PlacementKey.FromComponents(cellX: number, cellZ: number, facing: Facing?, level: number?): string
	local normalizedLevel = normalizeLevel(level)
	return ("%d:%d:%d:%s"):format(normalizedLevel, cellX, cellZ, normalizeFacing(facing))
end

function PlacementKey.ForPlacementType(
	cellX: number,
	cellZ: number,
	facing: Facing?,
	placementType: string?,
	level: number?
): string
	local normalizedLevel = normalizeLevel(level)
	return ("%d:%d:%d:%s:%s"):format(
		normalizedLevel,
		cellX,
		cellZ,
		normalizeFacing(facing),
		sanitizePlacementType(placementType)
	)
end

function PlacementKey.NormalizeFacing(facing: Facing?): Facing
	return normalizeFacing(facing)
end

local function assertFacing(value: string): Facing
	local mapped = FacingAliases[value]
	if not mapped then
		error(("Invalid facing '%s' in placement key"):format(value))
	end
	return mapped :: Facing
end

function PlacementKey.Parse(key: string): (number, number, Facing, number)
	local levelStr, xStr, zStr, facingStr = string.match(key, "^([^:]+):([^:]+):([^:]+):([^:]+)$")
	local parsedLevel = DEFAULT_LEVEL
	if levelStr and xStr and zStr and facingStr then
		local cellX = tonumber(xStr)
		local cellZ = tonumber(zStr)
		if not cellX or not cellZ then
			error(("Invalid placement key components for '%s'"):format(key))
		end
		local facing: Facing = assertFacing(facingStr)
		parsedLevel = normalizeLevel(tonumber(levelStr))
		return cellX, cellZ, facing, parsedLevel
	end

	local legacyX, legacyZ, legacyFacing = string.match(key, "^([^:]+):([^:]+):([^:]+)$")
	if legacyX and legacyZ and legacyFacing then
		local cellX = tonumber(legacyX)
		local cellZ = tonumber(legacyZ)
		if not cellX or not cellZ then
			error(("Invalid placement key components for '%s'"):format(key))
		end
		return cellX, cellZ, assertFacing(legacyFacing), DEFAULT_LEVEL
	end

	local tripleStr, typeStr = key:match("^(.-):([^:]+)$")
	if tripleStr and typeStr then
		local lx, lz, lf = string.match(tripleStr, "^([^:]+):([^:]+):([^:]+)$")
		if lx and lz and lf then
			local cellX = tonumber(lx)
			local cellZ = tonumber(lz)
			if not cellX or not cellZ then
				error(("Invalid placement key components for '%s'"):format(key))
			end
			return cellX, cellZ, assertFacing(lf), DEFAULT_LEVEL
		end
	end

	error(("Invalid placement key '%s'"):format(key))
end

function PlacementKey.ParseWithType(key: string): (number, number, Facing, string?, number)
	local levelStr, xStr, zStr, facingStr, typeStr = string.match(key, "^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$")
	if levelStr and xStr and zStr and facingStr and typeStr then
		local cellX = tonumber(xStr)
		local cellZ = tonumber(zStr)
		if not cellX or not cellZ then
			error(("Invalid placement key components for '%s'"):format(key))
		end
		local parsedFacing: Facing = assertFacing(facingStr)
		local parsedLevel = normalizeLevel(tonumber(levelStr))
		return cellX, cellZ, parsedFacing, typeStr, parsedLevel
	end

	local legacyX, legacyZ, legacyFacing, legacyType = string.match(key, "^([^:]+):([^:]+):([^:]+):([^:]+)$")
	if legacyX and legacyZ and legacyFacing and legacyType then
		local cellX = tonumber(legacyX)
		local cellZ = tonumber(legacyZ)
		if not cellX or not cellZ then
			error(("Invalid placement key components for '%s'"):format(key))
		end
		local parsedFacing: Facing = assertFacing(legacyFacing)
		return cellX, cellZ, parsedFacing, legacyType, DEFAULT_LEVEL
	end

	local cellX: number, cellZ: number, facing: Facing, level: number = PlacementKey.Parse(key)
	return cellX, cellZ, facing, nil, level
end

return PlacementKey
