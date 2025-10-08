--!strict

-- ServerScriptService/Server/Services/ResidentService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packets = require(ReplicatedStorage.Network.ResidentsPackets)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PlotService = require(ServerScriptService.Server.Services.PlotService)

local ResidentService = {}
local PlayersResidents = {}

local Config = {
	MaxResidentsPerHousehold = 8,
}

function ResidentService.Init()
	PlotService.PlotClaimed:Connect(function(player, _playerState)
		ResidentService.Load(player)
	end)

	Packets.AddResidentRequest.OnServerInvoke = function(player: Player, residentData: any)
		return ResidentService.CreateResident(player, residentData)
	end
end

function ResidentService.Load(player: Player)
	local data = PlayerSession.GetDataAwait(player, "HouseholdState") :: any

	if data.ResidentsCount == 0 then
		Packets.PromptResidentCreation:FireClient(player)
		PlayersResidents[player.UserId] = data.Residents or {}
	else
		PlayersResidents[player.UserId] = data.Residents or {}
		Packets.ResidentStateSync:FireClient(player, PlayersResidents[player.UserId])
	end
end

function ResidentService.CreateResident(player: Player, residentData: any)
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
	-- Add the new resident
	table.insert(PlayersResidents[player.UserId], newResidentData)
	data.ResidentsCount += 1
	return true, "Resident created successfully."
end

function ResidentService.Unload(player: Player)
	PlayersResidents[player.UserId] = nil
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
