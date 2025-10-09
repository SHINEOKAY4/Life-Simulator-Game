--!strict
-- StarterPlayerScripts/Client/ClientStores/ResidentsStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local ResidentsStore = {}
local PlayersResidents = {}

function ResidentsStore.Init()
	-- Future implementation for managing resident data on the client side
	ResidentsPackets.PlayersResidentsSync.OnClientEvent:Connect(function(payload)
		if not PlayersResidents[payload.UserId] then
			PlayersResidents[payload.UserId] = {}
		end

		for _, resident in ipairs(payload.Residents) do -- Rebuild the keyed table
			PlayersResidents[payload.UserId][resident.Name] = resident
		end
		print("Residents state synchronized for all players.", PlayersResidents)
	end)

	ResidentsPackets.PlayerResidentDelta.OnClientEvent:Connect(function(payload)
		local userId = payload.UserId

		if not PlayersResidents[userId] then
			PlayersResidents[userId] = {}
		end
		local delta = payload.ResidentDelta[1]

		if delta then
			PlayersResidents[userId][payload.ResidentName] = delta
		else
			PlayersResidents[userId][payload.ResidentName] = nil
		end
		print("Resident delta received for user:", PlayersResidents)
	end)
end

function ResidentsStore.RequestAddResident(residentData: { Name: string, Gender: string })
	local success, message = ResidentsPackets.AddResidentRequest:Fire(residentData)
	return success, message
end

function ResidentsStore.RequestDeleteResident(residentName: string)
	local success, message = ResidentsPackets.DeleteResidentRequest:Fire(residentName)
	return success, message
end

return ResidentsStore

--#TODO: IDEA: Server do not send the needs data constantly on drift, instead when a player opens the resident
-- managementUI, the client requests the full data for that resident only once, and then the server sends
-- then the ui for bars updates in client after request.
-- this avoids requiring server to keep sending to update the needs bars constantly for all residents

--#TODO: IDEA: Residents are all created and managed in client, the server only stores the data and sends it when requested
-- this make the residents feels smoother and more responsive, and the server only needs to send data when something changes
-- server side only sends the command to resident to do something then client will do the actions moving to the target etc
-- this also allows to have more residents without overloading the server

--#TODO IDEA: Strategy to handle replication of all the players' residents
-- 1. Tag the residents with the player's UserId so in the loop we can filter them
-- 2. Use a spatial partitioning system to only replicate residents that are near the player
-- 3. Implement a LOD system where distant residents have less frequent updates
-- 4. Use a combination of the above strategies to optimize replication based on distance and player
