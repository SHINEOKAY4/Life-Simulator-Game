local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NetworkFolder = ReplicatedStorage:WaitForChild("Network")

-- Require every packet definition before any remotes fire to avoid nil Packet registrations.
local function preloadPacketModules(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("ModuleScript") then
			require(child)
		elseif child:IsA("Folder") then
			preloadPacketModules(child)
		end
	end
end

preloadPacketModules(NetworkFolder)

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local ActiveQueryFolder = PlayerGui:WaitForChild("ActiveQuery")

local function ensureActiveQueryBool(name: string, defaultValue: boolean): BoolValue
	local existing = ActiveQueryFolder:FindFirstChild(name)
	if existing and existing:IsA("BoolValue") then
		return existing
	end
	local value = Instance.new("BoolValue")
	value.Name = name
	value.Value = defaultValue
	value.Parent = ActiveQueryFolder
	return value
end

ensureActiveQueryBool("CutawayVisible", false)

local ModulesFolder = script.Parent.Modules

local SoundtrackManager = require(ModulesFolder.SoundtrackManager)
local DayAndNight = require(ModulesFolder.DayAndNight)
local PlotSelector = require(ModulesFolder.PlotSelector)
local PlotGrid = require(ModulesFolder.PlotGridOverlay)
local PlotExpansion = require(ModulesFolder.PlotExpansion)
local RoomDebugOverlay = require(ModulesFolder.RoomDebugOverlay)
local PlotStateStore = require(script.Parent.ClientStores.PlotStateStore)
local ButtonSoundController = require(ModulesFolder.ButtonSoundController)
local PlotBuilder = require(ModulesFolder.PlotBuilder)
local ObjectPreview = require(ModulesFolder.ObjectPreview)
local ObjectSelector = require(ModulesFolder.ObjectSelector)
local ObjectAction = require(ModulesFolder.ObjectAction)
local WorldEventController = require(ModulesFolder.WorldEventController)
local MailboxInteractionController = require(ModulesFolder.MailboxInteractionController)
local SurfacePaintController = require(ModulesFolder.SurfacePaintController)
local PreviewToolController = require(ModulesFolder.PreviewToolController)
local TenantProspectController = require(ModulesFolder.TenantProspectController)
local TenantInteractionController = require(ModulesFolder.TenantInteractionController)
local TenantHelpController = require(ModulesFolder.TenantHelpController)
local ChoreController = require(ModulesFolder.ChoreController)
local TipsController = require(ModulesFolder.TipsController)
local ReviewController = require(ModulesFolder.ReviewController)
local UtilityVisuals = require(ModulesFolder.UtilityVisuals)
local CutawayController = require(ModulesFolder.CutawayController)
local SelectionController = require(ModulesFolder.SelectionController)
local WireController = require(ModulesFolder.WireController)
local EnvironmentHUDController = require(ModulesFolder.EnvironmentHUDController)
local ThermostatInteractionController = require(ModulesFolder.ThermostatInteractionController)
local PowerSwitchController = require(ModulesFolder.PowerSwitchController)
local WeatherController = require(ModulesFolder.WeatherController)
local ResidentController = require(ModulesFolder.ResidentController)
local ProgressionController = require(ModulesFolder.ProgressionController)

local PlotBuilderUI = require(script.Parent.UserInterface.PlotBuilderUI)
local BuildPaletteUI = require(script.Parent.UserInterface.BuildPaletteUI)
local BillboardRadialUI = require(script.Parent.UserInterface.BillboardRadialUI)
-- local ResidentNeedsUI = require(script.Parent.UserInterface.ResidentNeedsUI)
local ResidentChatBubbles = require(script.Parent.UserInterface.ResidentChatBubbles)
local ResidentNameBillboard = require(script.Parent.UserInterface.ResidentNameBillboard)
local MainHUD = require(script.Parent.UserInterface.MainHUD)
local BillUI = require(script.Parent.UserInterface.BillUI)
local LevelUpUI = require(script.Parent.UserInterface.LevelUpUI)
--local TimeUI = require(script.Parent.UserInterface.TimeUI)

ProgressionController.Init()
SoundtrackManager.Init()
DayAndNight.Init()
PlotGrid.Init()
PlotExpansion.Init()
PlotStateStore.Init()
RoomDebugOverlay.Init()
--TimeUI.Init()
ButtonSoundController.Init()
MainHUD.Init()
BillUI.Init()
LevelUpUI.Init()
ObjectPreview.Init()
PlotBuilder.Init()
ObjectSelector.Init()
-- ResidentNeedsUI.Init()
ObjectAction.Init()
WorldEventController.Init()
PlotBuilderUI:Init()
BuildPaletteUI.Init()
SurfacePaintController.Init()
PreviewToolController.Init()
TenantProspectController.Init()
TenantInteractionController.Init()
TenantHelpController.Init()
ChoreController.Init()
TipsController.Start()
ReviewController.Init()
BillboardRadialUI.Init()
ResidentChatBubbles.Init()
ResidentNameBillboard.Init()
PlotSelector.Init()
MailboxInteractionController.Init()
UtilityVisuals.Init()
CutawayController.Init()
SelectionController.Init()
WireController.Init()
EnvironmentHUDController.Init()
ThermostatInteractionController.Init()
PowerSwitchController.Init()
WeatherController.Start()
ResidentController.Init()
local ResidentsStore = require(script.Parent.ClientStores.ResidentsStore) :: any
local TenantStore = require(script.Parent.ClientStores.TenantStore)

ResidentsStore.Init()
TenantStore.Init()
RoomDebugOverlay.SetEnabled(true)
local function SetCollisionGroup(character: Model)
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = "Players"
		end
	end
end

SetCollisionGroup(Character)

LocalPlayer.CharacterAdded:Connect(SetCollisionGroup)

for _, player in ipairs(Players:GetPlayers()) do
	if player ~= LocalPlayer and player.Character then
		SetCollisionGroup(player.Character)
		player.CharacterAdded:Connect(SetCollisionGroup)
	end
end

Players.PlayerAdded:Connect(function(player: Player)
	player.CharacterAdded:Connect(SetCollisionGroup)
end)
