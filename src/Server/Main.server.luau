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
local KitchenService = require(ServicesFolder.KitchenService)
local ResidentAutonomyService = require(ServicesFolder.ResidentAutonomyService)
local ResidentNeedService = require(ServicesFolder.ResidentNeedService)
local ResidentCollapseService = require(ServicesFolder.ResidentCollapseService)
local WorldEventService = require(ServicesFolder.WorldEventService)
local BillingService = require(ServicesFolder.BillingService)
local TenantService = require(ServicesFolder.TenantService)
local TenantProspectService = require(ServicesFolder.TenantProspectService)
local FoodSourceService = require(ServicesFolder.FoodSourceService)
local WoodcuttingService = require(ServicesFolder.WoodcuttingService)
local MiningService = require(ServicesFolder.MiningService)

local _ResidentActionHandlers = require(ModulesFolder.ResidentActionHandlers)

ResidentService.Init()
BillingService.Init()
WorldEventService.Init()
PlotService.Init()
BuildService.Init()
TenantService.Init()
TenantProspectService.Init()
KitchenService.Init()
FoodSourceService.Init()
WoodcuttingService.Init()
MiningService.Init()
ResidentAutonomyService.Init()
ResidentNeedService.Init()
ResidentCollapseService.Init()

ResidentNeedService.UpdateRegisteredResidentsNeeds()
ResidentCollapseService.Refresh()
local function OnPlayerAdded(player: Player)
	print("Player added: " .. player.Name)
	print(PlayerSession.GetDataAwait(player))
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
	BillingService.Remove(player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

local _ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)

--_ResidentDebug.SetChannelEnabled("Movement", true)
--_ResidentDebug.SetChannelEnabled("Action", true)
--_ResidentDebug.SetChannelEnabled("Effects", true)
