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
	ImageAssetId: string?,
	RawHungerRestore: number?,
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
		RawHungerRestore = 28,
	},
	Raspberries = {
		Id = "Raspberries",
		Name = "Raspberries",
		Category = "Fruit",
		Description = "Sweet-tart berries for desserts and mood treats.",
		PurchaseCost = 20,
		PurchaseQuantity = 3,
		Tags = { "Premium", "Fruit" },
		PerMealCost = 6,
		ImageAssetId = "rbxassetid://126557338728692",
		RawHungerRestore = 18,
	},
	Blueberries = {
		Id = "Blueberries",
		Name = "Blueberries",
		Category = "Fruit",
		Description = "Bursting berries that keep breakfasts fresh and bright.",
		PurchaseCost = 18,
		PurchaseQuantity = 3,
		Tags = { "Premium", "Fruit" },
		PerMealCost = 5,
		ImageAssetId = "rbxassetid://74171363806705",
		RawHungerRestore = 18,
	},
	WholeGrains = {
		Id = "WholeGrains",
		Name = "Whole Grains",
		Category = "Grains",
		Description = "Hearty grains that stretch recipes and add energy.",
		PurchaseCost = 14,
		PurchaseQuantity = 4,
		Tags = { "Baseline", "Carb" },
		ImageAssetId = "rbxassetid://85319264147854",
		RawHungerRestore = 12,
	},
	LeanProtein = {
		Id = "LeanProtein",
		Name = "Lean Protein",
		Category = "Protein",
		Description = "Lean cuts and beans for balanced meals.",
		PurchaseCost = 22,
		PurchaseQuantity = 3,
		Tags = { "Baseline", "Protein" },
		ImageAssetId = "rbxassetid://118405140838377",
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
