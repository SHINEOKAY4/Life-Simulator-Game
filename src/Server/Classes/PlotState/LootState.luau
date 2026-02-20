-- ServerScriptService / Server/ Classes/ LootState.lua

local ServerScrptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

--[[

Weight must be in order from greatest to least

The higher the weight, the more likely it is to be chosen
((Relative to other items in loottable))

]]

local LootTables = {

	["LootTableA"] = {
		{ Item = Items[3], Weight = 125 }, -- Chair, highest weight
		{ Item = Items[1], Weight = 80 }, -- Table
	},
}

return LootTables
