--!strict
-- Server/Modules/Chores/RepairManager.luau
-- Centralized coordinator for breakable plot objects and repair chores.

local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local RepairConfig = require(ReplicatedStorage.Shared.Configurations.RepairConfig)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

export type RepairChorePayload = {
	PlotIndex: number,
	WorldPosition: Vector3,
	RewardAmount: number,
	Metadata: { [string]: any },
}

type BreakProfile = {
	BaseIntervalSeconds: number,
	IntervalJitterPercent: number,
	SeverityMin: number,
	SeverityMax: number,
	RewardMultiplier: number,
	MinReward: number,
	MaxReward: number,
	CompletionDistance: number,
	PromptHoldSeconds: number,
}

type ChoreBridge = {
	SpawnRepairChore: (player: Player, payload: RepairChorePayload) -> string?,
	RemoveChore: (choreId: string, reason: string) -> (),
}

type BreakableRecord = {
	Key: string,
	Player: Player?,
	UserId: number,
	PlotIndex: number,
	PlacementKey: string,
	ItemId: string,
	Spec: { [string]: any },
	Model: Model?,
	Profile: BreakProfile,
	State: "Healthy" | "Broken",
	NextBreakTime: number,
	ActiveChoreId: string?,
	Severity: number,
	RewardAmount: number,
	VisualSeed: number,
	Metadata: { [string]: any }?,
	Connection: RBXScriptConnection?,
	RoomCellX: number?,
	RoomCellZ: number?,
	RoomLevel: number?,
}

local RepairManager = {}
local RNG = Random.new()

local BreakablesByKey: { [string]: BreakableRecord } = {}
local ChoreIdToKey: { [string]: string } = {}
local Bridge: ChoreBridge? = nil
local UpdateBound = false
local PLAYER_CLEANUP_BOUND = false

local function cloneDefaultProfile(): BreakProfile
	local defaults = RepairConfig.DefaultProfile
	return {
		BaseIntervalSeconds = defaults.BaseIntervalSeconds,
		IntervalJitterPercent = defaults.IntervalJitterPercent,
		SeverityMin = defaults.SeverityMin,
		SeverityMax = defaults.SeverityMax,
		RewardMultiplier = defaults.RewardMultiplier,
		MinReward = defaults.MinReward,
		MaxReward = defaults.MaxReward,
		CompletionDistance = defaults.CompletionDistance,
		PromptHoldSeconds = defaults.PromptHoldSeconds,
	}
end

local function shouldTrackSpec(spec: { [string]: any }?): boolean
	if typeof(spec) ~= "table" then
		return false
	end

	local explicit = spec.Breakable
	if explicit == true then
		return true
	end
	if explicit == false then
		return false
	end

	local tags = spec.Tags
	if typeof(tags) == "table" then
		for _, tag in ipairs(tags) do
			if tag == "Appliance" or tag == "Electronics" or tag == "Utility" then
				return true
			end
		end
	end

	if spec.RequiresPower == true then
		return true
	end

	return false
end

local function resolveProfile(spec: { [string]: any }?): BreakProfile
	local profile = cloneDefaultProfile()
	if typeof(spec) ~= "table" then
		return profile
	end

	local override = spec.BreakableConfig
	if typeof(override) == "table" then
		if typeof(override.BaseIntervalSeconds) == "number" then
			profile.BaseIntervalSeconds = math.max(override.BaseIntervalSeconds, 30)
		end
		if typeof(override.IntervalJitterPercent) == "number" then
			profile.IntervalJitterPercent = math.clamp(override.IntervalJitterPercent, 0, 0.95)
		end
		if typeof(override.SeverityMin) == "number" then
			profile.SeverityMin = math.clamp(override.SeverityMin, 0, 1)
		end
		if typeof(override.SeverityMax) == "number" then
			profile.SeverityMax = math.clamp(override.SeverityMax, profile.SeverityMin, 1)
		end
		if typeof(override.RewardMultiplier) == "number" then
			profile.RewardMultiplier = math.max(override.RewardMultiplier, 0.005)
		end
		if typeof(override.MinReward) == "number" then
			profile.MinReward = math.max(0, override.MinReward)
		end
		if typeof(override.MaxReward) == "number" then
			profile.MaxReward = math.max(profile.MinReward, override.MaxReward)
		end
		if typeof(override.CompletionDistance) == "number" then
			profile.CompletionDistance = math.max(2, override.CompletionDistance)
		end
		if typeof(override.PromptHoldSeconds) == "number" then
			profile.PromptHoldSeconds = math.clamp(override.PromptHoldSeconds, 0.2, 4)
		end
	else
		local tags = spec.Tags
		if typeof(tags) == "table" then
			for _, tag in ipairs(tags) do
				local adjustment = RepairConfig.TagProfiles[tag]
				if adjustment then
					if typeof(adjustment.IntervalScale) == "number" then
						profile.BaseIntervalSeconds *= math.clamp(adjustment.IntervalScale, 0.25, 2)
					end
					if typeof(adjustment.RewardScale) == "number" then
						profile.MinReward *= math.clamp(adjustment.RewardScale, 0.25, 3)
						profile.MaxReward *= math.clamp(adjustment.RewardScale, 0.25, 3)
					end
					if typeof(adjustment.SeverityBoost) == "number" then
						profile.SeverityMin = math.clamp(profile.SeverityMin + adjustment.SeverityBoost, 0, 0.95)
						profile.SeverityMax =
							math.clamp(profile.SeverityMax + adjustment.SeverityBoost, profile.SeverityMin, 1)
					end
				end
			end
		end
	end

	return profile
end

local function computeIntervalSeconds(profile: BreakProfile): number
	local jitter = math.clamp(profile.IntervalJitterPercent, 0, 0.95)
	local minFactor = 1 - jitter
	local maxFactor = 1 + jitter
	return math.max(30, profile.BaseIntervalSeconds * RNG:NextNumber(minFactor, maxFactor))
end

local function makeKey(userId: number, placementKey: string): string
	return ("%d::%s"):format(userId, placementKey)
end

local function getModelPosition(model: Model?): Vector3?
	if not model then
		return nil
	end
	local primary = model.PrimaryPart or model:FindFirstChild("PrimaryPart")
	if primary and primary:IsA("BasePart") then
		return primary.Position
	end
	local basePart = model:FindFirstChildWhichIsA("BasePart")
	if basePart then
		return basePart.Position
	end
	local ok, pivot = pcall(function()
		return model:GetPivot()
	end)
	if ok and typeof(pivot) == "CFrame" then
		return pivot.Position
	end
	return nil
end

local function resolvePlayerPlotIndex(player: Player, fallback: number?): number
	local attr = player:GetAttribute("OwnedPlotIndex")
	if typeof(attr) == "number" then
		return attr
	end
	return fallback or 0
end

local function roundCell(value: any): number?
	if typeof(value) == "number" then
		return math.floor(value + 0.5)
	end
	local numeric = tonumber(value)
	if numeric then
		return math.floor(numeric + 0.5)
	end
	return nil
end

local FacingOffsets: { [string]: { dx: number, dz: number } } = {
	North = { dx = 0, dz = -1 },
	South = { dx = 0, dz = 1 },
	East = { dx = 1, dz = 0 },
	West = { dx = -1, dz = 0 },
}

local function resolveSampleCell(model: Model?, spec: { [string]: any }?): (number?, number?, number?)
	if not model then
		return nil, nil, nil
	end

	local cellX = roundCell(model:GetAttribute("CellX"))
	local cellZ = roundCell(model:GetAttribute("CellZ"))
	local levelAttr = model:GetAttribute("Level")
	local level = if typeof(levelAttr) == "number" then levelAttr else nil
	local facingAttr = model:GetAttribute("Facing")
	local facing = if typeof(facingAttr) == "string" then facingAttr else nil

	if not cellX or not cellZ then
		local placementKeyAttr = model:GetAttribute("PlacementKey")
		if typeof(placementKeyAttr) == "string" then
			local ok, parsedX, parsedZ, parsedFacing, _, parsedLevel =
				pcall(PlacementKey.ParseWithType, placementKeyAttr)
			if ok then
				cellX = cellX or parsedX
				cellZ = cellZ or parsedZ
				facing = facing or parsedFacing
				level = level or parsedLevel
			end
		end
	end

	local placementTypeAttr = model:GetAttribute("PlacementType")
	local placementType = if typeof(placementTypeAttr) == "string"
		then placementTypeAttr
		elseif spec and typeof(spec.PlacementType) == "string" then spec.PlacementType
		else "CellObject"

	if (placementType == "Wall" or placementType == "WallMounted") and facing then
		local offsets = FacingOffsets[facing]
		if offsets then
			if cellX then
				cellX += offsets.dx
			end
			if cellZ then
				cellZ += offsets.dz
			end
		end
	end

	return cellX, cellZ, level
end

local RoomResolver: ((player: Player, cellX: number, cellZ: number, level: number?) -> any)? = nil
local OccupancyResolver: ((player: Player) -> { [string]: number }?)? = nil

local function ensureRoomCell(record: BreakableRecord): (number?, number?, number?)
	local cellX = record.RoomCellX
	local cellZ = record.RoomCellZ
	local level = record.RoomLevel
	if cellX and cellZ then
		return cellX, cellZ, level
	end
	local resolvedX, resolvedZ, resolvedLevel = resolveSampleCell(record.Model, record.Spec)
	record.RoomCellX = resolvedX
	record.RoomCellZ = resolvedZ
	record.RoomLevel = resolvedLevel
	return resolvedX, resolvedZ, resolvedLevel
end

local function resolveRoomForRecord(record: BreakableRecord)
	local resolver = RoomResolver
	local player = record.Player
	if not resolver or not player then
		return nil
	end
	local cellX, cellZ, level = ensureRoomCell(record)
	if not cellX or not cellZ then
		return nil
	end
	return resolver(player, cellX, cellZ, level)
end

local function isRoomOccupied(player: Player?, roomKey: string?): boolean
	if not player or not roomKey or roomKey == "" then
		return false
	end
	local resolver = OccupancyResolver
	if not resolver then
		return false
	end
	local occupancy = resolver(player)
	if typeof(occupancy) ~= "table" then
		return false
	end
	local count = occupancy[roomKey]
	return typeof(count) == "number" and count > 0
end

local function clearBrokenAttributes(record: BreakableRecord)
	local model = record.Model
	if not model then
		return
	end
	model:SetAttribute("IsBroken", false)
	model:SetAttribute("BrokenSeverity", nil)
	model:SetAttribute("BrokenSeed", nil)
	model:SetAttribute("BrokenTimestamp", nil)
end

local function applyBrokenAttributes(record: BreakableRecord, severity: number)
	local model = record.Model
	if not model then
		return
	end
	model:SetAttribute("IsBroken", true)
	model:SetAttribute("BrokenSeverity", severity)
	model:SetAttribute("BrokenSeed", record.VisualSeed)
	model:SetAttribute("BrokenTimestamp", os.time())
end

local function disconnect(record: BreakableRecord)
	if record.Connection then
		record.Connection:Disconnect()
		record.Connection = nil
	end
end

local function cleanupRecord(record: BreakableRecord, reason: string)
	if record.ActiveChoreId and Bridge then
		Bridge.RemoveChore(record.ActiveChoreId, reason)
	end
	disconnect(record)
	clearBrokenAttributes(record)
	BreakablesByKey[record.Key] = nil
end

local function bindModelRemoval(record: BreakableRecord)
	disconnect(record)
	local model = record.Model
	if not model then
		return
	end
	record.Connection = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupRecord(record, "ObjectRemoved")
		end
	end)
end

local function computeReward(spec: { [string]: any }?, severity: number, profile: BreakProfile): number
	local baseCost = 400
	if typeof(spec) == "table" then
		local specCost = spec.Cost or spec.Price or spec.Value
		if typeof(specCost) == "number" and specCost > 0 then
			baseCost = specCost
		end
	end
	local raw = baseCost * profile.RewardMultiplier * math.clamp(severity, 0.2, 1)
	local reward = math.floor(raw + 0.5)
	reward = math.clamp(reward, profile.MinReward, profile.MaxReward)
	return reward
end

local function scheduleNext(record: BreakableRecord)
	record.NextBreakTime = os.clock() + computeIntervalSeconds(record.Profile)
end

local function attemptBreak(record: BreakableRecord)
	local bridge = Bridge
	local player = record.Player
	if not bridge or not player or not player.Parent then
		scheduleNext(record)
		return
	end

	local room = resolveRoomForRecord(record)
	if not room or not room.IsTenantRoom then
		scheduleNext(record)
		return
	end

	if not isRoomOccupied(player, room.RoomKey) then
		scheduleNext(record)
		return
	end

	local model = record.Model
	if not model or not model.Parent then
		scheduleNext(record)
		return
	end

	local worldPosition = getModelPosition(model)
	if not worldPosition then
		scheduleNext(record)
		return
	end

	local severity = RNG:NextNumber(record.Profile.SeverityMin, record.Profile.SeverityMax)
	local rewardAmount = computeReward(record.Spec, severity, record.Profile)
	local plotIndexValue = player:GetAttribute("OwnedPlotIndex")
	local plotIndex = if typeof(plotIndexValue) == "number" then plotIndexValue else record.PlotIndex
	local metadata = {
		PlacementKey = record.PlacementKey,
		ItemId = record.ItemId,
		ItemName = record.Spec.Name or record.ItemId,
		Severity = severity,
		VisualSeed = record.VisualSeed,
		PromptHoldSeconds = record.Profile.PromptHoldSeconds,
		RoomKey = room.RoomKey,
	}

	local choreId = bridge.SpawnRepairChore(player, {
		PlotIndex = plotIndex,
		WorldPosition = worldPosition,
		RewardAmount = rewardAmount,
		Metadata = metadata,
	})

	if not choreId then
		scheduleNext(record)
		return
	end

	record.State = "Broken"
	record.ActiveChoreId = choreId
	record.Severity = severity
	record.RewardAmount = rewardAmount
	record.Metadata = metadata
	ChoreIdToKey[choreId] = record.Key
	applyBrokenAttributes(record, severity)
end

local function tick()
	local now = os.clock()
	local processed = 0
	for _, record in pairs(BreakablesByKey) do
		if record.State == "Healthy" and now >= record.NextBreakTime then
			attemptBreak(record)
			processed += 1
			if processed >= (RepairConfig.MaxBreaksPerStep or 1) then
				break
			end
		end
	end
end

function RepairManager.RegisterModel(player: Player, spec: { [string]: any }?, model: Model)
	if not player or not model then
		return
	end

	if not shouldTrackSpec(spec) then
		return
	end

	local placementKeyValue = model:GetAttribute("PlacementKey")
	if typeof(placementKeyValue) ~= "string" then
		return
	end

	local roomCellX, roomCellZ, roomLevel = resolveSampleCell(model, spec)

	local key = makeKey(player.UserId, placementKeyValue)
	local existing = BreakablesByKey[key]
	if existing then
		existing.Player = player
		existing.Model = model
		existing.Spec = spec or existing.Spec
		existing.PlotIndex = resolvePlayerPlotIndex(player, existing.PlotIndex)
		existing.ItemId = tostring(model:GetAttribute("ItemId") or existing.ItemId)
		existing.RoomCellX = roomCellX
		existing.RoomCellZ = roomCellZ
		existing.RoomLevel = roomLevel
		bindModelRemoval(existing)
		if existing.State == "Broken" then
			applyBrokenAttributes(existing, existing.Severity)
		end
		return
	end

	local profile = resolveProfile(spec)
	local record: BreakableRecord = {
		Key = key,
		Player = player,
		UserId = player.UserId,
		PlotIndex = resolvePlayerPlotIndex(player, 0),
		PlacementKey = placementKeyValue,
		ItemId = tostring(model:GetAttribute("ItemId") or (spec and spec.Name) or placementKeyValue),
		Spec = spec or {},
		Model = model,
		Profile = profile,
		State = "Healthy",
		NextBreakTime = os.clock() + computeIntervalSeconds(profile),
		ActiveChoreId = nil,
		Severity = 0,
		RewardAmount = 0,
		VisualSeed = RNG:NextInteger(1, 1_000_000),
		Metadata = nil,
		Connection = nil,
		RoomCellX = roomCellX,
		RoomCellZ = roomCellZ,
		RoomLevel = roomLevel,
	}

	BreakablesByKey[key] = record
	bindModelRemoval(record)
end

function RepairManager.HandlePlacementRemoved(player: Player, placementKey: string?)
	if not player or typeof(placementKey) ~= "string" then
		return
	end
	local key = makeKey(player.UserId, placementKey)
	local record = BreakablesByKey[key]
	if record then
		cleanupRecord(record, "ObjectRemoved")
	end
end

function RepairManager.HandleRepairCompletion(
	player: Player,
	choreRecord: { [string]: any }
): (boolean, string, number?)
	local metadata = choreRecord.Metadata
	local placementKey = metadata and metadata.PlacementKey
	if typeof(placementKey) ~= "string" then
		return false, "Broken target missing", nil
	end

	local key = makeKey(player.UserId, placementKey)
	local record = BreakablesByKey[key]
	if not record or record.State ~= "Broken" then
		return false, "Already repaired", nil
	end

	local distanceLimit = math.max(4, record.Profile.CompletionDistance)
	local worldPosition = getModelPosition(record.Model) or metadata.WorldPosition
	local character = player.Character
	local root = character and character.PrimaryPart
	if worldPosition and root then
		if (root.Position - worldPosition).Magnitude > distanceLimit then
			return false, "Get closer to the item", nil
		end
	end

	record.State = "Healthy"
	record.ActiveChoreId = nil
	record.Severity = 0
	record.Metadata = nil
	clearBrokenAttributes(record)
	scheduleNext(record)

	return true, "Item repaired!", record.RewardAmount
end

function RepairManager.NotifyChoreRemoved(choreId: string, reason: string)
	local key = ChoreIdToKey[choreId]
	if not key then
		return
	end
	ChoreIdToKey[choreId] = nil
	local record = BreakablesByKey[key]
	if not record then
		return
	end
	record.ActiveChoreId = nil
	if reason ~= "Completed" and record.State == "Broken" then
		record.State = "Healthy"
		record.Severity = 0
		record.Metadata = nil
		clearBrokenAttributes(record)
		scheduleNext(record)
	end
end

function RepairManager.Configure(bridge: ChoreBridge)
	Bridge = bridge
	if not UpdateBound then
		UpdateBound = true
		WorldUpdate.Subscribe("RepairManager::Tick", RepairConfig.UpdateIntervalSeconds, function()
			tick()
		end)
	end

	if not PLAYER_CLEANUP_BOUND then
		PLAYER_CLEANUP_BOUND = true
		Players.PlayerRemoving:Connect(function(player)
			for _, record in pairs(BreakablesByKey) do
				if record.UserId == player.UserId then
					record.Player = nil
					cleanupRecord(record, "PlayerLeaving")
				end
			end
		end)
	end
end

function RepairManager.SetRoomResolver(resolver: (player: Player, cellX: number, cellZ: number, level: number?) -> any)
	RoomResolver = resolver
end

function RepairManager.SetOccupancyResolver(resolver: (player: Player) -> { [string]: number }?)
	OccupancyResolver = resolver
end

return RepairManager
