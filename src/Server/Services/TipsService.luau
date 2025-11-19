--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local TipsPackets = require(ReplicatedStorage.Network.TipsPackets)

local TipsService = {}

function TipsService.AwardTip(player: Player, residentName: string, amount: number, sourcePosition: Vector3)
	local currencyState = PlayerSession.GetDataAwait(player, "CurrencyState")
	if not currencyState then
		return
	end

	CurrencyService.Add(player, "Cash", amount, currencyState, {
		Source = "Tip",
		ResidentName = residentName,
	})

	TipsPackets.TipDropped:FireClient(player, {
		Amount = amount,
		SourcePosition = sourcePosition,
	})
end

return TipsService
