--!strict

export type CraftingIngredient = {
	ItemId: string,
	Quantity: number,
}

export type CraftingOutput = {
	ItemId: string,
	Quantity: number,
}

export type CraftingSkillRequirement = {
	SkillId: string,
	Level: number,
}

export type CraftingRecipe = {
	Id: string,
	Name: string,
	Description: string,
	Category: string,
	Ingredients: { CraftingIngredient },
	Output: CraftingOutput,
	RequiredStations: { string },
	SkillRequirements: { CraftingSkillRequirement },
	CraftingTimeSeconds: number,
	SkillGains: { [string]: number },
	ProgressionExperience: number,
}

local Recipes: { CraftingRecipe } = {
	{
		Id = "recipe_plank_bundle",
		Name = "Plank Bundle",
		Description = "Process logs into building planks.",
		Category = "Materials",
		Ingredients = { { ItemId = "WoodLog", Quantity = 2 } },
		Output = { ItemId = "Plank", Quantity = 4 },
		RequiredStations = { "BasicWorkbench" },
		SkillRequirements = { { SkillId = "Carpentry", Level = 1 } },
		CraftingTimeSeconds = 4,
		SkillGains = { Carpentry = 8 },
		ProgressionExperience = 5,
	},
	{
		Id = "recipe_stone_axe",
		Name = "Stone Axe",
		Description = "A starter tool for gathering and survival.",
		Category = "Tools",
		Ingredients = {
			{ ItemId = "WoodLog", Quantity = 1 },
			{ ItemId = "StoneChunk", Quantity = 2 },
			{ ItemId = "Fiber", Quantity = 1 },
		},
		Output = { ItemId = "StoneAxe", Quantity = 1 },
		RequiredStations = { "BasicWorkbench" },
		SkillRequirements = { { SkillId = "Survival", Level = 1 } },
		CraftingTimeSeconds = 6,
		SkillGains = { Survival = 10, Carpentry = 4 },
		ProgressionExperience = 12,
	},
	{
		Id = "recipe_wooden_spear",
		Name = "Wooden Spear",
		Description = "Light melee weapon with simple parts.",
		Category = "Weapons",
		Ingredients = {
			{ ItemId = "Plank", Quantity = 2 },
			{ ItemId = "StoneChunk", Quantity = 1 },
			{ ItemId = "Fiber", Quantity = 1 },
		},
		Output = { ItemId = "WoodenSpear", Quantity = 1 },
		RequiredStations = { "BasicWorkbench" },
		SkillRequirements = {
			{ SkillId = "Survival", Level = 2 },
			{ SkillId = "Carpentry", Level = 2 },
		},
		CraftingTimeSeconds = 8,
		SkillGains = { Survival = 12, Carpentry = 8 },
		ProgressionExperience = 16,
	},
	{
		Id = "recipe_torch",
		Name = "Torch",
		Description = "Portable light source.",
		Category = "Utility",
		Ingredients = {
			{ ItemId = "WoodLog", Quantity = 1 },
			{ ItemId = "Fiber", Quantity = 1 },
			{ ItemId = "Coal", Quantity = 1 },
		},
		Output = { ItemId = "Torch", Quantity = 2 },
		RequiredStations = { "BasicWorkbench" },
		SkillRequirements = { { SkillId = "Survival", Level = 1 } },
		CraftingTimeSeconds = 5,
		SkillGains = { Survival = 7 },
		ProgressionExperience = 6,
	},
	{
		Id = "recipe_bread_loaf",
		Name = "Bread Loaf",
		Description = "A simple cooked meal.",
		Category = "Food",
		Ingredients = {
			{ ItemId = "Wheat", Quantity = 3 },
			{ ItemId = "Water", Quantity = 1 },
		},
		Output = { ItemId = "BreadLoaf", Quantity = 1 },
		RequiredStations = { "CookingStation" },
		SkillRequirements = { { SkillId = "Cooking", Level = 1 } },
		CraftingTimeSeconds = 7,
		SkillGains = { Cooking = 10 },
		ProgressionExperience = 10,
	},
	{
		Id = "recipe_cooked_stew",
		Name = "Cooked Stew",
		Description = "Hearty food made from meat and herbs.",
		Category = "Food",
		Ingredients = {
			{ ItemId = "RawMeat", Quantity = 2 },
			{ ItemId = "Herb", Quantity = 2 },
			{ ItemId = "Water", Quantity = 1 },
		},
		Output = { ItemId = "CookedStew", Quantity = 1 },
		RequiredStations = { "CookingStation" },
		SkillRequirements = { { SkillId = "Cooking", Level = 2 } },
		CraftingTimeSeconds = 10,
		SkillGains = { Cooking = 15 },
		ProgressionExperience = 14,
	},
	{
		Id = "recipe_iron_ingot",
		Name = "Iron Ingot",
		Description = "Smelt iron ore into usable bars.",
		Category = "Materials",
		Ingredients = {
			{ ItemId = "IronOre", Quantity = 2 },
			{ ItemId = "Coal", Quantity = 1 },
		},
		Output = { ItemId = "IronIngot", Quantity = 1 },
		RequiredStations = { "Forge" },
		SkillRequirements = { { SkillId = "Smithing", Level = 1 } },
		CraftingTimeSeconds = 9,
		SkillGains = { Smithing = 12 },
		ProgressionExperience = 12,
	},
	{
		Id = "recipe_nails",
		Name = "Nails",
		Description = "Small fasteners for furniture projects.",
		Category = "Materials",
		Ingredients = { { ItemId = "IronIngot", Quantity = 1 } },
		Output = { ItemId = "Nails", Quantity = 8 },
		RequiredStations = { "AdvancedWorkbench" },
		SkillRequirements = { { SkillId = "Smithing", Level = 2 } },
		CraftingTimeSeconds = 6,
		SkillGains = { Smithing = 8 },
		ProgressionExperience = 9,
	},
	{
		Id = "recipe_iron_sword",
		Name = "Iron Sword",
		Description = "Reliable forged weapon.",
		Category = "Weapons",
		Ingredients = {
			{ ItemId = "IronIngot", Quantity = 3 },
			{ ItemId = "WoodLog", Quantity = 1 },
			{ ItemId = "Fiber", Quantity = 1 },
		},
		Output = { ItemId = "IronSword", Quantity = 1 },
		RequiredStations = { "Forge" },
		SkillRequirements = {
			{ SkillId = "Smithing", Level = 3 },
			{ SkillId = "Survival", Level = 2 },
		},
		CraftingTimeSeconds = 12,
		SkillGains = { Smithing = 20, Survival = 6 },
		ProgressionExperience = 24,
	},
	{
		Id = "recipe_fishing_rod",
		Name = "Fishing Rod",
		Description = "Durable rod for fishing activities.",
		Category = "Tools",
		Ingredients = {
			{ ItemId = "Plank", Quantity = 2 },
			{ ItemId = "Fiber", Quantity = 2 },
			{ ItemId = "Cloth", Quantity = 1 },
		},
		Output = { ItemId = "FishingRod", Quantity = 1 },
		RequiredStations = { "AdvancedWorkbench" },
		SkillRequirements = {
			{ SkillId = "Carpentry", Level = 3 },
			{ SkillId = "Survival", Level = 2 },
		},
		CraftingTimeSeconds = 11,
		SkillGains = { Carpentry = 14, Survival = 8 },
		ProgressionExperience = 18,
	},
	{
		Id = "recipe_wooden_chair",
		Name = "Wooden Chair",
		Description = "Basic seating furniture.",
		Category = "Furniture",
		Ingredients = {
			{ ItemId = "Plank", Quantity = 4 },
			{ ItemId = "Nails", Quantity = 4 },
		},
		Output = { ItemId = "WoodenChair", Quantity = 1 },
		RequiredStations = { "AdvancedWorkbench" },
		SkillRequirements = { { SkillId = "Carpentry", Level = 3 } },
		CraftingTimeSeconds = 13,
		SkillGains = { Carpentry = 18 },
		ProgressionExperience = 20,
	},
	{
		Id = "recipe_wooden_table",
		Name = "Wooden Table",
		Description = "Sturdy furniture for living spaces.",
		Category = "Furniture",
		Ingredients = {
			{ ItemId = "Plank", Quantity = 6 },
			{ ItemId = "Nails", Quantity = 8 },
		},
		Output = { ItemId = "WoodenTable", Quantity = 1 },
		RequiredStations = { "AdvancedWorkbench" },
		SkillRequirements = { { SkillId = "Carpentry", Level = 4 } },
		CraftingTimeSeconds = 16,
		SkillGains = { Carpentry = 24 },
		ProgressionExperience = 25,
	},
	{
		Id = "recipe_health_poultice",
		Name = "Health Poultice",
		Description = "Field medicine made from herbs and cloth.",
		Category = "Medicine",
		Ingredients = {
			{ ItemId = "Herb", Quantity = 3 },
			{ ItemId = "Cloth", Quantity = 1 },
			{ ItemId = "Water", Quantity = 1 },
		},
		Output = { ItemId = "HealthPoultice", Quantity = 1 },
		RequiredStations = { "CookingStation" },
		SkillRequirements = {
			{ SkillId = "Cooking", Level = 2 },
			{ SkillId = "Survival", Level = 1 },
		},
		CraftingTimeSeconds = 9,
		SkillGains = { Cooking = 10, Survival = 5 },
		ProgressionExperience = 13,
	},
}

local byId: { [string]: CraftingRecipe } = {}
for _, recipe in ipairs(Recipes) do
	byId[recipe.Id] = recipe
end

local CraftingRecipes = {
	List = Recipes,
	ById = byId,
}

function CraftingRecipes.GetById(recipeId: string): CraftingRecipe?
	return byId[recipeId]
end

return CraftingRecipes
