-- !strict
-- ReplicatedStorage/Shared/Utilities/ItemFinder.lua

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Floors = require(ReplicatedStorage.Shared.Definitions.Catalog.Floors)
local Walls = require(ReplicatedStorage.Shared.Definitions.Catalog.Walls)
local Furnitures = require(ReplicatedStorage.Shared.Definitions.Catalog.Furnitures)
local Roofs = require(ReplicatedStorage.Shared.Definitions.Catalog.Roofs)
local Decorations = require(ReplicatedStorage.Shared.Definitions.Catalog.Decorations)
local Doors = require(ReplicatedStorage.Shared.Definitions.Catalog.Doors)

local ItemFinder = {}
local ItemsById = {}
local NoTagModels = {}
local TagSetsById = {}

local function merge(group: { [string]: any })
	for id, spec in group do
		assert(ItemsById[id] == nil, ("Duplicate item id: %s"):format(id))
		ItemsById[id] = spec
		
		if spec.Tags then
			local tagSet = {}
			for i = 1, #spec.Tags do
				tagSet[spec.Tags[i]] = true
			end
			TagSetsById[id] = tagSet
		end
	end
end

ItemFinder.Floors = Floors
ItemFinder.Walls = Walls
ItemFinder.Furnitures = Furnitures
ItemFinder.Roofs = Roofs
ItemFinder.Doors = Doors

merge(Floors)
merge(Walls)
merge(Furnitures)
merge(Roofs)
merge(Decorations)
merge(Doors)

function ItemFinder.FindItemById(itemId: string)
	return ItemsById[itemId]
end

function ItemFinder.GetCategory(category: string)
	return ItemFinder[category] or {}
end

function ItemFinder.Exists(itemId: string): boolean
	return ItemsById[itemId] ~= nil
end

function ItemFinder.HasTag(itemId: string, tag: string): boolean
	local tagSet = TagSetsById[itemId]
	return tagSet ~= nil and tagSet[tag] == true
end

function ItemFinder.AnyTag(itemId: string, tags: { string }): boolean
	local tagSet = TagSetsById[itemId]
	if not tagSet then
		return false
	end

	for i = 1, #tags do
		if tagSet[tags[i]] then
			return true
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
	if NoTagModels[itemId] then
		return NoTagModels[itemId]:Clone()
	end
	return ItemFinder.ResolveItemModel(itemId):Clone()
end

function ItemFinder.ManageModelTags()
	for itemId, _ in pairs(ItemsById) do
		local model = ItemFinder.CloneModel(itemId)
		if model then
			local tags = model:GetTags()
			for _, tag in ipairs(tags) do
				model:RemoveTag(tag)
			end
			NoTagModels[itemId] = model
		end
	end
end

if RunService:IsServer() then
	ItemFinder.ManageModelTags()
end
return ItemFinder
