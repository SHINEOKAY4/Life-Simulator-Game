--!strict

export type SkinToneDefinition = {
	Id: string,
	Name: string,
	BrickColor: BrickColor,
	Color: Color3,
}

export type AccessoryDefinition = {
	Id: string,
	Name: string,
	AssetId: number,
}

export type ClothingDefinition = {
	Id: string,
	Name: string,
	AssetId: number,
}

export type FaceDefinition = {
	Id: string,
	Name: string,
	AssetId: number,
}

export type AgeDefinition = {
	Id: string,
	Label: string,
	Numeric: number,
	Scales: {
		BodyType: number,
		Height: number,
		Width: number,
		Depth: number,
		Head: number,
		Proportion: number,
	},
}

export type GenderDefinition = {
	Id: string,
	Label: string,
}

export type AppearanceSelection = {
	SkinToneId: string,
	HairId: string,
	FaceId: string,
	TopId: string,
	PantsId: string,
	GenderId: string,
	AgeId: string,
}

local function tone(id: string, name: string, rgb: Color3): SkinToneDefinition
	local brick = BrickColor.new(rgb)
	return {
		Id = id,
		Name = name,
		BrickColor = brick,
		Color = brick.Color,
	}
end

local SkinTones: { SkinToneDefinition } = {
	tone("porcelain", "Porcelain", Color3.fromRGB(255, 227, 199)),
	tone("sand", "Sand", Color3.fromRGB(235, 209, 165)),
	tone("amber", "Amber", Color3.fromRGB(216, 181, 141)),
	tone("bronze", "Bronze", Color3.fromRGB(155, 103, 60)),
	tone("espresso", "Espresso", Color3.fromRGB(90, 57, 32)),
}

local HairOptions: { AccessoryDefinition } = {
	{ Id = "classic_brown", Name = "Classic Brown", AssetId = 376548738 },
	{ Id = "pal", Name = "Pal", AssetId = 376546903 },
	{ Id = "ponytail_black", Name = "Black Ponytail", AssetId = 376524487 },
	{ Id = "chestnut_bun", Name = "Chestnut Bun", AssetId = 376546650 },
}

local FaceOptions: { FaceDefinition } = {
	{ Id = "smile", Name = "Friendly Smile", AssetId = 86487700 },
	{ Id = "freckles", Name = "Freckles", AssetId = 494291269 },
	{ Id = "chill", Name = "Chill", AssetId = 15432080 },
}

local TopOptions: { ClothingDefinition } = {
	{ Id = "denim_jacket", Name = "Denim Jacket", AssetId = 144076760 },
	{ Id = "green_plaid", Name = "Green Plaid", AssetId = 382537398 },
	{ Id = "sporty", Name = "Sporty Hoodie", AssetId = 398633584 },
}

local PantsOptions: { ClothingDefinition } = {
	{ Id = "black_jeans", Name = "Black Jeans", AssetId = 144076868 },
	{ Id = "classic_denim", Name = "Classic Denim", AssetId = 398633584 },
	{ Id = "khaki", Name = "Khaki Pants", AssetId = 256520207 },
}

local AgeOptions: { AgeDefinition } = {
	{
		Id = "Toddler",
		Label = "Toddler",
		Numeric = 0,
		Scales = {
			BodyType = 0.15,
			Height = 0.7,
			Width = 0.85,
			Depth = 0.85,
			Head = 0.95,
			Proportion = 0.3,
		},
	},
	{
		Id = "Teen",
		Label = "Teen",
		Numeric = 1,
		Scales = {
			BodyType = 0.55,
			Height = 0.93,
			Width = 0.95,
			Depth = 0.95,
			Head = 0.98,
			Proportion = 0.6,
		},
	},
	{
		Id = "Adult",
		Label = "Adult",
		Numeric = 2,
		Scales = {
			BodyType = 0.75,
			Height = 1,
			Width = 1,
			Depth = 1,
			Head = 1,
			Proportion = 0.75,
		},
	},
}

local GenderOptions: { GenderDefinition } = {
	{ Id = "Female", Label = "Female" },
	{ Id = "Male", Label = "Male" },
}

local function makeLookup<T>(array: { T }): { [string]: T }
	local map = {} :: { [string]: T }
	for _, item in ipairs(array) do
		local castItem = item :: any
		local rawId = castItem.Id
		if typeof(rawId) == "string" then
			map[rawId] = item
		end
	end
	return map
end

local SkinToneById = makeLookup(SkinTones)
local HairById = makeLookup(HairOptions)
local FaceById = makeLookup(FaceOptions)
local TopById = makeLookup(TopOptions)
local PantsById = makeLookup(PantsOptions)
local AgeById = makeLookup(AgeOptions)
local GenderById = makeLookup(GenderOptions)

local ResidentAppearanceConfig = {}

ResidentAppearanceConfig.SkinTones = SkinTones
ResidentAppearanceConfig.HairOptions = HairOptions
ResidentAppearanceConfig.FaceOptions = FaceOptions
ResidentAppearanceConfig.TopOptions = TopOptions
ResidentAppearanceConfig.PantsOptions = PantsOptions
ResidentAppearanceConfig.AgeOptions = AgeOptions
ResidentAppearanceConfig.GenderOptions = GenderOptions

ResidentAppearanceConfig.SkinToneById = SkinToneById
ResidentAppearanceConfig.HairById = HairById
ResidentAppearanceConfig.FaceById = FaceById
ResidentAppearanceConfig.TopById = TopById
ResidentAppearanceConfig.PantsById = PantsById
ResidentAppearanceConfig.AgeById = AgeById
ResidentAppearanceConfig.GenderById = GenderById

local defaultSelection: AppearanceSelection = {
	SkinToneId = SkinTones[2].Id,
	HairId = HairOptions[1].Id,
	FaceId = FaceOptions[1].Id,
	TopId = TopOptions[1].Id,
	PantsId = PantsOptions[1].Id,
	GenderId = GenderOptions[1].Id,
	AgeId = AgeOptions[3].Id,
}

function ResidentAppearanceConfig.GetDefaultSelection(): AppearanceSelection
	return table.clone(defaultSelection) :: AppearanceSelection
end

function ResidentAppearanceConfig.ResolveSkinTone(id: string?): SkinToneDefinition
	local resolved = if typeof(id) == "string" then SkinToneById[id] else nil
	return resolved or SkinTones[1]
end

function ResidentAppearanceConfig.ResolveHair(id: string?): AccessoryDefinition
	local resolved = if typeof(id) == "string" then HairById[id] else nil
	return resolved or HairOptions[1]
end

function ResidentAppearanceConfig.ResolveFace(id: string?): FaceDefinition
	local resolved = if typeof(id) == "string" then FaceById[id] else nil
	return resolved or FaceOptions[1]
end

function ResidentAppearanceConfig.ResolveTop(id: string?): ClothingDefinition
	local resolved = if typeof(id) == "string" then TopById[id] else nil
	return resolved or TopOptions[1]
end

function ResidentAppearanceConfig.ResolvePants(id: string?): ClothingDefinition
	local resolved = if typeof(id) == "string" then PantsById[id] else nil
	return resolved or PantsOptions[1]
end

function ResidentAppearanceConfig.ResolveAge(id: string?): AgeDefinition
	local resolved = if typeof(id) == "string" then AgeById[id] else nil
	return resolved or AgeOptions[3]
end

function ResidentAppearanceConfig.ResolveAgeByNumeric(value: number?): AgeDefinition
	if typeof(value) == "number" then
		for _, definition in ipairs(AgeOptions) do
			if definition.Numeric == value then
				return definition
			end
		end
	end
	return ResidentAppearanceConfig.ResolveAge(nil)
end

function ResidentAppearanceConfig.ResolveGender(id: string?): GenderDefinition
	local resolved = if typeof(id) == "string" then GenderById[id] else nil
	return resolved or GenderOptions[1]
end

function ResidentAppearanceConfig.CloneSelection(selection: AppearanceSelection): AppearanceSelection
	local cloned = {
		SkinToneId = selection.SkinToneId,
		HairId = selection.HairId,
		FaceId = selection.FaceId,
		TopId = selection.TopId,
		PantsId = selection.PantsId,
		GenderId = selection.GenderId,
		AgeId = selection.AgeId,
	}
	return cloned
end

return ResidentAppearanceConfig
