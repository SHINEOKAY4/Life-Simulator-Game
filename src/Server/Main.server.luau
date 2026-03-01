--!strict
-- ServerScriptService/Server/Main.server.lua
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerFolder = ServerScriptService.Server
local ServicesFolder = ServerFolder.Services
local ModulesFolder = ServerFolder.Modules
local SharedUtilitiesFolder = ReplicatedStorage.Shared.Utilities

local StartupDiagnostics = require(SharedUtilitiesFolder.StartupDiagnostics)
local StartupLog = StartupDiagnostics.new("ServerMain")

local function runStartupStep(stepName: string, callback: () -> ())
	StartupLog:Boundary(stepName, callback)
end

local PlayerSession = require(ServicesFolder.PlayerSession)
local ProgressionService = require(ServicesFolder.ProgressionService)
local AchievementService = require(ServicesFolder.AchievementService)
local PlotService = require(ServicesFolder.PlotService)
local BuildService = require(ServicesFolder.BuildService)
local ResidentService = require(ServicesFolder.ResidentService)
local WorldEventService = require(ServicesFolder.WorldEventService)
local BillingService = require(ServicesFolder.BillingService)
local ReviewService = require(ServicesFolder.ReviewService)
local ReputationService = require(ServicesFolder.ReputationService)
local TenantService = require(ServicesFolder.TenantService)
local TenantProspectService = require(ServicesFolder.TenantProspectService)
local TutorialService = require(ServicesFolder.TutorialService)
local ChoreService = require(ServicesFolder.ChoreService)
local CraftingService = require(ServicesFolder.CraftingService)
local TipsService = require(ServicesFolder.TipsService)
local UtilityService = require(ServicesFolder.UtilityService)
local TemperatureService = require(ServicesFolder.TemperatureService)
local WeatherService = require(ServicesFolder.WeatherService)
local SeasonalEventService = require(ServicesFolder.SeasonalEventService)
local TradeService = require(ServicesFolder.TradeService)
local TrashManager = require(ModulesFolder.Chores.TrashManager)
local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)

runStartupStep("ProgressionService.Init", function()
	ProgressionService.Init()
end)
runStartupStep("AchievementService.Init", function()
	AchievementService.Init()
end)
runStartupStep("ResidentService.Init", function()
	ResidentService.Init()
end)
runStartupStep("BillingService.Init", function()
	BillingService.Init()
end)
runStartupStep("WorldEventService.Init", function()
	WorldEventService.Init()
end)
runStartupStep("PlotService.Init", function()
	PlotService.Init()
end)
runStartupStep("BuildService.Init", function()
	BuildService.Init()
end)
runStartupStep("ReviewService.Init", function()
	ReviewService.Init()
end)
runStartupStep("ReputationService.Init", function()
	ReputationService.Init()
end)
runStartupStep("TenantService.Init", function()
	TenantService.Init()
end)
runStartupStep("TenantProspectService.Init", function()
	TenantProspectService.Init()
end)
runStartupStep("TutorialService.Init", function()
	TutorialService.Init()
end)
runStartupStep("ChoreService.Init", function()
	ChoreService.Init()
end)
runStartupStep("CraftingService.Init", function()
	CraftingService.Init()
end)
runStartupStep("TipsService.Init", function()
	TipsService.Init()
end)
runStartupStep("UtilityService.Init", function()
	UtilityService.Init()
end)
runStartupStep("TemperatureService.Init", function()
	TemperatureService.Init()
end)
runStartupStep("WeatherService.Start", function()
	WeatherService.Start()
end)
runStartupStep("SeasonalEventService.Init", function()
	SeasonalEventService.Init(WeatherService)
end)
runStartupStep("TradeService.Init", function()
	TradeService.Init()
end)
runStartupStep("TrashManager.Start", function()
	TrashManager.Start()
end)

-- Ensure power state is recalculated whenever a plot finishes loading
PlotService.PlotClaimed:Connect(function(player)
	task.defer(function()
		UtilityService.Recalculate(player)
	end)
end)

local function OnPlayerAdded(player: Player)
	StartupLog:Boundary(("OnPlayerAdded:%d"):format(player.UserId), function()
		print("Player added: " .. player.Name)
		print(PlayerSession.GetDataAwait(player))
		BillingService.LoadPlayer(player)
		TutorialService.OnPlayerAdded(player)
		player:GetAttributeChangedSignal(BillingConstants.PowerOutageAttribute):Connect(function()
			if player:GetAttribute("OwnedPlotIndex") ~= nil then
				UtilityService.Recalculate(player)
			end
		end)
		--PlayerSession.ClearData(player)
		local character = player.Character or player.CharacterAdded:Wait()
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CollisionGroup = "Players"
			end
		end
	end)
end

local function OnPlayerRemoving(player: Player)
	StartupLog:Boundary(("OnPlayerRemoving:%d"):format(player.UserId), function()
		print("Player removing: " .. player.Name)
		-- For now unload order matters, unloading plot service while other services still uses the plot will cause issues

		ResidentService.Unload(player) -- This should always be higher in the unload order
		PlotService.Unclaim(player) -- This should always be lower in the unload order
		BillingService.UnloadPlayer(player)
		UtilityService.ClearCache(player)
	end)
end

Players.PlayerAdded:Connect(OnPlayerAdded)
Players.PlayerRemoving:Connect(OnPlayerRemoving)

--local _ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)

--_ResidentDebug.SetChannelEnabled("Movement", true)
--_ResidentDebug.SetChannelEnabled("Action", true)
--_ResidentDebug.SetChannelEnabled("Effects", true)
