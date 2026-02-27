-- ServerScriptService / Server/ Classes/ LootState.lua

--[[

Weight must be in order from greatest to least

The higher the weight, the more likely it is to be chosen
((Relative to other items in loottable))

]]

local LootTables = {

	["LootTableA"] = {
		{ Item = "Chair", Weight = 125 }, -- Chair, highest weight
		{ Item = "Table", Weight = 80 }, -- Table
	},
}

return LootTables
