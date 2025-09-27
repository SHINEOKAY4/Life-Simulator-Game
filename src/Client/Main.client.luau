--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Main.client.luau
local ModulesFolder = script.Parent.Modules

local PlotSelector = require(ModulesFolder.PlotSelector)
local PlotGrid = require(ModulesFolder.PlotGrid)

PlotSelector.Init()
PlotGrid.Init()

print("Client Main initialized.")
