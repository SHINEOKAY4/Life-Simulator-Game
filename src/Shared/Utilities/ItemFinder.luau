-- !strict
-- ReplicatedStorage/Shared/Utilities/ItemFinder.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Floors = require(ReplicatedStorage.Shared.Definitions.Catalog.Floors)
local Walls = require(ReplicatedStorage.Shared.Definitions.Catalog.Walls)
local Furnitures = require(ReplicatedStorage.Shared.Definitions.Catalog.Furnitures)
local Roofs = require(ReplicatedStorage.Shared.Definitions.Catalog.Roofs)

local ItemFinder = {}
local ItemsById = {}

local function merge(group: { [string]: any })
	for id, spec in group do
		assert(ItemsById[id] == nil, ("Duplicate item id: %s"):format(id))
		ItemsById[id] = spec
	end
end

merge(Floors)
merge(Walls)
merge(Furnitures)
merge(Roofs)

function ItemFinder.FindItemById(itemId: string)
	return ItemsById[itemId]
end

function ItemFinder.Exists(itemId: string): boolean
	return ItemsById[itemId] ~= nil
end

function ItemFinder.HasTag(itemId: string, tag: string): boolean
	local spec = ItemsById[itemId]

	if not spec or not spec.Tags then
		return false
	end

	for i = 1, #spec.Tags do
		if spec.Tags[i] == tag then
			return true
		end
	end

	return false
end

function ItemFinder.AnyTag(itemId: string, tags: { string }): boolean
	local spec = ItemsById[itemId]

	if not spec or not spec.Tags then
		return false
	end

	for i = 1, #tags do
		for j = 1, #spec.Tags do
			if spec.Tags[j] == tags[i] then
				return true
			end
		end
	end

	return false
end

function ItemFinder.ResolveItemModel(itemId: string): Model
	local spec = ItemsById[itemId]
	assert(spec, ("Unknown item id: %s"):format(itemId))

	local node = ReplicatedStorage.Assets.Catalog
	for i = 1, #spec.ModelPath do
		local segment = spec.ModelPath[i]
		local nextNode = node:FindFirstChild(segment)
		assert(nextNode, ("Model path segment not found: %s"):format(segment))
		node = nextNode
	end

	return node
end

function ItemFinder.CloneModel(itemId: string): Model
	return ItemFinder.ResolveItemModel(itemId):Clone()
end

return ItemFinder
