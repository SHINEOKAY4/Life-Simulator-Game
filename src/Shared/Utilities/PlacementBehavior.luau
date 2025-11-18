--!strict

local PlacementBehavior = {}
local SubSlotResolver = require(script.Parent.SubSlotResolver)

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
		return SubSlotResolver.UsesSubSlots(spec)
	end
	if rules.AllowStacking == true then
		return true
	end
	if isOverlayLayer(rules) then
		return true
	end
	return SubSlotResolver.UsesSubSlots(spec)
end

local function sanitizeSlotIdForLabel(slotId: string): string
	local sanitized = slotId:gsub("[^%w%-_]", "-")
	if sanitized == "" then
		return "Slot"
	end
	return sanitized
end

local function computePlacementKeyLabel(spec: { [string]: any }?): string
	local baseType = resolveBaseType(spec)
	if PlacementBehavior.allowsStacking(spec) then
		return string.format("%sOverlay", baseType)
	end
	return baseType
end

function PlacementBehavior.getPlacementKeyLabel(spec: { [string]: any }?): string
	return computePlacementKeyLabel(spec)
end

function PlacementBehavior.getPlacementKeyLabelForSubSlot(spec: { [string]: any }?, subSlotId: string?): string
	local baseLabel = computePlacementKeyLabel(spec)
	if not subSlotId or subSlotId == "" then
		return baseLabel
	end
	if not SubSlotResolver.UsesSubSlots(spec) then
		return baseLabel
	end
	local normalized = SubSlotResolver.NormalizeSlotId(spec, subSlotId)
	if not normalized or normalized == "" then
		return baseLabel
	end
	local sanitized = sanitizeSlotIdForLabel(normalized)
	return string.format("%s-Slot-%s", baseLabel, sanitized)
end

return PlacementBehavior
