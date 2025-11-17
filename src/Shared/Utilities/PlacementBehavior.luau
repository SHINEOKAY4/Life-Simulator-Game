--!strict

local PlacementBehavior = {}

local function resolveBaseType(spec: { [string]: any }?): string
	if typeof(spec) == "table" then
		local placementType = spec.PlacementType or spec.Type
		if typeof(placementType) == "string" and placementType ~= "" then
			return placementType
		end
	end
	return "CellObject"
end

local function getRules(spec: { [string]: any }?): { [string]: any }?
	if typeof(spec) ~= "table" then
		return nil
	end
	local rules = spec.Rules
	if typeof(rules) ~= "table" then
		return nil
	end
	return rules
end

local function isOverlayLayer(rules: { [string]: any }?): boolean
	if not rules then
		return false
	end
	local layerValue = rules.FootprintLayer or rules.PlacementLayer
	if typeof(layerValue) ~= "string" then
		return false
	end
	return layerValue:lower() == "overlay"
end

function PlacementBehavior.getBasePlacementType(spec: { [string]: any }?): string
	return resolveBaseType(spec)
end

function PlacementBehavior.allowsStacking(spec: { [string]: any }?): boolean
	local rules = getRules(spec)
	if not rules then
		return false
	end
	if rules.AllowStacking == true then
		return true
	end
	return isOverlayLayer(rules)
end

function PlacementBehavior.getPlacementKeyLabel(spec: { [string]: any }?): string
	local baseType = resolveBaseType(spec)
	if PlacementBehavior.allowsStacking(spec) then
		return string.format("%sOverlay", baseType)
	end
	return baseType
end

return PlacementBehavior
