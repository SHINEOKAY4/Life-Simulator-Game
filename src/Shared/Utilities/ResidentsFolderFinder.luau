--!strict
-- Unified utility to find the Residents folder in a player's plot
-- Eliminates duplicate logic across TenantService, ChoreService, and client controllers

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local ResidentsFolderFinder = {}

local FOLDER_NAME = "Residents"

-- Find the Residents folder for a player's plot (server or client)
-- Returns nil if player doesn't have a plot or folder doesn't exist
function ResidentsFolderFinder.FindFolder(playerOrUserId: Player | number): Folder?
	local plotIndex

	if typeof(playerOrUserId) == "number" then
		-- UserId passed directly (not common, but supported)
		return nil
	elseif typeof(playerOrUserId) == "Instance" and playerOrUserId:IsA("Player") then
		plotIndex = playerOrUserId:GetAttribute("OwnedPlotIndex")
	else
		return nil
	end

	if typeof(plotIndex) ~= "number" then
		return nil
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end

	local folder = plotModel:FindFirstChild(FOLDER_NAME)
	if folder and folder:IsA("Folder") then
		return folder
	end

	return nil
end

-- Find a specific resident/tenant model by name
function ResidentsFolderFinder.FindResident(player: Player, residentName: string): Model?
	local folder = ResidentsFolderFinder.FindFolder(player)
	if not folder then
		return nil
	end

	local instance = folder:FindFirstChild(residentName)
	if instance and instance:IsA("Model") then
		return instance
	end

	return nil
end

return ResidentsFolderFinder
