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
local JobListingService = require(ServicesFolder.JobListingService)
local BillingService = require(ServicesFolder.BillingService)
local PayrollService = require(ServicesFolder.PayrollService)

local _ResidentActionHandlers = require(ModulesFolder.ResidentActionHandlers)

ResidentService.Init()
CareerService.Init()
BillingService.Init()
PayrollService.Init()
GigService.Init()
PlotService.Init()
BuildService.Init()
ResidentAutonomyService.Init()
DirectActionService.Init()
ResidentNeedService.Init()
ResidentCollapseService.Init()
JobListingService.Init()
JobListingService.Start()

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
	PayrollService.Remove(player)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

local _ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)

--_ResidentDebug.SetChannelEnabled("Movement", true)
--_ResidentDebug.SetChannelEnabled("Action", true)
--_ResidentDebug.SetChannelEnabled("Effects", true)
