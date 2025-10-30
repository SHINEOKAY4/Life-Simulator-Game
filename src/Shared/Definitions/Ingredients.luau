--!strict
-- ReplicatedStorage/Shared/Definitions/Ingredients.luau

export type IngredientSpec = {
	Id: string,
	Name: string,
	Category: string,
	Description: string,
	PurchaseCost: number,
	PurchaseQuantity: number,
	Tags: { string }?,
	PerMealCost: number?,
}

local Ingredients: { [string]: IngredientSpec } = {
	FreshProduce = {
		Id = "FreshProduce",
		Name = "Fresh Produce",
		Category = "Produce",
		Description = "Seasonal greens and veggies for light meals.",
		PurchaseCost = 18,
		PurchaseQuantity = 4,
		Tags = { "Baseline", "Vegetable" },
	},
	WholeGrains = {
		Id = "WholeGrains",
		Name = "Whole Grains",
		Category = "Grains",
		Description = "Hearty grains that stretch recipes and add energy.",
		PurchaseCost = 14,
		PurchaseQuantity = 4,
		Tags = { "Baseline", "Carb" },
	},
	LeanProtein = {
		Id = "LeanProtein",
		Name = "Lean Protein",
		Category = "Protein",
		Description = "Lean cuts and beans for balanced meals.",
		PurchaseCost = 22,
		PurchaseQuantity = 3,
		Tags = { "Baseline", "Protein" },
	},
	ComfortSeasoning = {
		Id = "ComfortSeasoning",
		Name = "Comfort Seasoning",
		Category = "Seasoning",
		Description = "Warm spices that improve mood when used.",
		PurchaseCost = 10,
		PurchaseQuantity = 2,
		Tags = { "MoodBoost" },
	},
}

return Ingredients
