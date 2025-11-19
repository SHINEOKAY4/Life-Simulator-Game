--!strict
-- ServerScriptService/Server/Services/ResidentNeedService.lua

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentAutonomyService = require(ServerScriptService.Server.Services.ResidentAutonomyService)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local TraitUtils = require(ReplicatedStorage.Shared.Utilities.TraitUtils)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local TenantService = require(ServerScriptService.Server.Services.TenantService)
local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)

type ResidentState = any

type ResidentEntry = {
	Player: Player,
	ResidentName: string,
	State: ResidentState,
}

local ResidentNeedService = {}
local Residents: { ResidentEntry } = {}

local IsRunning = false
local SubscriberId = "Needs"
local IntervalSeconds = 0.25

local function rebuildResidentSnapshot()
	table.clear(Residents)
	local playersResidents = ResidentService.GetResidents()
	for userId, residentMap in pairs(playersResidents) do
		local player = Players:GetPlayerByUserId(userId)
		if player then
			for residentName, residentState in pairs(residentMap) do
				Residents[#Residents + 1] = {
					Player = player,
					ResidentName = residentName,
					State = residentState,
				}
			end
		end
	end
end

local function pruneResidents(): boolean
	local writeIndex = 1
	local removed = false

	for readIndex = 1, #Residents do
		local entry = Residents[readIndex]
		local player = entry.Player
		local residentState = entry.State
		if player.Parent ~= nil and residentState ~= nil and residentState.ActionQueue ~= nil then
			if writeIndex ~= readIndex then
				Residents[writeIndex] = entry
			end
			writeIndex += 1
		else
			removed = true
		end
	end

	for i = #Residents, writeIndex, -1 do
		Residents[i] = nil
	end

	return removed
end

function ResidentNeedService.Init()
	ResidentService.PlayerResidentsChanged:Connect(function()
		ResidentNeedService.UpdateRegisteredResidentsNeeds()
	end)
	Players.PlayerRemoving:Connect(function(_player)
		ResidentNeedService.UpdateRegisteredResidentsNeeds()
	end)
end

function ResidentNeedService.Start()
	if IsRunning then
		return
	end
	IsRunning = true

	WorldUpdate.Subscribe(SubscriberId, IntervalSeconds, function(deltaTime: number)
		if #Residents == 0 then
			ResidentNeedService.Stop()
			return
		end

		if pruneResidents() and #Residents == 0 then
			ResidentNeedService.Stop()
			return
		end

		local gameHours = TimeScale.GameHoursFromRealDelta(deltaTime)
		if gameHours <= 0 then
			return
		end

		local nowClock = os.clock()
		local clockTime = TimeScale.GetClockTime()

		for _, entry in ipairs(Residents) do
			local residentState = entry.State
			if residentState ~= nil then
				ResidentNeedService.Decay(entry.Player, residentState, gameHours)
				ResidentAutonomyService.TrySatisfyNeedsForResident(
					entry.Player,
					entry.ResidentName,
					residentState,
					nowClock,
					clockTime
				)
			end
		end
	end)
end

function ResidentNeedService.Stop()
	if not IsRunning then
		return
	end
	IsRunning = false
	WorldUpdate.Unsubscribe(SubscriberId)
end

function ResidentNeedService.Decay(player: Player, resident: ResidentState, gameHours: number)
	if gameHours <= 0 then
		return
	end
	local globalPaused = false
	if resident and typeof(resident.IsNeedDecayPaused) == "function" then
		globalPaused = resident:IsNeedDecayPaused()
	end
	if globalPaused then
		return
	end

	-- Resolve tenant traits for decay multipliers
	local tenantMultipliers = {}
	if resident.Save and resident.Save.TenantId then
		local leases = TenantService.GetActiveLeases(player)
		if leases and leases[resident.Save.TenantId] then
			local lease = leases[resident.Save.TenantId]
			if lease.Traits then
				for _, traitId in ipairs(lease.Traits) do
					local trait = TenantTraits.GetTrait(traitId)
					if trait and trait.Effects and trait.Effects.NeedDecayMultipliers then
						for need, mult in pairs(trait.Effects.NeedDecayMultipliers) do
							tenantMultipliers[need] = (tenantMultipliers[need] or 1) * mult
						end
					end
				end
			end
		end
	end

	local hasNeedPauseCheck = resident and typeof(resident.IsNeedPaused) == "function"
	for needName, definition in pairs(NeedConfig.Needs) do
		if hasNeedPauseCheck and resident:IsNeedPaused(needName) then
			continue
		end
		local value = resident:GetNeed(needName)
		local traits = if resident.GetTraits then resident:GetTraits() else nil
		local decayMultiplier = TraitUtils.GetNeedDecayMultiplier(traits, needName)

		if tenantMultipliers[needName] then
			decayMultiplier *= tenantMultipliers[needName]
		end

		local decayRate = definition.DecayPerHour * decayMultiplier
		local newValue = math.clamp(value - decayRate * gameHours, definition.Min, definition.Max)
		if newValue ~= value then
			resident:SetNeed(needName, newValue)
		end
	end
end
function ResidentNeedService.UpdateRegisteredResidentsNeeds()
	rebuildResidentSnapshot()
	if #Residents == 0 then
		ResidentNeedService.Stop()
	else
		ResidentNeedService.Start()
	end
end

return ResidentNeedService
