--!strict
-- StarterPlayerScripts/Client/UserInterface/NewResident.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentStore = require(script.Parent.Parent.ClientStores.ResidentsStore)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local NewResidentUI = {}

function NewResidentUI.Init()
	ResidentsPackets.PromptResidentCreation.OnClientEvent:Connect(function()
		print("Received PromptResidentCreation packet from server. Opening resident creation UI...")
		-- Here you would typically trigger your UI to open
		-- For example:
		-- local ResidentCreationUI = require(script.Parent.UserInterface.ResidentCreationUI)
		-- ResidentCreationUI:Open()

		-- ========== Test firing AddResidentRequest ==========
		-- Simulate user input for testing purposes
		local johnDoe = {
			Name = "John Doe",
			Gender = "Male",
		}
		local janeDoe = {
			Name = "Jane Doe",
			Gender = "Female",
		}

		local success, message = ResidentStore.RequestAddResident(johnDoe)
		print("AddResidentRequest response:", success, message)

		local success2, message2 = ResidentStore.RequestAddResident(janeDoe)
		print("AddResidentRequest response:", success2, message2)
	end)
end

return NewResidentUI
