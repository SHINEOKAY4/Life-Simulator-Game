--!strict
-- ReplicatedStorage/Shared/Utilities/PlacementKey.luau
-- Utility helpers to build and parse placement keys formed from cell coordinates and facing.

type Facing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

local PlacementKey = {}

local DEFAULT_FACING: Facing = "North"

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

function PlacementKey.FromComponents(cellX: number, cellZ: number, facing: Facing?): string
	return ("%d:%d:%s"):format(cellX, cellZ, normalizeFacing(facing))
end

function PlacementKey.ForPlacementType(cellX: number, cellZ: number, facing: Facing?, placementType: string?): string
	return ("%d:%d:%s:%s"):format(cellX, cellZ, normalizeFacing(facing), sanitizePlacementType(placementType))
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

function PlacementKey.Parse(key: string): (number, number, Facing)
	local xStr, zStr, facingStr = string.match(key, "^([^:]+):([^:]+):([^:]+)$")
	if not xStr or not zStr or not facingStr then
		local tripleStr, typeStr = key:match("^(.-):([^:]+)$")
		if tripleStr and typeStr then
			xStr, zStr, facingStr = string.match(tripleStr, "^([^:]+):([^:]+):([^:]+)$")
		end
	end

	if not xStr or not zStr or not facingStr then
		error(("Invalid placement key '%s'"):format(key))
	end

	local cellX = tonumber(xStr)
	local cellZ = tonumber(zStr)
	if not cellX or not cellZ then
		error(("Invalid placement key components for '%s'"):format(key))
	end

	return cellX, cellZ, assertFacing(facingStr)
end

function PlacementKey.ParseWithType(key: string): (number, number, Facing, string?)
	local xStr, zStr, facingStr, typeStr = string.match(key, "^([^:]+):([^:]+):([^:]+):([^:]+)$")
	if xStr and zStr and facingStr then
		local cellX = tonumber(xStr)
		local cellZ = tonumber(zStr)
		if not cellX or not cellZ then
			error(("Invalid placement key components for '%s'"):format(key))
		end
		local parsedFacing: Facing = assertFacing(facingStr)
		return cellX, cellZ, parsedFacing, typeStr
	end

	local cellX: number, cellZ: number, facing: Facing = PlacementKey.Parse(key)
	return cellX, cellZ, facing, nil
end

return PlacementKey
