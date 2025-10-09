--!strict
-- StarterPlayerScripts/Client/Modules/NewResident.lua
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ResidentStore = require(script.Parent.Parent.ClientStores.ResidentsStore)

local AssetsFolder = ReplicatedStorage.Assets
local ResidentsTemplateFolder = AssetsFolder.Residents

local ResidentReplication = {}

local function OnResidentAdded(userId: number, residentData: any)
	print("New resident added for user:", userId, residentData)
	local player = Players:GetPlayerByUserId(userId)

	if not player then
		warn("Player not found for userId:", userId)
		return
	end

	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		warn("Player does not have a OwnedPlotIndex attribute:", player.Name)
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	local plotResidentsFolder = plotModel:FindFirstChild("Residents") :: Folder
	local spawnLocation = plotModel:FindFirstChild("Spawn") :: BasePart

	if residentData.Gender == "Male" then
		local maleTemplate = ResidentsTemplateFolder.Male:Clone() :: Model
		maleTemplate.Name = residentData.Name
		maleTemplate:PivotTo(spawnLocation.CFrame)
		maleTemplate.Parent = plotResidentsFolder
		maleTemplate:SetAttribute("OwnerUserId", userId)
		print("Male resident added:", maleTemplate.Name)
	else
		local femaleTemplate = ResidentsTemplateFolder.Female:Clone() :: Model
		femaleTemplate.Name = residentData.Name
		femaleTemplate:PivotTo(spawnLocation.CFrame)
		femaleTemplate.Parent = plotResidentsFolder
		femaleTemplate:SetAttribute("OwnerUserId", userId)
		print("Female resident added:", femaleTemplate.Name)
	end
end

local function OnResidentDeleted(userId: number, residentName: string)
	print("Resident deleted for user:", userId, "Resident Name:", residentName)
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		warn("Player not found for userId:", userId)
		return
	end

	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		warn("Player does not have a OwnedPlotIndex attribute:", player.Name)
		return
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	local plotResidentsFolder = plotModel:FindFirstChild("Residents") :: Folder

	local residentModel = plotResidentsFolder:FindFirstChild(residentName) :: Model
	if residentModel then
		residentModel:Destroy()
		print("Resident removed:", residentName)
	else
		warn("Resident not found:", residentName)
	end
end

local function OnResidentsUpdated(userId: number, residentData: any)
	print("Resident updated for user:", userId, residentData)
end

function ResidentReplication.Init()
	ResidentStore.ResidentAdded:Connect(OnResidentAdded)
	ResidentStore.ResidentRemoved:Connect(OnResidentDeleted)
	ResidentStore.ResidentsUpdated:Connect(OnResidentsUpdated)
end

return ResidentReplication
