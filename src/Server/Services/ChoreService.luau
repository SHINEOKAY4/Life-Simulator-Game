--!strict
-- Server/Services/ChoreService.luau
-- Manages interactive chores (messes, repairs) for player engagement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local ChorePackets = require(ReplicatedStorage.Network.ChorePackets)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)

local ChoreService = {}

type ChoreRecord = {
	Id: string,
	Type: string,
	Position: Vector3,
	PlotIndex: number,
	OwnerPlayer: Player?,
	CreatedAt: number,
	RewardAmount: number,
	TargetId: string?,
}

local ActiveChores: { [string]: ChoreRecord } = {}

-- Configuration
local MESS_REWARD = 15
local MESS_LIFETIME = 300 -- 5 minutes
local MAX_MESSES_PER_PLOT = 5

-- // Mess System Implementation //

function ChoreService.SpawnMess(player: Player, position: Vector3)
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if type(plotIndex) ~= "number" then
		return
	end

	-- Limit check
	local count = 0
	for _, chore in pairs(ActiveChores) do
		if chore.OwnerPlayer == player and chore.Type == "Trash" then
			count += 1
		end
	end
	if count >= MAX_MESSES_PER_PLOT then
		return
	end

	local id = HttpService:GenerateGUID(false)

	-- Randomize position slightly so it doesn't stack perfectly
	local offset = Vector3.new(math.random() * 2 - 1, 0, math.random() * 2 - 1)
	local finalPos = position + offset

	local record: ChoreRecord = {
		Id = id,
		Type = "Trash",
		Position = finalPos,
		PlotIndex = plotIndex,
		OwnerPlayer = player,
		CreatedAt = os.time(),
		RewardAmount = MESS_REWARD,
	}

	ActiveChores[id] = record

	ChorePackets.ChoreSpawned:FireClient(player, {
		ChoreId = id,
		Type = "Trash",
		Position = finalPos,
		PlotIndex = plotIndex,
		TargetId = "",
	})

	-- Auto-cleanup task
	task.delay(MESS_LIFETIME, function()
		if ActiveChores[id] then
			ChoreService.RemoveChore(id, "Expired")
		end
	end)
end

function ChoreService.RemoveChore(id: string, reason: string)
	local record = ActiveChores[id]
	if not record then
		return
	end

	ActiveChores[id] = nil

	if record.OwnerPlayer then
		ChorePackets.ChoreRemoved:FireClient(record.OwnerPlayer, {
			ChoreId = id,
			Reason = reason,
		})
	end
end

local function completeChore(player: Player, choreId: string): (boolean, string)
	local record = ActiveChores[choreId]
	if not record then
		return false, "Chore not found or already completed."
	end

	if record.OwnerPlayer ~= player then
		return false, "Not your chore."
	end

	-- Distance check
	local character = player.Character
	if not character then
		return false, "No character."
	end
	local root = character.PrimaryPart
	if not root then
		return false, "No root part."
	end

	if (root.Position - record.Position).Magnitude > 15 then
		return false, "Too far away."
	end

	-- Reward
	local profile = PlayerSession.GetData(player)
	if profile then
		CurrencyService.Add(
			player,
			"Cash",
			record.RewardAmount,
			profile.CurrencyState,
			{ Source = "Chore:" .. record.Type }
		)
	end

	ChoreService.RemoveChore(choreId, "Completed")

	return true, "Cleaned up!"
end

-- // Item Breakdown System (Stubbed) //

function ChoreService.RegisterBreakableItem(itemInstance: Instance)
	-- TODO: Track item usage and health
end

function ChoreService.TriggerBreakdown(itemInstance: Instance)
	-- TODO: Set item state to broken, spawn repair chore
	-- local id = HttpService:GenerateGUID(false)
	-- Create ChoreRecord with Type="Repair"
	-- Fire packet
end

function ChoreService.RepairItem(player: Player, choreId: string)
	-- TODO: Validate repair skill/parts?
	-- Restore item function
end

function ChoreService.Init()
	ChorePackets.CompleteChore.OnServerInvoke = completeChore
end

return ChoreService
