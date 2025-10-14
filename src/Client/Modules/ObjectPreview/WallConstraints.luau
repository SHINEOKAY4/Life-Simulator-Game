--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementUtils = require(script.Parent.PlacementUtils)

type Facing = string

type MoveOriginInfo = PlacementUtils.MoveOriginInfo

type EdgeAlignment = "Horizontal" | "Vertical"

local WallConstraints = {}

local EDGE_KIND_WALL = "Wall"
local EDGE_KIND_INTERIOR = "Interior"

local HorizontalWallEdges: { [string]: string } = {}
local VerticalWallEdges: { [string]: string } = {}

WallConstraints.EdgeKind = {
	Wall = EDGE_KIND_WALL,
	Interior = EDGE_KIND_INTERIOR,
}

local function edgeKey(edgeX: number, edgeZ: number): string
	return string.format("%d:%d", edgeX, edgeZ)
end

function WallConstraints.EdgeOfCell(cellX: number, cellZ: number, facing: Facing): (EdgeAlignment, number, number)
	if facing == "North" then
		return "Horizontal", cellX, cellZ
	elseif facing == "South" then
		return "Horizontal", cellX, cellZ + 1
	elseif facing == "West" then
		return "Vertical", cellX, cellZ
	else
		return "Vertical", cellX + 1, cellZ
	end
end

local function setEdgeOccupied(alignment: EdgeAlignment, key: string, kind: string)
	if alignment == "Horizontal" then
		HorizontalWallEdges[key] = kind
	else
		VerticalWallEdges[key] = kind
	end
end

function WallConstraints.Clear()
	table.clear(HorizontalWallEdges)
	table.clear(VerticalWallEdges)
end

function WallConstraints.Populate(grid: any, placed: any, ignorePlacement: MoveOriginInfo?)
	WallConstraints.Clear()
	if not placed or not grid then
		return
	end

	for _, entry in pairs(placed) do
		local _, placementType, width, depth, facingValue = PlacementUtils.ResolvePlacementEntry(entry)
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
	else
		return VerticalWallEdges[key]
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
