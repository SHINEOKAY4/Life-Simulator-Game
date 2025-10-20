--!strict
-- StarterPlayerScripts/Client/Modules/GigManager.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GigPackets = require(ReplicatedStorage.Network.GigPackets)

export type GigRunInfo = {
	RunId: string,
	GigId: string,
}

local GigManager = {}
local activeRuns: { [string]: GigRunInfo } = {}

function GigManager.StartGig(gigId: string): (boolean, string, string?)
	local success, message, remoteRunId = GigPackets.RequestStart:Fire(gigId)
	if not success then
		return false, message, nil
	end
	local runId = if type(remoteRunId) == "string" and remoteRunId ~= "" then remoteRunId else nil
	if runId then
		activeRuns[runId] = {
			RunId = runId,
			GigId = gigId,
		}
	end
	return true, message, runId
end

function GigManager.SubmitResult(runId: string, tier: string): (boolean, string, number)
	local runInfo = activeRuns[runId]
	if not runInfo then
		return false, "No active gig run.", 0
	end
	local success, message, payout = GigPackets.SubmitScore:Fire(runId, tier)
	if success then
		activeRuns[runId] = nil
	end
	return success, message, payout
end

function GigManager.Cancel(runId: string)
	activeRuns[runId] = nil
end

function GigManager.GetActiveRuns()
	return activeRuns
end

return GigManager
