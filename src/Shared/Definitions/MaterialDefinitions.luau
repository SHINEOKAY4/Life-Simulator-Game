--!strict
-- ReplicatedStorage/Shared/Definitions/MaterialDefinitions.luau
-- Central catalogue of core crafting materials and their presentation assets.

local MaterialDefinitions = {}

export type MaterialId = "Wood" | "Stone" | "Metal"

export type MaterialSpec = {
	Id: MaterialId,
	Name: string,
	IconImage: string,
	Description: string?,
}

local DEFAULT_ICON = "rbxassetid://134727745079555"

local materials: { [MaterialId]: MaterialSpec } = {
	Wood = {
		Id = "Wood",
		Name = "Wood",
		IconImage = "rbxassetid://134727745079555",
		Description = "Common lumber gathered from trees.",
	},
	Stone = {
		Id = "Stone",
		Name = "Stone",
		IconImage = "",
		Description = "Rough-cut stone suitable for building and crafting.",
	},
	Metal = {
		Id = "Metal",
		Name = "Metal",
		IconImage = "",
		Description = "Refined metal ingots used in advanced recipes.",
	},
}

MaterialDefinitions.Materials = materials
MaterialDefinitions.DefaultIconImage = DEFAULT_ICON

local byId = table.clone(materials)

MaterialDefinitions.ById = byId

function MaterialDefinitions.Get(materialId: string): MaterialSpec?
	return byId[materialId :: any]
end

return MaterialDefinitions
