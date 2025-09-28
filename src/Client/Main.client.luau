--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Main.client.lua
local ModulesFolder = script.Parent.Modules

local PlotSelector = require(ModulesFolder.PlotSelector)
local PlotGrid = require(ModulesFolder.PlotGrid)
local PlotExpansion = require(ModulesFolder.PlotExpansion)
local PlotStateStore = require(script.Parent.ClientStores.PlotStateStore)

PlotSelector.Init()
PlotGrid.Init()
PlotExpansion.Init()
PlotStateStore.Init()

print("Client Main initialized.")
