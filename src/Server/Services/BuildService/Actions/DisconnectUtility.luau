--!strict
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local UtilityService = require(ServerScriptService.Server.Services.UtilityService)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local function DisconnectUtility(player: Player, payload: { SourceKey: string, TargetKey: string }): (boolean, string)
	local sourceKey = payload.SourceKey
	local targetKey = payload.TargetKey

	if not sourceKey or not targetKey then
		return false, "Invalid keys"
	end

	local plotState = PlotService.GetState(player)
	if not plotState then
		return false, "No plot found"
	end

	local sourceObj = plotState.Save.PlacedObjects[sourceKey]
	local targetObj = plotState.Save.PlacedObjects[targetKey]

	if not sourceObj or not targetObj then
		return false, "Object not found"
	end

	-- Update Metadata
	local sourceMetadata = sourceObj.Metadata or {}
	local typedSourceMetadata = sourceMetadata :: { [string]: any }
	local sourceConnections = typedSourceMetadata.Connections or {}

	local targetMetadata = targetObj.Metadata or {}
	local typedTargetMetadata = targetMetadata :: { [string]: any }
	local targetConnections = typedTargetMetadata.Connections or {}

	local function removeConnection(list: { string }, key: string)
		for i = #list, 1, -1 do
			if list[i] == key then
				table.remove(list, i)
			end
		end
	end

	removeConnection(sourceConnections, targetKey)
	typedSourceMetadata.Connections = sourceConnections
	sourceObj.Metadata = sourceMetadata

	removeConnection(targetConnections, sourceKey)
	typedTargetMetadata.Connections = targetConnections
	targetObj.Metadata = targetMetadata

	-- Notify client of update
	Packets.UtilityUpdate:FireClient(player, {
		{ Key = sourceKey, Metadata = sourceMetadata },
		{ Key = targetKey, Metadata = targetMetadata },
	})

	print("[DisconnectUtility] Disconnection successful. Calling Recalculate...")
	-- Recalculate power
	UtilityService.Recalculate(player)
	print("[DisconnectUtility] Recalculate returned.")

	return true, "Disconnected"
end

return DisconnectUtility
