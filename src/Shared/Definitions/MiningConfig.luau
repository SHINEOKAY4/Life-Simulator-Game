--!strict
-- ReplicatedStorage/Shared/Definitions/MiningConfig.luau
-- Configuration for the mining system: rock specs, yields, audio, and presentation.

local MiningConfig = {}

export type RockYield = {
	ItemDefId: string,
	Quantity: number?,
}

export type RockSpec = {
	Id: string,
	Name: string,
	ModelName: string?,
	RespawnSeconds: number?,
	MineDurationSeconds: number?,
	Yield: RockYield,
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

MiningConfig.DefaultBagCategory = "Resources"

MiningConfig.RockStateAttributes = {
	Guid = "MiningRockGuid",
	TypeId = "MiningRockTypeId",
	State = "MiningRockState",
	BusyUserId = "MiningRockBusyUserId",
	RespawnAt = "MiningRockRespawnAt",
}

MiningConfig.RockStateEnum = {
	Ready = "Ready",
	Busy = "Busy",
	Regrowing = "Regrowing",
}

MiningConfig.RockTypes = {
	StoneCluster = {
		Id = "StoneCluster",
		Name = "Stone Cluster",
		ModelName = "StoneCluster",
		RespawnSeconds = 35,
		MineDurationSeconds = 4,
		Yield = {
			ItemDefId = "Ore_Stone",
			Quantity = 3,
		},
	},
}

MiningConfig.InventoryDefinitions = {
	Ore_Stone = {
		defId = "Ore_Stone",
		itemType = "Resource",
		maxStack = 50,
		canDelete = true,
		metadata = {
			DisplayName = "Stone Chunk",
			Description = "Chunk of rock mined from the forest quarry.",
			MaterialId = "Stone",
			IconImage = "rbxassetid://73777186611890",
		},
		defaultProps = {
			quantity = 1,
		},
	},
}

MiningConfig.SellPrices = {
	Ore_Stone = {
		UnitPrice = 6,
	},
}

MiningConfig.PlayerMineAnimationId = ""
MiningConfig.MineAnimationFadeTime = 0.1

MiningConfig.PickSwingSoundId = "rbxassetid://7650226201"
MiningConfig.PickSwingSoundVolume = 0.7

MiningConfig.RockBreakSoundId = "rbxassetid://9119049668"
MiningConfig.RockBreakSoundVolume = 0.9

MiningConfig.RockImageAssetId = "rbxassetid://73777186611890"

return MiningConfig
