--!strict

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ResidentActionHandlers = require(ServerScriptService.Server.Modules.ResidentActionHandlers)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local NeedEffects = require(ServerScriptService.Server.Utilities.NeedEffects)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local State = require(script.Parent.State)
local Utils = require(script.Parent.Utils)
local Constants = require(script.Parent.Constants)
local RandomProvider = require(script.Parent.RandomProvider)

export type ResidentState = any

local SocialCoordinator = {}
local roamRandom = RandomProvider.get()

local function getResidentRootPart(resident: ResidentState): BasePart?
	local model = resident and resident.Model
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	return nil
end

local function getResidentRootPosition(resident: ResidentState): Vector3?
	local root = getResidentRootPart(resident)
	return if root then root.Position else nil
end

local function faceWorldPosition(resident: ResidentState, lookAt: Vector3)
	local root = getResidentRootPart(resident)
	if not root then
		return
	end
	local origin = root.Position
	local target = Vector3.new(lookAt.X, origin.Y, lookAt.Z)
	root.CFrame = CFrame.new(origin, target)
end

local function planDirectSocialTargets(
	primaryResident: ResidentState,
	partnerResident: ResidentState
): (Vector3?, Vector3?)
	local primaryPosition = getResidentRootPosition(primaryResident)
	local partnerPosition = getResidentRootPosition(partnerResident)
	if not primaryPosition or not partnerPosition then
		return nil, nil
	end
	local delta = partnerPosition - primaryPosition
	if delta.Magnitude < 1 then
		delta = Vector3.new(0, 0, 1)
	else
		delta = delta.Unit
	end
	local midpoint = (primaryPosition + partnerPosition) * 0.5
	local averageY = (primaryPosition.Y + partnerPosition.Y) * 0.5
	local anchor = Vector3.new(midpoint.X, averageY, midpoint.Z)
	local separation = 2
	local targetPrimary = anchor - delta * separation
	local targetPartner = anchor + delta * separation
	return targetPrimary, targetPartner
end

local function enqueueDirectSocialPair(
	player: Player,
	primaryName: string,
	primaryResident: ResidentState,
	partnerName: string,
	partnerResident: ResidentState
): boolean
	local primaryBehavior = ResidentActionHandlers.GetDirectSocialBehavior() :: any
	local partnerBehavior = ResidentActionHandlers.GetDirectSocialBehavior() :: any
	if not primaryBehavior or not partnerBehavior then
		return false
	end
	local targetPrimary, targetPartner = planDirectSocialTargets(primaryResident, partnerResident)
	if not targetPrimary or not targetPartner then
		return false
	end
	local conversationPhrases = primaryBehavior.ChatPhrases
	primaryBehavior.ChatIntervalSeconds = nil
	partnerBehavior.ChatIntervalSeconds = nil
	primaryBehavior.ChatPhrases = nil
	partnerBehavior.ChatPhrases = nil
	local session = {
		Cancelled = false,
		CancelReason = nil :: string?,
		ReadyFlags = {} :: { [ResidentState]: boolean },
		ReadyCount = 0,
		ExpectedReady = 2,
		CompletedCount = 0,
		DialogueStarted = false,
		SpokenLines = 0,
		LastLines = {} :: { [ResidentState]: string? },
		ParticipantStarted = {} :: { [ResidentState]: boolean },
		CompletedResidents = {} :: { [ResidentState]: boolean },
		SuccessBoostApplied = false,
	}

	local participants = {
		{
			Name = primaryName,
			Resident = primaryResident,
			PartnerName = partnerName,
			PartnerResident = partnerResident,
			Behavior = primaryBehavior,
			TargetPosition = targetPrimary,
		},
		{
			Name = partnerName,
			Resident = partnerResident,
			PartnerName = primaryName,
			PartnerResident = primaryResident,
			Behavior = partnerBehavior,
			TargetPosition = targetPartner,
		},
	}

	local function applySuccessBoost()
		if session.SuccessBoostApplied or session.CompletedCount <= 0 then
			return
		end
		session.SuccessBoostApplied = true
		for _, entry in ipairs(participants) do
			if session.ParticipantStarted[entry.Resident] then
				Utils.ensureSocialSatisfaction(entry.Resident)
				if session.CompletedResidents[entry.Resident] ~= true then
					State.setNeedCooldown(entry.Resident, "Social")
				end
			end
		end
	end

	local function ensureDialogueThread()
		if session.DialogueStarted then
			return
		end
		if not conversationPhrases or #conversationPhrases == 0 then
			return
		end
		session.DialogueStarted = true
		task.spawn(function()
			local speakerIndex = roamRandom:NextInteger(1, session.ExpectedReady)
			local nextSpeak = os.clock() + roamRandom:NextNumber(3, 5)
			while not session.Cancelled do
				if session.CompletedCount >= session.ExpectedReady then
					break
				end
				if session.ReadyCount < session.ExpectedReady then
					RunService.Heartbeat:Wait()
					nextSpeak = os.clock() + roamRandom:NextNumber(3, 5)
					continue
				end
				if session.SpokenLines >= 6 then
					break
				end
				local now = os.clock()
				if now < nextSpeak then
					RunService.Heartbeat:Wait()
					continue
				end
				local entry = participants[speakerIndex]
				if session.ReadyFlags[entry.Resident] then
					local lastLine = session.LastLines[entry.Resident]
					local phrase = ResidentChat.SelectChatText(entry.Resident, conversationPhrases, lastLine)
					if phrase then
						ResidentChat.ShowAction(entry.Resident, phrase)
						session.LastLines[entry.Resident] = phrase
						session.SpokenLines += 1
					end
				end
				speakerIndex = if speakerIndex == 1 then 2 else 1
				nextSpeak = now + roamRandom:NextNumber(8, 13)
			end
		end)
	end

	local function normalizedReason(reason: string?): string
		if reason and reason ~= "" then
			return reason
		end
		if session.CancelReason and session.CancelReason ~= "" then
			return session.CancelReason
		end
		return "DirectSocialCancelled"
	end

	local function clearParticipantState(resident: ResidentState)
		if session.ReadyFlags[resident] then
			session.ReadyFlags[resident] = nil
			if session.ReadyCount > 0 then
				session.ReadyCount -= 1
			end
		else
			session.ReadyFlags[resident] = nil
		end
		session.LastLines[resident] = nil
		State.setPending(resident, nil)
		State.clearNextEvaluation(resident)
	end

	local function markReady(resident: ResidentState)
		if session.ReadyFlags[resident] then
			return
		end
		session.ReadyFlags[resident] = true
		session.ReadyCount += 1
		session.ParticipantStarted[resident] = true
		if session.ReadyCount >= session.ExpectedReady then
			ensureDialogueThread()
		end
	end

	local function cancelSession(sourceResident: ResidentState?, reason: string?)
		if session.Cancelled then
			if not session.CancelReason and reason and reason ~= "" then
				session.CancelReason = reason
			end
			return
		end
		session.Cancelled = true
		session.CancelReason = normalizedReason(reason)
		for _, entry in ipairs(participants) do
			clearParticipantState(entry.Resident)
			if entry.Resident ~= sourceResident then
				entry.Resident:CancelCurrentAction(session.CancelReason)
			else
				local token = entry.Resident:GetCancelToken()
				if token then
					token.Reason = token.Reason or session.CancelReason
				end
			end
		end
		if session.CompletedCount > 0 then
			applySuccessBoost()
		end
	end

	for _, entry in ipairs(participants) do
		State.setPending(entry.Resident, "Social")
		State.clearNextEvaluation(entry.Resident)
	end

	local function runParticipant(entry: any)
		local actionName = string.format("Auto:DirectSocial:%s", entry.PartnerName)
		entry.Resident:EnqueueAction(actionName, function(context)
			local cancelToken = context.CancelToken :: any
			if session.Cancelled then
				clearParticipantState(entry.Resident)
				return
			end

			local arrived = ResidentMovement.GoToWorldPosition(entry.Resident, entry.TargetPosition, {
				CancelToken = cancelToken,
				TimeoutSeconds = 18,
				DebugName = string.format("DirectSocial:%s", entry.Name),
			})

			if session.Cancelled then
				clearParticipantState(entry.Resident)
				return
			end

			if cancelToken.Cancelled then
				cancelSession(entry.Resident, cancelToken.Reason)
				clearParticipantState(entry.Resident)
				return
			end

			if not arrived then
				cancelSession(entry.Resident, "DirectSocialPartnerFailed")
				clearParticipantState(entry.Resident)
				return
			end

			markReady(entry.Resident)

			local waitStart = os.clock()
			while not session.Cancelled and session.ReadyCount < session.ExpectedReady do
				if cancelToken.Cancelled then
					cancelSession(entry.Resident, cancelToken.Reason)
					clearParticipantState(entry.Resident)
					return
				end
				if os.clock() - waitStart > 6 then
					cancelSession(entry.Resident, "DirectSocialPartnerFailed")
					clearParticipantState(entry.Resident)
					return
				end
				RunService.Heartbeat:Wait()
			end

			if session.Cancelled then
				clearParticipantState(entry.Resident)
				return
			end

			if cancelToken.Cancelled then
				cancelSession(entry.Resident, cancelToken.Reason)
				clearParticipantState(entry.Resident)
				return
			end

			local partnerPosition = getResidentRootPosition(entry.PartnerResident)
			if partnerPosition then
				faceWorldPosition(entry.Resident, partnerPosition)
			end

			local succeeded = NeedEffects.Run(entry.Resident, cancelToken, entry.Behavior, {
				StationType = "SocialStation",
				ActionName = "chat",
				NeedName = "Social",
				PartnerName = entry.PartnerName,
				Player = player,
			})

			if succeeded then
				State.setNeedCooldown(entry.Resident, "Social")
				session.CompletedResidents[entry.Resident] = true
				session.CompletedCount += 1
				clearParticipantState(entry.Resident)
				if session.CompletedCount >= session.ExpectedReady then
					applySuccessBoost()
				end
				return
			end

			local reason = cancelToken.Reason
			if not reason or reason == "" then
				reason = Utils.detectCriticalNeed(entry.Resident)
			end
			cancelSession(entry.Resident, reason)
			clearParticipantState(entry.Resident)
		end)
	end

	runParticipant(participants[1])
	runParticipant(participants[2])
	return true
end

function SocialCoordinator.attemptDirectSocial(
	player: Player,
	residentName: string,
	resident: ResidentState,
	stationCache: { [string]: any }?
): boolean
	local needs = State.getNeeds()
	local socialDef = needs.Social
	if not socialDef then
		return false
	end
	local nowClock = os.clock()
	local value = resident:GetNeed("Social")
	local cache = stationCache or PlotService.GetStationsForPlayer(player)
	if Utils.hasBlockingCriticalNeed(player, resident, "Social", cache) then
		return false
	end
	local deficit = socialDef.Low - value
	if deficit <= 0 then
		return false
	end
	local moodMultiplier = math.max(0, 1 + resident:GetMoodBias("Social", nowClock))
	if deficit * moodMultiplier <= 0 then
		return false
	end
	local residents = ResidentService.GetResidents(player)
	if not residents then
		return false
	end
	local bestName: string? = nil
	local bestState: ResidentState? = nil
	local bestDeficit = 0
	local bestScore = 0
	for candidateName, candidateState in pairs(residents) do
		if candidateName ~= residentName and candidateState ~= nil then
			local candidatePending = State.getPending(candidateState)
			local candidateAvailable = Utils.shouldEvaluate(candidateState)
			if not candidateAvailable and candidatePending == Constants.ROAM_ACTION_NAME then
				Utils.preemptRoamForDirectSocial(candidateState)
				candidatePending = State.getPending(candidateState)
				candidateAvailable = Utils.shouldEvaluate(candidateState)
			end
			if candidateAvailable and candidatePending == nil then
				if not Utils.hasBlockingCriticalNeed(player, candidateState, "Social", cache) then
					local candidateValue = candidateState:GetNeed("Social")
					local candidateDeficit = socialDef.Low - candidateValue
					if candidateDeficit > 0 then
						local candidateMoodMultiplier = math.max(0, 1 + candidateState:GetMoodBias("Social", nowClock))
						local candidateScore = candidateDeficit * candidateMoodMultiplier
						if candidateScore > bestScore then
							bestScore = candidateScore
							bestDeficit = candidateDeficit
							bestName = candidateName
							bestState = candidateState
						end
					end
				end
			end
		end
	end
	if bestName and bestState and bestDeficit > 0 then
		return enqueueDirectSocialPair(player, residentName, resident, bestName, bestState)
	end
	return false
end

return SocialCoordinator
