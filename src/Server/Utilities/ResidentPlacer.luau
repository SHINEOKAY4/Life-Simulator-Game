--!strict
-- ServerScriptService/Server/Utilities/ResidentPlacer.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ResidentAppearanceUtils = require(ReplicatedStorage.Shared.Utilities.ResidentAppearanceUtils)

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
	AssignedShiftId: string?,
	Appearance: {
		SkinToneId: string,
		HairId: string,
		FaceId: string,
		TopId: string,
		PantsId: string,
	},
}

local ResidentPlacer = {}

local hiddenFolder: Folder?
local assetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local residentsTemplateFolder = assetsFolder and assetsFolder:FindFirstChild("Residents")

local function ensurePlotResidentsFolder(plotModel: Model?): Folder?
	if not plotModel then
		return nil
	end

	local existing = plotModel:FindFirstChild("Residents")
	if existing and existing:IsA("Folder") then
		return existing
	end

	local residentsFolder = Instance.new("Folder")
	residentsFolder.Name = "Residents"
	residentsFolder.Parent = plotModel
	return residentsFolder
end

local function resolveSpawnCFrame(plotModel: Model?): CFrame?
	if not plotModel then
		return nil
	end

	local spawnBase = plotModel:FindFirstChild("Spawn")
	if spawnBase and spawnBase:IsA("BasePart") then
		return spawnBase.CFrame
	end

	local surface = plotModel:FindFirstChild("Surface")
	if surface and surface:IsA("BasePart") then
		local up = surface.CFrame.UpVector
		local look = surface.CFrame.LookVector
		local height = surface.Size.Y * 0.5
		local origin = surface.CFrame.Position + up * (height + 3)
		return CFrame.lookAt(origin, origin + look)
	end

	return nil
end

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

local function ensureResidentModel(residentState: any): Model?
	local existing = residentState.Model
	if existing and existing.Parent then
		return existing
	end

	if not assetsFolder then
		warn("ResidentPlacer: missing Assets folder in ReplicatedStorage")
		return existing
	end
	local residentsFolder = residentsTemplateFolder or assetsFolder:FindFirstChild("Residents")
	if not residentsFolder then
		warn("ResidentPlacer: missing Residents folder in Assets")
		return existing
	end
	local gender = residentState.Save.Gender
	local template = gender and residentsFolder:FindFirstChild(gender)
	if not template or not template:IsA("Model") then
		warn("ResidentPlacer: missing template for resident", residentState.Save and residentState.Save.Name)
		return existing
	end
	local model = template:Clone()
	model.Parent = getHiddenFolder()
	residentState.Model = model
	return model
end

local function loadResidentAppearance(residentState: any): Model?
	local model = ensureResidentModel(residentState)
	if not model then
		return nil
	end
	model.Name = residentState.Save.Name

	local needs = hydrateNeeds(residentState.Save)
	for needName, value in pairs(needs) do
		model:SetAttribute(needName, value)
	end

	residentState:SyncCurrentActionAttribute()
	local appearanceData = residentState.Save.Appearance
	if typeof(appearanceData) == "table" then
		ResidentAppearanceUtils.ApplyToModel(model, appearanceData, residentState.Save.Age)
	end
	return model
end
function ResidentPlacer.Spawn(player, residentState)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		warn("Player does not have a OwnedPlotIndex attribute:", player.Name)
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		warn("ResidentPlacer: no plot model for index", plotIndex, "player", player.Name)
		return
	end

	local plotResidentsFolder = ensurePlotResidentsFolder(plotModel)
	local spawnCFrame = resolveSpawnCFrame(plotModel)

	local loadedResidentModel = loadResidentAppearance(residentState)
	if not loadedResidentModel then
		return
	end

	local humanoidRootPart = loadedResidentModel:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoidRootPart then
		warn("Resident model is missing HumanoidRootPart:", residentState.Save and residentState.Save.Name)
		return
	end

	if not spawnCFrame then
		warn(
			"ResidentPlacer: missing spawn reference for plot",
			plotIndex,
			"resident",
			residentState.Save and residentState.Save.Name
		)
		loadedResidentModel.Parent = getHiddenFolder()
		return
	end

	loadedResidentModel:PivotTo(spawnCFrame)
	if plotResidentsFolder then
		loadedResidentModel.Parent = plotResidentsFolder
	else
		loadedResidentModel.Parent = getHiddenFolder()
	end

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
