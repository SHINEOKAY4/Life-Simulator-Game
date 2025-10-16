--!strict
-- StarterPlayerScripts/Client/UserInterface/JobSelectionUI.lua

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer

local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local JobSelectionGui = PlayerGui:WaitForChild("JobSelectionGui")
local JobSelectionContext = JobSelectionGui:WaitForChild("JobSelectionContext")
local BlurEffect = Lighting:FindFirstChild("Blur")

local JobSelectionUI = {}

function JobSelectionUI.Init()
	-- Initialization code for the Job Selection UI goes here
	JobSelectionContext.Toggle.Pressed:Connect(function()
		if JobSelectionGui.Enabled then
			JobSelectionUI.Hide()
		else
			JobSelectionUI.Show()
		end
	end)
end

function JobSelectionUI.Show()
	JobSelectionGui.Enabled = true
	BlurEffect.Enabled = true
end

function JobSelectionUI.Hide()
	JobSelectionGui.Enabled = false
	BlurEffect.Enabled = false
end

return JobSelectionUI
