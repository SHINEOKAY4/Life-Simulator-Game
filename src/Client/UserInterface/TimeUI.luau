--!strict
-- StarterPlayerScripts/Client/UserInterface/TimeUI.lua

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ClockGui = PlayerGui:WaitForChild("Clock") :: ScreenGui
local Frame = ClockGui:WaitForChild("Frame") :: Frame

local TextLabel = Frame:WaitForChild("TextLabel") :: TextLabel

local LastProcessedMinutes: string? = nil

local TimeUI = {}

function TimeUI.Init()
	Lighting:GetPropertyChangedSignal("TimeOfDay"):Connect(function()
		local rawHours, rawMinutes = Lighting.TimeOfDay:match("(%d+):(%d+)")
		if rawHours == nil or rawMinutes == nil then
			return
		end
		if LastProcessedMinutes == rawMinutes then
			return
		end

		local hoursNumber = tonumber(rawHours)
		local minutesNumber = tonumber(rawMinutes)
		if hoursNumber == nil or minutesNumber == nil then
			return
		end

		LastProcessedMinutes = rawMinutes
		local period = "AM"
		if hoursNumber >= 12 then
			period = "PM"
			if hoursNumber > 12 then
				hoursNumber = hoursNumber - 12
			end
		elseif hoursNumber == 0 then
			hoursNumber = 12
		end

		local formattedTime = string.format("%2d:%02d %s", hoursNumber, minutesNumber, period)
		TextLabel.Text = formattedTime
	end)
end

return TimeUI
