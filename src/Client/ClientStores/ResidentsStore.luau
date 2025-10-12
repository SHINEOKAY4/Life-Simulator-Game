--!strict
-- StarterPlayerScripts/Client/ClientStores/ResidentsStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local ResidentsStore = {}
local PlayersResidents = {}

ResidentsStore.ResidentsUpdated = GoodSignal.new()
ResidentsStore.ResidentAdded = GoodSignal.new()
ResidentsStore.ResidentRemoved = GoodSignal.new()

function ResidentsStore.Init()
	-- Future implementation for managing resident data on the client side
	ResidentsPackets.PlayersResidentsSync.OnClientEvent:Connect(function(payload)
		local userId = payload.UserId
		if not PlayersResidents[userId] then
			PlayersResidents[userId] = {}
		end

		for _, resident in ipairs(payload.Residents) do -- Rebuild the keyed table
			PlayersResidents[userId][resident.Name] = resident
			ResidentsStore.ResidentAdded:Fire(userId, resident)
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
			if not PlayersResidents[userId][payload.ResidentName] then
				-- New resident added
				ResidentsStore.ResidentAdded:Fire(userId, delta)
			else
				-- Existing resident updated
				ResidentsStore.ResidentsUpdated:Fire(userId, delta)
			end
			-- Update existing resident
			PlayersResidents[userId][payload.ResidentName] = delta
		else
			-- Remove existing resident
			PlayersResidents[userId][payload.ResidentName] = nil
			ResidentsStore.ResidentRemoved:Fire(userId, payload.ResidentName)
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
