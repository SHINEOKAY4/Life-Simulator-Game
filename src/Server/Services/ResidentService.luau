--!strict

-- ServerScriptService/Server/Services/ResidentService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local PlotService = require(ServerScriptService.Server.Services.PlotService)

local ResidentService = {}

function ResidentService.Init()
	PlotService.PlotClaimed:Connect(function(player, playerState) end)
end

function ResidentService.Load() end

return ResidentService
