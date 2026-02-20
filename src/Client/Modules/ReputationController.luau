--!strict
-- Client/Modules/ReputationController.luau
-- Syncs reputation updates from server to the client reputation UI.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReputationPackets = require(ReplicatedStorage.Network.ReputationPackets)
local ReputationUI = require(script.Parent.Parent.UserInterface.ReputationUI)

local ReputationController = {}
local isInitialized = false

function ReputationController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	ReputationUI.Init()

	ReputationPackets.ReputationUpdated.OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then
			ReputationUI.SetData(payload)
		end
	end)
end

return ReputationController
