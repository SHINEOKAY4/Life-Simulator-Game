--!strict
-- StarterPlayerScripts/Client/Modules/ResidentController.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local ResidentController = {}

function ResidentController.Init()
	-- Initialization code for ResidentController goes here
end

function ResidentController.RequestMoveToLocation(residentModel: Model, targetPosition: Vector3)
	if not residentModel or not targetPosition then
		return false, "Invalid move request"
	end

	local residentName = residentModel.Name
	local ok, success, message = pcall(function()
		return ResidentsPackets.RequestResidentMove:Fire(residentName, targetPosition)
	end)

	if not ok then
		warn("ResidentController.RequestMoveToLocation failed:", success)
		return false, "Failed to send move request"
	end

	if not success then
		warn(("Move request rejected for %s: %s"):format(residentName, message))
	end

	return success, message
end

function ResidentController.RequestResidentToStation(residentName: string, stationName: string)
	if not residentName or not stationName then
		return false, "Invalid station request"
	end

	local success, message = ResidentsPackets.RequestAssignStation:Fire(residentName, stationName)
	if not success then
		warn(("Station request rejected for %s: %s"):format(residentName, message))
	end

	return success, message
end
return ResidentController
