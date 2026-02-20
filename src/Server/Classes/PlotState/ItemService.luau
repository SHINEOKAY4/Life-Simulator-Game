local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local LootState = ServerScriptService.Server.Classes.PlotState.LootState

local ItemService = { LootState = LootState }

-- generate a random number
local function getTotalWeightOfLootTable(lootTable)
	local weight = 0
	for _, v in lootTable do
		weight = weight + v.Weight
	end

	return weight
end

function ItemService:GetRandomItemFromLootTable(lootTable)
	local totalWeight = getTotalWeightOfLootTable(lootTable)
	local randomNumber = math.random(totalWeight)
	--[[
    loops through the lootTable, if an iten is less or equal to the weight of the current entry
    it will return the item, otherwise it will subtract the weight  and continue the process
until an item is returned

    ]]

	for _, entry in lootTable do
		if randomNumber <= entry.Weght then --  weight is less than random number so returns item
			return entry.Item
		else -- no item, subtracts the weight from the randomNumber
			randomNumber = randomNumber - entry.Weight
		end
	end
end

return ItemService
