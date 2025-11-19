--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ActionQueue = require(script.Parent.ActionQueue)

local FallbackActions = {}

function FallbackActions.evaluateFallback(
	player: Player,
	residentName: string,
	resident: any,
	_stationCache: { [string]: any }?
): boolean
	-- 1. Check if we should wander
	-- For now, we always wander if no other needs are pressing and we are idle.

	-- 2. Pick a random position
	local plotState = PlotService.GetState(player)
	if not plotState then
		return false
	end

	local unlockedChunks = plotState.Save.UnlockedChunks
	if not unlockedChunks or #unlockedChunks == 0 then
		return false
	end

	local randomChunk = unlockedChunks[math.random(1, #unlockedChunks)]

	-- Chunk size is usually 5 (from PlotService.Load)
	local chunkSize = plotState.ChunkSizeInCells or 5

	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return false
	end

	local gridObject = PlotService.GetGrid(plotIndex)
	if not gridObject then
		return false
	end

	-- Pick random cell in chunk
	-- Chunk coordinates are 1-based indices of chunks.
	-- Cell coordinates: (cx-1)*chunkSize + 1 to cx*chunkSize

	local minX = (randomChunk.cx - 1) * chunkSize + 1
	local maxX = randomChunk.cx * chunkSize
	local minZ = (randomChunk.cz - 1) * chunkSize + 1
	local maxZ = randomChunk.cz * chunkSize

	local cellX = math.random(minX, maxX)
	local cellZ = math.random(minZ, maxZ)

	-- Convert to world position
	local worldPos = gridObject:CellToWorldCenter(cellX, cellZ)

	-- Enqueue Wander action
	return ActionQueue.enqueueFallbackAction(player, residentName, resident, "Wander", {
		TargetPosition = worldPos,
	})
end

return FallbackActions
