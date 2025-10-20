--!strict
-- ServerScriptService/Server/Utilities/ResidentPlacer.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local ResidentPlacer = {}

local hiddenFolder: Folder?

local function getHiddenFolder(): Folder
	if hiddenFolder and hiddenFolder.Parent then
		return hiddenFolder
	end
	local container = ReplicatedStorage:FindFirstChild("ResidentOffsite")
	if not container or not container:IsA("Folder") then
		container = Instance.new("Folder")
		container.Name = "ResidentOffsite"
		container.Parent = ReplicatedStorage
	end
	hiddenFolder = container
	return container
end

function ResidentPlacer.Spawn(player, residentState)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		warn("Player does not have a OwnedPlotIndex attribute:", player.Name)
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	local humanoidRootPart = residentState.Model:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoidRootPart then
		warn("Resident model is missing HumanoidRootPart:", residentState.Name)
		return
	end
	local plotResidentsFolder = plotModel:FindFirstChild("Residents") :: Folder
	local spawnLocation = plotModel:FindFirstChild("Spawn") :: BasePart
	local residentModel = residentState.Model :: Model

	residentModel:PivotTo(spawnLocation.CFrame)
	residentModel.Parent = plotResidentsFolder

	humanoidRootPart:SetNetworkOwner(nil)
end

function ResidentPlacer.Despawn(residentState) -- Only moves parent to nil, does not destroy
	local model = residentState.Model
	if not model then
		return
	end
	model.Parent = getHiddenFolder()
end

function ResidentPlacer.DespawnAll(allResidents) -- allResidents: {ResidentState}
	for _, resident in pairs(allResidents) do
		ResidentPlacer.Despawn(resident)
	end
end

return ResidentPlacer
