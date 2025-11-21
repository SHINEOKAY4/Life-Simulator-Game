--!strict
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local ThermostatUI = require(script.Parent.Parent.UserInterface.ThermostatUI)
local MinimalPromptUI = require(script.Parent.MinimalPromptUI)
local Packets = require(ReplicatedStorage.Network.TemperaturePackets)

local ThermostatInteractionController = {}

function ThermostatInteractionController.Init()
	local function onPromptAdded(prompt: ProximityPrompt)
		MinimalPromptUI.Attach(prompt)
	end

	CollectionService:GetInstanceAddedSignal("ThermostatPrompt"):Connect(onPromptAdded)
	for _, prompt in ipairs(CollectionService:GetTagged("ThermostatPrompt")) do
		if prompt:IsA("ProximityPrompt") then
			onPromptAdded(prompt)
		end
	end

	ProximityPromptService.PromptTriggered:Connect(function(prompt, player)
		if player ~= Players.LocalPlayer then
			return
		end

		local model = prompt.Parent
		if not model then
			return
		end
		if model:IsA("BasePart") then
			model = model.Parent
		end
		if not model or not model:IsA("Model") then
			return
		end

		local itemId = model:GetAttribute("ItemId")
		if itemId ~= "Thermostat" then
			return
		end

		local cellX = model:GetAttribute("CellX")
		local cellZ = model:GetAttribute("CellZ")
		local level = model:GetAttribute("Level")

		if not cellX or not cellZ or not level then
			return
		end

		local currentTarget = model:GetAttribute("TargetTemp") or 22

		-- Fetch room details from server
		local success, details = pcall(function()
			return Packets.GetRoomDetails:Fire({
				X = cellX,
				Z = cellZ,
				Level = level,
			})
		end)

		local minAchievable = 15
		local maxAchievable = 30

		if success and details then
			minAchievable = details.MinTemp
			maxAchievable = details.MaxTemp
		end

		ThermostatUI.Mount({
			InitialTemp = currentTarget,
			MinAchievable = minAchievable,
			MaxAchievable = maxAchievable,
			OnChanged = function(newTemp)
				Packets.SetTargetTemp:Fire({
					X = cellX,
					Z = cellZ,
					Level = level,
					TargetTemp = newTemp,
				})
			end,
			OnClose = function()
				-- Optional: Play sound
			end,
		})
	end)
end

return ThermostatInteractionController
