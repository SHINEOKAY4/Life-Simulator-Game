--!strict
-- StarterPlayerScripts/Modules/NewResident.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local NewResident = {}

function NewResident.Init()
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
		local success, message = ResidentsPackets.AddResidentRequest:Fire(johnDoe)
		local success2, message2 = ResidentsPackets.AddResidentRequest:Fire(janeDoe)
		print("AddResidentRequest response:", success, message)
		print("AddResidentRequest response:", success2, message2)
	end)
end

return NewResident
