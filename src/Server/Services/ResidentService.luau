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

type ResidentData = ResidentState.ResidentData

local ResidentService = {}
local PlayersResidents: { [number]: any } = {} -- [userId] = {residentData}
local NameToIndexMap: { [number]: { [string]: number } } = {} -- [userId][name] = index

ResidentService.PlayerResidentsChanged = GoodSignal.new()

local Config = {
	MaxResidentsPerHousehold = 8,
}

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
	if typeof(save.MomentumExpireClock) ~= "number" then
		save.MomentumExpireClock = 0
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
		Age = residentData.Age or 0,
		Gender = residentData.Gender or "Unknown",
		Traits = residentData.Traits or { "Balanced" },
		Occupation = "Unemployed",
		CurrentCareerId = "",
		CareerStreak = 0,
		MomentumExpireClock = 0,
		Statistics = {
			Intelligence = 1,
			Discipline = 1,
			Creativity = 1,
			Fitness = 1,
		},
		Needs = {
			Hunger = 100,
			Energy = 100,
			Hygiene = 100,
			Fun = 100,
			Social = 100,
		},
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
return ResidentService
