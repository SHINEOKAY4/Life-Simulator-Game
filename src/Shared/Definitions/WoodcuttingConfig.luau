--!strict
-- ReplicatedStorage/Shared/Definitions/WoodcuttingConfig.luau
-- Central configuration for the woodcutting system (tree specs, inventory defs, pricing).

local WoodcuttingConfig = {}

export type TreeYield = {
	ItemDefId: string,
	Quantity: number?,
}

export type TreeSpec = {
	Id: string,
	Name: string,
	ModelName: string?,
	RespawnSeconds: number?,
	ChopDurationSeconds: number?,
	Yield: TreeYield,
}

export type ItemDef = {
	defId: string,
	itemType: string,
	maxStack: number?,
	canDelete: boolean?,
	metadata: { [string]: any }?,
	defaultProps: { [string]: any }?,
}

export type SellPriceSpec = {
	UnitPrice: number,
}

WoodcuttingConfig.DefaultBagCategory = "Resources"

WoodcuttingConfig.TreeStateAttributes = {
	Guid = "WoodTreeGuid",
	TypeId = "WoodTreeTypeId",
	State = "WoodTreeState",
	BusyUserId = "WoodTreeBusyUserId",
	RespawnAt = "WoodTreeRespawnAt",
}

WoodcuttingConfig.TreeStateEnum = {
	Ready = "Ready",
	Busy = "Busy",
	Regrowing = "Regrowing",
}

WoodcuttingConfig.TreeTypes = {
	Pine = {
		Id = "Pine",
		Name = "Pine Tree",
		ModelName = "Pine",
		RespawnSeconds = 25,
		ChopDurationSeconds = 3.5,
		Yield = {
			ItemDefId = "Wood_Log_Pine",
			Quantity = 3,
		},
	},
	Birch = {
		Id = "Birch",
		Name = "Birch Tree",
		ModelName = "Birch",
		RespawnSeconds = 20,
		ChopDurationSeconds = 3,
		Yield = {
			ItemDefId = "Wood_Log_Birch",
			Quantity = 2,
		},
	},
}

WoodcuttingConfig.InventoryDefinitions = {
	Wood_Log_Pine = {
		defId = "Wood_Log_Pine",
		itemType = "Consumable",
		maxStack = 30,
		canDelete = true,
		metadata = {
			DisplayName = "Pine Log",
			Description = "Freshly chopped pine lumber.",
			MaterialId = "Wood",
		},
		defaultProps = {
			quantity = 1,
		},
	},
	Wood_Log_Birch = {
		defId = "Wood_Log_Birch",
		itemType = "Consumable",
		maxStack = 40,
		canDelete = true,
		metadata = {
			DisplayName = "Birch Log",
			Description = "Birch lumber ready to sell or craft.",
			MaterialId = "Wood",
		},
		defaultProps = {
			quantity = 1,
		},
	},
}

WoodcuttingConfig.SellPrices = {
	Wood_Log_Pine = {
		UnitPrice = 8,
	},
	Wood_Log_Birch = {
		UnitPrice = 10,
	},
}

-- Optional: animation to play on the local player while chopping. Leave blank to skip.
WoodcuttingConfig.PlayerChopAnimationId = "rbxassetid://71256805180055"
WoodcuttingConfig.ChopAnimationFadeTime = 0.1

WoodcuttingConfig.HackSoundId = "rbxassetid://9120262423"
WoodcuttingConfig.HackSoundVolume = 0.6

WoodcuttingConfig.TreeFallSoundId = "rbxassetid://6972249696"
WoodcuttingConfig.TreeFallSoundVolume = 0.85

WoodcuttingConfig.TreeShakeAngleDegrees = 4
WoodcuttingConfig.TreeImpactReturnSeconds = 0.2

WoodcuttingConfig.TreeFallAngleDegrees = 70
WoodcuttingConfig.TreeFallDuration = 1.2
WoodcuttingConfig.TreeRespawnLiftDuration = 0.7

return WoodcuttingConfig
