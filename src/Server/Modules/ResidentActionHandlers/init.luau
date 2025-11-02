--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DirectActionService = require(ServerScriptService.Server.Services.DirectActionService)
local KitchenService = require(ServerScriptService.Server.Services.KitchenService)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local FoodUtils = require(ReplicatedStorage.Shared.Utilities.FoodUtils)
local MealRecipesModule = require(ReplicatedStorage.Shared.Definitions.MealRecipes)

local BehaviorConfig = require(script.BehaviorConfig)
local Pipeline = require(script.Pipeline)
local Types = require(script.Types)

type Behavior = Types.Behavior
type HandlerContext = Types.HandlerContext
type HandlerAssignment = Types.HandlerAssignment
type CookingSession = KitchenService.CookingSession
type MealRecipe = MealRecipesModule.MealRecipe
type BeginCookingResult = {
	Success: boolean,
	Session: CookingSession?,
	Reason: string?,
}

type DiningReservation = Pipeline.DiningReservation

local ResidentActionHandlers = {}

local BeginCooking = KitchenService.BeginCooking :: any

local Needs = NeedConfig.Needs
local MealRecipes = MealRecipesModule.Recipes

local KitchenFailurePhrases: { [string]: string } = {
	NoCookableRecipe = "We need groceries before we can cook anything.",
	InsufficientIngredients = "We are out of ingredients right now.",
	KitchenStateUnavailable = "The kitchen isn't ready yet.",
	RecipeMissing = "I can't figure out what to cook just yet.",
	KitchenLocked = "The kitchen is closing up right now.",
}

local function resolveActionLabel(stationType: string, actionMode: string?): string
	if stationType == "CookStation" then
		if actionMode == "Snack" then
			return "grab snack"
		elseif actionMode == "PreparedMeal" then
			return "eat meal"
		end
		return "cook meal"
	end
	if actionMode == "PreparedMeal" then
		return "eat meal"
	end
	return BehaviorConfig.getStationLabel(stationType)
end

local function buildMetadata(
	assignment: HandlerAssignment,
	stationType: string,
	stationId: string,
	stationName: string?,
	actionLabel: string
): { [string]: any }
	return {
		StationType = stationType,
		StationId = stationId,
		StationName = stationName,
		NeedName = assignment.NeedName,
		ActionName = actionLabel,
		Player = assignment.Player,
	}
end

local function applyManualNeedGuard(behavior: Behavior, assignment: HandlerAssignment)
	local needName = assignment.NeedName
	if not needName then
		return
	end
	local needDef = Needs[needName]
	if not needDef then
		return
	end
	local originalShouldEnd = behavior.ShouldEnd
	behavior.ShouldEnd = function(residentState)
		local getter = residentState and residentState.GetNeed
		if typeof(getter) == "function" then
			local value = getter(residentState, needName)
			if typeof(value) == "number" then
				if value >= needDef.Max then
					return true
				end
				return false
			end
		end
		if originalShouldEnd then
			return originalShouldEnd(residentState)
		end
		return false
	end
	local originalReason = behavior.EndReasonProvider
	behavior.EndReasonProvider = function(residentState)
		local getter = residentState and residentState.GetNeed
		if typeof(getter) == "function" then
			local value = getter(residentState, needName)
			if typeof(value) == "number" and value >= needDef.Max then
				return "NeedFull:" .. needName
			end
		end
		if originalReason then
			return originalReason(residentState)
		end
		return nil
	end
end

local function configureRestBehavior(behavior: Behavior, assignment: HandlerAssignment): (string?, boolean)
	local restOverride = assignment.RestModeOverride
	if restOverride and restOverride ~= behavior.RestProfileKey then
		local baseMode = behavior.RestProfileKey
		local allowOverride = true
		if baseMode == "Nap" and restOverride ~= "Nap" then
			allowOverride = false
		end
		if behavior.UseSeat == true and BehaviorConfig.REST_LIE_MODES[restOverride] then
			allowOverride = false
		end
		if allowOverride then
			BehaviorConfig.applyRestProfile(behavior, restOverride)
		end
	end
	local restMode = behavior.RestProfileKey
	local restPoseEligible = false
	if restMode and BehaviorConfig.REST_LIE_MODES[restMode] and behavior.UseSeat ~= true then
		restPoseEligible = true
	end
	if restMode and BehaviorConfig.SEATED_ONLY_REST_MODES[restMode] then
		restPoseEligible = false
	end
	return restMode, restPoseEligible
end

local function selectDiningDisplayName(reservation: DiningReservation?, fallbackName: string?): string?
	if not reservation then
		return fallbackName
	end
	local itemSpec = reservation.ItemSpec
	if not itemSpec then
		return fallbackName
	end
	local displayName = itemSpec.DisplayName
	if typeof(displayName) == "string" and displayName ~= "" then
		return displayName
	end
	local name = itemSpec.Name
	if typeof(name) == "string" and name ~= "" then
		return name
	end
	return fallbackName
end

local function tryBeginCooking(player: Player, assignment: HandlerAssignment, behavior: Behavior): BeginCookingResult
	local beginOk, beginResult = BeginCooking(player, assignment, behavior, nil)
	if beginOk == true and typeof(beginResult) == "table" then
		return {
			Success = true,
			Session = beginResult :: CookingSession,
			Reason = nil,
		}
	end
	local reason = if typeof(beginResult) == "string" then beginResult else "KitchenUnavailable"
	return {
		Success = false,
		Session = nil,
		Reason = reason,
	}
end

local function executeStationAction(stationType: string, context: HandlerContext, assignment: HandlerAssignment)
	local pipeline = Pipeline.new(context, assignment)
	local behavior = BehaviorConfig.mergeBehavior(stationType, assignment.ItemSpec)
	local actionMode = assignment.ActionMode
	local isSnack = actionMode == "Snack"
	local isPreparedMeal = actionMode == "PreparedMeal"
	local manualOverride = assignment.ManualOverride == true

	if manualOverride then
		applyManualNeedGuard(behavior, assignment)
	end

	local restPoseMode: string? = nil
	local restPoseEligible = false
	if stationType == "RestStation" then
		restPoseMode, restPoseEligible = configureRestBehavior(behavior, assignment)
	end

	if isSnack then
		behavior.DurationSeconds = behavior.DurationSeconds or 16
		behavior.Effects = nil
		if not behavior.ChatPhrases then
			behavior.ChatPhrases = {
				{ Text = "Grabbing a quick snack." },
				{ Text = "Let me eat something fast." },
			}
		end
	elseif isPreparedMeal then
		behavior.DurationSeconds = math.min(behavior.DurationSeconds or 10, 6)
		behavior.Effects = nil
		if not behavior.ChatPhrases then
			behavior.ChatPhrases = {
				{ Text = "Let me plate some leftovers." },
				{ Text = "Warming up a meal." },
			}
		end
	end

	local actionLabel = resolveActionLabel(stationType, actionMode)
	pipeline:setActionLabel(actionLabel)
	pipeline:trace(string.format("Handler start: %s -> %s", assignment.ResidentName, stationType), {
		Resident = assignment.ResidentName,
		StationType = stationType,
		StationId = assignment.StationId,
	})

	local followUpBehavior: Behavior? = nil
	local followUpRecipe: MealRecipe? = nil
	local followUpActionLabel = if isSnack then "eat snack" else "eat meal"

	local preparedMealId = assignment.PreparedMealId
	local preparedMealServings = math.max(1, assignment.PreparedMealServings or 1)
	local preparedMealHungerPerPortion = assignment.PreparedMealHungerPerPortion or 0
	local preparedMealRecipe = preparedMealId and MealRecipes[preparedMealId] or nil

	local cookingSession: CookingSession? = nil

	local function currentMetadata(label: string)
		return buildMetadata(assignment, stationType, assignment.StationId, pipeline:getStationName(), label)
	end

	local caughtError: any = nil
	local success = xpcall(function()
		if stationType == "CookStation" and assignment.Player and not isSnack and not isPreparedMeal then
			local beginOutcome = tryBeginCooking(assignment.Player :: Player, assignment, behavior)
			if not beginOutcome.Success or not beginOutcome.Session then
				local reason = beginOutcome.Reason or "KitchenUnavailable"
				pipeline:showInterrupt(reason, currentMetadata(actionLabel))
				pipeline:trace(string.format("Kitchen session blocked: %s", assignment.ResidentName), {
					Resident = assignment.ResidentName,
					StationType = stationType,
					Failure = reason,
					Hint = KitchenFailurePhrases[reason],
				})
				return
			end
			cookingSession = beginOutcome.Session
		end

		local moveOk, _arrival = pipeline:moveToPrimary(behavior, {
			RestPoseMode = restPoseMode,
			RestPoseEligible = restPoseEligible,
		})
		if not moveOk or context.CancelToken.Cancelled then
			local reason = if context.CancelToken.Cancelled
				then context.CancelToken.Reason or "Cancelled"
				else "MovementFailed"
			if cookingSession then
				KitchenService.CancelCooking(cookingSession, reason)
				cookingSession = nil
			end
			pipeline:showInterrupt(reason, currentMetadata(actionLabel))
			return
		end

		if isSnack then
			local player = assignment.Player
			local containerId = assignment.TargetContainerId or assignment.StationId
			if not player or not containerId or containerId == "" then
				pipeline:showInterrupt("NoFoodAvailable", currentMetadata(actionLabel))
				return
			end
			local consumeOk, hungerRestore = KitchenService.TryConsumeEdibleFromContainer(player, containerId)
			if not consumeOk or not hungerRestore or hungerRestore <= 0 then
				pipeline:showInterrupt("NoFoodAvailable", currentMetadata(actionLabel))
				return
			end
			followUpBehavior = BehaviorConfig.buildMealEatingBehavior(hungerRestore, nil)
			behavior.Effects = nil
			pipeline:ensureDiningReservation()
		elseif isPreparedMeal then
			local player = assignment.Player
			if not player or not preparedMealId or preparedMealHungerPerPortion <= 0 then
				pipeline:showInterrupt("NoFoodAvailable", currentMetadata(actionLabel))
				return
			end
			local consumed = KitchenService.ConsumePreparedMeal(player, preparedMealId, preparedMealServings)
			if not consumed then
				pipeline:showInterrupt("NoFoodAvailable", currentMetadata(actionLabel))
				return
			end
			local totalRestore = preparedMealHungerPerPortion * preparedMealServings
			if totalRestore <= 0 and preparedMealRecipe then
				totalRestore = FoodUtils.ComputeHungerEffect(preparedMealRecipe.HungerRestore)
			end
			if totalRestore <= 0 then
				totalRestore = 12
			end
			followUpBehavior = BehaviorConfig.buildMealEatingBehavior(totalRestore, preparedMealRecipe)
			followUpRecipe = preparedMealRecipe
			pipeline:ensureDiningReservation()
		end

		local stageMetadata = currentMetadata(actionLabel)
		local stageSuccess, stageAbortReason, stageError = pipeline:runNeedEffects(behavior, stageMetadata)
		if stageError then
			error(stageError)
		end

		if cookingSession then
			if stageSuccess and not context.CancelToken.Cancelled then
				local portions, recipe = KitchenService.CompleteCooking(cookingSession)
				if portions and portions > 0 and recipe then
					local perPortion = FoodUtils.ComputeHungerEffect(recipe.HungerRestore)
					local totalRestore = perPortion * portions
					if totalRestore > 0 then
						followUpBehavior = BehaviorConfig.buildMealEatingBehavior(totalRestore, recipe)
						followUpRecipe = recipe
						pipeline:ensureDiningReservation()
					end
				end
			else
				local cancelReason = stageAbortReason
				if not cancelReason or cancelReason == "" then
					if context.CancelToken.Cancelled then
						cancelReason = context.CancelToken.Reason or "Cancelled"
					else
						cancelReason = "ActionError"
					end
				end
				KitchenService.CancelCooking(cookingSession, cancelReason)
			end
			cookingSession = nil
		end

		if not stageSuccess then
			if stageAbortReason then
				error(pipeline:formatAbortError(stageAbortReason), 0)
			end
			error("NeedEffectsFailed")
		end

		if not followUpBehavior or context.CancelToken.Cancelled then
			return
		end

		local reservation = pipeline:ensureDiningReservation()
		if reservation and reservation.StationType == "MealStation" then
			BehaviorConfig.applyMealStationBonus(followUpBehavior, reservation.StationType, followUpRecipe)
		end

		local followStationType = stationType
		local followStationId = assignment.StationId
		local followStationName = pipeline:getStationName()

		if reservation then
			if stationType == "FoodStorage" then
				pipeline:releasePrimaryReservation()
			end
			local movedDining, _diningArrival = pipeline:moveToDining(reservation, followUpBehavior, nil)
			if movedDining then
				followStationType = reservation.StationType
				followStationId = reservation.UniqueId
				followStationName = selectDiningDisplayName(reservation, followStationName)
			else
				pipeline:releaseDiningReservation()
				reservation = nil
			end
		end

		pipeline:setActionLabel(followUpActionLabel)
		local followMetadata =
			buildMetadata(assignment, followStationType, followStationId, followStationName, pipeline:getActionLabel())

		local followSuccess, followAbortReason, followError = pipeline:runNeedEffects(followUpBehavior, followMetadata)
		if followError then
			error(followError)
		end
		if not followSuccess then
			if followAbortReason then
				error(pipeline:formatAbortError(followAbortReason), 0)
			end
			error("NeedEffectsFailed")
		end
	end, function(message)
		caughtError = message
		return debug.traceback(message)
	end)

	pipeline:cleanup()

	if not success then
		error(caughtError)
	end

	pipeline:trace(string.format("Handler completed: %s -> %s", assignment.ResidentName, stationType), {
		Resident = assignment.ResidentName,
		StationType = stationType,
	})
end

local function registerHandler(stationType: string)
	DirectActionService.RegisterHandler(stationType, function(context: HandlerContext, assignment: HandlerAssignment)
		executeStationAction(stationType, context, assignment)
	end)
end

registerHandler("RestStation")
registerHandler("CookStation")
registerHandler("MealStation")
registerHandler("SocialStation")
registerHandler("HygieneStation")
registerHandler("ComfortStation")
registerHandler("FunStation")
registerHandler("FoodStorage")

function ResidentActionHandlers.GetDefaultBehavior(stationType: string): BehaviorConfig.BehaviorSpec?
	local base = BehaviorConfig.StationDefaults[stationType]
	if not base then
		return nil
	end
	local behavior = BehaviorConfig.shallowCopyBehavior(base)
	if stationType == "RestStation" then
		BehaviorConfig.applyRestProfile(behavior, "Sleep")
	end
	return behavior
end

function ResidentActionHandlers.GetRestBehavior(mode: string?): BehaviorConfig.BehaviorSpec?
	local base = BehaviorConfig.StationDefaults.RestStation
	if not base then
		return nil
	end
	local behavior = BehaviorConfig.shallowCopyBehavior(base)
	BehaviorConfig.applyRestProfile(behavior, mode)
	return behavior
end

function ResidentActionHandlers.GetDirectSocialBehavior(): BehaviorConfig.BehaviorSpec?
	local base = BehaviorConfig.StationDefaults.SocialStation
	if not base then
		return nil
	end
	return BehaviorConfig.shallowCopyBehavior(base)
end

return ResidentActionHandlers
