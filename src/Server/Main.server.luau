--!strict
-- ServerScriptService/Server/Main.server.lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService.Server
local ServicesFolder = ServerFolder.Services

local PlayerSession = require(ServicesFolder.PlayerSession)
local PlotService = require(ServicesFolder.PlotService)
local BuildService = require(ServicesFolder.BuildService)
local ResidentService = require(ServicesFolder.ResidentService)

PlotService.Init()
BuildService.Init()
ResidentService.Init()

local function OnPlayerAdded(player: Player)
	print("Player added: " .. player.Name)
	print(PlayerSession.GetDataAwait(player))
	--PlayerSession.ClearData(player)
end

local function OnPlayerRemoving(player: Player)
	print("Player removing: " .. player.Name)
	-- For now unload order matters, unloading plot service while other services still uses the plot will cause issues

	PlotService.Unclaim(player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)
