--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementUtils = require(script.Parent.PlacementUtils)

type Facing = string

type EdgeAlignment = "Horizontal" | "Vertical" | "DiagonalForward" | "DiagonalBackward"

type MoveOriginInfo = PlacementUtils.MoveOriginInfo

local WallConstraints = {}

local EDGE_KIND_WALL = "Wall"
local EDGE_KIND_INTERIOR = "Interior"

local HorizontalWallEdges: { [string]: string } = {}
local VerticalWallEdges: { [string]: string } = {}

WallConstraints.EdgeKind = {
	Wall = EDGE_KIND_WALL,
	Interior = EDGE_KIND_INTERIOR,
}

local ForwardDiagonalWallEdges: { [string]: string } = {}
local BackwardDiagonalWallEdges: { [string]: string } = {}

local function edgeKey(edgeX: number, edgeZ: number): string
	return string.format("%d:%d", edgeX, edgeZ)
end

function WallConstraints.EdgeOfCell(cellX: number, cellZ: number, facing: Facing): (EdgeAlignment, number, number)
	local resolvedFacing = PlacementKey.NormalizeFacing(facing :: any)
	if resolvedFacing == "North" then
		return "Horizontal", cellX, cellZ
	elseif resolvedFacing == "South" then
		return "Horizontal", cellX, cellZ + 1
	elseif resolvedFacing == "West" then
		return "Vertical", cellX, cellZ
	elseif resolvedFacing == "East" then
		return "Vertical", cellX + 1, cellZ
	elseif resolvedFacing == "NorthEast" then
		return "DiagonalForward", cellX, cellZ
	elseif resolvedFacing == "NorthWest" then
		return "DiagonalBackward", cellX, cellZ
	end

	error(("Unsupported facing '%s' for wall constraints"):format(tostring(facing)))
end

local function setEdgeOccupied(alignment: EdgeAlignment, key: string, kind: string)
	if alignment == "Horizontal" then
		HorizontalWallEdges[key] = kind
	elseif alignment == "Vertical" then
		VerticalWallEdges[key] = kind
	elseif alignment == "DiagonalForward" then
		ForwardDiagonalWallEdges[key] = kind
	else
		BackwardDiagonalWallEdges[key] = kind
	end
end

function WallConstraints.Clear()
	table.clear(HorizontalWallEdges)
	table.clear(VerticalWallEdges)
	table.clear(ForwardDiagonalWallEdges)
	table.clear(BackwardDiagonalWallEdges)
end

function WallConstraints.Populate(grid: any, placed: any, ignorePlacement: MoveOriginInfo?, activeLevel: number?)
	WallConstraints.Clear()
	if not placed or not grid then
		return
	end

	for _, entry in pairs(placed) do
		local _, placementType, width, depth, facingValue, entryLevel = PlacementUtils.ResolvePlacementEntry(entry)
		if activeLevel ~= nil and entryLevel ~= activeLevel then
			continue
		end
		if PlacementUtils.MatchesIgnorePlacement(entry, placementType, facingValue, ignorePlacement) then
			continue
		end

		if placementType == "Wall" then
			local normalizedFacing = PlacementKey.NormalizeFacing(facingValue :: any)
			local alignment: EdgeAlignment, edgeX, edgeZ =
				WallConstraints.EdgeOfCell(entry.cellX, entry.cellZ, normalizedFacing)
			setEdgeOccupied(alignment, edgeKey(edgeX, edgeZ), EDGE_KIND_WALL)
		elseif placementType == "CellObject" then
			local minCellX, minCellZ, maxCellX, maxCellZ =
				grid:FootprintBounds(entry.cellX, entry.cellZ, width, depth, facingValue)
			local rotatedWidth = maxCellX - minCellX
			local rotatedDepth = maxCellZ - minCellZ

			if rotatedWidth >= 1 then
				for cellZ = minCellZ, maxCellZ do
					for cellX = minCellX, maxCellX - 1 do
						local alignment: EdgeAlignment, edgeX, edgeZ = WallConstraints.EdgeOfCell(cellX, cellZ, "East")
						if alignment == "Vertical" then
							setEdgeOccupied("Vertical", edgeKey(edgeX, edgeZ), EDGE_KIND_INTERIOR)
						end
					end
				end
			end

			if rotatedDepth >= 1 then
				for cellZ = minCellZ, maxCellZ - 1 do
					for cellX = minCellX, maxCellX do
						local alignment: EdgeAlignment, edgeX, edgeZ = WallConstraints.EdgeOfCell(cellX, cellZ, "South")
						if alignment == "Horizontal" then
							setEdgeOccupied("Horizontal", edgeKey(edgeX, edgeZ), EDGE_KIND_INTERIOR)
						end
					end
				end
			end
		end
	end
end

function WallConstraints.GetEdgeOccupant(cellX: number, cellZ: number, facing: Facing): string?
	local alignment, edgeX, edgeZ = WallConstraints.EdgeOfCell(cellX, cellZ, facing)
	local key = edgeKey(edgeX, edgeZ)
	if alignment == "Horizontal" then
		return HorizontalWallEdges[key]
	elseif alignment == "Vertical" then
		return VerticalWallEdges[key]
	elseif alignment == "DiagonalForward" then
		return ForwardDiagonalWallEdges[key]
	else
		return BackwardDiagonalWallEdges[key]
	end
end

function WallConstraints.HasInteriorEdgeBetweenCells(
	minCellX: number,
	minCellZ: number,
	maxCellX: number,
	maxCellZ: number
): boolean
	if maxCellX - minCellX >= 1 then
		for cellZ = minCellZ, maxCellZ do
			for cellX = minCellX, maxCellX - 1 do
				local _, edgeX, edgeZ = WallConstraints.EdgeOfCell(cellX, cellZ, "East")
				if VerticalWallEdges[edgeKey(edgeX, edgeZ)] then
					return true
				end
			end
		end
	end

	if maxCellZ - minCellZ >= 1 then
		for cellZ = minCellZ, maxCellZ - 1 do
			for cellX = minCellX, maxCellX do
				local _, edgeX, edgeZ = WallConstraints.EdgeOfCell(cellX, cellZ, "South")
				if HorizontalWallEdges[edgeKey(edgeX, edgeZ)] then
					return true
				end
			end
		end
	end

	return false
end

return WallConstraints
