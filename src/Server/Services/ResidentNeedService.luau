--!strict
-- ServerScriptService/Server/Services/ResidentNeedService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentAutonomyService = require(ServerScriptService.Server.Services.ResidentAutonomyService)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)

local ResidentNeedService = {}
local Residents: { any } = {}

local IsRunning = false
local SubscriberId = "Needs"
local IntervalSeconds = 0.25

function ResidentNeedService.Init()
	-- Placeholder for future implementation
	ResidentService.PlayerResidentsChanged:Connect(function()
		ResidentNeedService.UpdateRegisteredResidentsNeeds()
	end)
end

function ResidentNeedService.Start()
	if IsRunning then
		return
	end
	IsRunning = true

	WorldUpdate.Subscribe(SubscriberId, IntervalSeconds, function(deltaTime: number)
		-- implementation for evaluating resident needs goes here
		if next(Residents) == nil then
			return
		end

		local gameHours = TimeScale.GameHoursFromRealDelta(deltaTime)

		for _, resident in ipairs(Residents) do
			ResidentNeedService.Decay(resident, gameHours)
			if resident.AutoActionsEnabled and not resident.IsBusy then
				print("Evaluating needs for resident: " .. resident.Save.Name)
			end
			-- #TODO: Evaluate needs and decide actions / ResidentAutonomyService.Decide()
		end
	end)
end

function ResidentNeedService.Decay(resident: any, gameHours: number)
	for needName, definition in pairs(NeedConfig.Needs) do
		local value = resident:GetNeed(needName)
		local newValue = math.clamp(value - definition.DecayPerHour * gameHours, definition.Min, definition.Max)
		if newValue ~= value then
			resident:SetNeed(needName, newValue)
		end
	end
end
function ResidentNeedService.UpdateRegisteredResidentsNeeds()
	local playersResidents = ResidentService.GetResidents()
	for _userId, residents in pairs(playersResidents) do
		for _residentName, resident in pairs(residents) do
			if not table.find(Residents, resident) then
				table.insert(Residents, resident)
			end
		end
	end
	ResidentNeedService.Start()
end

return ResidentNeedService
