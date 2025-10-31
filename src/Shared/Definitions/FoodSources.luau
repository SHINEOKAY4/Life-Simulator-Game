--!strict
-- ReplicatedStorage/Shared/Definitions/FoodSources.luau

export type FoodSourceYield = {
	IngredientId: string,
	Quantity: number?,
	MinQuantity: number?,
	MaxQuantity: number?,
	Weight: number?,
}

export type FoodSourceTargetSpec = {
	ContainerId: string,
	StationType: string?,
	ItemId: string?,
	Capacity: number?,
}

export type FoodSourceSpec = {
	Id: string,
	Name: string,
	Category: string,
	Description: string?,
	HarvestDurationSeconds: number,
	RestockSeconds: number,
	Charges: number?,
	YieldMode: "Guaranteed" | "Weighted" | "Scatter"?,
	Yields: { FoodSourceYield },
	StationType: string?,
	RequiresToolId: string?,
	Tags: { string }?,
	TargetStorage: FoodSourceTargetSpec?,
}

local FoodSources: { [string]: FoodSourceSpec } = {
	RaspberryCanes = {
		Id = "RaspberryCanes",
		Name = "Raspberry Canes",
		Category = "BerryPatch",
		Description = "Ripe canes that yield tart raspberries when pruned.",
		HarvestDurationSeconds = 4,
		RestockSeconds = 120,
		Charges = 1,
		YieldMode = "Guaranteed",
		Yields = {
			{ IngredientId = "Raspberries", MinQuantity = 2, MaxQuantity = 4 },
		},
		StationType = "HarvestBerryStation",
		Tags = { "Outdoor", "SmallPlot" },
	},
	BlueberryBush = {
		Id = "BlueberryBush",
		Name = "Blueberry Bush",
		Category = "BerryPatch",
		Description = "A low shrub packed with sweet blueberries.",
		HarvestDurationSeconds = 4,
		RestockSeconds = 135,
		Charges = 1,
		YieldMode = "Guaranteed",
		Yields = {
			{ IngredientId = "Blueberries", MinQuantity = 2, MaxQuantity = 4 },
		},
		StationType = "HarvestBerryStation",
		Tags = { "Outdoor", "SmallPlot" },
	},
	VegetablePlanter = {
		Id = "VegetablePlanter",
		Name = "Vegetable Planter",
		Category = "GardenBed",
		Description = "An indoor planter that rotates seasonal greens.",
		HarvestDurationSeconds = 6,
		RestockSeconds = 180,
		Charges = 1,
		YieldMode = "Weighted",
		Yields = {
			{ IngredientId = "FreshProduce", MinQuantity = 2, MaxQuantity = 3, Weight = 60 },
			{ IngredientId = "WholeGrains", MinQuantity = 1, MaxQuantity = 2, Weight = 25 },
			{ IngredientId = "ComfortSeasoning", Quantity = 1, Weight = 15 },
		},
		StationType = "HarvestPlanterStation",
		Tags = { "Indoor", "MediumPlot" },
	},
	HerbPlanter = {
		Id = "HerbPlanter",
		Name = "Herb Planter",
		Category = "GardenBed",
		Description = "Countertop herbs that replenish seasoning stocks.",
		HarvestDurationSeconds = 3,
		RestockSeconds = 90,
		Charges = 2,
		YieldMode = "Guaranteed",
		Yields = {
			{ IngredientId = "ComfortSeasoning", Quantity = 1 },
		},
		StationType = "HarvestPlanterStation",
		Tags = { "Indoor", "SmallPlot" },
	},
}

local FoodSourceList: { FoodSourceSpec } = {}
for _, spec in pairs(FoodSources) do
	FoodSourceList[#FoodSourceList + 1] = spec
end

table.sort(FoodSourceList, function(a, b)
	if a.Category == b.Category then
		return a.Name < b.Name
	end
	return a.Category < b.Category
end)

return {
	Sources = FoodSources,
	List = FoodSourceList,
}
