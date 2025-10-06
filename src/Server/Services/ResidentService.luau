--!strict
-- ServerScriptService/Server/Services/ResidentService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ResidentState = require(ServerScriptService.Server.Classes.ResidentState)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)
local ResidentBehavior = require(ServerScriptService.Server.Utilities.ResidentBehavior)

local ResidentService = {}
local PlayerResidents = {} -- [playerId] = { resident1 = ResidentState, resident2 = ResidentState, ... }
local MaxResidentsPerPlayer = 8 -- Global max residents allowed in game, cannot be overriden. This is to prevent abuse.

local function CreateResident(payload: { Name: string, Gender: string })
	-- Placeholder for resident creation logic do
	local newResident = {
		Name = payload.Name,
		Age = 0,
		Gender = payload.Gender,
		Occupation = "Unemployed",
		Cash = 0,
		Mood = 100,
		Intelligence = 0,
		Fitness = 0,
		Social = 0,
	}

	return newResident
end

function ResidentService.Init()
	print("ResidentService Init")
	PlotService.PlotClaimed:Connect(function(player: Player, _plotstate) -- Plotstate is not used yet perhaps later
		print("Plot claimed by player: " .. player.Name)
		ResidentService.Load(player)
	end)

	ResidentsPackets.AddResidentRequest.OnServerInvoke = function(
		player: Player,
		payload: { Name: string, Gender: string }
	)
		print("AddResidentRequest received from player: " .. player.Name)
		-- Here you would typically validate and save the new resident data
		local data = PlayerSession.GetDataAwait(player, "HouseholdState") :: any
		local residentsCount = #data.Residents
		if residentsCount >= MaxResidentsPerPlayer or residentsCount >= data.MaxResidents then
			return false, "Maximum number of residents reached."
		end

		local newResident = CreateResident(payload)
		table.insert(data.Residents, newResident)
		PlayerResidents[player.UserId][newResident.Name] = ResidentState.new(newResident)
		ResidentBehavior.SpawnResident(player, newResident)
		return true, "Resident created successfully."
	end
end

function ResidentService.Load(player: Player)
	print("ResidentService Load")
	local userId = player.UserId

	if PlayerResidents[userId] then
		return PlayerResidents[userId]
	end

	local data = PlayerSession.GetDataAwait(player, "HouseholdState") :: any
	PlayerResidents[userId] = {}
	-- if no residents exist, prompt client to open ui to create one
	-- otherwise, create NPC instances for each resident
	local residents = data.Residents :: { ResidentState.ResidentData }

	-- =========== Test resident data ======================

	--local testResident = {
	--	Name = "Alex",
	--	Age = 30,
	--	Occupation = "Farmer",
	--	Gender = "Male",
	--	Cash = 100,
	--	Mood = 100,
	--	Intelligence = 50,
	--	Fitness = 70,
	--	Social = 60,
	--}

	--table.insert(residents, testResident)
	--=========================================
	if #residents == 0 then
		print("No residents found for player " .. player.Name .. ". Prompting creation UI.")
		-- The reason the residentStore is not prompting and why a packet needs to be sent:
		-- residentstore prompting requires sending residentstatesync with empty residents; table will have mismatched packet shape (error)
		-- resident store prompting would be better but won't match the packet shape (nil ~= {residentData})
		ResidentsPackets.PromptResidentCreation:FireClient(player)
	else
		for _, resident in ipairs(residents) do
			print("Resident: " .. resident.Name .. ", Age: " .. resident.Age .. ", Occupation: " .. resident.Occupation)
			PlayerResidents[userId][resident.Name] = ResidentState.new(resident)
			-- Here you would typically create NPC instances or load them into the game world
			ResidentBehavior.SpawnResident(player, resident)
			task.defer(function()
				task.wait(4) -- Wait a moment to ensure the resident is fully spawned
				ResidentBehavior.MoveToStation(player, resident.Name, "WoodenTable")
			end)
		end

		ResidentsPackets.ResidentStateSync:FireClient(player, residents)
	end

	return PlayerResidents[userId]
end

function ResidentService.Unload(player: Player)
	print("ResidentService Unload")
	local userId = player.UserId
	if not PlayerResidents[userId] then
		return
	end
	for residentName, _ in pairs(PlayerResidents[userId]) do
		ResidentBehavior.DespawnResident(player, residentName)
	end

	PlayerResidents[userId] = nil
end

function ResidentService.GetState(player: Player)
	local userId = player.UserId
	return PlayerResidents[userId]
end

return ResidentService
