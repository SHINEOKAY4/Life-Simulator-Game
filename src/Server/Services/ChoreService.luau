-- Server/Services/ChoreService.luau
-- Manages interactive chores (messes, repairs) for player engagement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local ChorePackets = require(ReplicatedStorage.Network.ChorePackets)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local ProgressionService = require(ServerScriptService.Server.Services.ProgressionService)
local ResidentsFolderFinder = require(ReplicatedStorage.Shared.Utilities.ResidentsFolderFinder)
local RepairManager = require(ServerScriptService.Server.Modules.Chores.RepairManager)

local ChoreService = {}

export type SpawnMessPayload = {
	TenantName: string?,
	PlotIndex: number?,
	Position: Vector3?,
	RewardAmount: number?,
	Metadata: { [string]: any }?,
}

type ChoreRecord = {
	Id: string,
	Type: string,
	PlotIndex: number,
	OwnerPlayer: Player?,
	CreatedAt: number,
	RewardAmount: number,
	TenantName: string?,
	SampledPosition: Vector3?,
	Metadata: { [string]: any }?,
}

type BaseChorePayload = {
	PlotIndex: number?,
	RewardAmount: number?,
	TenantName: string?,
	Position: Vector3?,
	Metadata: { [string]: any }?,
}

type CompletionHandler = (player: Player, record: ChoreRecord, root: BasePart?) -> (boolean, string?, number?)
type RepairBridgePayload = RepairManager.RepairChorePayload

local ActiveChores: { [string]: ChoreRecord } = {}

local TRASH_DISPOSAL_ITEM_IDS = {
	TrashBin = true,
}

local TRASH_CONTAINER_ITEM_IDS = {
	TrashCan = true,
}

local TRASH_RECEPTACLE_ITEM_IDS = {}
for itemId in pairs(TRASH_DISPOSAL_ITEM_IDS) do
	TRASH_RECEPTACLE_ITEM_IDS[itemId] = true
end
for itemId in pairs(TRASH_CONTAINER_ITEM_IDS) do
	TRASH_RECEPTACLE_ITEM_IDS[itemId] = true
end

local MESS_REWARD = 15
local MESS_LIFETIME = 300 -- 5 minutes
local MAX_MESSES_PER_PLOT = 5

local function sampleTenantPosition(player: Player, tenantName: string?): Vector3?
	if typeof(tenantName) ~= "string" or tenantName == "" then
		return nil
	end
	local instance = ResidentsFolderFinder.FindResident(player, tenantName)
	if not instance then
		return nil
	end
	local primary = instance.PrimaryPart or instance:FindFirstChild("HumanoidRootPart")
	if primary and primary:IsA("BasePart") then
		return primary.Position
	end
	local basePart = instance:FindFirstChildWhichIsA("BasePart")
	if basePart then
		return basePart.Position
	end
	local pivotCFrame = instance:GetPivot()
	if typeof(pivotCFrame) == "CFrame" then
		return pivotCFrame.Position
	end
	return nil
end

local function completeTrashChore(player: Player, record: ChoreRecord, root: BasePart?): (boolean, string?, number?)
	if not root then
		return false, "No character.", nil
	end

	local comparisonPosition = record.SampledPosition
	if not comparisonPosition then
		comparisonPosition = sampleTenantPosition(player, record.TenantName)
	end
	if comparisonPosition and (root.Position - comparisonPosition).Magnitude > 18 then
		return false, "Too far away.", nil
	end

	return true, "Cleaned up!", nil
end

local CompletionHandlers: { [string]: CompletionHandler } = {
	Trash = completeTrashChore,
	Repair = function(player: Player, record: ChoreRecord): (boolean, string?, number?)
		return RepairManager.HandleRepairCompletion(player, record)
	end,
}

local function sendChoreSpawn(record: ChoreRecord)
	local player = record.OwnerPlayer
	if not player then
		return
	end
	ChorePackets.ChoreSpawned:FireClient(player, {
		ChoreId = record.Id,
		Type = record.Type,
		TenantName = record.TenantName or "",
		PlotIndex = record.PlotIndex,
		Metadata = record.Metadata,
	})
end

local function createChoreRecord(player: Player, choreType: string, payload: BaseChorePayload): ChoreRecord?
	local plotIndex = payload.PlotIndex
	if typeof(plotIndex) ~= "number" then
		local attr = player:GetAttribute("OwnedPlotIndex")
		if typeof(attr) ~= "number" then
			return nil
		end
		plotIndex = attr
	end

	local record: ChoreRecord = {
		Id = HttpService:GenerateGUID(false),
		Type = choreType,
		PlotIndex = plotIndex,
		OwnerPlayer = player,
		CreatedAt = os.time(),
		RewardAmount = payload.RewardAmount or (choreType == "Trash" and MESS_REWARD or 0),
		TenantName = payload.TenantName,
		SampledPosition = payload.Position,
		Metadata = payload.Metadata,
	}

	return record
end

local function registerChoreRecord(record: ChoreRecord, lifetimeSeconds: number?): string
	ActiveChores[record.Id] = record
	sendChoreSpawn(record)
	if lifetimeSeconds and lifetimeSeconds > 0 then
		task.delay(lifetimeSeconds, function()
			if ActiveChores[record.Id] == record then
				ChoreService.RemoveChore(record.Id, "Expired")
			end
		end)
	end
	return record.Id
end

local function spawnRepairChoreForBridge(player: Player, payload: RepairBridgePayload): string?
	local record = createChoreRecord(player, "Repair", {
		PlotIndex = payload.PlotIndex,
		RewardAmount = payload.RewardAmount,
		Position = payload.WorldPosition,
		Metadata = payload.Metadata,
	})
	if not record then
		return nil
	end
	return registerChoreRecord(record, nil)
end

function ChoreService.SpawnMess(player: Player, payload: SpawnMessPayload?)
	if not player then
		return
	end

	local options = payload or {}
	local plotIndex = options.PlotIndex
	if typeof(plotIndex) ~= "number" then
		plotIndex = player:GetAttribute("OwnedPlotIndex")
	end
	if typeof(plotIndex) ~= "number" then
		return
	end

	if ChoreService.GetTrashCount(player) >= MAX_MESSES_PER_PLOT then
		return
	end

	local resolvedPayload: SpawnMessPayload = {
		TenantName = options.TenantName,
		PlotIndex = plotIndex,
		Position = options.Position,
		RewardAmount = options.RewardAmount,
		Metadata = options.Metadata,
	}

	local record = createChoreRecord(player, "Trash", resolvedPayload)
	if not record then
		return
	end

	registerChoreRecord(record, MESS_LIFETIME)
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

	RepairManager.NotifyChoreRemoved(id, reason)
end

function ChoreService.GetTrashCount(player: Player): number
	local count = 0
	for _, chore in pairs(ActiveChores) do
		if chore.OwnerPlayer == player and chore.Type == "Trash" then
			count += 1
		end
	end
	return count
end

local function completeChore(player: Player, choreId: string): (boolean, string)
	local record = ActiveChores[choreId]
	if not record then
		return false, "Chore not found or already completed."
	end

	if record.OwnerPlayer ~= player then
		return false, "Not your chore."
	end

	local character = player.Character
	local root = character and character.PrimaryPart
	local handler = CompletionHandlers[record.Type] or completeTrashChore
	local success, message, rewardOverride = handler(player, record, root)
	if not success then
		return false, message or "Unable to complete"
	end

	local rewardAmount = rewardOverride
	if rewardAmount == nil then
		rewardAmount = record.RewardAmount
	end

	if rewardAmount > 0 then
		local profile = PlayerSession.GetData(player)
		if profile then
			CurrencyService.Add(
				player,
				"Cash",
				rewardAmount,
				profile.CurrencyState,
				{ Source = "Chore:" .. record.Type }
			)
		end
	end

	ProgressionService.RecordChoreCompletion(player)
	ChoreService.RemoveChore(choreId, "Completed")

	return true, message or "Nice work!"
end

function ChoreService.Init()
	ChorePackets.CompleteChore.OnServerInvoke = completeChore

	Players.PlayerRemoving:Connect(function(player)
		player:SetAttribute("CarryingTrashId", nil)
	end)

	RepairManager.Configure({
		SpawnRepairChore = function(player, payload)
			return spawnRepairChoreForBridge(player, payload)
		end,
		RemoveChore = function(choreId: string, reason: string)
			ChoreService.RemoveChore(choreId, reason)
		end,
	})
end

return ChoreService
