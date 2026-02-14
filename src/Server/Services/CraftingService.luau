--!strict

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Packages.GoodSignal)
local CraftingPackets = require(ReplicatedStorage.Network.CraftingPackets)
local CraftingItems = require(ReplicatedStorage.Shared.Definitions.CraftingItems)
local CraftingRecipes = require(ReplicatedStorage.Shared.Definitions.CraftingRecipes)
local CraftingStation = require(ReplicatedStorage.Shared.Definitions.CraftingStation)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local InventoryService = require(ServerScriptService.Server.Services.InventoryService)
local ProgressionService = require(ServerScriptService.Server.Services.ProgressionService)

export type SkillRequirement = {
	SkillId: string,
	Level: number,
}

export type IngredientRequirement = {
	ItemId: string,
	Quantity: number,
}

export type CraftingJob = {
	JobId: string,
	Player: Player,
	RecipeId: string,
	StationId: string,
	StartedAt: number,
	EndsAt: number,
	ConsumedIngredients: { [string]: number },
}

local CraftingService = {
	CraftStarted = Signal.new(),
	CraftCompleted = Signal.new(),
	CraftFailed = Signal.new(),
}

local CraftingInventory = InventoryService.new("Crafting", 180, 4, CraftingItems.Definitions)
local ActiveJobsByUserId: { [number]: CraftingJob } = {}

local DEFAULT_AVAILABLE_STATIONS = {
	BasicWorkbench = true,
}

local DEFAULT_SKILLS = {
	"Survival",
	"Carpentry",
	"Cooking",
	"Smithing",
}

local STARTER_RESOURCES = {
	WoodLog = 16,
	StoneChunk = 12,
	Fiber = 10,
	Wheat = 8,
	Herb = 8,
	Water = 8,
	RawMeat = 4,
	IronOre = 8,
	Coal = 8,
	Cloth = 4,
}

local SKILL_BASE_XP = 45
local SKILL_GROWTH = 1.24
local SKILL_MAX_LEVEL = 50

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function skillXpForLevel(level: number): number
	if level <= 1 then
		return math.floor(SKILL_BASE_XP + 0.5)
	end
	return math.floor(SKILL_BASE_XP * (SKILL_GROWTH ^ (level - 1)) + 0.5)
end

local function computeSkillLevel(totalExperience: number): (number, number, number)
	local level = 1
	local remaining = math.max(0, math.floor(totalExperience + 0.5))
	local requirement = skillXpForLevel(level)

	while level < SKILL_MAX_LEVEL and remaining >= requirement do
		remaining -= requirement
		level += 1
		requirement = skillXpForLevel(level)
	end

	if level >= SKILL_MAX_LEVEL then
		remaining = 0
		requirement = 0
	end

	return level, remaining, requirement
end

local function getInventoryRoot(profile: { [string]: any }): { [string]: any }
	if typeof(profile.InventoryState) ~= "table" then
		profile.InventoryState = {}
	end
	return profile.InventoryState
end

local function ensureCraftingState(profile: { [string]: any }): { [string]: any }
	if typeof(profile.CraftingState) ~= "table" then
		profile.CraftingState = {
			Skills = {},
			StarterResourcesGranted = false,
		}
	end

	local craftingState = profile.CraftingState
	if typeof(craftingState.Skills) ~= "table" then
		craftingState.Skills = {}
	end
	if typeof(craftingState.StarterResourcesGranted) ~= "boolean" then
		craftingState.StarterResourcesGranted = false
	end

	for _, skillId in ipairs(DEFAULT_SKILLS) do
		if typeof(craftingState.Skills[skillId]) ~= "table" then
			craftingState.Skills[skillId] = {
				Experience = 0,
				Level = 1,
			}
		end
		local entry = craftingState.Skills[skillId]
		if typeof(entry.Experience) ~= "number" then
			entry.Experience = 0
		end
		if typeof(entry.Level) ~= "number" then
			entry.Level = 1
		end
		entry.Level = select(1, computeSkillLevel(entry.Experience))
	end

	return craftingState
end

local function getSkillLevel(craftingState: { [string]: any }, skillId: string): number
	local entry = craftingState.Skills[skillId]
	if typeof(entry) ~= "table" then
		return 1
	end
	local level = entry.Level
	if typeof(level) ~= "number" then
		return 1
	end
	return math.max(1, math.floor(level + 0.5))
end

local function applySkillGains(
	craftingState: { [string]: any },
	skillGains: { [string]: number }
): { [string]: { GainedXP: number, OldLevel: number, NewLevel: number } }
	local results: { [string]: { GainedXP: number, OldLevel: number, NewLevel: number } } = {}

	for skillId, gain in pairs(skillGains) do
		if typeof(skillId) == "string" and typeof(gain) == "number" and gain > 0 then
			local entry = craftingState.Skills[skillId]
			if typeof(entry) ~= "table" then
				entry = {
					Experience = 0,
					Level = 1,
				}
				craftingState.Skills[skillId] = entry
			end

			local oldLevel = getSkillLevel(craftingState, skillId)
			entry.Experience = math.max(0, math.floor((entry.Experience or 0) + gain + 0.5))
			entry.Level = select(1, computeSkillLevel(entry.Experience))

			results[skillId] = {
				GainedXP = math.floor(gain + 0.5),
				OldLevel = oldLevel,
				NewLevel = entry.Level,
			}
		end
	end

	return results
end

local function getItemQuantity(player: Player, profile: { [string]: any }, itemId: string): number
	local inventoryRoot = getInventoryRoot(profile)
	local items = CraftingInventory:GetItemsByDef(player, itemId, inventoryRoot)
	local total = 0
	for _, item in ipairs(items) do
		local quantity = item.properties.quantity
		if typeof(quantity) == "number" then
			total += math.max(0, math.floor(quantity + 0.5))
		else
			total += 1
		end
	end
	return total
end

local function getItemDisplayName(itemId: string): string
	local definition = CraftingItems.Definitions[itemId]
	if definition and definition.metadata and typeof(definition.metadata.Name) == "string" then
		return definition.metadata.Name
	end
	return itemId
end

local function resolveAvailableStations(player: Player): { [string]: boolean }
	local available: { [string]: boolean } = table.clone(DEFAULT_AVAILABLE_STATIONS)

	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return available
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return available
	end

	local container = plotModel:FindFirstChild("Container")
	if not container then
		return available
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		local stationTypeAttr = descendant:GetAttribute("CraftingStationType")
		if typeof(stationTypeAttr) == "string" and CraftingStation.IsValid(stationTypeAttr) then
			available[stationTypeAttr] = true
		end

		local itemId = descendant:GetAttribute("ItemId")
		if typeof(itemId) == "string" and itemId ~= "" then
			local stationId = CraftingStation.ResolveFromItemId(itemId)
			if stationId then
				available[stationId] = true
			end
		end
	end

	return available
end

local function resolveStationSelection(
	recipeRequiredStations: { string },
	requestedStationId: string,
	availableStations: { [string]: boolean }
): (string?, string?)
	if #recipeRequiredStations == 0 then
		return "", nil
	end

	local selected = requestedStationId
	if selected == "" then
		selected = recipeRequiredStations[1]
	end

	local allowed = false
	for _, required in ipairs(recipeRequiredStations) do
		if required == selected then
			allowed = true
			break
		end
	end

	if not allowed then
		return nil, "Selected station is not valid for this recipe."
	end

	if not availableStations[selected] then
		local stationDef = CraftingStation.GetById(selected)
		local stationName = if stationDef then stationDef.Name else selected
		return nil, string.format("%s is required to craft this item.", stationName)
	end

	return selected, nil
end

local function verifySkillRequirements(
	craftingState: { [string]: any },
	requirements: { SkillRequirement }
): (boolean, string?)
	for _, requirement in ipairs(requirements) do
		local currentLevel = getSkillLevel(craftingState, requirement.SkillId)
		if currentLevel < requirement.Level then
			return false,
				string.format(
					"Requires %s level %d (current level %d).",
					requirement.SkillId,
					requirement.Level,
					currentLevel
				)
		end
	end
	return true, nil
end

local function verifyIngredients(
	player: Player,
	profile: { [string]: any },
	ingredients: { IngredientRequirement }
): (boolean, string?)
	for _, ingredient in ipairs(ingredients) do
		local available = getItemQuantity(player, profile, ingredient.ItemId)
		if available < ingredient.Quantity then
			return false,
				string.format(
					"Missing %dx %s (have %d).",
					ingredient.Quantity,
					getItemDisplayName(ingredient.ItemId),
					available
				)
		end
	end
	return true, nil
end

local function consumeIngredients(
	player: Player,
	profile: { [string]: any },
	ingredients: { IngredientRequirement }
): (boolean, string?, { [string]: number })
	local inventoryRoot = getInventoryRoot(profile)
	local consumedByDef: { [string]: number } = {}

	for _, ingredient in ipairs(ingredients) do
		local remaining = ingredient.Quantity
		local stacks = CraftingInventory:GetItemsByDef(player, ingredient.ItemId, inventoryRoot)
		table.sort(stacks, function(a, b)
			local aQty = if typeof(a.properties.quantity) == "number" then a.properties.quantity else 1
			local bQty = if typeof(b.properties.quantity) == "number" then b.properties.quantity else 1
			return aQty < bQty
		end)

		for _, stack in ipairs(stacks) do
			if remaining <= 0 then
				break
			end
			local stackQty = if typeof(stack.properties.quantity) == "number" then stack.properties.quantity else 1
			local take = math.min(remaining, math.max(1, math.floor(stackQty + 0.5)))
			local ok, err = CraftingInventory:Consume(player, stack.id, take, inventoryRoot)
			if not ok then
				return false, err or "Failed to consume ingredients.", consumedByDef
			end
			consumedByDef[ingredient.ItemId] = (consumedByDef[ingredient.ItemId] or 0) + take
			remaining -= take
		end

		if remaining > 0 then
			return false, "Not enough ingredients at craft time.", consumedByDef
		end
	end

	return true, nil, consumedByDef
end

local function refundIngredients(player: Player, profile: { [string]: any }, consumedByDef: { [string]: number }): boolean
	local inventoryRoot = getInventoryRoot(profile)
	for itemId, quantity in pairs(consumedByDef) do
		local ok = CraftingInventory:Add(player, itemId, quantity, inventoryRoot)
		if not ok then
			return false
		end
	end
	return true
end

local function emitCraftFailed(player: Player, recipeId: string, jobId: string, reason: string)
	CraftingService.CraftFailed:Fire(player, recipeId, reason)
	CraftingPackets.CraftFailed:FireClient(player, {
		JobId = jobId,
		RecipeId = recipeId,
		Reason = reason,
	})
end

local function ensureStarterResources(player: Player, profile: { [string]: any })
	local craftingState = ensureCraftingState(profile)
	if craftingState.StarterResourcesGranted then
		return
	end

	local inventoryRoot = getInventoryRoot(profile)
	for itemId, quantity in pairs(STARTER_RESOURCES) do
		CraftingInventory:Add(player, itemId, quantity, inventoryRoot)
	end

	craftingState.StarterResourcesGranted = true
end

local function getRecipeById(recipeId: string)
	return CraftingRecipes.GetById(recipeId)
end

local function buildInventorySummary(player: Player, profile: { [string]: any }): { [string]: number }
	local summary: { [string]: number } = {}
	for defId, _ in pairs(CraftingItems.Definitions) do
		local quantity = getItemQuantity(player, profile, defId)
		if quantity > 0 then
			summary[defId] = quantity
		end
	end
	return summary
end

local function buildSkillSummary(craftingState: { [string]: any }): { any }
	local skills: { any } = {}
	for _, skillId in ipairs(DEFAULT_SKILLS) do
		local entry = craftingState.Skills[skillId]
		local experience = if entry and typeof(entry.Experience) == "number" then entry.Experience else 0
		local level, xpIntoLevel, xpForNext = computeSkillLevel(experience)
		table.insert(skills, {
			SkillId = skillId,
			Level = level,
			Experience = experience,
			ExperienceIntoLevel = xpIntoLevel,
			ExperienceForNext = xpForNext,
		})
	end
	return skills
end

local function buildRecipePayload(
	player: Player,
	profile: { [string]: any },
	craftingState: { [string]: any },
	availableStations: { [string]: boolean }
): { any }
	local recipes: { any } = {}

	for _, recipe in ipairs(CraftingRecipes.List) do
		local ingredients: { any } = {}
		local missingIngredients = false

		for _, ingredient in ipairs(recipe.Ingredients) do
			local available = getItemQuantity(player, profile, ingredient.ItemId)
			local missing = math.max(0, ingredient.Quantity - available)
			if missing > 0 then
				missingIngredients = true
			end
			table.insert(ingredients, {
				ItemId = ingredient.ItemId,
				Name = getItemDisplayName(ingredient.ItemId),
				Required = ingredient.Quantity,
				Available = available,
				Missing = missing,
			})
		end

		local skillRequirements: { any } = {}
		local missingSkills = false
		for _, requirement in ipairs(recipe.SkillRequirements) do
			local current = getSkillLevel(craftingState, requirement.SkillId)
			if current < requirement.Level then
				missingSkills = true
			end
			table.insert(skillRequirements, {
				SkillId = requirement.SkillId,
				RequiredLevel = requirement.Level,
				CurrentLevel = current,
			})
		end

		local hasStation = #recipe.RequiredStations == 0
		for _, stationId in ipairs(recipe.RequiredStations) do
			if availableStations[stationId] then
				hasStation = true
				break
			end
		end

		local canCraft = hasStation and not missingIngredients and not missingSkills and ActiveJobsByUserId[player.UserId] == nil
		local blockedReason = ""
		if ActiveJobsByUserId[player.UserId] ~= nil then
			blockedReason = "Another crafting task is active."
		elseif not hasStation then
			blockedReason = "Missing required station."
		elseif missingSkills then
			blockedReason = "Skill requirements not met."
		elseif missingIngredients then
			blockedReason = "Missing required ingredients."
		end

		table.insert(recipes, {
			Id = recipe.Id,
			Name = recipe.Name,
			Description = recipe.Description,
			Category = recipe.Category,
			Ingredients = ingredients,
			Output = {
				ItemId = recipe.Output.ItemId,
				Quantity = recipe.Output.Quantity,
				Name = getItemDisplayName(recipe.Output.ItemId),
			},
			RequiredStations = recipe.RequiredStations,
			SkillRequirements = skillRequirements,
			CraftingTimeSeconds = recipe.CraftingTimeSeconds,
			CanCraft = canCraft,
			BlockedReason = blockedReason,
		})
	end

	return recipes
end

local function buildCraftingDataPayload(player: Player, profile: { [string]: any }): { [string]: any }
	local craftingState = ensureCraftingState(profile)
	local availableStations = resolveAvailableStations(player)
	local stationsPayload: { any } = {}
	for _, station in ipairs(CraftingStation.GetAll()) do
		table.insert(stationsPayload, {
			Id = station.Id,
			Name = station.Name,
			Description = station.Description,
			Available = availableStations[station.Id] == true,
		})
	end

	local activeJob = ActiveJobsByUserId[player.UserId]
	local activeJobPayload = nil
	if activeJob then
		activeJobPayload = {
			JobId = activeJob.JobId,
			RecipeId = activeJob.RecipeId,
			StationId = activeJob.StationId,
			StartedAt = activeJob.StartedAt,
			EndsAt = activeJob.EndsAt,
		}
	end

	return {
		Inventory = buildInventorySummary(player, profile),
		Skills = buildSkillSummary(craftingState),
		Recipes = buildRecipePayload(player, profile, craftingState, availableStations),
		Stations = stationsPayload,
		ActiveJob = activeJobPayload,
	}
end

local function completeCraftingJob(job: CraftingJob)
	local active = ActiveJobsByUserId[job.Player.UserId]
	if active ~= job then
		return
	end
	ActiveJobsByUserId[job.Player.UserId] = nil

	if not job.Player.Parent then
		return
	end

	local profile = PlayerSession.GetData(job.Player)
	if not profile then
		emitCraftFailed(job.Player, job.RecipeId, job.JobId, "Crafting data unavailable.")
		return
	end

	local recipe = getRecipeById(job.RecipeId)
	if not recipe then
		emitCraftFailed(job.Player, job.RecipeId, job.JobId, "Recipe no longer exists.")
		return
	end

	local inventoryRoot = getInventoryRoot(profile)
	local outputAdded, outputErr = CraftingInventory:Add(job.Player, recipe.Output.ItemId, recipe.Output.Quantity, inventoryRoot)
	if not outputAdded then
		refundIngredients(job.Player, profile, job.ConsumedIngredients)
		emitCraftFailed(job.Player, job.RecipeId, job.JobId, outputErr or "Could not add crafted output.")
		return
	end

	local craftingState = ensureCraftingState(profile)
	local skillResults = applySkillGains(craftingState, recipe.SkillGains)

	local progressionExperience = math.max(0, math.floor((recipe.ProgressionExperience or 0) + 0.5))
	if progressionExperience > 0 then
		ProgressionService.AwardExperience(job.Player, progressionExperience, "Crafting:" .. recipe.Id)
	end

	CraftingService.CraftCompleted:Fire(job.Player, recipe.Id, recipe.Output.ItemId, recipe.Output.Quantity)
	CraftingPackets.CraftCompleted:FireClient(job.Player, {
		JobId = job.JobId,
		RecipeId = recipe.Id,
		StationId = job.StationId,
		OutputItemId = recipe.Output.ItemId,
		OutputQuantity = recipe.Output.Quantity,
		SkillGains = skillResults,
		ProgressionExperience = progressionExperience,
	})
end

local function startCrafting(player: Player, recipeId: string, requestedStationId: string): (boolean, string, any)
	local profile = PlayerSession.GetData(player)
	if not profile then
		emitCraftFailed(player, recipeId, "", "Player profile unavailable.")
		return false, "Player profile unavailable.", nil
	end

	ensureStarterResources(player, profile)
	local craftingState = ensureCraftingState(profile)

	local activeJob = ActiveJobsByUserId[player.UserId]
	if activeJob then
		emitCraftFailed(player, activeJob.RecipeId, activeJob.JobId, "Crafting already in progress.")
		return false, "Crafting already in progress.", nil
	end

	local recipe = getRecipeById(recipeId)
	if not recipe then
		emitCraftFailed(player, recipeId, "", "Recipe not found.")
		return false, "Recipe not found.", nil
	end

	local availableStations = resolveAvailableStations(player)
	local stationId, stationErr = resolveStationSelection(recipe.RequiredStations, requestedStationId, availableStations)
	if not stationId then
		emitCraftFailed(player, recipeId, "", stationErr or "Missing required station.")
		return false, stationErr or "Missing required station.", nil
	end

	local skillOk, skillErr = verifySkillRequirements(craftingState, recipe.SkillRequirements)
	if not skillOk then
		emitCraftFailed(player, recipeId, "", skillErr or "Skill requirement not met.")
		return false, skillErr or "Skill requirement not met.", nil
	end

	local ingredientOk, ingredientErr = verifyIngredients(player, profile, recipe.Ingredients)
	if not ingredientOk then
		emitCraftFailed(player, recipeId, "", ingredientErr or "Missing ingredients.")
		return false, ingredientErr or "Missing ingredients.", nil
	end

	local consumedOk, consumeErr, consumedByDef = consumeIngredients(player, profile, recipe.Ingredients)
	if not consumedOk then
		refundIngredients(player, profile, consumedByDef)
		emitCraftFailed(player, recipeId, "", consumeErr or "Failed to consume ingredients.")
		return false, consumeErr or "Failed to consume ingredients.", nil
	end

	local startedAt = now()
	local duration = math.max(1, math.floor((recipe.CraftingTimeSeconds or 1) + 0.5))
	local job: CraftingJob = {
		JobId = HttpService:GenerateGUID(false),
		Player = player,
		RecipeId = recipe.Id,
		StationId = stationId,
		StartedAt = startedAt,
		EndsAt = startedAt + duration,
		ConsumedIngredients = consumedByDef,
	}

	ActiveJobsByUserId[player.UserId] = job
	CraftingService.CraftStarted:Fire(player, recipe.Id, stationId, job.EndsAt)
	CraftingPackets.CraftStarted:FireClient(player, {
		JobId = job.JobId,
		RecipeId = recipe.Id,
		StationId = stationId,
		EndsAt = job.EndsAt,
	})

	task.delay(duration, function()
		completeCraftingJob(job)
	end)

	return true, "Crafting started.", {
		JobId = job.JobId,
		RecipeId = job.RecipeId,
		StationId = job.StationId,
		EndsAt = job.EndsAt,
	}
end

local function handleGetCraftingData(player: Player): (boolean, string, any)
	local profile = PlayerSession.GetData(player)
	if not profile then
		return false, "Player profile unavailable.", nil
	end

	ensureStarterResources(player, profile)
	local payload = buildCraftingDataPayload(player, profile)
	return true, "", payload
end

local function onPlayerAdded(player: Player)
	task.defer(function()
		local profile = PlayerSession.GetDataAwait(player)
		if not profile then
			return
		end
		ensureCraftingState(profile)
		ensureStarterResources(player, profile)
	end)
end

function CraftingService.Init()
	CraftingPackets.GetCraftingData.OnServerInvoke = handleGetCraftingData
	CraftingPackets.StartCrafting.OnServerInvoke = function(player: Player, recipeId: string, stationId: string)
		if typeof(recipeId) ~= "string" or recipeId == "" then
			return false, "Recipe id is required.", nil
		end
		local station = if typeof(stationId) == "string" then stationId else ""
		return startCrafting(player, recipeId, station)
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		ActiveJobsByUserId[player.UserId] = nil
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		onPlayerAdded(player)
	end
end

function CraftingService.GetRecipe(recipeId: string)
	return getRecipeById(recipeId)
end

function CraftingService.GetActiveJob(player: Player): CraftingJob?
	return ActiveJobsByUserId[player.UserId]
end

return CraftingService
