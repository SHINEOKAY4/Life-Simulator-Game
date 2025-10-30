--!strict
-- ReplicatedStorage/Shared/Definitions/MealRecipes.luau

export type IngredientRequirement = {
	IngredientId: string,
	Quantity: number,
}

export type MealRecipe = {
	Id: string,
	Name: string,
	Description: string,
	CookTimeSeconds: number,
	Servings: number,
	AutoConsumePortions: number?,
	HungerRestore: number,
	MoodBonus: number?,
	Ingredients: { IngredientRequirement },
	Tags: { string }?,
}

local Recipes: { [string]: MealRecipe } = {
	QuickSalad = {
		Id = "QuickSalad",
		Name = "Garden Salad",
		Description = "Fast greens that keep residents going.",
		CookTimeSeconds = 18,
		Servings = 1,
		AutoConsumePortions = 1,
		HungerRestore = 38,
		MoodBonus = 2,
		Ingredients = {
			{ IngredientId = "FreshProduce", Quantity = 2 },
		},
		Tags = { "Quick", "Light" },
	},
	HeartyStew = {
		Id = "HeartyStew",
		Name = "Hearty Stew",
		Description = "Balanced meal that restores a big chunk of hunger.",
		CookTimeSeconds = 32,
		Servings = 2,
		AutoConsumePortions = 1,
		HungerRestore = 60,
		MoodBonus = 4,
		Ingredients = {
			{ IngredientId = "FreshProduce", Quantity = 2 },
			{ IngredientId = "WholeGrains", Quantity = 1 },
			{ IngredientId = "LeanProtein", Quantity = 1 },
		},
		Tags = { "Comfort" },
	},
	ComfortSkillet = {
		Id = "ComfortSkillet",
		Name = "Comfort Skillet",
		Description = "Mood-forward skillet that leaves leftovers.",
		CookTimeSeconds = 40,
		Servings = 3,
		AutoConsumePortions = 1,
		HungerRestore = 52,
		MoodBonus = 8,
		Ingredients = {
			{ IngredientId = "LeanProtein", Quantity = 2 },
			{ IngredientId = "WholeGrains", Quantity = 2 },
			{ IngredientId = "ComfortSeasoning", Quantity = 1 },
		},
		Tags = { "MoodBoost", "Comfort" },
	},
}

local MealRecipes = {
	Recipes = Recipes,
	DefaultOrder = { "ComfortSkillet", "HeartyStew", "QuickSalad" },
	DefaultFallback = "QuickSalad",
}

return MealRecipes
