--!strict
-- ServerScriptService/Server/Main.server.luau
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService.Server
local ServicesFolder = ServerFolder.Services

local PlotService = require(ServicesFolder.PlotService)

PlotService.Init()

local function OnPlayerAdded(player: Player)
	print("Player added: " .. player.Name)
end

local function OnPlayerRemoving(player: Player)
	print("Player removing: " .. player.Name)
	PlotService.Unclaim(player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)
