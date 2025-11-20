--!strict
-- Client/Modules/ReviewController.luau
-- Manages the review system on the client.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReviewPackets = require(ReplicatedStorage.Network.ReviewPackets)
local ReviewsUI = require(script.Parent.Parent.UserInterface.ReviewsUI)

local ReviewController = {}
local isInitialized = false

function ReviewController.Init()
	if isInitialized then
		return
	end
	isInitialized = true

	ReviewsUI.Init()

	ReviewPackets.NewReview.OnClientEvent:Connect(function(payload)
		ReviewsUI.AddLiveReview(payload.Review)
	end)
end

return ReviewController
