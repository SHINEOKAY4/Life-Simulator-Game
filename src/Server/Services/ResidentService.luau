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
	local data = PlayerSession.GetDataAwait(player, "HouseholdState") :: any
	local userId = player.UserId

	local payload = {
		UserId = userId,
		Residents = data.Residents,
	}

	if data.ResidentsCount == 0 then
		ResidentsPackets.PromptResidentCreation:FireClient(player)
	end

	-- Build a keyed map and index map for easier access
	PlayersResidents[userId] = {}
	NameToIndexMap[userId] = {}

	for index, resident in ipairs(data.Residents) do
		local mapKey = resident.Name
		local indexKey = index
		PlayersResidents[userId][mapKey] = ResidentState.new(resident)
		NameToIndexMap[userId][mapKey] = indexKey
		ResidentPlacer.Spawn(player, PlayersResidents[userId][mapKey])
	end

	ResidentService.PlayerResidentsChanged:Fire(player)
	ResidentsPackets.PlayersResidentsSync:Fire(payload)
end

function ResidentService.CreateResident(player: Player, residentData: ResidentData)
	local data = PlayerSession.GetDataAwait(player, "HouseholdState") :: any

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
		Needs = {
			Hunger = 100,
			Energy = 100,
			Hygiene = 100,
			Fun = 100,
			Social = 100,
		},
	}

	local payload = {
		UserId = player.UserId,
		ResidentName = newResidentData.Name,
		ResidentDelta = { newResidentData },
	}
	-- Add the new resident
	table.insert(data.Residents, newResidentData) -- Append to the saved data first, so the index is correct, NameToIndexMap uses # of array
	data.ResidentsCount += 1
	PlayersResidents[player.UserId][newResidentData.Name] = ResidentState.new(newResidentData)
	NameToIndexMap[player.UserId][newResidentData.Name] = #data.Residents

	ResidentPlacer.Spawn(player, PlayersResidents[player.UserId][newResidentData.Name])
	ResidentService.PlayerResidentsChanged:Fire(player)
	ResidentsPackets.PlayerResidentDelta:Fire(payload)
	return true, "Resident created successfully."
end

function ResidentService.DeleteResident(player: Player, residentName: string)
	local data = PlayerSession.GetDataAwait(player, "HouseholdState") :: any
	local userId = player.UserId
	local resident = PlayersResidents[userId][residentName]

	if not resident then
		return false, "Resident not found."
	end

	local index = NameToIndexMap[userId][residentName]
	if not index then
		return false, "Resident index not found."
	end
	print(residentName, index, data.Residents)
	table.remove(data.Residents, index)

	PlayersResidents[userId][residentName] = nil

	-- Rebuild the index map
	NameToIndexMap[userId] = {}
	for idx, res in ipairs(data.Residents) do
		NameToIndexMap[userId][res.Name] = idx
	end

	data.ResidentsCount = math.max(0, data.ResidentsCount - 1)
	local payload = {
		UserId = userId,
		ResidentName = residentName,
		ResidentDelta = {},
	}

	resident:Destroy()
	ResidentService.PlayerResidentsChanged:Fire(player)
	ResidentsPackets.PlayerResidentDelta:Fire(payload)
	return true, "Resident deleted successfully."
end

function ResidentService.Unload(player: Player)
	local userId = player.UserId
	for _, resident in pairs(PlayersResidents[userId] or {}) do
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
return ResidentService
