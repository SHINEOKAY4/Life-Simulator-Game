--!strict
-- Client/Modules/ClientResidentPlacer.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

export type ResidentData = {
	Name: string,
	Traits: { string },
	TenantId: string?,
}

local ClientResidentPlacer = {}

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

local function ensureResidentModel(residentName: string): Model?
	if not assetsFolder then
		warn("ClientResidentPlacer: missing Assets folder in ReplicatedStorage")
		return nil
	end
	local residentsFolder = residentsTemplateFolder or assetsFolder:FindFirstChild("Residents")
	if not residentsFolder then
		warn("ClientResidentPlacer: missing Residents folder in Assets")
		return nil
	end

	local template: Model? = nil
	local candidates = {}
	for _, child in ipairs(residentsFolder:GetChildren()) do
		if child:IsA("Model") then
			table.insert(candidates, child)
		end
	end

	if #candidates > 0 then
		local rng = Random.new()
		template = candidates[rng:NextInteger(1, #candidates)]
	end

	if not template then
		warn("ClientResidentPlacer: missing resident template for", residentName)
		return nil
	end
	local model = template:Clone()
	model.Name = residentName
	return model
end

local function applyResidentAttributes(model: Model, residentData: ResidentData)
	if typeof(residentData.Name) == "string" and residentData.Name ~= "" then
		model:SetAttribute("ResidentName", residentData.Name)
	end

	local tenantIdValue = residentData.TenantId
	if type(tenantIdValue) == "string" and tenantIdValue ~= "" then
		model:SetAttribute("TenantId", tenantIdValue)
	else
		model:SetAttribute("TenantId", nil)
	end
end

function ClientResidentPlacer.Spawn(userId: number, residentData: ResidentData, spawnOverride: CFrame?): Model?
	local player = Players:GetPlayerByUserId(userId)
	if not player then
		-- Player might not be streamed in or available, but we can try to find plot by other means if needed.
		-- For now, rely on player presence.
		return nil
	end

	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	if not plotIndex then
		return nil
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end

	local plotResidentsFolder = ensurePlotResidentsFolder(plotModel)
	local spawnCFrame = spawnOverride or resolveSpawnCFrame(plotModel)

	local model = ensureResidentModel(residentData.Name)
	if not model then
		return nil
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoidRootPart then
		model:Destroy()
		return nil
	end

	if spawnCFrame then
		model:PivotTo(spawnCFrame)
	end

	applyResidentAttributes(model, residentData)
	model.Parent = plotResidentsFolder

	return model
end

function ClientResidentPlacer.Despawn(model: Model?)
	if model then
		model:Destroy()
	end
end

return ClientResidentPlacer
