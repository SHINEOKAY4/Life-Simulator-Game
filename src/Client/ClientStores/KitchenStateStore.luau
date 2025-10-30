--!strict
-- StarterPlayerScripts/Client/ClientStores/KitchenStateStore.luau
-- Maintains the player's kitchen snapshot (pantry, prepared meals, storage containers).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FoodPackets = require(ReplicatedStorage.Network.FoodPackets)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

export type IngredientMap = { [string]: number }
export type ContainerSnapshot = {
	Id: string,
	StationType: string,
	ItemId: string,
	Capacity: number,
	Ingredients: IngredientMap,
}
export type KitchenSnapshot = {
	Pantry: IngredientMap,
	Meals: IngredientMap,
	Containers: { [string]: ContainerSnapshot },
	LastCookedAt: number,
}

local KitchenStateStore = {}
KitchenStateStore.Changed = GoodSignal.new()

local state: KitchenSnapshot = {
	Pantry = {},
	Meals = {},
	Containers = {},
	LastCookedAt = 0,
}

local isInitialized = false

local function cloneMap(map: IngredientMap): IngredientMap
	local copy: IngredientMap = {}
	for ingredientId, quantity in pairs(map) do
		if typeof(ingredientId) == "string" and typeof(quantity) == "number" then
			copy[ingredientId] = quantity
		end
	end
	return copy
end

local function cloneContainer(container: ContainerSnapshot): ContainerSnapshot
	return {
		Id = container.Id,
		StationType = container.StationType,
		ItemId = container.ItemId,
		Capacity = container.Capacity,
		Ingredients = cloneMap(container.Ingredients),
	}
end

local function sanitizeIngredientArray(raw: any): IngredientMap
	local map: IngredientMap = {}
	if typeof(raw) ~= "table" then
		return map
	end
	for _, entry in ipairs(raw :: { any }) do
		if typeof(entry) == "table" then
			local id = entry.Id
			local q = entry.Quantity or entry.Portions
			if typeof(id) == "string" and typeof(q) == "number" and q > 0 then
				map[id] = q
			end
		end
	end
	return map
end

local function applySnapshot(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	state.Pantry = sanitizeIngredientArray(payload.Ingredients)
	state.Meals = sanitizeIngredientArray(payload.Meals)

	local containersPayload = payload.Containers
	local containers: { [string]: ContainerSnapshot } = {}
	if typeof(containersPayload) == "table" then
		for _, entry in ipairs(containersPayload :: { any }) do
			if typeof(entry) == "table" then
				local containerId = entry.Id
				if typeof(containerId) == "string" and containerId ~= "" then
					local capacityValue = 0
					if typeof(entry.Capacity) == "number" and entry.Capacity > 0 then
						capacityValue = entry.Capacity
					end
					containers[containerId] = {
						Id = containerId,
						StationType = if typeof(entry.StationType) == "string" and entry.StationType ~= ""
							then entry.StationType
							else "CookStation",
						ItemId = if typeof(entry.ItemId) == "string" then entry.ItemId else "",
						Capacity = capacityValue,
						Ingredients = sanitizeIngredientArray(entry.Ingredients),
					}
				end
			end
		end
	end
	state.Containers = containers

	local cookedAt = payload.LastCookedAt
	if typeof(cookedAt) == "number" then
		state.LastCookedAt = cookedAt
	end

	KitchenStateStore.Changed:Fire(KitchenStateStore.GetSnapshot())
end

function KitchenStateStore.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	FoodPackets.KitchenStateUpdate.OnClientEvent:Connect(function(payload: any)
		applySnapshot(payload)
	end)

	task.defer(function()
		local success, payload = pcall(function()
			return FoodPackets.RequestKitchenState:Fire()
		end)
		if success and payload then
			applySnapshot(payload)
		end
	end)
end

function KitchenStateStore.GetSnapshot(): KitchenSnapshot
	local containerCopy: { [string]: ContainerSnapshot } = {}
	for id, container in pairs(state.Containers) do
		containerCopy[id] = cloneContainer(container)
	end
	return {
		Pantry = cloneMap(state.Pantry),
		Meals = cloneMap(state.Meals),
		Containers = containerCopy,
		LastCookedAt = state.LastCookedAt,
	}
end

function KitchenStateStore.GetPantry(): IngredientMap
	return cloneMap(state.Pantry)
end

function KitchenStateStore.GetMeals(): IngredientMap
	return cloneMap(state.Meals)
end

function KitchenStateStore.GetContainer(containerId: string): ContainerSnapshot?
	local container = state.Containers[containerId]
	if not container then
		return nil
	end
	return cloneContainer(container)
end

function KitchenStateStore.ResolveContainer(
	containerId: string,
	fallback: { StationType: string?, ItemId: string?, Capacity: number? }?
): ContainerSnapshot?
	local container = KitchenStateStore.GetContainer(containerId)
	if container then
		return container
	end
	if not fallback then
		return nil
	end
	return {
		Id = containerId,
		StationType = fallback.StationType or "CookStation",
		ItemId = fallback.ItemId or "",
		Capacity = fallback.Capacity or 0,
		Ingredients = {},
	}
end

function KitchenStateStore.GetCapacityUsage(containerId: string): (number, number)
	local container = state.Containers[containerId]
	if not container then
		return 0, 0
	end
	local sum = 0
	for _, quantity in pairs(container.Ingredients) do
		if typeof(quantity) == "number" then
			sum += quantity
		end
	end
	return sum, container.Capacity
end

function KitchenStateStore.RequestRefresh()
	local success, payload = pcall(function()
		return FoodPackets.RequestKitchenState:Fire()
	end)
	if success and payload then
		applySnapshot(payload)
	end
	return success, payload
end

return KitchenStateStore
