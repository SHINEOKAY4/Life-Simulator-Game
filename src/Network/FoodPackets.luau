--!strict
-- ReplicatedStorage/Network/FoodPackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packet = require(ReplicatedStorage.Packages.Packet)

local FoodPackets = {}

FoodPackets.KitchenStateUpdate = Packet("KitchenStateUpdate", {
	Ingredients = {
		{
			Id = Packet.String,
			Quantity = Packet.NumberU16,
		},
	},
	Meals = {
		{
			Id = Packet.String,
			Portions = Packet.NumberU16,
		},
	},
	LastCookedAt = Packet.NumberF32,
	Containers = {
		{
			Id = Packet.String,
			StationType = Packet.String,
			ItemId = Packet.String,
			Capacity = Packet.NumberU16,
			Ingredients = {
				{
					Id = Packet.String,
					Quantity = Packet.NumberU16,
				},
			},
		},
	},
})

FoodPackets.RequestKitchenState = Packet("RequestKitchenState"):Response({
	Ingredients = {
		{
			Id = Packet.String,
			Quantity = Packet.NumberU16,
		},
	},
	Meals = {
		{
			Id = Packet.String,
			Portions = Packet.NumberU16,
		},
	},
	LastCookedAt = Packet.NumberF32,
	Containers = {
		{
			Id = Packet.String,
			StationType = Packet.String,
			ItemId = Packet.String,
			Capacity = Packet.NumberU16,
			Ingredients = {
				{
					Id = Packet.String,
					Quantity = Packet.NumberU16,
				},
			},
		},
	},
})

FoodPackets.PurchaseIngredientRequest =
	Packet("PurchaseIngredientRequest", Packet.String, Packet.NumberU8):Response(Packet.Boolean8, Packet.StringLong)

FoodPackets.ContainerTransferRequest = Packet(
	"FoodContainerTransferRequest",
	Packet.String,
	Packet.String,
	Packet.String,
	Packet.NumberU8,
	Packet.String
):Response(Packet.Boolean8, Packet.StringLong)

FoodPackets.HarvestFoodSourceRequest =
	Packet("HarvestFoodSourceRequest", Packet.String):Response(Packet.Boolean8, Packet.StringLong)

FoodPackets.IngredientGrantNotice = Packet("IngredientGrantNotice", {
	SourceId = Packet.String,
	SourceName = Packet.String,
	Entries = {
		{
			Id = Packet.String,
			Quantity = Packet.NumberU8,
			Image = Packet.String,
		},
	},
})

return FoodPackets
