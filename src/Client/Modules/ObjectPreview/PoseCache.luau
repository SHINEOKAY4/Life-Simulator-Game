--!strict

local Types = require(script.Parent.Types)

type PreviewKind = Types.PreviewKind
type PoseCacheComparable = Types.PoseCacheComparable
type PoseCacheSnapshot = Types.PoseCacheSnapshot

local PoseCache = {}

local lastSnapshot: PoseCacheSnapshot = {}

local WALL_WOBBLE_TOLERANCE = 0.05

local function vectorsAreClose(a: Vector3?, b: Vector3?, epsilon: number): boolean
	if not a or not b then
		return false
	end
	return (a - b).Magnitude <= epsilon
end

function PoseCache.ShouldSkip(kind: PreviewKind, info: PoseCacheComparable, surfaceLocalEpsilon: number): boolean
	if lastSnapshot.cellX == nil or lastSnapshot.cellZ == nil or lastSnapshot.facing == nil then
		return false
	end

	if kind == "WallMounted" then
		if not info.wallPosition then
			return false
		end
		if
			info.cellX ~= lastSnapshot.cellX
			or info.cellZ ~= lastSnapshot.cellZ
			or info.facing ~= lastSnapshot.facing
		then
			return false
		end
		return vectorsAreClose(lastSnapshot.wallPosition, info.wallPosition, WALL_WOBBLE_TOLERANCE)
	end

	if kind == "SurfaceMounted" then
		if info.surfaceParentKey ~= lastSnapshot.surfaceParentKey then
			return false
		end
		if info.facing ~= lastSnapshot.facing then
			return false
		end
		return vectorsAreClose(lastSnapshot.surfaceLocalPosition, info.surfaceLocalPosition, surfaceLocalEpsilon)
	end

	if kind == "Wall" and info.windowHeightOffset ~= nil then
		if
			info.cellX ~= lastSnapshot.cellX
			or info.cellZ ~= lastSnapshot.cellZ
			or info.facing ~= lastSnapshot.facing
		then
			return false
		end
		if lastSnapshot.windowHeightOffset == nil then
			return false
		end
		return math.abs(lastSnapshot.windowHeightOffset - info.windowHeightOffset) < 1e-3
	end

	if kind == "Ceiling" then
		if
			info.cellX ~= lastSnapshot.cellX
			or info.cellZ ~= lastSnapshot.cellZ
			or info.facing ~= lastSnapshot.facing
		then
			return false
		end
		if lastSnapshot.ceilingDrop == nil or info.ceilingDrop == nil then
			return false
		end
		if lastSnapshot.ceilingRotation == nil or info.ceilingRotation == nil then
			return false
		end
		return math.abs(lastSnapshot.ceilingDrop - info.ceilingDrop) < 1e-3
			and math.abs(lastSnapshot.ceilingRotation - info.ceilingRotation) < 1e-3
	end

	return info.cellX == lastSnapshot.cellX and info.cellZ == lastSnapshot.cellZ and info.facing == lastSnapshot.facing
end

local function assignSnapshot(kind: PreviewKind, info: PoseCacheComparable)
	lastSnapshot.cellX = info.cellX
	lastSnapshot.cellZ = info.cellZ
	lastSnapshot.facing = info.facing

	if kind == "WallMounted" then
		lastSnapshot.wallPosition = info.wallPosition
	else
		lastSnapshot.wallPosition = nil
	end

	if kind == "SurfaceMounted" then
		lastSnapshot.surfaceParentKey = info.surfaceParentKey
		lastSnapshot.surfaceLocalPosition = info.surfaceLocalPosition
	else
		lastSnapshot.surfaceParentKey = nil
		lastSnapshot.surfaceLocalPosition = nil
	end

	if kind == "Wall" then
		lastSnapshot.windowHeightOffset = info.windowHeightOffset
	else
		lastSnapshot.windowHeightOffset = nil
	end

	if kind == "Ceiling" then
		lastSnapshot.ceilingDrop = info.ceilingDrop
		lastSnapshot.ceilingRotation = info.ceilingRotation
	else
		lastSnapshot.ceilingDrop = nil
		lastSnapshot.ceilingRotation = nil
	end
end

function PoseCache.Update(kind: PreviewKind, info: PoseCacheComparable)
	assignSnapshot(kind, info)
end

function PoseCache.Reset()
	lastSnapshot = {}
end

function PoseCache.GetSnapshot(): PoseCacheSnapshot
	return {
		cellX = lastSnapshot.cellX,
		cellZ = lastSnapshot.cellZ,
		facing = lastSnapshot.facing,
		wallPosition = lastSnapshot.wallPosition,
		surfaceParentKey = lastSnapshot.surfaceParentKey,
		surfaceLocalPosition = lastSnapshot.surfaceLocalPosition,
		windowHeightOffset = lastSnapshot.windowHeightOffset,
		ceilingDrop = lastSnapshot.ceilingDrop,
		ceilingRotation = lastSnapshot.ceilingRotation,
	}
end

return PoseCache
