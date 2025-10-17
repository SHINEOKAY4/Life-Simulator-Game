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
local DirectActionService = require(ServicesFolder.DirectActionService)

local _ResidentActionHandlers = require(ModulesFolder.ResidentActionHandlers)

ResidentService.Init()
PlotService.Init()
BuildService.Init()
ResidentAutonomyService.Init()
DirectActionService.Init()
ResidentNeedService.Init()

ResidentNeedService.UpdateRegisteredResidentsNeeds()
local function OnPlayerAdded(player: Player)
	PlayerSession.GetDataAwait(player)
	local character = player.Character or player.CharacterAdded:Wait()
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
end

local function OnPlayerRemoving(player: Player)
	-- Unload order matters: unloading plot service while other services still use the plot will cause issues
	ResidentService.Unload(player) -- This should always be higher in the unload order
	PlotService.Unclaim(player) -- This should always be lower in the unload order
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

local _ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
