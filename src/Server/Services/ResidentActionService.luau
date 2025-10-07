--!strict
-- ServerScriptService/Services/ResidentActionService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local ResidentBehavior = require(ServerScriptService.Server.Utilities.ResidentBehavior)

local ResidentActionService = {}

ResidentActionService.Actions = {
	Eat = "Eat",
	Sleep = "Sleep",
	Rest = "Rest",
	Socialize = "Socialize",
	Exercise = "Exercise",
	Idle = "Idle",
}

--#TODO: Solve occupancy checks for residents, caching stations would be necessary
function ResidentActionService.Init()
	ResidentBehavior.DestinationReached:Connect(function(player: Player, residentName: string, stationName: string)
		print(("Resident '%s' of player '%s' has reached station '%s'"):format(residentName, player.Name, stationName))
		-- Here you can handle what happens when a resident reaches their destination
		-- For example, start an activity, update state, etc.
		local stationSpec = ItemFinder.FindItemById(stationName)
		if stationSpec and stationSpec.ActionType and ResidentActionService.Actions[stationSpec.ActionType] then
			local action = stationSpec.ActionType
			if action == "Eat" then
				ResidentActionService.Eat(player, residentName, "Sample Meal") -- Replace "Sample Meal" with actual meal data
			elseif action == "Sleep" then
				ResidentActionService.Sleep(player, residentName, 60) -- Sleep for 60 minutes as an example
			elseif action == "Rest" then
				ResidentActionService.Rest(player, residentName, 30) -- Rest for 30 minutes as an example
			elseif action == "Socialize" then
				ResidentActionService.Socialize(player, residentName) -- Replace with actual resident name
			elseif action == "Exercise" then
				ResidentActionService.Exercise(player, residentName, "Jogging") -- Replace with actual exercise type
			elseif action == "Idle" then
				ResidentActionService.Idle(player, residentName, 15) -- Idle for 15 minutes as an example
			end
		else
			warn(("[ResidentActionService] No valid action found for station '%s'"):format(stationName))
		end
	end)
end

function ResidentActionService.Eat(player: Player, residentName: string, mealName: string)
	print(("Resident '%s' of player '%s' is eating meal '%s'"):format(residentName, player.Name, mealName))
	-- Implement eating logic here
end

function ResidentActionService.Sleep(player: Player, residentName: string, duration: number)
	print(("Resident '%s' of player '%s' is sleeping for %d minutes"):format(residentName, player.Name, duration))
	-- Implement sleeping logic here
end

function ResidentActionService.Rest(player: Player, residentName: string, duration: number)
	print(("Resident '%s' of player '%s' is resting for %d minutes"):format(residentName, player.Name, duration))
	-- Implement resting logic here
end

function ResidentActionService.Socialize(player: Player, residentName: string)
	print(("Resident '%s' of player '%s' is trying to socialize"):format(residentName, player.Name))

	-- Implement a check if another resident is socializing in the same area
	-- Implement socializing logic here
end

function ResidentActionService.Exercise(player: Player, residentName: string, exerciseType: string)
	print(("Resident '%s' of player '%s' is exercising with type '%s'"):format(residentName, player.Name, exerciseType))
	-- Implement exercising logic here
end

function ResidentActionService.Idle(player: Player, residentName: string, duration: number)
	print(("Resident '%s' of player '%s' is idling for %d minutes"):format(residentName, player.Name, duration))
	-- Implement idling logic here
end

function ResidentActionService.GoToStation(player: Player, residentName: string, stationName: string)
	print(
		("Requesting resident '%s' of player '%s' to go to station '%s'"):format(residentName, player.Name, stationName)
	)
	ResidentBehavior.MoveToStation(player, residentName, stationName)
end

return ResidentActionService
