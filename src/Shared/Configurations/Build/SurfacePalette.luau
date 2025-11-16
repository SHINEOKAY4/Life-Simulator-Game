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
	Transparency: number?,
	Tags: { string }?,
}

local SurfacePalette = {}
local DYNAMIC_PREFIX = "enum"
local MATERIAL_TRANSPARENCY: { [Enum.Material]: number } = {
	[Enum.Material.Glass] = 0.35,
}

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
	["floor:plaster-warm"] = {
		Id = "floor:plaster-warm",
		Kind = "Floor",
		DisplayName = "Matte Plaster",
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(244, 237, 226),
		Tags = { "neutral", "matte" },
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

local function toLower(str: string): string
	return string.lower(str)
end

local MATERIAL_LOOKUP: { [string]: Enum.Material } = {}
for _, material in ipairs(Enum.Material:GetEnumItems()) do
	MATERIAL_LOOKUP[toLower(material.Name)] = material
end

local function resolveEnumMaterial(candidate: string?): Enum.Material?
	if typeof(candidate) ~= "string" then
		return nil
	end
	local normalized = toLower(candidate)
	return MATERIAL_LOOKUP[normalized]
end

local function makeDynamicSurfaceId(kind: SurfaceKind, material: Enum.Material): string
	return string.format("%s:%s:%s", DYNAMIC_PREFIX, kind, material.Name)
end

local function ensureDynamicDefinition(kind: SurfaceKind, material: Enum.Material): SurfaceDefinition
	local surfaceId = makeDynamicSurfaceId(kind, material)
	local existing = SURFACE_DEFINITIONS[surfaceId]
	if existing then
		return existing
	end
	local defaultTransparency = MATERIAL_TRANSPARENCY[material]
	local definition: SurfaceDefinition = {
		Id = surfaceId,
		Kind = kind,
		DisplayName = material.Name,
		Material = material,
		Color = Color3.new(1, 1, 1),
		Transparency = defaultTransparency,
	}
	SURFACE_DEFINITIONS[surfaceId] = definition
	return definition
end

local function parseDynamicSurfaceId(surfaceId: string?): (SurfaceKind?, string?)
	if typeof(surfaceId) ~= "string" then
		return nil, nil
	end
	if not string.find(surfaceId, DYNAMIC_PREFIX .. ":", 1, true) then
		return nil, nil
	end
	local kindToken, materialName = string.match(surfaceId, "^" .. DYNAMIC_PREFIX .. ":([^:]+):(.+)$")
	if not kindToken or not materialName then
		return nil, nil
	end
	if kindToken ~= "Wall" and kindToken ~= "Floor" then
		return nil, nil
	end
	return kindToken :: SurfaceKind, materialName
end

local function isDynamicSurfaceId(surfaceId: string?): boolean
	local kindToken = select(1, parseDynamicSurfaceId(surfaceId))
	return kindToken ~= nil
end

local DEFAULT_SURFACE_BY_KIND: { [SurfaceKind]: string } = {
	Wall = "wall:plaster-warm",
	Floor = "floor:plaster-warm",
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

local function resolveDynamicSurfaceId(kind: SurfaceKind?, candidate: string?): string?
	if not candidate or candidate == "" then
		return nil
	end
	local parsedKind, parsedMaterial = parseDynamicSurfaceId(candidate)
	if parsedKind and parsedMaterial then
		local material = resolveEnumMaterial(parsedMaterial)
		if material then
			local dynamicKind: SurfaceKind = if parsedKind == "Wall" then "Wall" else "Floor"
			return ensureDynamicDefinition(dynamicKind, material).Id
		end
		return nil
	end
	if kind ~= "Wall" and kind ~= "Floor" then
		return nil
	end
	local material = resolveEnumMaterial(candidate)
	if not material then
		return nil
	end
	return ensureDynamicDefinition(kind, material).Id
end

function SurfacePalette.GetSurface(surfaceId: string?): SurfaceDefinition?
	if typeof(surfaceId) ~= "string" then
		return nil
	end
	local definition = SURFACE_DEFINITIONS[surfaceId]
	if definition then
		if definition.Transparency == nil then
			local fallback = MATERIAL_TRANSPARENCY[definition.Material]
			if fallback ~= nil then
				definition.Transparency = fallback
			end
		end
		return definition
	end
	local kind, materialName = parseDynamicSurfaceId(surfaceId)
	if kind and materialName then
		local material = resolveEnumMaterial(materialName)
		if material then
			local dynamicKind: SurfaceKind = if kind == "Wall" then "Wall" else "Floor"
			return ensureDynamicDefinition(dynamicKind, material)
		end
	end
	return nil
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

	if contains(allowed :: { string }, surfaceId) then
		return true
	end

	if isDynamicSurfaceId(surfaceId) then
		return true
	end

	return false
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
	if inferredKind and typeof(candidateId) == "string" and candidateId ~= "" then
		local dynamicId = resolveDynamicSurfaceId(inferredKind, candidateId)
		if dynamicId and SurfacePalette.IsSurfaceAllowedForItem(dynamicId, itemSpec) then
			return dynamicId
		end
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
		Transparency = definition.Transparency,
	}
end

return SurfacePalette
