--!strict
-- StarterPlayerScripts/Client/ClientStores/ResidentsStore.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local ResidentsStore = {}
local ResidentsState = {}

function ResidentsStore.Init()
	print("ResidentsStore initialized.")

	-- Future implementation for managing resident data on the client side
	ResidentsPackets.ResidentStateSync.OnClientEvent:Connect(function(residentsData)
		for _, resident in ipairs(residentsData) do
			ResidentsState[resident.Name] = resident
		end
		print("Residents state synchronized:", ResidentsState)
		-- Here you would typically update your UI or state management system with the new residents data
	end)
end

return ResidentsStore
