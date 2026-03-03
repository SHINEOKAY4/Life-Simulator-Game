-- selene: allow(global_usage)
--!strict

local function hasRobloxRuntime()
	if type(game) ~= "userdata" then
		return false
	end
	return pcall(function()
		return game:GetService("Players")
	end)
end

local IS_ROBLOX = hasRobloxRuntime()

local ReplicatedStorage = nil
local ServerScriptService = nil
local HttpService = nil
local Workspace = nil
local Players = nil

local CurrencyService = nil
local PlayerSession = nil
local TipsPackets = nil
local WorldUpdate = nil
local ResidentService = nil
local WorldEventService = nil

if IS_ROBLOX then
	ReplicatedStorage = game:GetService("ReplicatedStorage")
	ServerScriptService = game:GetService("ServerScriptService")
	HttpService = game:GetService("HttpService")
	Workspace = game:GetService("Workspace")
	Players = game:GetService("Players")

	CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
	PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
	TipsPackets = require(ReplicatedStorage.Network.TipsPackets)
	WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
	ResidentService = require(ServerScriptService.Server.Services.ResidentService)
	WorldEventService = require(ServerScriptService.Server.Services.WorldEventService)
else
	local fallbackHttp = {
		GenerateGUID = function()
			return tostring(os.clock())
		end,
	}
	if type(_G) == "table" and _G.HttpService then
		HttpService = _G.HttpService
	else
		HttpService = fallbackHttp
	end
	local okWorkspace, workspaceService = pcall(function()
		return game:GetService("Workspace")
	end)
	if okWorkspace and workspaceService then
		Workspace = workspaceService
	else
		Workspace = { Raycast = function()
			return nil
		end }
	end
	local okPlayers, playersService = pcall(function()
		return game:GetService("Players")
	end)
	if okPlayers and playersService then
		Players = playersService
	else
		Players = { GetPlayers = function()
			return {}
		end }
	end
	TipsPackets = { TipDropped = { FireClient = function() end }, ClaimTip = { OnServerEvent = { Connect = function() end } } }
	WorldUpdate = { Subscribe = function() end }
	ResidentService = { GetResidents = function()
		return {}
	end }
	local okServer, serverScriptService = pcall(function()
		return game:GetService("ServerScriptService")
	end)
	if okServer and serverScriptService and serverScriptService.Server and serverScriptService.Server.Services then
		WorldEventService = serverScriptService.Server.Services.WorldEventService
	else
		WorldEventService = nil
	end
end

local TipsService = {}

local ActiveTips = {}
local TIP_LIFETIME = 45 -- Seconds (slightly longer than client to allow for latency)
local UPDATE_TASK_NAME = "TipsService"
local UPDATE_INTERVAL = 1
local TIP_CHANCE_PER_MINUTE = 0.5 -- 50% chance per minute per resident
local TIP_CHECK_INTERVAL = 60

local lastTipCheck = 0

local function getTipMultiplier()
	if WorldEventService and WorldEventService.GetBuffMultiplier then
		local ok, multiplier = pcall(WorldEventService.GetBuffMultiplier, "TipMultiplier")
		if ok and type(multiplier) == "number" and multiplier > 0 then
			return multiplier
		end
	end
	return 1.0
end

local function applyTipMultiplier(amount)
	if amount <= 0 then
		return amount
	end
	local adjusted = amount * getTipMultiplier()
	if adjusted ~= adjusted or adjusted <= 0 then
		return amount
	end
	local rounded = math.floor(adjusted + 0.5)
	if rounded < 1 then
		return 1
	end
	return rounded
end

local function getGroundPosition(position, ignoreList)
	local rayOrigin = position + Vector3.new(0, 5, 0)
	local rayDirection = Vector3.new(0, -50, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignoreList or {}

	local result = Workspace:Raycast(rayOrigin, rayDirection, params)
	if result then
		return result.Position
	end
	return position
end

local function stepTips(_dt)
	local now = os.clock()
	if now - lastTipCheck < TIP_CHECK_INTERVAL then
		return
	end
	lastTipCheck = now

	for _, player in ipairs(Players:GetPlayers()) do
		local residents = ResidentService.GetResidents(player)
		if residents then
			for residentName, _ in pairs(residents) do
				if math.random() < TIP_CHANCE_PER_MINUTE then
					TipsService.SpawnTip(player, residentName, math.random(5, 15), nil, "Passive Income")
				end
			end
		end
	end
end

function TipsService.Init()
	TipsPackets.ClaimTip.OnServerEvent:Connect(function(player, packet)
		local userId = player.UserId
		local userTips = ActiveTips[userId]
		if not userTips then
			return
		end

		local tipId = packet.TipId
		local tipData = userTips[tipId]

		if not tipData then
			-- Tip not found or already claimed
			return
		end

		-- Check expiration
		if os.clock() > tipData.ExpiresAt then
			userTips[tipId] = nil
			return
		end

		-- Claim successful
		userTips[tipId] = nil

		local currencyState = PlayerSession.GetDataAwait(player, "CurrencyState")
		if currencyState then
			CurrencyService.Add(player, "Cash", tipData.Amount, currencyState, {
				Source = "Tip",
				ResidentName = tipData.ResidentName,
				Reason = tipData.Reason,
			})
		end
	end)

	WorldUpdate.Subscribe(UPDATE_TASK_NAME, UPDATE_INTERVAL, stepTips)
end

function TipsService.SpawnTip(player, residentName, amount, sourcePosition, reason)
	if not WorldEventService then
		local okServer, serverScriptService = pcall(function()
			return game:GetService("ServerScriptService")
		end)
		if okServer and serverScriptService and serverScriptService.Server and serverScriptService.Server.Services then
			WorldEventService = serverScriptService.Server.Services.WorldEventService
		end
	end
	local userId = player.UserId
	local tipAmount = applyTipMultiplier(amount)
	if not ActiveTips[userId] then
		ActiveTips[userId] = {}
	end

	local tipId = HttpService:GenerateGUID(false)
	ActiveTips[userId][tipId] = {
		Amount = tipAmount,
		ResidentName = residentName,
		Reason = reason,
		ExpiresAt = os.clock() + TIP_LIFETIME,
	}

	-- Cleanup old tips occasionally
	local count = 0
	for _ in pairs(ActiveTips[userId]) do
		count = count + 1
	end
	if count > 20 then
		local now = os.clock()
		for id, data in pairs(ActiveTips[userId]) do
			if now > data.ExpiresAt then
				ActiveTips[userId][id] = nil
			end
		end
	end

	local groundPos = Vector3.zero
	if sourcePosition then
		groundPos = getGroundPosition(sourcePosition, { player.Character })
	end

	local packets = TipsService._TipsPackets or TipsPackets
	if packets and packets.TipDropped then
		packets.TipDropped:FireClient(player, {
			TipId = tipId,
			Amount = tipAmount,
			SourcePosition = groundPos,
			Reason = reason or "Tip",
			ResidentName = residentName or "",
		})
	end
end

-- Test hook for patching TipsPackets in specs.
TipsService._TipsPackets = TipsPackets

function TipsService._SetPacketsForTests(packets)
	TipsService._TipsPackets = packets
end

function TipsService._SetWorldEventServiceForTests(service)
	WorldEventService = service
end

return TipsService
