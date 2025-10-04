--!strict
-- ServerScriptService/Server/Main.server.lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService.Server
local ServicesFolder = ServerFolder.Services

local PlayerSession = require(ServicesFolder.PlayerSession)
local PlotService = require(ServicesFolder.PlotService)
local BuildService = require(ServicesFolder.BuildService)

PlotService.Init()
BuildService.Init()

local function OnPlayerAdded(player: Player)
	print("Player added: " .. player.Name)
	PlayerSession.GetData(player)
end

local function OnPlayerRemoving(player: Player)
	print("Player removing: " .. player.Name)
	PlotService.Unclaim(player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)
