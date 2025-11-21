--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local TipsPackets = require(ReplicatedStorage.Network.TipsPackets)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)

local TipsService = {}

type TipData = {
	Amount: number,
	ResidentName: string,
	Reason: string?,
	ExpiresAt: number,
}

local ActiveTips: { [number]: { [string]: TipData } } = {}
local TIP_LIFETIME = 45 -- Seconds (slightly longer than client to allow for latency)
local UPDATE_TASK_NAME = "TipsService"
local UPDATE_INTERVAL = 1
local TIP_CHANCE_PER_MINUTE = 0.5 -- 50% chance per minute per resident
local TIP_CHECK_INTERVAL = 60

local lastTipCheck = 0

local function getGroundPosition(position: Vector3, ignoreList: { Instance }?): Vector3
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

local function stepTips(_dt: number)
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

function TipsService.SpawnTip(
	player: Player,
	residentName: string,
	amount: number,
	sourcePosition: Vector3?,
	reason: string?
)
	local userId = player.UserId
	if not ActiveTips[userId] then
		ActiveTips[userId] = {}
	end

	local tipId = HttpService:GenerateGUID(false)
	ActiveTips[userId][tipId] = {
		Amount = amount,
		ResidentName = residentName,
		Reason = reason,
		ExpiresAt = os.clock() + TIP_LIFETIME,
	}

	-- Cleanup old tips occasionally
	local count = 0
	for _ in pairs(ActiveTips[userId]) do
		count += 1
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

	TipsPackets.TipDropped:FireClient(player, {
		TipId = tipId,
		Amount = amount,
		SourcePosition = groundPos,
		Reason = reason or "Tip",
		ResidentName = residentName or "",
	})
end

return TipsService
