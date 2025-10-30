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

local ActiveSessions: { [number]: { [string]: CookingSession } } = {}

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

local function dispatchKitchenState(player: Player, state: KitchenStateData)
	FoodPackets.KitchenStateUpdate:FireClient(player, buildKitchenPayload(state))
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
	local available = computeAggregateIngredients(state)
	for recipeId, recipe in pairs(MealRecipes) do
		if recipeId and FoodUtils.CanSatisfyRecipe(available, recipe.Ingredients) then
			return true
		end
	end
	return false
end

function KitchenService.HasPreparedMeal(player: Player): boolean
	local state = KitchenService.TryGetKitchenState(player)
	if not state then
		return false
	end
	local meals = state.Meals or {}
	for _, portions in pairs(meals) do
		if portions and portions > 0 then
			return true
		end
	end
	return false
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
	behavior.Effects = {
		{
			Need = "Hunger",
			InstantAmount = FoodUtils.ComputeHungerEffect(recipe.HungerRestore),
		},
	}
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

function KitchenService.CompleteCooking(session: CookingSession)
	if session.Completed or session.Cancelled then
		return
	end
	session.Completed = true
	local state = getKitchenStateBlocking(session.Player)
	if not state then
		clearSession(session)
		return
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

	local state = getKitchenStateBlocking(player)
	if not state then
		return false, "Kitchen unavailable."
	end

	CurrencyService.Remove(player, "Cash", totalCost, currencyState)
	local batchQuantity = ingredientSpec.PurchaseQuantity * sanitizedQuantity
	FoodUtils.AddIngredients(state.Ingredients or {}, {
		{ IngredientId = ingredientId, Quantity = batchQuantity },
	})
	dispatchKitchenState(player, state)
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
