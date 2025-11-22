-- Server/Services/ChoreService.luau
-- Manages interactive chores (messes, repairs) for player engagement.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local ChorePackets = require(ReplicatedStorage.Network.ChorePackets)
local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local ProgressionService = require(ServerScriptService.Server.Services.ProgressionService)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

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

local ActiveChores: { [string]: ChoreRecord } = {}

local MESS_REWARD = 15
local MESS_LIFETIME = 300 -- 5 minutes
local MAX_MESSES_PER_PLOT = 5

local function findTenantFolder(player: Player): Folder?
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local residents = plotModel:FindFirstChild("Residents")
	if residents and residents:IsA("Folder") then
		return residents
	end
	return nil
end

local function sampleTenantPosition(player: Player, tenantName: string?): Vector3?
	if typeof(tenantName) ~= "string" or tenantName == "" then
		return nil
	end
	local folder = findTenantFolder(player)
	if not folder then
		return nil
	end
	local instance = folder:FindFirstChild(tenantName)
	if not instance or not instance:IsA("Model") then
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

local function sendTrashSpawn(record: ChoreRecord)
	local player = record.OwnerPlayer
	if not player then
		return
	end
	ChorePackets.ChoreSpawned:FireClient(player, {
		ChoreId = record.Id,
		Type = record.Type,
		TenantName = record.TenantName or "",
		PlotIndex = record.PlotIndex,
	})
end

local function createChoreRecord(player: Player, payload: SpawnMessPayload): ChoreRecord?
	local plotIndex = payload.PlotIndex
	if typeof(plotIndex) ~= "number" then
		local attr = player:GetAttribute("OwnedPlotIndex")
		if typeof(attr) ~= "number" then
			return nil
		end
		plotIndex = attr
	end

	local id = HttpService:GenerateGUID(false)
	local reward = payload.RewardAmount or MESS_REWARD

	local record: ChoreRecord = {
		Id = id,
		Type = "Trash",
		PlotIndex = plotIndex,
		OwnerPlayer = player,
		CreatedAt = os.time(),
		RewardAmount = reward,
		TenantName = payload.TenantName,
		SampledPosition = payload.Position,
		Metadata = payload.Metadata,
	}

	return record
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

	local record = createChoreRecord(player, resolvedPayload)
	if not record then
		return
	end

	ActiveChores[record.Id] = record
	sendTrashSpawn(record)

	task.delay(MESS_LIFETIME, function()
		if ActiveChores[record.Id] then
			ChoreService.RemoveChore(record.Id, "Expired")
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

	-- Distance check
	local character = player.Character
	if not character then
		return false, "No character."
	end
	local root = character.PrimaryPart
	if not root then
		return false, "No root part."
	end

	local comparisonPosition = record.SampledPosition
	if not comparisonPosition then
		comparisonPosition = sampleTenantPosition(player, record.TenantName)
	end
	if comparisonPosition and (root.Position - comparisonPosition).Magnitude > 18 then
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
	ProgressionService.RecordChoreCompletion(player)

	ChoreService.RemoveChore(choreId, "Completed")

	return true, "Cleaned up!"
end

-- // Item Breakdown System (Stubbed) //

function ChoreService.RegisterBreakableItem(_itemInstance: Instance)
	-- TODO: Track item usage and health
end

function ChoreService.TriggerBreakdown(_itemInstance: Instance)
	-- TODO: Set item state to broken, spawn repair chore
	-- local id = HttpService:GenerateGUID(false)
	-- Create ChoreRecord with Type="Repair"
	-- Fire packet
end

function ChoreService.RepairItem(_player: Player, _choreId: string)
	-- TODO: Validate repair skill/parts?
	-- Restore item function
end

function ChoreService.Init()
	ChorePackets.CompleteChore.OnServerInvoke = completeChore
end

return ChoreService
