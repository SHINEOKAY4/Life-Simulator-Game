--!strict
-- ServerScriptService/Server/Services/KitchenService.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local ServicesFolder = ServerScriptService.Server.Services

local PlayerSession = require(ServicesFolder.PlayerSession)
local CurrencyService = require(ServicesFolder.CurrencyService)
local PlotService = require(ServicesFolder.PlotService)
local FoodPackets = require(ReplicatedStorage.Network.FoodPackets)
local MealRecipesModule = require(ReplicatedStorage.Shared.Definitions.MealRecipes)
local IngredientsCatalog = require(ReplicatedStorage.Shared.Definitions.Ingredients)
local FoodUtils = require(ReplicatedStorage.Shared.Utilities.FoodUtils)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local MealRecipes = MealRecipesModule.Recipes
local RecipeEvaluationOrder = MealRecipesModule.DefaultOrder
local RecipeFallbackId = MealRecipesModule.DefaultFallback
local HungerRestoreCache: { [string]: number } = {}

export type ContainerEntry = {
	StationType: string,
	ItemId: string?,
	Capacity: number?,
	Ingredients: { [string]: number },
}

export type KitchenStateData = {
	Version: number?,
	Ingredients: { [string]: number }?,
	Meals: { [string]: number }?,
	Containers: { [string]: ContainerEntry }?,
	LastCookedAt: number?,
	Seeded: boolean?,
}

export type CookingSession = {
	Player: Player,
	ResidentName: string,
	RecipeId: string,
	Recipe: MealRecipesModule.MealRecipe,
	ReservedPantry: { [string]: number },
	ReservedContainers: { [string]: { [string]: number } },
	StartedAt: number,
	ManualOverride: boolean,
	StationId: string?,
	Completed: boolean,
	Cancelled: boolean,
}

export type IngredientGrantEntry = {
	IngredientId: string,
	Quantity: number,
}

export type IngredientGrantOptions = {
	SourceId: string?,
	SourceName: string?,
	NotifyClient: boolean?,
	Mutator: ((KitchenStateData) -> ())?,
	TargetContainerId: string?,
	TargetStationType: string?,
	TargetItemId: string?,
	TargetCapacity: number?,
}

type GrantNoticePayloadEntry = {
	Id: string,
	Quantity: number,
	Image: string,
}

type GrantNoticePayload = {
	SourceId: string,
	SourceName: string,
	Entries: { GrantNoticePayloadEntry },
}

type AllowedLookup = { [string]: boolean }

type ResolvedStorageConfig = {
	Capacity: number,
	AllowedIngredients: AllowedLookup?,
	AllowedTags: AllowedLookup?,
}

local KitchenService = {}

local STATE_VERSION = 1
local MAX_STORAGE_CAPACITY = 300
local DEFAULT_PANTRY: { [string]: number } = {
	FreshProduce = 4,
	WholeGrains = 3,
	LeanProtein = 3,
	ComfortSeasoning = 1,
}
local MAX_PURCHASE_QUANTITY = 12
local MAX_PANTRY_QUANTITY = 65535
local GRANT_NOTICE_MAX_QUANTITY = 255

local ActiveSessions: { [number]: { [string]: CookingSession } } = {}

type KitchenAvailabilityEntry = {
	HasCookable: boolean,
	HasEdible: boolean,
	BestContainerId: string?,
	HasPreparedMeal: boolean,
	BestMealId: string?,
	BestMealServings: number,
	BestMealHungerPerPortion: number,
	BestMealMoodBonus: number,
	ComputedAt: number,
}

export type KitchenAvailabilitySnapshot = KitchenAvailabilityEntry

local KitchenAvailabilityCache: { [number]: KitchenAvailabilityEntry } = {}

local function invalidateKitchenAvailability(userId: number)
	KitchenAvailabilityCache[userId] = nil
end

local function sanitizePositiveInteger(value: any): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	local rounded = math.floor(value + 0.5)
	if rounded < 0 then
		return 0
	end
	return rounded
end

local function sanitizeInventory(inventory: any?): { [string]: number }
	if typeof(inventory) ~= "table" then
		return {}
	end
	for key, amount in pairs(inventory) do
		if typeof(key) ~= "string" then
			inventory[key] = nil
		else
			local sanitized = sanitizePositiveInteger(amount)
			if sanitized <= 0 then
				inventory[key] = nil
			else
				inventory[key] = sanitized
			end
		end
	end
	return inventory
end

local function clampCapacity(rawCapacity: any): number?
	if typeof(rawCapacity) ~= "number" then
		return nil
	end
	local rounded = sanitizePositiveInteger(rawCapacity)
	if rounded <= 0 then
		return nil
	end
	return math.min(rounded, MAX_STORAGE_CAPACITY)
end

local function buildLookup(list: any?): AllowedLookup?
	if typeof(list) ~= "table" then
		return nil
	end
	local lookup: AllowedLookup = {}
	local count = 0
	for _, value in ipairs(list) do
		if typeof(value) == "string" and value ~= "" then
			lookup[value] = true
			count += 1
		end
	end
	if count == 0 then
		return nil
	end
	return lookup
end

local function resolveStorageConfigFromSpec(itemSpec: any): ResolvedStorageConfig?
	if typeof(itemSpec) ~= "table" then
		return nil
	end
	local rawConfig = itemSpec.StorageConfig
	if typeof(rawConfig) ~= "table" then
		return nil
	end
	local capacity = clampCapacity(rawConfig.Capacity)
	if not capacity then
		return nil
	end
	return {
		Capacity = capacity,
		AllowedIngredients = buildLookup(rawConfig.AllowedIngredients),
		AllowedTags = buildLookup(rawConfig.AllowedTags),
	}
end

local function ingredientAllowedForStorage(ingredientId: string, config: ResolvedStorageConfig): boolean
	local allowedIngredients = config.AllowedIngredients
	if allowedIngredients and not allowedIngredients[ingredientId] then
		return false
	end
	local allowedTags = config.AllowedTags
	if allowedTags then
		local ingredientSpec = IngredientsCatalog[ingredientId]
		local tags = ingredientSpec and ingredientSpec.Tags
		if typeof(tags) == "table" then
			for _, tag in ipairs(tags) do
				if allowedTags[tag] then
					return true
				end
			end
			return false
		end
		return false
	end
	return true
end

local function sanitizeContainerEntry(rawEntry: any): ContainerEntry?
	if typeof(rawEntry) ~= "table" then
		return nil
	end
	local stationType = rawEntry.StationType
	if typeof(stationType) ~= "string" or stationType == "" then
		stationType = "CookStation"
	end
	local itemId = rawEntry.ItemId
	if typeof(itemId) ~= "string" or itemId == "" then
		itemId = nil
	end
	local rawIngredients = rawEntry.Ingredients
	local ingredients: { [string]: number }
	if typeof(rawIngredients) ~= "table" then
		ingredients = {}
	else
		ingredients = sanitizeInventory(rawIngredients)
	end
	local capacity = clampCapacity(rawEntry.Capacity)
	return {
		StationType = stationType,
		ItemId = itemId,
		Capacity = capacity,
		Ingredients = ingredients,
	}
end

local function sanitizeContainerMap(containers: any): { [string]: ContainerEntry }
	local sanitized: { [string]: ContainerEntry } = {}
	if typeof(containers) ~= "table" then
		return sanitized
	end
	for containerId, entry in pairs(containers) do
		if typeof(containerId) == "string" and containerId ~= "" then
			local sanitizedEntry = sanitizeContainerEntry(entry)
			if sanitizedEntry then
				sanitized[containerId] = sanitizedEntry
			end
		end
	end
	return sanitized
end

local function ensureContainerMap(state: KitchenStateData): { [string]: ContainerEntry }
	local containers = state.Containers
	if not containers then
		containers = {}
		state.Containers = containers
	end
	return containers :: { [string]: ContainerEntry }
end

local function getOrCreateContainerEntry(
	state: KitchenStateData,
	containerId: string,
	stationType: string,
	itemId: string?,
	capacity: number?
): ContainerEntry
	local containers = ensureContainerMap(state)
	local existing = containers[containerId]
	if existing then
		existing.StationType = stationType
		existing.ItemId = itemId
		existing.Capacity = capacity or existing.Capacity
		return existing
	end
	local entry: ContainerEntry = {
		StationType = stationType,
		ItemId = itemId,
		Capacity = capacity,
		Ingredients = {},
	}
	containers[containerId] = entry
	return entry
end

local function sumIngredients(inventory: { [string]: number }): number
	local total = 0
	for _, amount in pairs(inventory) do
		if typeof(amount) == "number" then
			total += math.max(0, amount)
		end
	end
	return total
end

local function resolveRawHungerRestore(ingredientId: string): number
	local cached = HungerRestoreCache[ingredientId]
	if cached ~= nil then
		return cached
	end
	local spec = IngredientsCatalog[ingredientId]
	if not spec then
		HungerRestoreCache[ingredientId] = 0
		return 0
	end
	local rawValue = spec.RawHungerRestore
	if typeof(rawValue) ~= "number" then
		HungerRestoreCache[ingredientId] = 0
		return 0
	end
	local computed = FoodUtils.ComputeHungerEffect(rawValue)
	HungerRestoreCache[ingredientId] = computed
	return computed
end

type EdibleSelection = {
	Source: "Pantry" | "Container",
	IngredientId: string,
	HungerRestore: number,
	ContainerId: string?,
	Priority: number,
}

local function considerEdibleCandidate(
	bestSelection: EdibleSelection?,
	source: "Pantry" | "Container",
	ingredientId: string,
	hungerRestore: number,
	containerId: string?,
	priority: number
): EdibleSelection?
	if hungerRestore <= 0 then
		return bestSelection
	end
	local candidate: EdibleSelection = {
		Source = source,
		IngredientId = ingredientId,
		HungerRestore = hungerRestore,
		ContainerId = containerId,
		Priority = priority,
	}
	if not bestSelection then
		return candidate
	end
	if priority > bestSelection.Priority then
		return candidate
	end
	if priority == bestSelection.Priority and hungerRestore > bestSelection.HungerRestore then
		return candidate
	end
	if priority == bestSelection.Priority and hungerRestore == bestSelection.HungerRestore then
		if source == "Container" and bestSelection.Source ~= "Container" then
			return candidate
		end
		if
			source == bestSelection.Source
			and source == "Container"
			and (containerId or "") < (bestSelection.ContainerId or "")
		then
			return candidate
		end
		return candidate
	end
	return bestSelection
end

local function selectBestEdibleIngredient(state: KitchenStateData): EdibleSelection?
	local bestSelection: EdibleSelection? = nil

	local containers = state.Containers
	if containers then
		for containerId, entry in pairs(containers) do
			local inventory = entry.Ingredients
			for ingredientId, amount in pairs(inventory) do
				if typeof(ingredientId) == "string" and typeof(amount) == "number" and amount > 0 then
					local hungerRestore = resolveRawHungerRestore(ingredientId)
					bestSelection =
						considerEdibleCandidate(bestSelection, "Container", ingredientId, hungerRestore, containerId, 2)
				end
			end
		end
	end

	local pantry = state.Ingredients
	if pantry then
		for ingredientId, amount in pairs(pantry) do
			if typeof(ingredientId) == "string" and typeof(amount) == "number" and amount > 0 then
				local hungerRestore = resolveRawHungerRestore(ingredientId)
				bestSelection = considerEdibleCandidate(bestSelection, "Pantry", ingredientId, hungerRestore, nil, 1)
			end
		end
	end

	return bestSelection
end

local function consumeEdibleSelection(state: KitchenStateData, selection: EdibleSelection): boolean
	if selection.Source == "Pantry" then
		local pantry = state.Ingredients
		if not pantry then
			return false
		end
		local current = pantry[selection.IngredientId] or 0
		if current <= 0 then
			return false
		end
		if current <= 1 then
			(pantry :: any)[selection.IngredientId] = nil
		else
			pantry[selection.IngredientId] = current - 1
		end
		return true
	end

	local containers = state.Containers
	if not containers then
		return false
	end
	local containerId = selection.ContainerId
	if not containerId then
		return false
	end
	local entry = containers[containerId]
	if not entry then
		return false
	end
	local inventory = entry.Ingredients
	local current = inventory[selection.IngredientId] or 0
	if current <= 0 then
		return false
	end
	if current <= 1 then
		(inventory :: any)[selection.IngredientId] = nil
	else
		inventory[selection.IngredientId] = current - 1
	end
	return true
end

local function computeAggregateIngredients(state: KitchenStateData): { [string]: number }
	local aggregate: { [string]: number } = {}
	local pantry = state.Ingredients or {}
	for ingredientId, amount in pairs(pantry) do
		if typeof(ingredientId) == "string" and typeof(amount) == "number" then
			aggregate[ingredientId] = (aggregate[ingredientId] or 0) + math.max(0, amount)
		end
	end
	local containers = state.Containers
	if containers then
		for _, entry in pairs(containers) do
			for ingredientId, amount in pairs(entry.Ingredients) do
				if typeof(ingredientId) == "string" and typeof(amount) == "number" then
					aggregate[ingredientId] = (aggregate[ingredientId] or 0) + math.max(0, amount)
				end
			end
		end
	end
	return aggregate
end

local function sanitizeGrantEntries(entries: { IngredientGrantEntry }?): { { IngredientId: string, Quantity: number } }
	local sanitized: { { IngredientId: string, Quantity: number } } = {}
	if typeof(entries) ~= "table" then
		return sanitized
	end
	local aggregate: { [string]: number } = {}
	for _, entry in ipairs(entries :: { any }) do
		if typeof(entry) == "table" then
			local ingredientId = entry.IngredientId or entry.Id
			local quantityValue = entry.Quantity or entry.Amount or entry.Count
			if typeof(ingredientId) == "string" and ingredientId ~= "" and IngredientsCatalog[ingredientId] then
				local quantity = sanitizePositiveInteger(quantityValue)
				if quantity > 0 then
					aggregate[ingredientId] = math.min((aggregate[ingredientId] or 0) + quantity, MAX_PANTRY_QUANTITY)
				end
			end
		end
	end
	for ingredientId, quantity in pairs(aggregate) do
		sanitized[#sanitized + 1] = { IngredientId = ingredientId, Quantity = math.min(quantity, MAX_PANTRY_QUANTITY) }
	end
	table.sort(sanitized, function(a, b)
		return a.IngredientId < b.IngredientId
	end)
	return sanitized
end

local function collectSortedKeys(dictionary: { [string]: any }): { string }
	local keys: { string } = {}
	for key, _ in pairs(dictionary) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	return keys
end

local function restoreReservations(
	state: KitchenStateData,
	reservedPantry: { [string]: number },
	reservedContainers: { [string]: { [string]: number } }
)
	local pantry = state.Ingredients
	if not pantry then
		pantry = {}
		state.Ingredients = pantry
	end
	local pantryInventory = pantry :: { [string]: number }
	for ingredientId, amount in pairs(reservedPantry) do
		pantryInventory[ingredientId] = (pantryInventory[ingredientId] or 0) + amount
	end
	if next(reservedContainers) == nil then
		return
	end
	local containers = ensureContainerMap(state)
	for containerId, ingredients in pairs(reservedContainers) do
		local entry = containers[containerId]
		if not entry then
			entry = {
				StationType = "CookStation",
				ItemId = nil,
				Capacity = nil,
				Ingredients = {},
			}
			containers[containerId] = entry
		end
		local inventory = entry.Ingredients
		for ingredientId, amount in pairs(ingredients) do
			inventory[ingredientId] = (inventory[ingredientId] or 0) + amount
		end
	end
end

local function allocateIngredientsForRecipe(
	state: KitchenStateData,
	recipe: MealRecipesModule.MealRecipe
): (boolean, { [string]: number }, { [string]: { [string]: number } })
	local pantry = state.Ingredients
	if not pantry then
		pantry = {}
		state.Ingredients = pantry
	end
	local pantryInventory = pantry :: { [string]: number }
	local containers = state.Containers or {}
	local containerOrder: { string } = {}
	if next(containers) ~= nil then
		containerOrder = collectSortedKeys(containers)
	end
	local reservedPantry: { [string]: number } = {}
	local reservedContainers: { [string]: { [string]: number } } = {}
	for _, requirement in ipairs(recipe.Ingredients) do
		local ingredientId = requirement.IngredientId
		local needed = sanitizePositiveInteger(requirement.Quantity)
		if typeof(ingredientId) ~= "string" or ingredientId == "" or needed <= 0 then
			restoreReservations(state, reservedPantry, reservedContainers)
			return false, reservedPantry, reservedContainers
		end
		local pantryAvailable = pantryInventory[ingredientId] or 0
		if pantryAvailable > 0 then
			local useAmount = math.min(pantryAvailable, needed)
			local nextValue = pantryAvailable - useAmount
			if nextValue <= 0 then
				(pantryInventory :: any)[ingredientId] = nil
			else
				pantryInventory[ingredientId] = nextValue
			end
			reservedPantry[ingredientId] = (reservedPantry[ingredientId] or 0) + useAmount
			needed -= useAmount
		end
		if needed > 0 then
			for _, containerId in ipairs(containerOrder) do
				local entry = containers[containerId]
				if entry then
					local inventory = entry.Ingredients
					local available = inventory[ingredientId] or 0
					if available > 0 then
						local useAmount = math.min(available, needed)
						local nextValue = available - useAmount
						if nextValue <= 0 then
							(inventory :: any)[ingredientId] = nil
						else
							inventory[ingredientId] = nextValue
						end
						local reserved = reservedContainers[containerId]
						if not reserved then
							reserved = {}
							reservedContainers[containerId] = reserved
						end
						reserved[ingredientId] = (reserved[ingredientId] or 0) + useAmount
						needed -= useAmount
						if needed <= 0 then
							break
						end
					end
				end
			end
		end
		if needed > 0 then
			restoreReservations(state, reservedPantry, reservedContainers)
			return false, reservedPantry, reservedContainers
		end
	end
	return true, reservedPantry, reservedContainers
end

local function seedKitchenDefaults(state: KitchenStateData)
	if state.Seeded then
		return
	end
	local ingredients = state.Ingredients or {}
	for ingredientId, quantity in pairs(DEFAULT_PANTRY) do
		if quantity > 0 then
			ingredients[ingredientId] = math.max(ingredients[ingredientId] or 0, quantity)
		end
	end
	state.Ingredients = ingredients
	state.Seeded = true
end

local function sanitizeKitchenState(raw: any?): KitchenStateData?
	if typeof(raw) ~= "table" then
		return nil
	end
	local state = raw :: KitchenStateData
	state.Version = STATE_VERSION
	local ingredients = sanitizeInventory(state.Ingredients)
	state.Ingredients = ingredients
	local meals = sanitizeInventory(state.Meals)
	state.Meals = meals
	local containers = sanitizeContainerMap(state.Containers)
	local basketEntry = containers and containers.HarvestBasket or nil
	if basketEntry then
		for ingredientId, amount in pairs(basketEntry.Ingredients) do
			if typeof(ingredientId) == "string" and typeof(amount) == "number" then
				ingredients[ingredientId] =
					math.clamp((ingredients[ingredientId] or 0) + amount, 0, MAX_PANTRY_QUANTITY)
			end
		end
		containers.HarvestBasket = nil :: any
	end
	state.Containers = containers
	seedKitchenDefaults(state)
	local lastCooked = state.LastCookedAt
	if typeof(lastCooked) ~= "number" or lastCooked ~= lastCooked then
		state.LastCookedAt = 0
	else
		state.LastCookedAt = lastCooked
	end

	return state
end

local function getKitchenStateBlocking(player: Player): KitchenStateData?
	local data = PlayerSession.GetDataAwait(player, "KitchenState")
	return sanitizeKitchenState(data)
end

local function getKitchenStateNonBlocking(player: Player): KitchenStateData?
	local data = PlayerSession.GetData(player, "KitchenState")
	return sanitizeKitchenState(data)
end

function KitchenService.GetKitchenState(player: Player): KitchenStateData?
	return getKitchenStateBlocking(player)
end

function KitchenService.TryGetKitchenState(player: Player): KitchenStateData?
	return getKitchenStateNonBlocking(player)
end

local function getSessionContainer(player: Player): { [string]: CookingSession }
	local container = ActiveSessions[player.UserId]
	if not container then
		container = {}
		ActiveSessions[player.UserId] = container
	end
	return container
end

local function clearSession(session: CookingSession)
	local playerSessions = ActiveSessions[session.Player.UserId]
	if not playerSessions then
		return
	end
	if playerSessions[session.ResidentName] ~= session then
		return
	end
	playerSessions[session.ResidentName] = nil
	if next(playerSessions) == nil then
		ActiveSessions[session.Player.UserId] = nil
	end
end

local function serializeIngredients(map: { [string]: number }): { { Id: string, Quantity: number } }
	local array: { { Id: string, Quantity: number } } = {}
	for id, amount in pairs(map) do
		local quantity = sanitizePositiveInteger(amount)
		if quantity > 0 then
			array[#array + 1] = {
				Id = id,
				Quantity = math.clamp(quantity, 0, 65535),
			}
		end
	end
	table.sort(array, function(a, b)
		if a.Id == b.Id then
			return false
		end
		return a.Id < b.Id
	end)
	return array
end

local function serializeMeals(map: { [string]: number }): { { Id: string, Portions: number } }
	local array: { { Id: string, Portions: number } } = {}
	for id, amount in pairs(map) do
		local portions = sanitizePositiveInteger(amount)
		if portions > 0 then
			array[#array + 1] = {
				Id = id,
				Portions = math.clamp(portions, 0, 65535),
			}
		end
	end
	table.sort(array, function(a, b)
		if a.Id == b.Id then
			return false
		end
		return a.Id < b.Id
	end)
	return array
end

local function buildKitchenPayload(state: KitchenStateData)
	local ingredients = state.Ingredients or {}
	local meals = state.Meals or {}
	local containers = state.Containers or {}
	local serializedContainers = {}
	for containerId, entry in pairs(containers) do
		local stationType = entry.StationType
		if typeof(stationType) ~= "string" or stationType == "" then
			stationType = "CookStation"
		end
		local serializedIngredients = serializeIngredients(entry.Ingredients)
		serializedContainers[#serializedContainers + 1] = {
			Id = containerId,
			StationType = stationType,
			ItemId = entry.ItemId or "",
			Capacity = math.clamp(entry.Capacity or 0, 0, MAX_STORAGE_CAPACITY),
			Ingredients = serializedIngredients,
		}
	end
	table.sort(
		serializedContainers,
		function(a: { StationType: string, Id: string }, b: { StationType: string, Id: string }): boolean
			if a.StationType == b.StationType then
				return a.Id < b.Id
			end
			return a.StationType < b.StationType
		end
	)
	return {
		Ingredients = serializeIngredients(ingredients),
		Meals = serializeMeals(meals),
		LastCookedAt = state.LastCookedAt or 0,
		Containers = serializedContainers,
	}
end

local function buildGrantNoticePayload(
	sanitizedEntries: { { IngredientId: string, Quantity: number } },
	sourceId: string?,
	sourceName: string?
): GrantNoticePayload?
	if #sanitizedEntries == 0 then
		return nil
	end
	local entriesPayload: { GrantNoticePayloadEntry } = {}
	for _, entry in ipairs(sanitizedEntries) do
		local spec = IngredientsCatalog[entry.IngredientId]
		local imageAssetId = ""
		if spec and typeof(spec.ImageAssetId) == "string" then
			imageAssetId = spec.ImageAssetId
		end
		entriesPayload[#entriesPayload + 1] = {
			Id = entry.IngredientId,
			Quantity = math.clamp(entry.Quantity, 0, GRANT_NOTICE_MAX_QUANTITY),
			Image = imageAssetId,
		}
	end
	return {
		SourceId = sourceId or "",
		SourceName = sourceName or "",
		Entries = entriesPayload,
	}
end

local function dispatchKitchenState(player: Player, state: KitchenStateData)
	invalidateKitchenAvailability(player.UserId)
	FoodPackets.KitchenStateUpdate:FireClient(player, buildKitchenPayload(state))
end

local function selectBestEdibleInContainer(state: KitchenStateData, containerId: string): EdibleSelection?
	local containers = state.Containers
	if not containers then
		return nil
	end
	local entry = containers[containerId]
	if not entry then
		return nil
	end
	local bestSelection: EdibleSelection? = nil
	for ingredientId, amount in pairs(entry.Ingredients) do
		if typeof(ingredientId) == "string" and typeof(amount) == "number" and amount > 0 then
			local hungerRestore = resolveRawHungerRestore(ingredientId)
			if hungerRestore > 0 then
				local candidate: EdibleSelection = {
					Source = "Container",
					IngredientId = ingredientId,
					HungerRestore = hungerRestore,
					ContainerId = containerId,
					Priority = 2,
				}
				if not bestSelection or hungerRestore > bestSelection.HungerRestore then
					bestSelection = candidate
				end
			end
		end
	end
	return bestSelection
end

local function selectBestPreparedMeal(state: KitchenStateData): (string?, MealRecipesModule.MealRecipe?, number, number)
	local meals = state.Meals
	if not meals then
		return nil, nil, 0, 0
	end
	local bestId: string? = nil
	local bestRecipe: MealRecipesModule.MealRecipe? = nil
	local bestServings = 0
	local bestMood = 0
	local bestScore = -math.huge
	for mealId, portions in pairs(meals) do
		if typeof(mealId) == "string" and typeof(portions) == "number" and portions > 0 then
			local recipe = MealRecipes[mealId]
			if recipe then
				local hungerPerPortion = FoodUtils.ComputeHungerEffect(recipe.HungerRestore)
				local moodBonus = if typeof(recipe.MoodBonus) == "number" then recipe.MoodBonus else 0
				local score = hungerPerPortion * 100 + moodBonus
				if score > bestScore then
					bestScore = score
					bestId = mealId
					bestRecipe = recipe
					bestServings = math.max(0, math.floor(portions + 0.5))
					bestMood = moodBonus
				end
			end
		end
	end
	return bestId, bestRecipe, bestServings, bestMood
end

local function getKitchenAvailabilityEntry(player: Player, state: KitchenStateData?): KitchenAvailabilityEntry?
	local userId = player.UserId
	local cached = KitchenAvailabilityCache[userId]
	if cached then
		return cached
	end

	state = state or KitchenService.TryGetKitchenState(player)
	if not state then
		return nil
	end

	local available = computeAggregateIngredients(state)
	local canCook = false
	for _, recipe in pairs(MealRecipes) do
		if recipe and FoodUtils.CanSatisfyRecipe(available, recipe.Ingredients) then
			canCook = true
			break
		end
	end

	local selection = selectBestEdibleIngredient(state)
	local bestContainerId: string? = nil
	local hasEdible = selection ~= nil
	if selection and selection.Source == "Container" then
		bestContainerId = selection.ContainerId
	end

	local bestMealId, bestMealRecipe, bestMealServings, bestMealMood = selectBestPreparedMeal(state)
	local bestMealHungerPerPortion = 0
	if bestMealRecipe then
		bestMealHungerPerPortion = FoodUtils.ComputeHungerEffect(bestMealRecipe.HungerRestore)
	end
	local hasPreparedMeal = bestMealId ~= nil and bestMealServings > 0 and bestMealHungerPerPortion > 0

	local entry: KitchenAvailabilityEntry = {
		HasCookable = canCook,
		HasEdible = hasEdible,
		BestContainerId = bestContainerId,
		HasPreparedMeal = hasPreparedMeal,
		BestMealId = if hasPreparedMeal then bestMealId else nil,
		BestMealServings = if hasPreparedMeal then bestMealServings else 0,
		BestMealHungerPerPortion = if hasPreparedMeal then bestMealHungerPerPortion else 0,
		BestMealMoodBonus = if hasPreparedMeal then bestMealMood else 0,
		ComputedAt = os.clock(),
	}
	KitchenAvailabilityCache[userId] = entry
	return entry
end

function KitchenService.GetPreparedMealCandidate(
	player: Player
): (string?, MealRecipesModule.MealRecipe?, number, number, number)
	local entry = getKitchenAvailabilityEntry(player, nil)
	if not entry or not entry.HasPreparedMeal or not entry.BestMealId then
		return nil, nil, 0, 0, 0
	end
	local recipe = MealRecipes[entry.BestMealId]
	if not recipe then
		return nil, nil, 0, 0, 0
	end
	return entry.BestMealId, recipe, entry.BestMealServings, entry.BestMealHungerPerPortion, entry.BestMealMoodBonus
end

function KitchenService.PeekBestEdibleContainer(player: Player): string?
	local state = KitchenService.TryGetKitchenState(player)
	if not state then
		return nil
	end
	local entry = getKitchenAvailabilityEntry(player, state)
	if not entry then
		return nil
	end
	return entry.BestContainerId
end

function KitchenService.TryConsumeEdibleFromContainer(player: Player, containerId: string): (boolean, number?)
	if typeof(containerId) ~= "string" or containerId == "" then
		return false, nil
	end
	local state = getKitchenStateBlocking(player)
	if not state then
		return false, nil
	end
	local selection = selectBestEdibleInContainer(state, containerId)
	if not selection then
		return false, nil
	end
	if not consumeEdibleSelection(state, selection) then
		return false, nil
	end
	dispatchKitchenState(player, state)
	return true, selection.HungerRestore
end

function KitchenService.HasEdibleIngredient(player: Player): boolean
	local state = KitchenService.TryGetKitchenState(player)
	if not state then
		return false
	end
	local entry = getKitchenAvailabilityEntry(player, state)
	return entry ~= nil and entry.HasEdible
end

function KitchenService.TryConsumeBestEdibleIngredient(player: Player): (boolean, number?)
	local state = KitchenService.TryGetKitchenState(player)
	if not state then
		return false, nil
	end
	local selection = selectBestEdibleIngredient(state)
	if not selection then
		return false, nil
	end
	if not consumeEdibleSelection(state, selection) then
		return false, nil
	end
	dispatchKitchenState(player, state)
	return true, selection.HungerRestore
end

function KitchenService.ApplyIngredientGrant(
	player: Player,
	entries: { IngredientGrantEntry },
	options: IngredientGrantOptions?
): (boolean, string?, { { IngredientId: string, Quantity: number } }?)
	local state = getKitchenStateBlocking(player)
	if not state then
		return false, "KitchenStateUnavailable", nil
	end
	local sanitizedEntries = sanitizeGrantEntries(entries)
	if #sanitizedEntries == 0 then
		return false, "NoValidIngredients", nil
	end
	local pantry = state.Ingredients
	if not pantry then
		pantry = {}
		state.Ingredients = pantry
	end

	local finalEntries = sanitizedEntries
	local targetContainerId = if options then options.TargetContainerId else nil
	if targetContainerId and targetContainerId ~= "" then
		local stationType = "HarvestStorage"
		if options and typeof(options.TargetStationType) == "string" and options.TargetStationType ~= "" then
			stationType = options.TargetStationType
		end
		local itemId = if options
				and typeof(options.TargetItemId) == "string"
				and options.TargetItemId ~= ""
			then options.TargetItemId
			else nil
		local capacityValue: number? = nil
		if options and typeof(options.TargetCapacity) == "number" then
			local clamped = clampCapacity(options.TargetCapacity)
			capacityValue = clamped
		end
		local containerEntry = getOrCreateContainerEntry(state, targetContainerId, stationType, itemId, capacityValue)
		if capacityValue then
			containerEntry.Capacity = capacityValue
		end
		local inventory = containerEntry.Ingredients
		local appliedEntries: { { IngredientId: string, Quantity: number } } = {}
		local remainingCapacity: number? = nil
		if containerEntry.Capacity and containerEntry.Capacity > 0 then
			remainingCapacity = math.max(0, containerEntry.Capacity - sumIngredients(inventory))
		end
		for _, entry in ipairs(sanitizedEntries) do
			if remainingCapacity and remainingCapacity <= 0 then
				break
			end
			local requested = entry.Quantity
			if requested <= 0 then
				continue
			end
			local allowed = requested
			if remainingCapacity then
				allowed = math.min(allowed, remainingCapacity)
			end
			if allowed <= 0 then
				continue
			end
			local current = inventory[entry.IngredientId] or 0
			local maxAddition = math.max(0, MAX_PANTRY_QUANTITY - current)
			if maxAddition <= 0 then
				continue
			end
			local applied = math.min(allowed, maxAddition)
			if applied <= 0 then
				continue
			end
			inventory[entry.IngredientId] = current + applied
			appliedEntries[#appliedEntries + 1] = {
				IngredientId = entry.IngredientId,
				Quantity = applied,
			}
			if remainingCapacity then
				remainingCapacity -= applied
			end
		end
		if #appliedEntries == 0 then
			return false, "StorageFull", nil
		end
		finalEntries = appliedEntries
	else
		FoodUtils.AddIngredients(pantry :: { [string]: number }, sanitizedEntries)
		finalEntries = sanitizedEntries
	end
	if options and options.Mutator then
		options.Mutator(state)
	end
	dispatchKitchenState(player, state)
	if not (options and options.NotifyClient == false) then
		local payload =
			buildGrantNoticePayload(finalEntries, options and options.SourceId, options and options.SourceName)
		if payload then
			FoodPackets.IngredientGrantNotice:FireClient(player, payload)
		end
	end
	return true, nil, finalEntries
end

local function selectRecipeId(state: KitchenStateData, requestedId: string?): string?
	local available = computeAggregateIngredients(state)
	if requestedId then
		local requested = MealRecipes[requestedId]
		if requested and FoodUtils.CanSatisfyRecipe(available, requested.Ingredients) then
			return requestedId
		end
	end

	for _, recipeId in ipairs(RecipeEvaluationOrder) do
		local recipe = MealRecipes[recipeId]
		if recipe and FoodUtils.CanSatisfyRecipe(available, recipe.Ingredients) then
			return recipeId
		end
	end

	if RecipeFallbackId then
		local fallback = MealRecipes[RecipeFallbackId]
		if fallback and FoodUtils.CanSatisfyRecipe(available, fallback.Ingredients) then
			return fallback.Id
		end
	end

	for recipeId, recipe in pairs(MealRecipes) do
		if FoodUtils.CanSatisfyRecipe(available, recipe.Ingredients) then
			return recipeId
		end
	end

	return nil
end

function KitchenService.HasCookableRecipe(player: Player): boolean
	local state = KitchenService.TryGetKitchenState(player)
	if not state then
		return false
	end
	local entry = getKitchenAvailabilityEntry(player, state)
	return entry ~= nil and entry.HasCookable
end

function KitchenService.HasPreparedMeal(player: Player): boolean
	local entry = getKitchenAvailabilityEntry(player, nil)
	return entry ~= nil and entry.HasPreparedMeal
end

function KitchenService.GetAvailabilitySnapshot(player: Player): KitchenAvailabilitySnapshot?
	local entry = getKitchenAvailabilityEntry(player, nil)
	if not entry then
		return nil
	end
	return entry
end

function KitchenService.BeginCooking(
	player: Player,
	assignment: any,
	behavior: any,
	overrides: { RequestedRecipeId: string? }?
): (boolean, CookingSession | string)
	local state = getKitchenStateBlocking(player)
	if not state then
		return false, "KitchenStateUnavailable"
	end
	local requestedRecipeId = overrides and overrides.RequestedRecipeId or nil
	local recipeId = selectRecipeId(state, requestedRecipeId)
	if not recipeId then
		return false, "NoCookableRecipe"
	end

	local recipe = MealRecipes[recipeId]
	if not recipe then
		return false, "RecipeMissing"
	end

	local success, reservedPantry, reservedContainers = allocateIngredientsForRecipe(state, recipe)
	if not success then
		return false, "InsufficientIngredients"
	end
	state.LastCookedAt = os.clock()
	dispatchKitchenState(player, state)

	behavior.DurationSeconds = recipe.CookTimeSeconds
	behavior.ChatPhrases = behavior.ChatPhrases or {
		"Putting together a " .. recipe.Name .. ".",
	}

	local session: CookingSession = {
		Player = player,
		ResidentName = assignment.ResidentName,
		RecipeId = recipeId,
		Recipe = recipe,
		ReservedPantry = reservedPantry,
		ReservedContainers = reservedContainers,
		StartedAt = os.clock(),
		ManualOverride = assignment.ManualOverride == true,
		StationId = assignment.StationId,
		Completed = false,
		Cancelled = false,
	}

	local container = getSessionContainer(player)
	container[assignment.ResidentName] = session
	return true, session
end

local function refundReservedIngredients(session: CookingSession, state: KitchenStateData)
	local pantry = state.Ingredients
	if not pantry then
		pantry = {}
		state.Ingredients = pantry
	end
	local pantryInventory = pantry :: { [string]: number }
	for ingredientId, quantity in pairs(session.ReservedPantry) do
		pantryInventory[ingredientId] = (pantryInventory[ingredientId] or 0) + quantity
	end
	if next(session.ReservedContainers) == nil then
		return
	end
	local containers = state.Containers or {}
	for containerId, ingredients in pairs(session.ReservedContainers) do
		local entry = containers[containerId]
		if entry then
			local inventory = entry.Ingredients
			for ingredientId, quantity in pairs(ingredients) do
				inventory[ingredientId] = (inventory[ingredientId] or 0) + quantity
			end
		else
			for ingredientId, quantity in pairs(ingredients) do
				pantryInventory[ingredientId] = (pantryInventory[ingredientId] or 0) + quantity
			end
		end
	end
end

function KitchenService.CancelCooking(session: CookingSession, _reason: string?)
	if session.Cancelled or session.Completed then
		return
	end
	session.Cancelled = true
	local state = getKitchenStateBlocking(session.Player)
	if state then
		refundReservedIngredients(session, state)
		dispatchKitchenState(session.Player, state)
	end
	clearSession(session)
end

function KitchenService.CompleteCooking(session: CookingSession): (number, MealRecipesModule.MealRecipe?)
	if session.Completed or session.Cancelled then
		return 0, session.Recipe
	end
	session.Completed = true
	local state = getKitchenStateBlocking(session.Player)
	if not state then
		clearSession(session)
		return 0, session.Recipe
	end

	local recipe = session.Recipe
	local servings = math.max(1, recipe.Servings)
	local autoConsume = math.clamp(recipe.AutoConsumePortions or 1, 0, servings)
	local stored = servings - autoConsume

	if stored > 0 then
		FoodUtils.AddMealPortions(state.Meals or {}, recipe.Id, stored)
	end

	state.LastCookedAt = os.clock()
	dispatchKitchenState(session.Player, state)
	clearSession(session)

	return autoConsume, recipe
end

function KitchenService.ConsumePreparedMeal(player: Player, mealId: string, servings: number?): boolean
	local state = getKitchenStateBlocking(player)
	if not state then
		return false
	end
	local mealInventory = state.Meals or {}
	state.Meals = mealInventory
	local consumeCount = sanitizePositiveInteger(servings or 1)
	if consumeCount <= 0 then
		return false
	end
	FoodUtils.RemoveMealPortions(mealInventory, mealId, consumeCount)
	dispatchKitchenState(player, state)
	return true
end

local function handlePurchaseRequest(player: Player, ingredientId: string, quantity: number): (boolean, string)
	local ingredientSpec = IngredientsCatalog[ingredientId]
	if not ingredientSpec then
		return false, "Unknown ingredient."
	end
	local sanitizedQuantity = math.max(1, math.min(MAX_PURCHASE_QUANTITY, sanitizePositiveInteger(quantity)))
	local totalCost = ingredientSpec.PurchaseCost * sanitizedQuantity

	local currencyState = PlayerSession.GetDataAwait(player, "CurrencyState")
	if not currencyState then
		return false, "Currency unavailable."
	end
	local cashBalance = CurrencyService.Get(player, "Cash", currencyState)
	if cashBalance < totalCost then
		return false, "Not enough cash."
	end

	CurrencyService.Remove(player, "Cash", totalCost, currencyState)
	local batchQuantity = ingredientSpec.PurchaseQuantity * sanitizedQuantity
	local grantEntries = {
		{ IngredientId = ingredientId, Quantity = batchQuantity },
	}
	local success, reason = KitchenService.ApplyIngredientGrant(player, grantEntries, {
		SourceId = "KitchenPurchase",
		SourceName = "Pantry Purchase",
		NotifyClient = false,
	})
	if not success then
		CurrencyService.Add(player, "Cash", totalCost, currencyState, { Source = "KitchenRefund" })
		return false, reason or "Kitchen unavailable."
	end
	return true, string.format("Purchased %d %s", batchQuantity, ingredientSpec.Name)
end

local function formatIngredientName(ingredientId: string): string
	local spec = IngredientsCatalog[ingredientId]
	if spec and typeof(spec.Name) == "string" and spec.Name ~= "" then
		return spec.Name
	end
	return ingredientId
end

local function resolveStationRecord(player: Player, stationType: string, stationId: string): { Id: string }?
	local stationCache = PlotService.GetStationsForPlayer(player)
	local scope = stationCache[stationType]
	if not scope then
		return nil
	end
	return scope[stationId]
end

function KitchenService.TransferPantryToContainer(
	player: Player,
	stationType: string,
	stationId: string,
	ingredientId: string,
	quantity: number
): (boolean, string)
	local sanitizedQuantity = sanitizePositiveInteger(quantity)
	if sanitizedQuantity <= 0 then
		return false, "Quantity must be positive."
	end
	local state = getKitchenStateBlocking(player)
	if not state then
		return false, "Kitchen unavailable."
	end
	local ingredientSpec = IngredientsCatalog[ingredientId]
	if not ingredientSpec then
		return false, "Unknown ingredient."
	end
	local stationRecord = resolveStationRecord(player, stationType, stationId)
	if not stationRecord then
		return false, "Container not found."
	end
	local itemSpec = ItemFinder.FindItemById(stationRecord.Id)
	local storageConfig = resolveStorageConfigFromSpec(itemSpec)
	if not storageConfig then
		return false, "This object cannot store food."
	end
	if not ingredientAllowedForStorage(ingredientId, storageConfig) then
		return false, "That ingredient cannot be stored here."
	end
	local pantry = state.Ingredients
	if not pantry then
		pantry = {}
		state.Ingredients = pantry
	end
	local pantryInventory = pantry :: { [string]: number }
	local pantryAvailable = pantryInventory[ingredientId] or 0
	if pantryAvailable < sanitizedQuantity then
		return false, "Not enough in pantry."
	end
	local entry = getOrCreateContainerEntry(state, stationId, stationType, stationRecord.Id, storageConfig.Capacity)
	local containerInventory = entry.Ingredients
	local currentLoad = sumIngredients(containerInventory)
	if currentLoad + sanitizedQuantity > storageConfig.Capacity then
		return false, "Container is full."
	end
	local nextPantry = pantryAvailable - sanitizedQuantity
	if nextPantry <= 0 then
		(pantryInventory :: any)[ingredientId] = nil
	else
		pantryInventory[ingredientId] = nextPantry
	end
	containerInventory[ingredientId] = (containerInventory[ingredientId] or 0) + sanitizedQuantity
	dispatchKitchenState(player, state)
	local ingredientName = formatIngredientName(ingredientId)
	return true, string.format("Stored %d %s", sanitizedQuantity, ingredientName)
end

function KitchenService.TransferContainerToPantry(
	player: Player,
	stationType: string,
	stationId: string,
	ingredientId: string,
	quantity: number
): (boolean, string)
	local sanitizedQuantity = sanitizePositiveInteger(quantity)
	if sanitizedQuantity <= 0 then
		return false, "Quantity must be positive."
	end
	local state = getKitchenStateBlocking(player)
	if not state then
		return false, "Kitchen unavailable."
	end
	local ingredientSpec = IngredientsCatalog[ingredientId]
	if not ingredientSpec then
		return false, "Unknown ingredient."
	end
	local containers = state.Containers
	if not containers then
		return false, "Container is empty."
	end
	local entry = containers[stationId]
	if not entry then
		return false, "Container is empty."
	end
	entry.StationType = stationType
	local containerInventory = entry.Ingredients
	local available = containerInventory[ingredientId] or 0
	if available < sanitizedQuantity then
		return false, "Not enough stored in container."
	end
	local pantry = state.Ingredients
	if not pantry then
		pantry = {}
		state.Ingredients = pantry
	end
	local pantryInventory = pantry :: { [string]: number }
	pantryInventory[ingredientId] = (pantryInventory[ingredientId] or 0) + sanitizedQuantity
	local nextValue = available - sanitizedQuantity
	if nextValue <= 0 then
		(containerInventory :: any)[ingredientId] = nil
	else
		containerInventory[ingredientId] = nextValue
	end
	dispatchKitchenState(player, state)
	local ingredientName = formatIngredientName(ingredientId)
	return true, string.format("Moved %d %s to pantry", sanitizedQuantity, ingredientName)
end

function KitchenService.Remove(player: Player)
	invalidateKitchenAvailability(player.UserId)
	local sessions = ActiveSessions[player.UserId]
	if not sessions then
		return
	end
	for _, session in pairs(sessions) do
		KitchenService.CancelCooking(session, "PlayerRemoving")
	end
	ActiveSessions[player.UserId] = nil
end

function KitchenService.Init()
	FoodPackets.RequestKitchenState.OnServerInvoke = function(player: Player)
		local state = getKitchenStateBlocking(player)
		if not state then
			return {
				Ingredients = {},
				Meals = {},
				LastCookedAt = 0,
				Containers = {},
			}
		end
		return buildKitchenPayload(state)
	end

	FoodPackets.PurchaseIngredientRequest.OnServerInvoke = function(
		player: Player,
		ingredientId: string,
		quantity: number
	)
		local success, message = handlePurchaseRequest(player, ingredientId, quantity)
		return success, message
	end

	FoodPackets.ContainerTransferRequest.OnServerInvoke = function(
		player: Player,
		stationType: string,
		stationId: string,
		ingredientId: string,
		quantity: number,
		direction: string
	)
		if direction == "Deposit" then
			return KitchenService.TransferPantryToContainer(player, stationType, stationId, ingredientId, quantity)
		elseif direction == "Withdraw" then
			return KitchenService.TransferContainerToPantry(player, stationType, stationId, ingredientId, quantity)
		end
		return false, "Unknown transfer direction."
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		KitchenService.Remove(player)
	end)

	PlotService.StationRemoved:Connect(function(player: Player, stationType: string, stationId: string, _occupants)
		local state = getKitchenStateNonBlocking(player)
		if not state then
			return
		end
		local containers = state.Containers
		if not containers then
			return
		end
		local entry = containers[stationId]
		if not entry then
			return
		end
		if entry.StationType ~= stationType then
			return
		end
		local pantry = state.Ingredients
		if not pantry then
			pantry = {}
			state.Ingredients = pantry
		end
		local pantryInventory = pantry :: { [string]: number }
		local storedIngredients = entry.Ingredients
		if storedIngredients then
			for ingredientId, amount in pairs(storedIngredients) do
				pantryInventory[ingredientId] = (pantryInventory[ingredientId] or 0) + amount
			end
		end
		containers[stationId] = nil
		dispatchKitchenState(player, state)
	end)
end

return KitchenService
