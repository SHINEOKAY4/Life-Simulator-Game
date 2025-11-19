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
local TenantToResidentMap: { [number]: { [string]: string } } = {} -- [userId][tenantId] = residentName
local ResidentToTenantMap: { [number]: { [string]: string } } = {} -- [userId][residentName] = tenantId

ResidentService.PlayerResidentsChanged = GoodSignal.new()

local Config = {
	MaxResidentsPerHousehold = 8,
}

local function ensureTenantMaps(userId: number)
	if not TenantToResidentMap[userId] then
		TenantToResidentMap[userId] = {}
	end
	if not ResidentToTenantMap[userId] then
		ResidentToTenantMap[userId] = {}
	end
end

local function setTenantLinkInternal(userId: number, residentName: string, tenantId: string?)
	ensureTenantMaps(userId)
	local tenantMap = TenantToResidentMap[userId]
	local residentMap = ResidentToTenantMap[userId]

	local previousTenant = residentMap[residentName]
	if previousTenant and tenantMap then
		tenantMap[previousTenant] = nil
	end
	residentMap[residentName] = nil

	if tenantId and tenantId ~= "" then
		local previousResident = tenantMap[tenantId]
		if previousResident then
			residentMap[previousResident] = nil
		end
		tenantMap[tenantId] = residentName
		residentMap[residentName] = tenantId
	end
end

local function clearTenantLinkByTenant(userId: number, tenantId: string)
	local tenantMap = TenantToResidentMap[userId]
	local residentMap = ResidentToTenantMap[userId]
	if not tenantMap then
		return
	end
	local residentName = tenantMap[tenantId]
	tenantMap[tenantId] = nil
	if residentName and residentMap then
		residentMap[residentName] = nil
	end
end

local function clearTenantLinkByResident(userId: number, residentName: string)
	local residentMap = ResidentToTenantMap[userId]
	local tenantMap = TenantToResidentMap[userId]
	if not residentMap then
		return
	end
	local tenantId = residentMap[residentName]
	residentMap[residentName] = nil
	if tenantId and tenantMap then
		tenantMap[tenantId] = nil
	end
end

local function stripAppearance(residentSave: any)
	if typeof(residentSave) ~= "table" then
		return
	end
	residentSave.Appearance = nil
	residentSave.Age = nil
	residentSave.Gender = nil
	residentSave.Statistics = nil
end

local function stripCareerData(residentSave: any)
	if typeof(residentSave) ~= "table" then
		return
	end
	residentSave.Occupation = nil
	residentSave.CurrentCareerId = nil
	residentSave.CareerStreak = nil
	residentSave.AssignedShiftId = nil
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

local function resolveTenantTransmissionId(rawValue: any): string
	if type(rawValue) == "string" then
		return rawValue
	end
	return ""
end

local function cloneResidentForNetwork(residentData: any): any?
	if typeof(residentData) ~= "table" then
		return nil
	end
	local copy = cloneTable(residentData)
	copy.TenantId = resolveTenantTransmissionId(copy.TenantId)
	return copy
end

local function buildNetworkResidentList(residents: { any }): { any }
	local payload = table.create(#residents)
	for index, resident in ipairs(residents) do
		local clone = cloneResidentForNetwork(resident)
		if clone then
			payload[index] = clone
		end
	end
	return payload
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

	data.Residents = data.Residents or {}
	data.ResidentsCount = math.max(#data.Residents, 0)

	-- Build a keyed map and index map for easier access
	PlayersResidents[userId] = {}
	NameToIndexMap[userId] = {}

	local incomingResidents = data.Residents or {}
	local filteredResidents = {}
	local residentsMap = PlayersResidents[userId]
	local indexMap = NameToIndexMap[userId]
	local seenNames: { [string]: boolean } = {}

	local function ingestResident(entry: any, sourceKey: any)
		if typeof(entry) ~= "table" then
			warn("[ResidentService] Skipping non-table resident entry during load")
			return
		end

		local residentName = entry.Name
		if type(residentName) ~= "string" or residentName == "" then
			if type(sourceKey) == "string" and sourceKey ~= "" then
				residentName = sourceKey
				entry.Name = sourceKey
			else
				warn("[ResidentService] Skipping resident with missing name during load")
				return
			end
		end

		if seenNames[residentName] then
			return
		end
		seenNames[residentName] = true

		stripCareerData(entry)
		stripAppearance(entry)

		local newIndex = #filteredResidents + 1
		filteredResidents[newIndex] = entry

		local residentState = ResidentState.new(entry)
		residentsMap[residentName] = residentState
		indexMap[residentName] = newIndex

		local tenantId = if type(entry.TenantId) == "string" then entry.TenantId else nil
		if tenantId then
			setTenantLinkInternal(userId, residentName, tenantId)
		else
			setTenantLinkInternal(userId, residentName, nil)
		end

		ResidentPlacer.Spawn(player, residentState)
	end

	local arrayLength = #incomingResidents
	for idx = 1, arrayLength do
		ingestResident(incomingResidents[idx], idx)
	end

	for key, resident in pairs(incomingResidents) do
		if typeof(key) ~= "number" or key < 1 or key > arrayLength then
			ingestResident(resident, key)
		end
	end

	data.Residents = filteredResidents
	data.ResidentsCount = #filteredResidents

	local payload = {
		UserId = userId,
		Residents = buildNetworkResidentList(filteredResidents),
	}

	ResidentService.PlayerResidentsChanged:Fire(player)
	ResidentsPackets.PlayersResidentsSync:Fire(payload)
end

function ResidentService.CreateResident(player: Player, residentData: ResidentData, spawnOverride: CFrame?)
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
		Traits = residentData.Traits or { "Balanced" },
		Needs = {
			Hunger = 100,
			Bladder = 100,
			Energy = 100,
			Hygiene = 100,
			Fun = 100,
			Social = 100,
		},
	}

	stripCareerData(newResidentData)
	stripAppearance(newResidentData)

	local newResidentClone = cloneResidentForNetwork(newResidentData)
	local payload = {
		UserId = player.UserId,
		ResidentName = newResidentData.Name,
		ResidentDelta = newResidentClone and { newResidentClone } or {},
	}
	-- Add the new resident
	local newIndex = #data.Residents + 1
	data.Residents[newIndex] = newResidentData
	data.ResidentsCount = newIndex
	local residentState = ResidentState.new(newResidentData)
	local residentName = newResidentData.Name
	PlayersResidents[player.UserId][residentName] = residentState
	NameToIndexMap[player.UserId][residentName] = newIndex

	ResidentPlacer.Spawn(player, residentState, spawnOverride)
	setTenantLinkInternal(player.UserId, residentName, nil)
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
	clearTenantLinkByResident(userId, residentName)
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
	TenantToResidentMap[userId] = nil
	ResidentToTenantMap[userId] = nil
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
	stripAppearance(save)
	stripCareerData(save)
	local residentName = save.Name
	if type(residentName) ~= "string" or residentName == "" then
		return
	end
	local saveClone = cloneResidentForNetwork(save)
	local payload = {
		UserId = player.UserId,
		ResidentName = residentName,
		ResidentDelta = saveClone and { saveClone } or {},
	}
	ResidentsPackets.PlayerResidentDelta:Fire(payload)
end

function ResidentService.SetResidentTenantData(player: Player, residentName: string, tenantId: string?)
	local data = ensureHouseholdState(player, PlayerSession.GetDataAwait(player, "HouseholdState"))
	if not data then
		return false, "Household data not available."
	end

	local userId = player.UserId
	local indexMap = NameToIndexMap[userId]
	if not indexMap then
		return false, "Residents not loaded yet."
	end

	local index = indexMap[residentName]
	if not index then
		return false, "Resident not found."
	end

	local entry = data.Residents[index] :: { [string]: any }
	if entry then
		entry.TenantId = tenantId
	end

	local residentState = ResidentService.GetResident(player, residentName)
	if residentState and residentState.Save then
		residentState.Save.TenantId = tenantId
	end

	setTenantLinkInternal(userId, residentName, tenantId)

	local source = nil
	if residentState and residentState.Save then
		source = residentState.Save
	elseif entry then
		source = entry
	end
	local tenantClone = source and cloneResidentForNetwork(source) or nil
	if tenantClone then
		local payload = {
			UserId = userId,
			ResidentName = residentName,
			ResidentDelta = { tenantClone },
		}
		ResidentsPackets.PlayerResidentDelta:Fire(payload)
	end
	return true, "Success"
end

function ResidentService.GetResidentNameByTenantId(player: Player, tenantId: string): string?
	local tenantMap = TenantToResidentMap[player.UserId]
	if not tenantMap then
		return nil
	end
	return tenantMap[tenantId]
end

function ResidentService.ClearTenantLink(player: Player, tenantId: string)
	clearTenantLinkByTenant(player.UserId, tenantId)
end

return ResidentService
