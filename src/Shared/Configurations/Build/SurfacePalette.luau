--!strict
-- ReplicatedStorage/Shared/Configurations/Build/SurfacePalette.luau
-- Defines the canonical palette for structural surfaces (walls/floors).

export type SurfaceKind = "Wall" | "Floor"

export type SurfaceDefinition = {
	Id: string,
	Kind: SurfaceKind,
	DisplayName: string,
	Material: Enum.Material,
	Color: Color3,
	Roughness: number?,
	Metalness: number?,
	Tags: { string }?,
}

local SurfacePalette = {}

local SURFACE_DEFINITIONS: { [string]: SurfaceDefinition } = {
	["wall:plaster-warm"] = {
		Id = "wall:plaster-warm",
		Kind = "Wall",
		DisplayName = "Warm Plaster",
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(244, 237, 226),
		Tags = { "neutral", "matte" },
	},
	["wall:plaster-cool"] = {
		Id = "wall:plaster-cool",
		Kind = "Wall",
		DisplayName = "Cool Plaster",
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(225, 233, 241),
		Tags = { "neutral", "cool" },
	},
	["wall:brick-russet"] = {
		Id = "wall:brick-russet",
		Kind = "Wall",
		DisplayName = "Russet Brick",
		Material = Enum.Material.Brick,
		Color = Color3.fromRGB(169, 88, 73),
		Tags = { "textured", "brick" },
	},
	["floor:oak-herringbone"] = {
		Id = "floor:oak-herringbone",
		Kind = "Floor",
		DisplayName = "Oak Herringbone",
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(201, 170, 125),
		Tags = { "warm", "wood" },
	},
	["floor:walnut-panel"] = {
		Id = "floor:walnut-panel",
		Kind = "Floor",
		DisplayName = "Walnut Panel",
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(143, 111, 82),
		Tags = { "rich", "wood" },
	},
	["floor:stone-slate"] = {
		Id = "floor:stone-slate",
		Kind = "Floor",
		DisplayName = "Slate Stone",
		Material = Enum.Material.Slate,
		Color = Color3.fromRGB(92, 97, 101),
		Tags = { "stone", "cool" },
	},
}

local DEFAULT_SURFACE_BY_KIND: { [SurfaceKind]: string } = {
	Wall = "wall:plaster-warm",
	Floor = "floor:oak-herringbone",
}

local function getPlacementKind(placementType: string?): SurfaceKind?
	if placementType == "Wall" then
		return "Wall"
	elseif placementType == "Floor" then
		return "Floor"
	end
	return nil
end

local function contains(list: { string }?, value: string): boolean
	if typeof(list) ~= "table" then
		return false
	end
	for _, entry in ipairs(list :: { string }) do
		if entry == value then
			return true
		end
	end
	return false
end

function SurfacePalette.GetSurface(surfaceId: string?): SurfaceDefinition?
	if typeof(surfaceId) ~= "string" then
		return nil
	end
	return SURFACE_DEFINITIONS[surfaceId]
end

function SurfacePalette.GetDefaultForKind(kind: SurfaceKind?): string?
	if not kind then
		return nil
	end
	return DEFAULT_SURFACE_BY_KIND[kind]
end

function SurfacePalette.IsSurfaceAllowedForItem(surfaceId: string?, itemSpec: { [string]: any }?): boolean
	if typeof(surfaceId) ~= "string" then
		return false
	end
	local definition = SurfacePalette.GetSurface(surfaceId)
	if not definition then
		return false
	end
	if typeof(itemSpec) ~= "table" then
		return false
	end

	local placementType = itemSpec.PlacementType or itemSpec.Type
	local inferredKind: SurfaceKind? = getPlacementKind(typeof(placementType) == "string" and placementType or nil)
	if not inferredKind or definition.Kind ~= inferredKind then
		return false
	end

	local allowed = itemSpec.AllowedSurfaceIds
	if typeof(allowed) ~= "table" or #allowed == 0 then
		return true
	end

	return contains(allowed :: { string }, surfaceId)
end

function SurfacePalette.ResolveForPlacement(itemSpec: { [string]: any }?, requestedSurfaceId: string?): string?
	if typeof(itemSpec) ~= "table" then
		return nil
	end

	local placementType = itemSpec.PlacementType or itemSpec.Type
	local inferredKind: SurfaceKind? = getPlacementKind(typeof(placementType) == "string" and placementType or nil)
	local candidateId = requestedSurfaceId
	if typeof(candidateId) == "string" and SurfacePalette.IsSurfaceAllowedForItem(candidateId, itemSpec) then
		return candidateId
	end

	local defaultId = if typeof(itemSpec.DefaultSurfaceId) == "string" then itemSpec.DefaultSurfaceId else nil
	if defaultId and SurfacePalette.IsSurfaceAllowedForItem(defaultId, itemSpec) then
		return defaultId
	end

	if inferredKind then
		local fallback = SurfacePalette.GetDefaultForKind(inferredKind)
		if fallback and SurfacePalette.IsSurfaceAllowedForItem(fallback, itemSpec) then
			return fallback
		end
	end

	return nil
end

function SurfacePalette.GetAllByKind(kind: SurfaceKind): { SurfaceDefinition }
	local list: { SurfaceDefinition } = {}
	for _, definition in SURFACE_DEFINITIONS do
		if definition.Kind == kind then
			list[#list + 1] = definition
		end
	end
	table.sort(list, function(left, right)
		if left.DisplayName == right.DisplayName then
			return left.Id < right.Id
		end
		return left.DisplayName < right.DisplayName
	end)
	return list
end

function SurfacePalette.Serialize(definition: SurfaceDefinition?): { [string]: any }?
	if not definition then
		return nil
	end

	return {
		Id = definition.Id,
		Kind = definition.Kind,
		DisplayName = definition.DisplayName,
		Material = definition.Material,
		Color = definition.Color,
	}
end

return SurfacePalette
