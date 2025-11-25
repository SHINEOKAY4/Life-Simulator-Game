--!strict
-- ServerScriptService/Server/Main.server.lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local ServerFolder = ServerScriptService.Server
local ServicesFolder = ServerFolder.Services
local ModulesFolder = ServerFolder.Modules

local PlayerSession = require(ServicesFolder.PlayerSession)
local ProgressionService = require(ServicesFolder.ProgressionService)
local PlotService = require(ServicesFolder.PlotService)
local BuildService = require(ServicesFolder.BuildService)
local ResidentService = require(ServicesFolder.ResidentService)
local WorldEventService = require(ServicesFolder.WorldEventService)
local BillingService = require(ServicesFolder.BillingService)
local ReviewService = require(ServicesFolder.ReviewService)
local TenantService = require(ServicesFolder.TenantService)
local TenantProspectService = require(ServicesFolder.TenantProspectService)
local TutorialService = require(ServicesFolder.TutorialService)
local ChoreService = require(ServicesFolder.ChoreService)
local TipsService = require(ServicesFolder.TipsService)
local UtilityService = require(ServicesFolder.UtilityService)
local TemperatureService = require(ServicesFolder.TemperatureService)
local WeatherService = require(ServicesFolder.WeatherService)
local TrashManager = require(ModulesFolder.Chores.TrashManager)

ProgressionService.Init()
ResidentService.Init()
BillingService.Init()
WorldEventService.Init()
PlotService.Init()
BuildService.Init()
ReviewService.Init()
TenantService.Init()
TenantProspectService.Init()
TutorialService.Init()
ChoreService.Init()
TipsService.Init()
UtilityService.Init()
TemperatureService.Init()
WeatherService.Start()
TrashManager.Start()

-- Ensure power state is recalculated whenever a plot finishes loading
PlotService.PlotClaimed:Connect(function(player)
	task.defer(function()
		UtilityService.Recalculate(player)
	end)
end)

local function OnPlayerAdded(player: Player)
	print("Player added: " .. player.Name)
	print(PlayerSession.GetDataAwait(player))
	BillingService.LoadPlayer(player)
	TutorialService.OnPlayerAdded(player)
	--PlayerSession.ClearData(player)
	local character = player.Character or player.CharacterAdded:Wait()
	for _, part in pairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end
end

local function OnPlayerRemoving(player: Player)
	print("Player removing: " .. player.Name)
	-- For now unload order matters, unloading plot service while other services still uses the plot will cause issues

	ResidentService.Unload(player) -- This should always be higher in the unload order
	PlotService.Unclaim(player) -- This should always be lower in the unload order
	BillingService.UnloadPlayer(player)
	UtilityService.ClearCache(player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

--local _ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)

--_ResidentDebug.SetChannelEnabled("Movement", true)
--_ResidentDebug.SetChannelEnabled("Action", true)
--_ResidentDebug.SetChannelEnabled("Effects", true)
