--!strict

-- ServerScriptService/Server/Services/ResidentService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local ResidentState = require(ServerScriptService.Server.Classes.ResidentState)
local ResidentPlacer = require(ServerScriptService.Server.Utilities.ResidentPlacer)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentAppearanceConfig = require(ReplicatedStorage.Shared.Configurations.ResidentAppearanceConfig)

type ResidentData = ResidentState.ResidentData

local ResidentService = {}
local PlayersResidents: { [number]: any } = {} -- [userId] = {residentData}
local NameToIndexMap: { [number]: { [string]: number } } = {} -- [userId][name] = index

ResidentService.PlayerResidentsChanged = GoodSignal.new()

local Config = {
	MaxResidentsPerHousehold = 8,
}

local function sanitizeGender(rawValue: any): string
	local resolved = ResidentAppearanceConfig.ResolveGender(if typeof(rawValue) == "string" then rawValue else nil)
	return resolved.Id
end

local function resolveAgeNumeric(rawValue: any): number
	if typeof(rawValue) == "number" then
		for _, definition in ipairs(ResidentAppearanceConfig.AgeOptions) do
			if definition.Numeric == rawValue then
				return rawValue
			end
		end
	elseif typeof(rawValue) == "string" then
		local ageDefinition = ResidentAppearanceConfig.ResolveAge(rawValue)
		return ageDefinition.Numeric
	end
	local fallback = ResidentAppearanceConfig.ResolveAge(nil)
	return fallback.Numeric
end

local function sanitizeAppearance(rawAppearance: any): any
	local appearanceTable = if typeof(rawAppearance) == "table" then rawAppearance else nil
	local skinTone = ResidentAppearanceConfig.ResolveSkinTone(appearanceTable and appearanceTable.SkinToneId)
	local hair = ResidentAppearanceConfig.ResolveHair(appearanceTable and appearanceTable.HairId)
	local face = ResidentAppearanceConfig.ResolveFace(appearanceTable and appearanceTable.FaceId)
	local top = ResidentAppearanceConfig.ResolveTop(appearanceTable and appearanceTable.TopId)
	local pants = ResidentAppearanceConfig.ResolvePants(appearanceTable and appearanceTable.PantsId)

	return {
		SkinToneId = skinTone.Id,
		HairId = hair.Id,
		FaceId = face.Id,
		TopId = top.Id,
		PantsId = pants.Id,
	}
end

local function ensureAppearance(residentSave: any)
	if typeof(residentSave) ~= "table" then
		return
	end
	residentSave.Appearance = sanitizeAppearance(residentSave.Appearance)
	residentSave.Age = resolveAgeNumeric(residentSave.Age)
	residentSave.Gender = sanitizeGender(residentSave.Gender)
end

local function cloneTable(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = table.clone(value)
	for key, item in value do
		copy[key] = cloneTable(item)
	end
	return copy
end

local function ensureHouseholdState(player: Player, data: any?)
	if data == nil then
		warn(string.format("[ResidentService] Household data unavailable for %s", player.Name))
		return nil
	end

	data.Residents = data.Residents or {}
	data.ResidentsCount = data.ResidentsCount or #data.Residents
	data.MaxResidents = data.MaxResidents or Config.MaxResidentsPerHousehold

	return data
end

local function ensureResidentCareerState(save: any)
	if typeof(save) ~= "table" then
		return
	end
	if typeof(save.Occupation) ~= "string" or save.Occupation == "" then
		save.Occupation = "Unemployed"
	end
	if typeof(save.CurrentCareerId) ~= "string" then
		save.CurrentCareerId = if save.Occupation ~= "Unemployed" then save.Occupation else ""
	end
	if typeof(save.CareerStreak) ~= "number" then
		save.CareerStreak = 0
	end
	if typeof(save.AssignedShiftId) ~= "string" then
		save.AssignedShiftId = ""
	end
end

local function prepareResidentForRemoval(residentState, timeoutSeconds: number?): (boolean, string?)
	if not residentState then
		return false, "Resident state missing"
	end

	local autoActions = residentState.AutoActionsEnabled
	local autoJob = residentState.AutoJobEnabled
	residentState:DisableAutomation()
	residentState:ClearManualOverrideState()
	residentState:CancelCurrentAction("DeleteResident")

	local idle = residentState:WaitUntilIdle(timeoutSeconds)
	if not idle then
		residentState:SetAutoActionEnabled(autoActions)
		residentState:SetAutoJobEnabled(autoJob)
		residentState:ResetCancelToken()
		return false, "Resident is busy"
	end

	residentState:ClearQueuedActions()
	residentState:ResetCancelToken()
	return true, nil
end

function ResidentService.Init()
	PlotService.PlotClaimed:Connect(function(player, _playerState)
		ResidentService.Load(player)
	end)

	ResidentsPackets.AddResidentRequest.OnServerInvoke = function(player: Player, residentData: any)
		local success, message = ResidentService.CreateResident(player, residentData)
		return success, message
	end

	ResidentsPackets.DeleteResidentRequest.OnServerInvoke = function(player: Player, residentName: string)
		local success, message = ResidentService.DeleteResident(player, residentName)
		return success, message
	end
end

function ResidentService.Load(player: Player)
	local data = ensureHouseholdState(player, PlayerSession.GetDataAwait(player, "HouseholdState"))
	if not data then
		return
	end
	local userId = player.UserId

	if data.ResidentsCount == 0 then
		ResidentsPackets.PromptResidentCreation:FireClient(player)
	end

	-- Build a keyed map and index map for easier access
	PlayersResidents[userId] = {}
	NameToIndexMap[userId] = {}

	local filteredResidents = {}
	local residentsMap = PlayersResidents[userId]
	local indexMap = NameToIndexMap[userId]

	for _, resident in ipairs(data.Residents) do
		if typeof(resident) == "table" and type(resident.Name) == "string" then
			ensureResidentCareerState(resident)
			ensureAppearance(resident)
			local count = #filteredResidents + 1
			filteredResidents[count] = resident
			local residentName = resident.Name
			local residentState = ResidentState.new(resident)
			residentsMap[residentName] = residentState
			indexMap[residentName] = count
			ResidentPlacer.Spawn(player, residentState)
		else
			warn("[ResidentService] Skipping invalid resident entry during load")
		end
	end

	data.Residents = filteredResidents
	data.ResidentsCount = #filteredResidents

	local payload = {
		UserId = userId,
		Residents = filteredResidents,
	}

	ResidentService.PlayerResidentsChanged:Fire(player)
	ResidentsPackets.PlayersResidentsSync:Fire(payload)
end

function ResidentService.CreateResident(player: Player, residentData: ResidentData)
	local data = ensureHouseholdState(player, PlayerSession.GetDataAwait(player, "HouseholdState"))
	if not data then
		return false, "Household data not available. Please try again."
	end

	PlayersResidents[player.UserId] = PlayersResidents[player.UserId] or {}
	NameToIndexMap[player.UserId] = NameToIndexMap[player.UserId] or {}

	local maxGlobalResidentsPerHousehold = Config.MaxResidentsPerHousehold
	data.MaxResidents =
		math.clamp(data.MaxResidents or maxGlobalResidentsPerHousehold, 1, maxGlobalResidentsPerHousehold)
	if data.ResidentsCount + 1 > data.MaxResidents then
		return false, "Maximum number of residents reached."
	end
	-- Basic validation
	if typeof(residentData) ~= "table" then
		return false, "Invalid data format."
	end

	if type(residentData.Name) ~= "string" or residentData.Name == "" then
		return false, "Invalid name."
	end

	if data.Residents then
		for _, resident in ipairs(data.Residents) do
			if resident.Name == residentData.Name then
				return false, "Resident with this name already exists."
			end
		end
	end

	local newResidentData = {
		Name = residentData.Name,
		Age = resolveAgeNumeric(residentData.Age),
		Gender = sanitizeGender(residentData.Gender),
		Traits = residentData.Traits or { "Balanced" },
		Occupation = "Unemployed",
		CurrentCareerId = "",
		CareerStreak = 0,
		AssignedShiftId = "",
		Statistics = {
			Intelligence = 1,
			Discipline = 1,
			Creativity = 1,
			Fitness = 1,
		},
		Needs = {
			Hunger = 100,
			Bladder = 100,
			Energy = 100,
			Hygiene = 100,
			Fun = 100,
			Social = 100,
		},
		Appearance = sanitizeAppearance(residentData.Appearance),
	}

	ensureResidentCareerState(newResidentData)

	local payload = {
		UserId = player.UserId,
		ResidentName = newResidentData.Name,
		ResidentDelta = { newResidentData },
	}
	-- Add the new resident
	local newIndex = #data.Residents + 1
	data.Residents[newIndex] = newResidentData
	data.ResidentsCount = newIndex
	local residentState = ResidentState.new(newResidentData)
	local residentName = newResidentData.Name
	PlayersResidents[player.UserId][residentName] = residentState
	NameToIndexMap[player.UserId][residentName] = newIndex

	ResidentPlacer.Spawn(player, residentState)
	ResidentService.PlayerResidentsChanged:Fire(player)
	ResidentsPackets.PlayerResidentDelta:Fire(payload)
	return true, "Resident created successfully."
end

function ResidentService.DeleteResident(player: Player, residentName: string)
	local data = ensureHouseholdState(player, PlayerSession.GetDataAwait(player, "HouseholdState"))
	if not data then
		return false, "Household data not available. Please try again."
	end
	local userId = player.UserId
	local residentMap = PlayersResidents[userId]
	if not residentMap then
		return false, "Residents not loaded yet."
	end

	local indexMap = NameToIndexMap[userId]
	if not indexMap then
		return false, "Residents not loaded yet."
	end

	local resident = residentMap[residentName]

	if not resident then
		return false, "Resident not found."
	end

	local index = indexMap[residentName]
	if not index then
		return false, "Resident index not found."
	end

	local prepared, reason = prepareResidentForRemoval(resident, 4)
	if not prepared then
		return false, reason or "Resident is busy"
	end
	table.remove(data.Residents, index)

	residentMap[residentName] = nil

	-- Rebuild the index map
	NameToIndexMap[userId] = {}
	for idx, res in ipairs(data.Residents) do
		NameToIndexMap[userId][res.Name] = idx
	end

	data.ResidentsCount = math.max(0, #data.Residents)
	local payload = {
		UserId = userId,
		ResidentName = residentName,
		ResidentDelta = {},
	}

	ResidentPlacer.Despawn(resident)
	resident:Destroy()
	ResidentService.PlayerResidentsChanged:Fire(player)
	ResidentsPackets.PlayerResidentDelta:Fire(payload)
	return true, "Resident deleted successfully."
end

function ResidentService.Unload(player: Player)
	local userId = player.UserId
	for _, resident in pairs(PlayersResidents[userId] or {}) do
		ResidentPlacer.Despawn(resident)
		resident:Destroy()
	end
	PlayersResidents[userId] = nil
	NameToIndexMap[userId] = nil
end

function ResidentService.GetResidents(player: Player?)
	if player and player:IsA("Player") then
		return PlayersResidents[player.UserId]
	end
	if not player then
		return PlayersResidents
	end
	return nil
end

function ResidentService.GetResident(player: Player, residentName: string)
	local residents = PlayersResidents[player.UserId]
	if not residents then
		return nil
	end
	return residents[residentName]
end

function ResidentService.DispatchResidentUpdate(player: Player, residentState: any)
	if residentState == nil then
		return
	end
	local save = residentState.Save
	if typeof(save) ~= "table" then
		return
	end
	ensureAppearance(save)
	ensureResidentCareerState(save)
	local residentName = save.Name
	if type(residentName) ~= "string" or residentName == "" then
		return
	end
	local payload = {
		UserId = player.UserId,
		ResidentName = residentName,
		ResidentDelta = { cloneTable(save) },
	}
	ResidentsPackets.PlayerResidentDelta:Fire(payload)
end
return ResidentService
