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
local KitchenStateStore = require(script.Parent.ClientStores.KitchenStateStore)
local ButtonSoundController = require(ModulesFolder.ButtonSoundController)
local PlotBuilder = require(ModulesFolder.PlotBuilder)
local ObjectPreview = require(ModulesFolder.ObjectPreview)
local ObjectSelector = require(ModulesFolder.ObjectSelector)
local ResidentSelector = require(ModulesFolder.ResidentMover)
local ResidentController = require(ModulesFolder.ResidentController)
local CutawayViewController = require(ModulesFolder.CutawayViewController)
local ObjectAction = require(ModulesFolder.ObjectAction)
local WorldEventController = require(ModulesFolder.WorldEventController)
local MiningInteractionController = require(ModulesFolder.MiningInteractionController)
local StorageInteractionController = require(ModulesFolder.StorageInteractionController)
local FoodSourceInteractionController = require(ModulesFolder.FoodSourceInteractionController)
local WoodcuttingInteractionController = require(ModulesFolder.WoodcuttingInteractionController)
local SurfacePaintController = require(ModulesFolder.SurfacePaintController)

local PlotBuilderUI = require(script.Parent.UserInterface.PlotBuilderUI)
local BuildPaletteUI = require(script.Parent.UserInterface.BuildPaletteUI)
local BillboardRadialUI = require(script.Parent.UserInterface.BillboardRadialUI)
local StationRadialUI = require(script.Parent.UserInterface.StationRadialUI)
local ResidentNeedsUI = require(script.Parent.UserInterface.ResidentNeedsUI)
local NeedWarningNotifications = require(script.Parent.UserInterface.NeedWarningNotifications)
local ResidentStationBillboard = require(script.Parent.UserInterface.ResidentStationBillboard)
local ResidentChatBubbles = require(script.Parent.UserInterface.ResidentChatBubbles)
local ResidentNameBillboard = require(script.Parent.UserInterface.ResidentNameBillboard)
local ResidentRoster = require(script.Parent.UserInterface.ResidentRoster)
local MainHUD = require(script.Parent.UserInterface.MainHUD)
local TimeUI = require(script.Parent.UserInterface.TimeUI)
local StorageBillboardUI = require(script.Parent.UserInterface.StorageBillboardUI)

SoundtrackManager.Init()
DayAndNight.Init()
PlotGrid.Init()
PlotExpansion.Init()
PlotStateStore.Init()
RoomDebugOverlay.Init()
CutawayViewController.Init()
KitchenStateStore.Init()
TimeUI.Init()
ButtonSoundController.Init()
MainHUD.Init()
ResidentRoster.Init()
ObjectPreview.Init()
PlotBuilder.Init()
ObjectSelector.Init()
ResidentSelector.Init()
ResidentController.Init()
ResidentNeedsUI.Init()
NeedWarningNotifications.Init()
ObjectAction.Init()
WorldEventController.Init()
MiningInteractionController.Init()
PlotBuilderUI:Init()
BuildPaletteUI.Init()
SurfacePaintController.Init()
BillboardRadialUI.Init()
StationRadialUI.Init()
ResidentStationBillboard.Init()
ResidentChatBubbles.Init()
ResidentNameBillboard.Init()
PlotSelector.Init()
StorageBillboardUI.Init()
StorageInteractionController.Init()
FoodSourceInteractionController.Init()
WoodcuttingInteractionController.Init()
local ResidentsStore = require(script.Parent.ClientStores.ResidentsStore) :: any

ResidentsStore.Init()
--RoomDebugOverlay.SetEnabled(true)
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
