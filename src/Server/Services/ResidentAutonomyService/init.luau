--!strict
-- ServerScriptService/Server/Services/ResidentAutonomyService.lua

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local Constants = require(script.Constants)
local State = require(script.State)
local Utils = require(script.Utils)
local NeedEvaluator = require(script.NeedEvaluator)
local SocialCoordinator = require(script.SocialCoordinator)
local ActionQueue = require(script.ActionQueue)
local FallbackActions = require(script.FallbackActions)
local TipsService = require(ServerScriptService.Server.Services.TipsService)
local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)

local TenantService -- Lazy loaded to avoid circular dependency

export type ResidentState = any

local ResidentAutonomyService = {}

local function getPlayerByUserId(userId: number): Player?
	return Players:GetPlayerByUserId(userId)
end

function ResidentAutonomyService.EvaluateResidentNeeds(
	player: Player,
	residentName: string,
	resident: ResidentState,
	nowClock: number,
	clockTime: number,
	stationCache: { [string]: any }?
)
	return NeedEvaluator.evaluate(player, residentName, resident, nowClock, clockTime, stationCache)
end

function ResidentAutonomyService.TrySatisfyNeedsForResident(
	player: Player,
	residentName: string,
	residentState: ResidentState,
	nowClock: number?,
	clockTime: number?,
	stationCacheOverride: { [string]: any }?
): boolean
	if not Utils.shouldEvaluate(residentState) then
		return false
	end
	local evaluationClock = nowClock or os.clock()
	local scheduled = State.getNextEvaluation(residentState)
	if scheduled and evaluationClock < scheduled then
		return false
	end
	State.clearNextEvaluation(residentState)
	local evaluationTime = clockTime or TimeScale.GetClockTime()
	local stationCache = stationCacheOverride or PlotService.GetStationsForPlayer(player)
	local attemptedDirectSocial = false

	-- Prefer conversational social interactions before falling back to stations.
	local needs = State.getNeeds()
	local socialDef = needs.Social
	if socialDef then
		local cooldownSeconds = State.getNeedCooldownSeconds("Social", socialDef)
		local onCooldown = State.isNeedOnCooldown(residentState, "Social", cooldownSeconds, evaluationClock)
		if not onCooldown then
			local socialValue = residentState:GetNeed("Social")
			if socialValue < socialDef.Low then
				local blocking = Utils.hasBlockingCriticalNeed(player, residentState, "Social", stationCache)
				if not blocking then
					attemptedDirectSocial = true
					if SocialCoordinator.attemptDirectSocial(player, residentName, residentState, stationCache) then
						return true
					end
				end
			end
		end
	end
	local decision = ResidentAutonomyService.EvaluateResidentNeeds(
		player,
		residentName,
		residentState,
		evaluationClock,
		evaluationTime,
		stationCache
	)
	if not decision then
		local forcedNeed = State.getForcedNeed(residentState, evaluationClock)
		if forcedNeed then
			local forcedDef = State.getNeeds()[forcedNeed]
			if forcedDef then
				local value = residentState:GetNeed(forcedNeed)
				if value <= forcedDef.Critical then
					State.setForcedNeed(residentState, forcedNeed, evaluationClock)
				end
			end
			local delay = math.min(2, State.computeNextEvaluationDelay(residentState))
			State.setNextEvaluation(residentState, evaluationClock + delay)
			return false
		end
		local otherCriticalNeeds = Utils.hasBlockingCriticalNeed(player, residentState, "Social", stationCache)
		if not otherCriticalNeeds and not attemptedDirectSocial then
			if SocialCoordinator.attemptDirectSocial(player, residentName, residentState, stationCache) then
				return true
			end
		end

		if FallbackActions.evaluateFallback(player, residentName, residentState, stationCache) then
			return true
		end

		local delay = State.computeNextEvaluationDelay(residentState)
		State.setNextEvaluation(residentState, evaluationClock + delay)
		return false
	end
	if ActionQueue.enqueueNeedAction(player, residentName, residentState, decision) then
		State.clearNextEvaluation(residentState)
		return true
	end
	local delay = State.computeNextEvaluationDelay(residentState)
	State.setNextEvaluation(residentState, evaluationClock + delay)
	return false
end

local function updatePassiveFun(residents: { [string]: ResidentState }, stationCache: { [string]: any })
	local funStations = stationCache["FunStation"]
	local funScore = 0
	if funStations then
		-- Simple logic: each fun station adds 25% to the passive fun score
		-- This could be expanded to check item quality/tier in the future
		local count = 0
		for _ in pairs(funStations) do
			count += 1
		end
		funScore = count * 25
	end
	funScore = math.clamp(funScore, 0, 100)

	for _, resident in pairs(residents) do
		resident:SetNeed("Fun", funScore)
	end
end

local function handleStationRemoved(player: Player, _stationType: string, _uniqueId: string, residentNames: { string })
	if typeof(residentNames) ~= "table" then
		return
	end
	for _, residentName in ipairs(residentNames) do
		if typeof(residentName) == "string" and residentName ~= "" then
			local residentState = ResidentService.GetResident(player, residentName)
			if residentState then
				residentState:CancelCurrentAction("StationRemoved")
				residentState:ClearQueuedActions()
				-- Ensure we clear any rest pose (lying down) in case the station (e.g., a bed)
				-- was removed while the resident was resting. LeaveSeat handles seated
				-- residents but does not clear rest poses applied for lying down.
				ResidentMovement.LeaveSeat(residentState, nil)
				ResidentMovement.ClearRestPose(residentState)
				State.setPending(residentState, nil)
				State.clearNextEvaluation(residentState)
				task.defer(function()
					ResidentAutonomyService.TrySatisfyNeedsForResident(
						player,
						residentName,
						residentState,
						os.clock(),
						TimeScale.GetClockTime()
					)
				end)
			end
		end
	end
end

function ResidentAutonomyService.Decide(dt: number)
	local nowClock = os.clock()
	local clockTime = TimeScale.GetClockTime()
	local allResidents = ResidentService.GetResidents()
	for userId, residents in pairs(allResidents) do
		local player = getPlayerByUserId(userId)
		if player then
			local stationCache = PlotService.GetStationsForPlayer(player)

			-- Update passive fun based on plot contents
			updatePassiveFun(residents, stationCache)

			for residentName, residentState in pairs(residents) do
				-- Update dissatisfaction
				local satisfaction = residentState:GetSatisfaction()

				-- Resolve tenant traits
				local tipMultiplier = 1
				local dissatisfactionMultiplier = 1
				local tenantId = residentState.Save.TenantId
				local lease = nil

				if tenantId then
					if not TenantService then
						TenantService = require(ServerScriptService.Server.Services.TenantService)
					end
					local leases = TenantService.GetActiveLeases(player)
					if leases and leases[tenantId] then
						lease = leases[tenantId]
						if lease.Traits then
							for _, traitId in ipairs(lease.Traits) do
								local trait = TenantTraits.GetTrait(traitId)
								if trait and trait.Effects then
									if trait.Effects.TipMultiplier then
										tipMultiplier *= trait.Effects.TipMultiplier
									end
									if trait.Effects.DissatisfactionMultiplier then
										dissatisfactionMultiplier *= trait.Effects.DissatisfactionMultiplier
									end
								end
							end
						end
					end
				end

				-- Tip Logic: Detect transition from Not Satisfied (< 0.5) to Satisfied (>= 0.5)
				local isSatisfied = satisfaction >= 0.5
				local wasSatisfied = residentState.WasSatisfied

				if wasSatisfied == nil then
					residentState.WasSatisfied = isSatisfied
				elseif not wasSatisfied and isSatisfied then
					residentState.WasSatisfied = true
					local root = residentState.Model and residentState.Model.PrimaryPart
					if root then
						local tipAmount = 50
						if lease then
							local tierId = lease.TierId
							if tierId == "Cozy" then
								tipAmount = 100
							elseif tierId == "Upgraded" then
								tipAmount = 250
							elseif tierId == "Premium" then
								tipAmount = 500
							end
						end

						tipAmount = math.floor(tipAmount * tipMultiplier)
						TipsService.AwardTip(player, residentName, tipAmount, root.Position)
					end
				elseif wasSatisfied and not isSatisfied then
					residentState.WasSatisfied = false
				end

				-- Apply dissatisfaction multiplier to dt
				residentState:UpdateDissatisfaction(dt * dissatisfactionMultiplier, satisfaction, 0.35) -- 35% threshold

				if residentState:GetDissatisfactionTime() > 1200 then -- 20 minutes tolerance
					if tenantId then
						task.defer(function()
							TenantService.EvictTenant(player, tenantId)
							-- Notification could be handled here or in TenantService
						end)
					end
				end

				ResidentAutonomyService.TrySatisfyNeedsForResident(
					player,
					residentName,
					residentState,
					nowClock,
					clockTime,
					stationCache
				)
			end
		end
	end
end

local function startTask()
	if not WorldUpdate.IsSubscribed(Constants.AUTONOMY_TASK) then
		WorldUpdate.Subscribe(Constants.AUTONOMY_TASK, Constants.AUTONOMY_INTERVAL, function(dt)
			ResidentAutonomyService.Decide(dt)
		end)
	end
end

function ResidentAutonomyService.Init()
	State.refreshTimeScaleCaches()
	Lighting:GetAttributeChangedSignal("SecondsPerFullDay"):Connect(State.refreshTimeScaleCaches)
	PlotService.PlotClaimed:Connect(function(player)
		State.StationIteratorState[player.UserId] = nil
	end)
	PlotService.PlotUnclaimed:Connect(function(player)
		State.StationIteratorState[player.UserId] = nil
	end)
	PlotService.StationRemoved:Connect(handleStationRemoved)
	ResidentService.PlayerResidentsChanged:Connect(function()
		-- Cooldowns use weak keys; no explicit cleanup needed beyond clearing pending flags.
	end)
	startTask()
end

return ResidentAutonomyService
