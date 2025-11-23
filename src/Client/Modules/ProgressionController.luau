--!strict
-- StarterPlayerScripts/Client/Modules/ProgressionController.luau
-- Keeps local progression state in sync and surfaces level-up feedback.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionPackets = require(ReplicatedStorage.Network.ProgressionPackets)
local ExperienceVFX = require(script.Parent.ExperienceVFX)

local LocalPlayer = Players.LocalPlayer

type ProgressionSnapshot = {
	Level: number,
	ExperienceTotal: number,
	ExperienceIntoLevel: number,
	ExperienceForNext: number,
}

local ProgressionController = {}

local state: ProgressionSnapshot = {
	Level = 1,
	ExperienceTotal = 0,
	ExperienceIntoLevel = 0,
	ExperienceForNext = 0,
}

local unlockedCache: { [string]: boolean } = {}

local function setAttributes(snapshot: ProgressionSnapshot)
	LocalPlayer:SetAttribute("PlayerLevel", snapshot.Level)
	LocalPlayer:SetAttribute("PlayerExperience", snapshot.ExperienceTotal)
	LocalPlayer:SetAttribute("PlayerXPIntoLevel", snapshot.ExperienceIntoLevel)
	LocalPlayer:SetAttribute("PlayerXPForNext", snapshot.ExperienceForNext)
end

local function cacheUnlockIds(ids: any)
	if typeof(ids) ~= "table" then
		return
	end
	for _, id in ipairs(ids) do
		if typeof(id) == "string" and id ~= "" then
			unlockedCache[id] = true
		end
	end
end

local function onProgressionUpdate(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local previousExperience = state.ExperienceTotal

	state.Level = payload.Level or state.Level
	state.ExperienceTotal = payload.ExperienceTotal or state.ExperienceTotal
	state.ExperienceIntoLevel = payload.ExperienceIntoLevel or state.ExperienceIntoLevel
	state.ExperienceForNext = payload.ExperienceForNext or state.ExperienceForNext
	setAttributes(state)

	cacheUnlockIds(payload.UnlockedItemIds)

	local xpDelta = if typeof(payload.Delta) == "number"
		then payload.Delta
		else state.ExperienceTotal - previousExperience
	if xpDelta and xpDelta > 0 then
		ExperienceVFX.PlayExperienceGain(xpDelta, payload.Reason)
	end
end

function ProgressionController.GetLevel(): number
	return state.Level
end

function ProgressionController.IsUnlocked(itemId: string): boolean
	return unlockedCache[itemId] == true
end

function ProgressionController.Init()
	state.Level = typeof(LocalPlayer:GetAttribute("PlayerLevel")) == "number"
			and (LocalPlayer:GetAttribute("PlayerLevel") :: any)
		or state.Level
	state.ExperienceTotal = typeof(LocalPlayer:GetAttribute("PlayerExperience")) == "number"
			and (LocalPlayer:GetAttribute("PlayerExperience") :: any)
		or state.ExperienceTotal
	state.ExperienceIntoLevel = typeof(LocalPlayer:GetAttribute("PlayerXPIntoLevel")) == "number"
			and (LocalPlayer:GetAttribute("PlayerXPIntoLevel") :: any)
		or state.ExperienceIntoLevel
	state.ExperienceForNext = typeof(LocalPlayer:GetAttribute("PlayerXPForNext")) == "number"
			and (LocalPlayer:GetAttribute("PlayerXPForNext") :: any)
		or state.ExperienceForNext
	setAttributes(state)

	ProgressionPackets.ProgressionUpdate.OnClientEvent:Connect(onProgressionUpdate)
end

return ProgressionController
