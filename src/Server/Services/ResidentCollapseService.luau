--!strict

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local AutonomyState = require(ServerScriptService.Server.Services.ResidentAutonomyService.State)
local ResidentActionHandlers = require(ServerScriptService.Server.Modules.ResidentActionHandlers)
local NeedEffects = require(ServerScriptService.Server.Utilities.NeedEffects)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)

local ResidentCollapseService = {}

local energyDef = NeedConfig.Needs.Energy
local COLLAPSE_RELEASE_ENERGY = 4 -- minimum energy needed before regaining manual control
local COLLAPSE_CHANNEL = "Collapse"
local COLLAPSE_RELEASE_REASON_HUNGER = "HungerInterrupt"

local collapseConnections = setmetatable({} :: { [any]: RBXScriptConnection }, { __mode = "k" })
local contextByResident = setmetatable({} :: { [any]: { UserId: number?, Name: string } }, { __mode = "k" })
local activeCollapse = setmetatable({} :: { [any]: boolean }, { __mode = "k" })
local energyPauseTokens = setmetatable({} :: { [any]: string }, { __mode = "k" })
local releaseReasons = setmetatable({} :: { [any]: string }, { __mode = "k" })

local collapseChat = {
	{ Text = "I'm spent... hitting the floor." },
	{ Text = "Too exhausted to stand another second." },
	{ Text = "Need to crash right here." },
}

local function getResidentName(residentState: any): string
	local save = residentState and residentState.Save
	local name = if save and typeof(save.Name) == "string" then save.Name else "UnknownResident"
	return name
end

local function setCollapseAttribute(residentState: any, active: boolean)
	local model = residentState and residentState.Model
	if model and model:IsA("Model") then
		model:SetAttribute("EnergyCollapseActive", active)
	end
end

local function applyEnergyPause(residentState: any)
	if energyPauseTokens[residentState] ~= nil then
		return
	end
	if typeof(residentState.PushNeedPause) == "function" then
		residentState:PushNeedPause("Energy")
		energyPauseTokens[residentState] = "Need"
		return
	end
	if typeof(residentState.PushNeedDecayPause) == "function" then
		residentState:PushNeedDecayPause()
		energyPauseTokens[residentState] = "Global"
		return
	end
	if typeof(residentState.SetNeedDecayPaused) == "function" then
		residentState:SetNeedDecayPaused(true)
		energyPauseTokens[residentState] = "Toggle"
	end
end

local function releaseEnergyPause(residentState: any)
	local token = energyPauseTokens[residentState]
	if token == nil then
		return
	end
	energyPauseTokens[residentState] = nil
	if token == "Need" then
		if typeof(residentState.PopNeedPause) == "function" then
			residentState:PopNeedPause("Energy")
		end
		return
	end
	if token == "Global" then
		if typeof(residentState.PopNeedDecayPause) == "function" then
			residentState:PopNeedDecayPause()
		end
		return
	end
	if token == "Toggle" then
		if typeof(residentState.SetNeedDecayPaused) == "function" then
			residentState:SetNeedDecayPaused(false)
		end
	end
end

local function setReleaseReason(residentState: any, reason: string)
	releaseReasons[residentState] = reason
end

local function takeReleaseReason(residentState: any): string?
	local reason = releaseReasons[residentState]
	if reason ~= nil then
		releaseReasons[residentState] = nil
	end
	return reason
end

local function releaseCollapseHold(residentState: any)
	activeCollapse[residentState] = nil
	AutonomyState.setPending(residentState, nil)
	setCollapseAttribute(residentState, false)
	releaseEnergyPause(residentState)
	ResidentMovement.ClearRestPose(residentState)
	residentState._EnergyCollapseRelease = nil
end

function ResidentCollapseService.ReleaseCollapseHold(residentState: any)
	if residentState then
		releaseCollapseHold(residentState)
	end
end

local handleEnergyChanged: ((residentState: any, context: { UserId: number?, Name: string }, value: number) -> ())?

local function suppressHungerGuard(residentState: any): boolean
	if not energyDef then
		return false
	end
	local energy = residentState:GetNeed("Energy")
	if typeof(energy) ~= "number" then
		return true
	end
	return energy < COLLAPSE_RELEASE_ENERGY
end

local function startCollapse(residentState: any, context: { UserId: number?, Name: string })
	if not energyDef then
		return
	end
	if activeCollapse[residentState] then
		return
	end
	releaseReasons[residentState] = nil
	activeCollapse[residentState] = true
	setCollapseAttribute(residentState, true)
	residentState._EnergyCollapseRelease = function()
		releaseCollapseHold(residentState)
	end
	applyEnergyPause(residentState)

	local residentName = context.Name or getResidentName(residentState)
	ResidentDebug.Trace(COLLAPSE_CHANNEL, string.format("Energy collapse triggered: %s", residentName))

	residentState:CancelCurrentAction("EnergyCollapse")
	residentState:ClearQueuedActions()
	AutonomyState.setPending(residentState, "Energy")
	AutonomyState.clearNextEvaluation(residentState)
	ResidentMovement.LeaveSeat(residentState, nil)

	local behavior = ResidentActionHandlers.GetRestBehavior("Ground")
	if not behavior then
		activeCollapse[residentState] = nil
		setCollapseAttribute(residentState, false)
		AutonomyState.setPending(residentState, nil)
		releaseEnergyPause(residentState)
		return
	end

	behavior.ChatPhrases = collapseChat
	behavior.ChatIntervalSeconds = nil
	behavior.EmergencyGuards = {
		Hunger = function(state, value, def)
			if suppressHungerGuard(state) then
				return true
			end
			if typeof(value) == "number" and def and typeof(def) == "table" then
				local critical = def.Critical
				if typeof(critical) == "number" and value <= critical then
					setReleaseReason(state, COLLAPSE_RELEASE_REASON_HUNGER)
				end
			end
			return false
		end,
	}

	local baseEndReason = behavior.EndReasonProvider
	behavior.EndReasonProvider = function(state): string?
		local energyValue = state:GetNeed("Energy")
		if type(energyValue) == "number" and energyValue >= COLLAPSE_RELEASE_ENERGY then
			return nil
		end
		if baseEndReason then
			return baseEndReason(state)
		end
		return nil
	end

	local userId = context.UserId

	residentState:EnqueueAction("Forced:EnergyCollapse", function(_context)
		local model = residentState.Model
		local rootPart: BasePart? = nil
		if model and model:IsA("Model") then
			rootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		end

		local restPoseApplied = false
		if rootPart then
			restPoseApplied = ResidentMovement.ApplyRestPose(residentState, {
				Mode = "Ground",
				EntryCFrame = rootPart.CFrame,
				StationModel = nil,
				EntryAttachment = nil,
			})
		end

		local player: Player? = nil
		if userId then
			player = Players:GetPlayerByUserId(userId)
		end

		local cancelToken = if _context then _context.CancelToken else nil
		local ok, result = pcall(function()
			return NeedEffects.Run(residentState, cancelToken, behavior, {
				StationType = "GroundCollapse",
				ActionName = "collapse",
				NeedName = "Energy",
				Player = player,
			})
		end)

		local currentEnergy = residentState:GetNeed("Energy")
		local keepPose = restPoseApplied

		if keepPose then
			if activeCollapse[residentState] then
				AutonomyState.setPending(residentState, "Energy")
			else
				AutonomyState.setPending(residentState, nil)
			end
			if type(currentEnergy) == "number" and currentEnergy >= COLLAPSE_RELEASE_ENERGY then
				setCollapseAttribute(residentState, false)
			else
				setCollapseAttribute(residentState, true)
			end
		else
			releaseCollapseHold(residentState)
		end

		local succeeded = ok and result == true
		if succeeded then
			AutonomyState.setNeedCooldown(residentState, "Energy")
		else
			ResidentDebug.Trace(COLLAPSE_CHANNEL, string.format("Collapse run failed: %s", residentName), {
				Error = if ok then "Cancelled" else result,
			})
		end

		local releaseReason = takeReleaseReason(residentState)
		if releaseReason == COLLAPSE_RELEASE_REASON_HUNGER then
			if restPoseApplied then
				ResidentMovement.ClearRestPose(residentState)
			end
			if activeCollapse[residentState] then
				releaseCollapseHold(residentState)
			end
		end

		if handleEnergyChanged then
			task.defer(function()
				handleEnergyChanged(residentState, context, residentState:GetNeed("Energy"))
			end)
		end
	end)
end

handleEnergyChanged = function(residentState: any, context: { UserId: number?, Name: string }, value: number)
	if not energyDef then
		return
	end
	if type(value) ~= "number" then
		return
	end
	if value <= energyDef.Min then
		if not activeCollapse[residentState] then
			startCollapse(residentState, context)
		else
			setCollapseAttribute(residentState, true)
		end
		return
	end
	if value >= COLLAPSE_RELEASE_ENERGY then
		setCollapseAttribute(residentState, false)
		local release = residentState._EnergyCollapseRelease
		if activeCollapse[residentState] and typeof(release) == "function" then
			release()
		end
	end
end

local function ensureConnection(residentState: any, userId: number?, residentName: string)
	local context = contextByResident[residentState]
	if not context then
		context = { UserId = userId, Name = residentName }
		contextByResident[residentState] = context
	else
		context.UserId = userId
		context.Name = residentName
	end

	local existing = collapseConnections[residentState]
	if existing then
		existing:Disconnect()
	end

	collapseConnections[residentState] = residentState.NeedsChanged:Connect(function(needName: string, newValue: number)
		if needName ~= "Energy" then
			return
		end
		if handleEnergyChanged then
			handleEnergyChanged(residentState, context, newValue)
		end
	end)

	if handleEnergyChanged then
		handleEnergyChanged(residentState, context, residentState:GetNeed("Energy"))
	end
end

local function cleanupResident(residentState: any)
	local connection = collapseConnections[residentState]
	if connection then
		connection:Disconnect()
		collapseConnections[residentState] = nil
	end
	contextByResident[residentState] = nil
	releaseCollapseHold(residentState)
	releaseEnergyPause(residentState)
	releaseReasons[residentState] = nil
end

function ResidentCollapseService.Refresh()
	local seen: { [any]: boolean } = {}
	local allResidents = ResidentService.GetResidents()
	for userId, residentMap in pairs(allResidents) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			for residentName, residentState in pairs(residentMap) do
				if residentState then
					seen[residentState] = true
					ensureConnection(residentState, userId, residentName)
				end
			end
		end
	end

	for residentState in pairs(collapseConnections) do
		if not seen[residentState] then
			cleanupResident(residentState)
		end
	end
end

function ResidentCollapseService.ReleaseForPlayer(player: Player)
	for residentState, context in pairs(contextByResident) do
		if context.UserId == player.UserId then
			cleanupResident(residentState)
		end
	end
end

function ResidentCollapseService.Init()
	if not energyDef then
		return
	end
	ResidentService.PlayerResidentsChanged:Connect(function()
		ResidentCollapseService.Refresh()
	end)
	Players.PlayerRemoving:Connect(function(player)
		ResidentCollapseService.ReleaseForPlayer(player)
	end)
	task.defer(ResidentCollapseService.Refresh)
end

return ResidentCollapseService
