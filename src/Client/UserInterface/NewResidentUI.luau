--!strict
-- StarterPlayerScripts/Client/UserInterface/NewResident.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentStore = require(script.Parent.Parent.ClientStores.ResidentsStore)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local NewResidentUI = {}

function NewResidentUI.Init()
	ResidentsPackets.PromptResidentCreation.OnClientEvent:Connect(function()
		-- Create default starter residents
		local johnDoe = {
			Name = "John Doe",
			Gender = "Male",
		}
		local janeDoe = {
			Name = "Jane Doe",
			Gender = "Female",
		}

		ResidentStore.RequestAddResident(johnDoe)
		ResidentStore.RequestAddResident(janeDoe)
	end)
end

return NewResidentUI
