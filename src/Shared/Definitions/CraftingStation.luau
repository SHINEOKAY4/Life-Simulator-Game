--!strict

export type CraftingStationDefinition = {
	Id: string,
	Name: string,
	Description: string,
	ItemIds: { string },
}

local CraftingStation = {}

CraftingStation.Definitions = {
	BasicWorkbench = {
		Id = "BasicWorkbench",
		Name = "Basic Workbench",
		Description = "Simple bench for foundational recipes.",
		ItemIds = {
			"BasicWorkbench",
			"Workbench",
			"CraftingTable",
			"WoodWorkbench",
		},
	},
	AdvancedWorkbench = {
		Id = "AdvancedWorkbench",
		Name = "Advanced Workbench",
		Description = "Precision station for advanced tools and furniture.",
		ItemIds = {
			"AdvancedWorkbench",
			"ToolBench",
			"MachiningBench",
		},
	},
	CookingStation = {
		Id = "CookingStation",
		Name = "Cooking Station",
		Description = "Used for preparing meals and consumables.",
		ItemIds = {
			"CookingStation",
			"Stove",
			"KitchenCounter",
			"CampfireStove",
		},
	},
	Forge = {
		Id = "Forge",
		Name = "Forge",
		Description = "High-heat station used for smithing.",
		ItemIds = {
			"Forge",
			"Anvil",
			"Smelter",
		},
	},
} :: { [string]: CraftingStationDefinition }

function CraftingStation.GetById(stationId: string): CraftingStationDefinition?
	return CraftingStation.Definitions[stationId]
end

function CraftingStation.GetAll(): { CraftingStationDefinition }
	local out: { CraftingStationDefinition } = {}
	for _, definition in pairs(CraftingStation.Definitions) do
		table.insert(out, definition)
	end
	table.sort(out, function(a, b)
		return a.Name < b.Name
	end)
	return out
end

function CraftingStation.IsValid(stationId: string): boolean
	return CraftingStation.Definitions[stationId] ~= nil
end

function CraftingStation.ResolveFromItemId(itemId: string): string?
	if itemId == "" then
		return nil
	end
	for stationId, definition in pairs(CraftingStation.Definitions) do
		for _, candidate in ipairs(definition.ItemIds) do
			if candidate == itemId then
				return stationId
			end
		end
	end
	return nil
end

return CraftingStation
