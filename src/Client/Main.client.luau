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

local ModulesFolder = script.Parent.Modules

local SoundtrackManager = require(ModulesFolder.SoundtrackManager)
local DayAndNight = require(ModulesFolder.DayAndNight)
local PlotSelector = require(ModulesFolder.PlotSelector)
local PlotGrid = require(ModulesFolder.PlotGridOverlay)
local PlotExpansion = require(ModulesFolder.PlotExpansion)
local PlotStateStore = require(script.Parent.ClientStores.PlotStateStore)
local KitchenStateStore = require(script.Parent.ClientStores.KitchenStateStore)
local PlotBuilder = require(ModulesFolder.PlotBuilder)
local ObjectPreview = require(ModulesFolder.ObjectPreview)
local ObjectSelector = require(ModulesFolder.ObjectSelector)
local ResidentSelector = require(ModulesFolder.ResidentMover)
local ResidentController = require(ModulesFolder.ResidentController)
local ObjectAction = require(ModulesFolder.ObjectAction)
local WorldEventController = require(ModulesFolder.WorldEventController)
local StorageInteractionController = require(ModulesFolder.StorageInteractionController)

local PlotBuilderUI = require(script.Parent.UserInterface.PlotBuilderUI)
local BillboardRadialUI = require(script.Parent.UserInterface.BillboardRadialUI)
local StationRadialUI = require(script.Parent.UserInterface.StationRadialUI)
local ResidentNeedsUI = require(script.Parent.UserInterface.ResidentNeedsUI)
local NeedWarningNotifications = require(script.Parent.UserInterface.NeedWarningNotifications)
local JobSelectionUI = require(script.Parent.UserInterface.JobSelectionUI)
local ResidentStationBillboard = require(script.Parent.UserInterface.ResidentStationBillboard)
local ResidentChatBubbles = require(script.Parent.UserInterface.ResidentChatBubbles)
local ResidentNameBillboard = require(script.Parent.UserInterface.ResidentNameBillboard)
local ResidentRoster = require(script.Parent.UserInterface.ResidentRoster)
local MainHUD = require(script.Parent.UserInterface.MainHUD)
local MailboxCashEffect = require(script.Parent.UserInterface.MailboxCashEffect)
local TimeUI = require(script.Parent.UserInterface.TimeUI)
local ShiftStatusPanel = require(script.Parent.UserInterface.ShiftStatusPanel)
local StorageBillboardUI = require(script.Parent.UserInterface.StorageBillboardUI)

SoundtrackManager.Init()
DayAndNight.Init()
PlotGrid.Init()
PlotExpansion.Init()
PlotStateStore.Init()
KitchenStateStore.Init()
TimeUI.Init()
MainHUD.Init()
MailboxCashEffect.Init()
ResidentRoster.Init()
ObjectPreview.Init()
PlotBuilder.Init()
ObjectSelector.Init()
ResidentSelector.Init()
ResidentController.Init()
ResidentNeedsUI.Init()
ShiftStatusPanel.Init()
NeedWarningNotifications.Init()
ObjectAction.Init()
WorldEventController.Init()
PlotBuilderUI:Init()
BillboardRadialUI.Init()
StationRadialUI.Init()
JobSelectionUI.Init()
ResidentStationBillboard.Init()
ResidentChatBubbles.Init()
ResidentNameBillboard.Init()
PlotSelector.Init()
StorageBillboardUI.Init()
StorageInteractionController.Init()
local ResidentsStore = require(script.Parent.ClientStores.ResidentsStore)
local NewResidentUI = require(script.Parent.UserInterface.NewResidentUI)

ResidentsStore.Init()
NewResidentUI.Init()

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
