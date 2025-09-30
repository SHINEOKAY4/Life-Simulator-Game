--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Main.client.lua
local ModulesFolder = script.Parent.Modules

local PlotSelector = require(ModulesFolder.PlotSelector)
local PlotGrid = require(ModulesFolder.PlotGridOverlay)
local PlotExpansion = require(ModulesFolder.PlotExpansion)
local PlotStateStore = require(script.Parent.ClientStores.PlotStateStore)
local PlotBuilder = require(ModulesFolder.PlotBuilder)
local ObjectPreview = require(ModulesFolder.ObjectPreview)

PlotSelector.Init()
PlotGrid.Init()
PlotExpansion.Init()
PlotStateStore.Init()
ObjectPreview.Init()
PlotBuilder.Init()

print("Client Main initialized.")
