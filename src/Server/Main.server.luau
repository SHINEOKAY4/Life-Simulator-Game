--!strict
-- ServerScriptService/Server/Main.server.lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService.Server
local ServicesFolder = ServerFolder.Services
local ModulesFolder = ServerFolder.Modules

local PlayerSession = require(ServicesFolder.PlayerSession)
local PlotService = require(ServicesFolder.PlotService)
local BuildService = require(ServicesFolder.BuildService)
local ResidentService = require(ServicesFolder.ResidentService)
local ResidentAutonomyService = require(ServicesFolder.ResidentAutonomyService)
local ResidentNeedService = require(ServicesFolder.ResidentNeedService)
local ResidentCollapseService = require(ServicesFolder.ResidentCollapseService)
local DirectActionService = require(ServicesFolder.DirectActionService)
local CareerService = require(ServicesFolder.CareerService)
local GigService = require(ServicesFolder.GigService)
local EconomyCycleService = require(ServicesFolder.EconomyCycleService)
local JobListingService = require(ServicesFolder.JobListingService)

local _ResidentActionHandlers = require(ModulesFolder.ResidentActionHandlers)

ResidentService.Init()
CareerService.Init()
GigService.Init()
EconomyCycleService.Init()
PlotService.Init()
BuildService.Init()
ResidentAutonomyService.Init()
DirectActionService.Init()
ResidentNeedService.Init()
ResidentCollapseService.Init()
JobListingService.Init()
JobListingService.Start()
EconomyCycleService.Start()

ResidentNeedService.UpdateRegisteredResidentsNeeds()
ResidentCollapseService.Refresh()
local function setCharacterCollisionGroup(character: Model)
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
end

local function OnPlayerAdded(player: Player)
	print("Player added: " .. player.Name)
	print(PlayerSession.GetDataAwait(player))
	local character = player.Character or player.CharacterAdded:Wait()
	setCharacterCollisionGroup(character)
end

local function OnPlayerRemoving(player: Player)
	print("Player removing: " .. player.Name)
	ResidentService.Unload(player)
	PlotService.Unclaim(player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

local _ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
