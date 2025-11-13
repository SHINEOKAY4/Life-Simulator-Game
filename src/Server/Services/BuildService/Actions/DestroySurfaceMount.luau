--!strict

local ServerScriptService = game:GetService("ServerScriptService")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)

local function DestroySurfaceMount(player: Player, payload: { MountKey: string }): (boolean, string)
	if typeof(payload) ~= "table" then
		return false, "Invalid payload"
	end

	local mountKey = payload.MountKey
	if typeof(mountKey) ~= "string" or mountKey == "" then
		return false, "Invalid surface mount"
	end

	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local removed = state:RemoveSurfaceMount(mountKey)
	if not removed then
		return false, "Surface mount not found"
	end

	WorldPlacer.DespawnSurfaceMount(player, mountKey)
	Helpers.sendSurfaceMountDelta(player, "Removed", mountKey, removed)

	return true, "Surface mount removed"
end

return DestroySurfaceMount
