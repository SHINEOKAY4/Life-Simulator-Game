--!strict
-- ServerScriptService/Server/Utilities/ResidentPlacer.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local ResidentPlacer = {}

function ResidentPlacer.Spawn(player, residentState)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		warn("Player does not have a OwnedPlotIndex attribute:", player.Name)
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	local plotResidentsFolder = plotModel:FindFirstChild("Residents") :: Folder
	local spawnLocation = plotModel:FindFirstChild("Spawn") :: BasePart
	local residentModel = residentState.Model :: Model

	residentModel:PivotTo(spawnLocation.CFrame)
	residentModel.Parent = plotResidentsFolder
end

function ResidentPlacer.Despawn(residentState) -- Only moves parent to nil, does not destroy
	residentState.Model.Parent = nil
end

function ResidentPlacer.DespawnAll(allResidents) -- allResidents: {ResidentState}
	for _, resident in pairs(allResidents) do
		ResidentPlacer.Despawn(resident)
	end
end

return ResidentPlacer
