--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Main.client.lua

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local Character = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()

local ModulesFolder = script.Parent.Modules

local DayAndNight = require(ModulesFolder.DayAndNight)
local PlotSelector = require(ModulesFolder.PlotSelector)
local PlotGrid = require(ModulesFolder.PlotGridOverlay)
local PlotExpansion = require(ModulesFolder.PlotExpansion)
local PlotStateStore = require(script.Parent.ClientStores.PlotStateStore)
local PlotBuilder = require(ModulesFolder.PlotBuilder)
local ObjectPreview = require(ModulesFolder.ObjectPreview)
local ObjectSelector = require(ModulesFolder.ObjectSelector)
local ResidentSelector = require(ModulesFolder.ResidentSelector)
local ResidentController = require(ModulesFolder.ResidentController)
local ObjectAction = require(ModulesFolder.ObjectAction)

local PlotBuilderUI = require(script.Parent.UserInterface.PlotBuilderUI)
local BillboardRadialUI = require(script.Parent.UserInterface.BillboardRadialUI)
local ResidentRadialUI = require(script.Parent.UserInterface.ResidentRadialUI)
local NeedsInterface = require(script.Parent.UserInterface.ResidentUI)
local JobSelectionUI = require(script.Parent.UserInterface.JobSelectionUI)
local ResidentStationBillboard = require(script.Parent.UserInterface.ResidentStationBillboard)

DayAndNight.Init()
PlotSelector.Init()
PlotGrid.Init()
PlotExpansion.Init()
PlotStateStore.Init()
ObjectPreview.Init()
PlotBuilder.Init()
ObjectSelector.Init()
ResidentSelector.Init()
ResidentController.Init()
NeedsInterface.Init()
ObjectAction.Init()
PlotBuilderUI:Init()
BillboardRadialUI.Init()
ResidentRadialUI.Init()
JobSelectionUI.Init()
ResidentStationBillboard.Init()

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
