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
	ResidentsPackets.PlayersResidentsSync.OnClientEvent:Connect(function(payload)
		local userId = payload.UserId
		local current = PlayersResidents[userId]
		if not current then
			current = {}
			PlayersResidents[userId] = current
		end

		local seen: { [string]: boolean } = {}
		local residentsPayload = payload.Residents :: { any }?
		if type(residentsPayload) ~= "table" then
			return
		end

		for _, resident in ipairs(residentsPayload) do
			if typeof(resident) == "table" and type(resident.Name) == "string" then
				local residentName = resident.Name
				seen[residentName] = true
				local existing = current[residentName]
				current[residentName] = resident
				if existing then
					ResidentsStore.ResidentsUpdated:Fire(userId, resident)
				else
					ResidentsStore.ResidentAdded:Fire(userId, resident)
				end
			end
		end

		local toRemove = {}
		for residentName in pairs(current) do
			if not seen[residentName] then
				table.insert(toRemove, residentName)
			end
		end
		for _, residentName in ipairs(toRemove) do
			current[residentName] = nil
			ResidentsStore.ResidentRemoved:Fire(userId, residentName)
		end
	end)

	ResidentsPackets.PlayerResidentDelta.OnClientEvent:Connect(function(payload)
		local userId = payload.UserId
		local residents = PlayersResidents[userId]
		if not residents then
			residents = {}
			PlayersResidents[userId] = residents
		end

		local deltas = (payload.ResidentDelta :: { any }?) or {}
		if #deltas > 0 then
			for _, resident in ipairs(deltas) do
				if typeof(resident) == "table" and type(resident.Name) == "string" then
					local residentName = resident.Name
					local existing = residents[residentName]
					residents[residentName] = resident
					if existing then
						ResidentsStore.ResidentsUpdated:Fire(userId, resident)
					else
						ResidentsStore.ResidentAdded:Fire(userId, resident)
					end
				end
			end
		else
			local residentName = payload.ResidentName
			if type(residentName) == "string" then
				local previous = residents[residentName]
				if previous then
					residents[residentName] = nil
					ResidentsStore.ResidentRemoved:Fire(userId, residentName)
				end
			end
		end
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

-- TODO: Optimize needs data synchronization
-- Consider sending needs data on-demand when UI is opened rather than constant updates
-- This would reduce network traffic for all residents

return ResidentsStore
