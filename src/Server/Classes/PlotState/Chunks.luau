--!strict
-- ServerScriptService/Server/Classes/PlotState/Chunks.lua
local Chunks = {}

function Chunks.attach(PlotState)
	function PlotState:ChunkIndex(chunkX: number, chunkZ: number): number
		return self.Grid:ChunkToIndex(chunkX, chunkZ, self.ChunkColumns)
	end

	function PlotState:IsChunkUnlocked(chunkX: number, chunkZ: number): boolean
		return self.ChunkUnlocked[self:ChunkIndex(chunkX, chunkZ)] == true
	end

	function PlotState:IsChunkInBounds(chunkX: number, chunkZ: number): boolean
		return chunkX >= 1 and chunkX <= self.ChunkColumns and chunkZ >= 1 and chunkZ <= self.ChunkRows
	end

	function PlotState:UnlockChunk(chunkX: number, chunkZ: number): boolean
		local chunkIndex = self:ChunkIndex(chunkX, chunkZ)
		if self.ChunkUnlocked[chunkIndex] then
			return false
		end

		self.ChunkUnlocked[chunkIndex] = true
		self.Save.UnlockedChunks[#self.Save.UnlockedChunks + 1] = { cx = chunkX, cz = chunkZ }
		return true
	end

	function PlotState:HasAdjacentUnlocked(chunkX: number, chunkZ: number): boolean
		if chunkX > 1 and self:IsChunkUnlocked(chunkX - 1, chunkZ) then
			return true
		end
		if chunkX < self.ChunkColumns and self:IsChunkUnlocked(chunkX + 1, chunkZ) then
			return true
		end
		if chunkZ > 1 and self:IsChunkUnlocked(chunkX, chunkZ - 1) then
			return true
		end
		if chunkZ < self.ChunkRows and self:IsChunkUnlocked(chunkX, chunkZ + 1) then
			return true
		end
		return false
	end
end

return Chunks
