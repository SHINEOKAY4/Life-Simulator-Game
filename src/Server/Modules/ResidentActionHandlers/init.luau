--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local StationActionRegistry = require(ServerScriptService.Server.Modules.StationActionRegistry)
local ChoreService = require(ServerScriptService.Server.Services.ChoreService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)

local BehaviorConfig = require(script.BehaviorConfig)
local Pipeline = require(script.Pipeline)
local Types = require(script.Types)

type Behavior = Types.Behavior
type HandlerContext = Types.HandlerContext
type HandlerAssignment = Types.HandlerAssignment
type DiningReservation = Pipeline.DiningReservation

local ResidentActionHandlers = {}

local Needs = NeedConfig.Needs

local function resolveActionLabel(stationType: string, _actionMode: string?): string
	if stationType == "CookStation" then
		return "eat meal"
	end
	if stationType == "FoodStorage" then
		return "eat snack"
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

local function executeStationAction(stationType: string, context: HandlerContext, assignment: HandlerAssignment)
	local pipeline = Pipeline.new(context, assignment)
	local behavior = BehaviorConfig.mergeBehavior(stationType, assignment.ItemSpec)
	local manualOverride = assignment.ManualOverride == true

	if manualOverride then
		applyManualNeedGuard(behavior, assignment)
	end

	local restPoseMode: string? = nil
	local restPoseEligible = false
	if stationType == "RestStation" then
		restPoseMode, restPoseEligible = configureRestBehavior(behavior, assignment)
	end

	local actionLabel = resolveActionLabel(stationType, assignment.ActionMode)
	pipeline:setActionLabel(actionLabel)
	pipeline:trace(string.format("Handler start: %s -> %s", assignment.ResidentName, stationType), {
		Resident = assignment.ResidentName,
		StationType = stationType,
		StationId = assignment.StationId,
	})

	local function currentMetadata(label: string)
		return buildMetadata(assignment, stationType, assignment.StationId, pipeline:getStationName(), label)
	end

	local caughtError: any = nil
	local success = xpcall(function()
		local moveOk, _arrival = pipeline:moveToPrimary(behavior, {
			RestPoseMode = restPoseMode,
			RestPoseEligible = restPoseEligible,
		})
		if not moveOk or context.CancelToken.Cancelled then
			local reason = if context.CancelToken.Cancelled
				then context.CancelToken.Reason or "Cancelled"
				else "MovementFailed"
			pipeline:showInterrupt(reason, currentMetadata(actionLabel))
			return
		end

		local stageMetadata = currentMetadata(actionLabel)
		local stageSuccess, stageAbortReason, stageError = pipeline:runNeedEffects(behavior, stageMetadata)
		if stageError then
			error(stageError)
		end

		if not stageSuccess then
			if stageAbortReason then
				error(pipeline:formatAbortError(stageAbortReason), 0)
			end
			error("NeedEffectsFailed")
		end

		-- If this is a CookStation, we want to simulate eating a meal afterwards
		if stationType == "CookStation" and not context.CancelToken.Cancelled then
			local followUpBehavior = BehaviorConfig.buildMealEatingBehavior(50, nil) -- Restore 50 hunger
			local reservation = pipeline:ensureDiningReservation()

			if reservation and reservation.StationType == "MealStation" then
				BehaviorConfig.applyMealStationBonus(followUpBehavior, reservation.StationType, nil)
			end

			local followStationType = stationType
			local followStationId = assignment.StationId
			local followStationName = pipeline:getStationName()

			if reservation then
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

			pipeline:setActionLabel("eat meal")
			local followMetadata = buildMetadata(
				assignment,
				followStationType,
				followStationId,
				followStationName,
				pipeline:getActionLabel()
			)

			local followSuccess, followAbortReason, followError =
				pipeline:runNeedEffects(followUpBehavior, followMetadata)
			if followError then
				error(followError)
			end
			if not followSuccess then
				if followAbortReason then
					error(pipeline:formatAbortError(followAbortReason), 0)
				end
				error("NeedEffectsFailed")
			end
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

	-- Chance to spawn a mess or give a tip
	if assignment.Player then
		local residentState = ResidentService.GetResident(assignment.Player, assignment.ResidentName)
		if residentState and residentState.Model and residentState.Model.PrimaryPart then
			-- Mess chance
			if stationType == "CookStation" or stationType == "MealStation" or stationType == "HygieneStation" then
				if math.random() < 0.2 then
					ChoreService.SpawnMess(assignment.Player, residentState.Model.PrimaryPart.Position)
				end
			end

			-- Tip chance on successful action completion (Fun/Social/Comfort)
			if stationType == "FunStation" or stationType == "SocialStation" or stationType == "ComfortStation" then
				if math.random() < 0.3 then -- 30% chance
					local TipsService = require(ServerScriptService.Server.Services.TipsService)
					local tipAmount = math.random(10, 25)
					TipsService.SpawnTip(
						assignment.Player,
						assignment.ResidentName,
						tipAmount,
						residentState.Model.PrimaryPart.Position,
						"Enjoyment"
					)
				end
			end
		end
	end
end

local function registerHandler(stationType: string)
	StationActionRegistry.RegisterHandler(stationType, function(context: HandlerContext, assignment: any)
		executeStationAction(stationType, context, assignment)
	end)
end

StationActionRegistry.RegisterHandler("Wander", function(context: HandlerContext, assignment: any)
	local residentState = assignment.ResidentState
	local itemSpec = assignment.ItemSpec
	local targetPosition = itemSpec and itemSpec.TargetPosition

	if not targetPosition then
		return
	end

	local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
	ResidentMovement.GoToWorldPosition(residentState, targetPosition, {
		CancelToken = context.CancelToken,
		DebugName = "Wander",
		TimeoutSeconds = 15,
	})

	-- Small idle wait after arriving
	if not context.CancelToken.Cancelled then
		task.wait(math.random(2, 5))
	end
end)

StationActionRegistry.RegisterHandler("Sit", function(context: HandlerContext, assignment: any)
	local _residentState = assignment.ResidentState
	local _itemSpec = assignment.ItemSpec
	local _stationId = assignment.StationId

	-- Just use the pipeline to move to the seat and sit
	local pipeline = Pipeline.new(context, assignment)
	pipeline:setActionLabel("relax")

	-- Create a dummy behavior that just sits
	local behavior = {
		DurationSeconds = math.random(20, 40),
		UseSeat = true,
		RestProfileKey = "Sit", -- Assuming 'Sit' is a valid rest profile or default
		ChatPhrases = {
			{ Text = "..." },
			{ Text = "Ah..." },
		},
	}

	local moveOk, _ = pipeline:moveToPrimary(behavior, {
		RestPoseMode = "Sit",
		RestPoseEligible = true,
	})

	if moveOk and not context.CancelToken.Cancelled then
		-- Just wait out the duration
		local duration = behavior.DurationSeconds
		local elapsed = 0
		while elapsed < duration do
			if context.CancelToken.Cancelled then
				break
			end
			task.wait(1)
			elapsed += 1
		end
	end

	pipeline:cleanup()
end)

StationActionRegistry.RegisterHandler("ViewObject", function(context: HandlerContext, assignment: any)
	local residentState = assignment.ResidentState
	local itemSpec = assignment.ItemSpec
	local targetPosition = itemSpec and itemSpec.TargetPosition

	if not targetPosition then
		return
	end

	local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)

	-- Move near the object
	local moveSuccess = ResidentMovement.GoToWorldPosition(residentState, targetPosition, {
		CancelToken = context.CancelToken,
		DebugName = "ViewObject",
		TimeoutSeconds = 15,
		ArrivalDistance = 4, -- Stand back a bit
	})

	if moveSuccess and not context.CancelToken.Cancelled then
		-- Look at the object
		if residentState.Model and residentState.Model.PrimaryPart then
			local lookCFrame = CFrame.new(residentState.Model.PrimaryPart.Position, targetPosition)
			-- Keep only Y rotation
			local _, y, _ = lookCFrame:ToOrientation()
			residentState.Model.PrimaryPart.CFrame = CFrame.new(residentState.Model.PrimaryPart.Position)
				* CFrame.fromOrientation(0, y, 0)
		end

		-- Play "Look" animation or just wait
		-- TODO: Play animation if available

		task.wait(math.random(5, 10))

		if math.random() < 0.5 then
			ResidentChat.ShowAction(residentState, {
				{ Text = "Hmm..." },
				{ Text = "Nice." },
				{ Text = "Interesting." },
			})
		end
	end
end)

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
