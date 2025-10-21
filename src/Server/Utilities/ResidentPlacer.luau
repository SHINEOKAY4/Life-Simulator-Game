--!strict
-- ServerScriptService/Server/Utilities/ResidentPlacer.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

export type ResidentData = {
	Name: string,
	Age: number,
	Gender: string,
	Needs: { [string]: number },
	Traits: { string },
	Occupation: string,
	Statistics: { [string]: number }?,
	CurrentCareerId: string?,
	CareerStreak: number?,
	MomentumExpireClock: number?,
}

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

local function hydrateNeeds(save: ResidentData)
	local needs = save.Needs
	if typeof(needs) ~= "table" then
		needs = {}
		save.Needs = needs
	end

	for needName, definition in pairs(NeedConfig.Needs) do
		local value = needs[needName]
		if typeof(value) ~= "number" then
			needs[needName] = definition.Max
		else
			needs[needName] = math.clamp(value, definition.Min, definition.Max)
		end
	end

	return needs
end

local function LoadResidentAppearance(residentState: any)
	local AssetsFolder = ReplicatedStorage.Assets
	local ResidentsTemplateFolder = AssetsFolder.Residents
	local needs = hydrateNeeds(residentState.Save)
	local ResidentOffsite = getHiddenFolder()
	local model = ResidentsTemplateFolder:FindFirstChild(residentState.Save.Gender):Clone() :: Model
	model.Name = residentState.Save.Name
	model.Parent = ResidentOffsite

	--#TODO Future stub for handling resident clothes, accessories for character appearance
	-- After appearance is set we can clone the model for other systems to use like viewport

	----========----
	for needName, value in pairs(needs) do
		model:SetAttribute(needName, value)
	end
	residentState.Model = model
	return model
end
function ResidentPlacer.Spawn(player, residentState)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		warn("Player does not have a OwnedPlotIndex attribute:", player.Name)
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	local plotResidentsFolder = plotModel:FindFirstChild("Residents") :: Folder
	local spawnLocation = plotModel:FindFirstChild("Spawn") :: BasePart

	local loadedResidentModel = LoadResidentAppearance(residentState)

	local humanoidRootPart = loadedResidentModel:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoidRootPart then
		warn("Resident model is missing HumanoidRootPart:", residentState.Name)
		return
	end

	loadedResidentModel:PivotTo(spawnLocation.CFrame)
	loadedResidentModel.Parent = plotResidentsFolder

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
