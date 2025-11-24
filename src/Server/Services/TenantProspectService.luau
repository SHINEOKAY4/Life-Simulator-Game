--!strict
-- Server/Services/TenantProspectService.luau
-- Manages roaming tenant prospects per plot and routes accept/decline decisions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local TenantService = require(ServerScriptService.Server.Services.TenantService) :: any
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)
local WorldUpdate = require(ServerScriptService.Server.Utilities.WorldUpdate)
local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local MAX_PROSPECTS = 4
local TARGET_ATTRIBUTE_NAMES = {
	"TenantProspectTarget1",
	"TenantProspectTarget2",
	"TenantProspectTarget3",
	"TenantProspectTarget4",
}
local ROAM_MIN_SECONDS = 4
local ROAM_MAX_SECONDS = 9
local SPAWN_DELAY_MIN = 35
local SPAWN_DELAY_MAX = 80
local PROSPECT_LIFETIME = 210
local EXIT_WALK_SECONDS = 3
local UPDATE_TASK_NAME = "TenantProspects"
local TARGET_ATTRIBUTE_EPSILON = 0.25
local ESCORT_TIMEOUT_SECONDS = 80
local ESCORT_TARGET_REFRESH = 0.35

local rng = Random.new()

type TenantOffer = {
	OfferId: string,
	TierId: string,
	RentPerInterval: number,
	RentIntervalSeconds: number,
	LeaseSeconds: number,
	Deposit: number,
	TenantName: string?,
	RentBoostPercent: number?,
	Traits: { string }?,
}

export type ProspectRecord = {
	Id: string,
	Slot: number,
	Player: Player,
	Part: Part,
	Offer: TenantOffer,
	CreatedUnix: number,
	ExpireUnix: number,
	NextMoveUnix: number,
	TargetPosition: Vector3,
	ClickConnection: RBXScriptConnection?,
	SpawnCFrame: CFrame,
	Leaving: boolean,
	ExitDeadline: number,
	ExitReason: string?,
	EscortPlayer: Player?,
	EscortDeadline: number,
}

export type PlayerProspectState = {
	Player: Player,
	Prospects: { ProspectRecord? },
	NextSpawnUnix: { number },
	ResidentsFolder: Folder?,
	LastTargetAttributes: { Vector3? },
	PlotModel: Model?,
	SpawnPoints: { CFrame },
	RoamCenter: Vector3?,
	RoamForward: Vector3?,
	RoamRight: Vector3?,
	RoamForwardRadius: number,
	RoamRightRadius: number,
}

local TenantProspectService = {}
local TrackedPlayers: { [number]: PlayerProspectState } = {}
local ProspectPool: { Part } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function getProspectPart(): Part
	local pooled = table.remove(ProspectPool)
	if pooled then
		return pooled
	end

	local part = Instance.new("Part")
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Size = Vector3.new(2, 5, 2)
	part.Transparency = 1
	return part
end

local function returnProspectPart(part: Part)
	part.Parent = nil
	table.insert(ProspectPool, part)
end

local function randomBetween(minValue: number, maxValue: number): number
	return minValue + rng:NextNumber() * (maxValue - minValue)
end

local function chooseSpawnCFrame(points: { CFrame }): CFrame?
	local count = #points
	if count == 0 then
		return nil
	end
	if count == 1 then
		return points[1]
	end
	local index = rng:NextInteger(1, count)
	return points[index]
end

local function ensureResidentsFolder(plotModel: Model?): Folder?
	if not plotModel then
		return nil
	end
	local existing = plotModel:FindFirstChild("Residents")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "Residents"
	folder.Parent = plotModel
	return folder
end

local function computeHorizontalUnit(vector: Vector3, fallback: Vector3): Vector3
	local horizontal = Vector3.new(vector.X, 0, vector.Z)
	if horizontal.Magnitude < 1e-3 then
		local fallbackHorizontal = Vector3.new(fallback.X, 0, fallback.Z)
		if fallbackHorizontal.Magnitude < 1e-3 then
			return Vector3.new(0, 0, -1)
		end
		return fallbackHorizontal.Unit
	end
	return horizontal.Unit
end

local function resolveSpawnPoints(plotModel: Model?): ({ CFrame }, Vector3?, Vector3?, Vector3?, number, number)
	local spawnPoints = {} :: { CFrame }
	if not plotModel then
		return spawnPoints, nil, nil, nil, 0, 0
	end

	-- Collect spawn points
	for _, name in ipairs({ "SpawnA", "SpawnB" }) do
		local part = plotModel:FindFirstChild(name)
		if part and part:IsA("BasePart") then
			table.insert(spawnPoints, part.CFrame)
		end
	end

	if #spawnPoints == 0 then
		local spawn = plotModel:FindFirstChild("Spawn")
		if spawn and spawn:IsA("BasePart") then
			table.insert(spawnPoints, spawn.CFrame)
		end
	end

	if #spawnPoints == 0 then
		local surface = plotModel:FindFirstChild("Surface")
		if surface and surface:IsA("BasePart") then
			table.insert(spawnPoints, CFrame.new(surface.Position + surface.CFrame.UpVector * 4))
		end
	end

	if #spawnPoints == 0 then
		return spawnPoints, nil, nil, nil, 0, 0
	end

	-- Calculate center
	local positionAccumulator = Vector3.zero
	for _, cf in ipairs(spawnPoints) do
		positionAccumulator += cf.Position
	end
	local center = positionAccumulator / #spawnPoints

	-- Calculate orientation basis
	local forward
	local forwardRadius, rightRadius = 6, 4

	if #spawnPoints >= 2 then
		local diff = spawnPoints[2].Position - spawnPoints[1].Position
		forward = computeHorizontalUnit(diff, spawnPoints[1].LookVector)

		local separation = Vector3.new(diff.X, 0, diff.Z).Magnitude
		forwardRadius = math.max(3, separation * 0.25)
		rightRadius = math.max(3, forwardRadius * 0.5)
	else
		forward = computeHorizontalUnit(spawnPoints[1].LookVector, Vector3.new(0, 0, -1))
	end

	local up = Vector3.yAxis
	local rightCandidate = up:Cross(forward)
	if rightCandidate.Magnitude < 1e-3 then
		rightCandidate = Vector3.xAxis
	end
	local right = rightCandidate.Unit

	return spawnPoints, center, forward, right, forwardRadius, rightRadius
end

local function setTargetAttribute(state: PlayerProspectState, slot: number, position: Vector3?)
	local folder = state.ResidentsFolder
	local attrName = TARGET_ATTRIBUTE_NAMES[slot]
	if not folder or not attrName then
		return
	end
	local lastTargets = state.LastTargetAttributes
	if not lastTargets then
		local newTargets = {} :: { Vector3? }
		state.LastTargetAttributes = newTargets
		lastTargets = newTargets
	end

	local last = lastTargets[slot]
	if position then
		if last and (last - position).Magnitude <= TARGET_ATTRIBUTE_EPSILON then
			return
		end
		lastTargets[slot] = position
		folder:SetAttribute(attrName, position)
	else
		if last == nil then
			return
		end
		lastTargets[slot] = nil
		folder:SetAttribute(attrName, nil)
	end
end

local function pickRoamTarget(state: PlayerProspectState): Vector3?
	local center = state.RoamCenter
	local forward = state.RoamForward
	local right = state.RoamRight
	local forwardRadius = state.RoamForwardRadius
	local rightRadius = state.RoamRightRadius

	if not center then
		local firstSpawn = state.SpawnPoints[1]
		if not firstSpawn then
			return nil
		end
		center = firstSpawn.Position
		local computedForward = computeHorizontalUnit(firstSpawn.LookVector, Vector3.new(0, 0, -1))
		local up = Vector3.new(0, 1, 0)
		local rightCandidate = up:Cross(computedForward)
		if rightCandidate.Magnitude < 1e-3 then
			rightCandidate = Vector3.new(1, 0, 0)
		end
		forward = computedForward
		right = rightCandidate.Unit
		forwardRadius = 6
		rightRadius = 4
	end

	local finalCenter = center or Vector3.zero
	local finalForward = forward or Vector3.new(0, 0, -1)
	if finalForward.Magnitude > 1e-3 then
		finalForward = finalForward.Unit
	end
	local finalRight = right or Vector3.new(1, 0, 0)
	if finalRight.Magnitude > 1e-3 then
		finalRight = finalRight.Unit
	end
	local finalForwardRadius = if forwardRadius > 0 then forwardRadius else 6
	local finalRightRadius = if rightRadius > 0 then rightRadius else 4

	local forwardOffset = rng:NextNumber(-finalForwardRadius * 0.6, finalForwardRadius * 0.6)
	local lateralOffset = rng:NextNumber(-finalRightRadius * 0.6, finalRightRadius * 0.6)
	local height = rng:NextNumber(1.5, 2.5)
	return finalCenter + finalForward * forwardOffset + finalRight * lateralOffset + Vector3.new(0, height, 0)
end

local function finalizeProspectRemoval(state: PlayerProspectState, slot: number, record: ProspectRecord, reason: string)
	if state.Prospects[slot] == record then
		state.Prospects[slot] = nil
	end
	if record.ClickConnection then
		record.ClickConnection:Disconnect()
		record.ClickConnection = nil
	end

	setTargetAttribute(state, slot, nil)

	if record.Part then
		returnProspectPart(record.Part)
	end

	TenantPackets.ProspectRemoved:FireClient(state.Player, {
		ProspectId = record.Id,
		Slot = record.Slot,
		Reason = reason,
	})
	state.NextSpawnUnix[slot] = serverNow() + randomBetween(SPAWN_DELAY_MIN, SPAWN_DELAY_MAX)
end

local function destroyProspect(state: PlayerProspectState, slot: number, reason: string, skipExit: boolean?)
	local record = state.Prospects[slot]
	if not record then
		return
	end
	record.EscortPlayer = nil
	if skipExit then
		finalizeProspectRemoval(state, slot, record, reason)
		return
	end
	if record.Leaving then
		record.ExitReason = record.ExitReason or reason
		return
	end
	record.Leaving = true
	record.ExitReason = reason
	record.ExitDeadline = serverNow() + EXIT_WALK_SECONDS
	record.NextMoveUnix = record.ExitDeadline + 5
	if record.ClickConnection then
		record.ClickConnection:Disconnect()
		record.ClickConnection = nil
	end
	local clickDetector = record.Part:FindFirstChildOfClass("ClickDetector")
	if clickDetector then
		clickDetector.MaxActivationDistance = 0
	end
	if record.Part.Parent then
		record.Part:PivotTo(record.SpawnCFrame)
	end
	local spawnPosition = record.SpawnCFrame.Position
	record.TargetPosition = spawnPosition
	setTargetAttribute(state, slot, spawnPosition)
end

local function buildProspectSpawnPayload(record: ProspectRecord)
	return {
		ProspectId = record.Id,
		Slot = record.Slot,
		Name = record.Offer.TenantName or "Tenant",
		TierId = record.Offer.TierId,
		RentPerInterval = record.Offer.RentPerInterval,
		RentIntervalSeconds = record.Offer.RentIntervalSeconds,
		Deposit = record.Offer.Deposit,
		LeaseSeconds = 0,
		RentBoostPercent = record.Offer.RentBoostPercent or 0,
		Traits = record.Offer.Traits or {},
	}
end

local function spawnProspect(state: PlayerProspectState, slot: number)
	local player = state.Player
	local offer = TenantService.GenerateProspectOffer(player)
	if not offer then
		state.NextSpawnUnix[slot] = serverNow() + 10
		return
	end
	local residentsFolder = state.ResidentsFolder
	if not residentsFolder then
		state.NextSpawnUnix[slot] = serverNow() + 10
		return
	end
	local spawnCFrame = chooseSpawnCFrame(state.SpawnPoints)
	if not spawnCFrame then
		state.NextSpawnUnix[slot] = serverNow() + 10
		return
	end

	local part = getProspectPart()
	part.Name = string.format("TenantProspectSlot%d", slot)
	part.CFrame = spawnCFrame
	part.Parent = residentsFolder

	local now = serverNow()
	local targetPosition = spawnCFrame.Position
	local record: ProspectRecord = {
		Id = offer.OfferId,
		Slot = slot,
		Player = player,
		Part = part,
		Offer = offer,
		CreatedUnix = now,
		ExpireUnix = now + PROSPECT_LIFETIME,
		NextMoveUnix = now + randomBetween(ROAM_MIN_SECONDS, ROAM_MAX_SECONDS),
		TargetPosition = targetPosition,
		ClickConnection = nil,
		SpawnCFrame = spawnCFrame,
		Leaving = false,
		ExitDeadline = 0,
		ExitReason = nil,
		EscortPlayer = nil,
		EscortDeadline = 0,
	}

	state.Prospects[slot] = record
	setTargetAttribute(state, slot, targetPosition)
	TenantPackets.ProspectSpawn:FireClient(player, buildProspectSpawnPayload(record))
end

local function ensureStateForPlayer(player: Player): PlayerProspectState
	local userId = player.UserId
	local state = TrackedPlayers[userId]
	if state then
		return state
	end
	local newState: PlayerProspectState = {
		Player = player,
		Prospects = table.create(MAX_PROSPECTS),
		NextSpawnUnix = table.create(MAX_PROSPECTS),
		ResidentsFolder = nil,
		LastTargetAttributes = table.create(MAX_PROSPECTS),
		PlotModel = nil,
		SpawnPoints = {},
		RoamCenter = nil,
		RoamForward = nil,
		RoamRight = nil,
		RoamForwardRadius = 0,
		RoamRightRadius = 0,
	}
	for slot = 1, MAX_PROSPECTS do
		newState.NextSpawnUnix[slot] = serverNow() + randomBetween(SPAWN_DELAY_MIN, SPAWN_DELAY_MAX)
	end
	TrackedPlayers[userId] = newState
	return newState
end

local function refreshPlotContext(state: PlayerProspectState)
	local player = state.Player
	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if type(plotIndex) ~= "number" then
		state.PlotModel = nil
		state.ResidentsFolder = nil
		state.SpawnPoints = {}
		state.RoamCenter = nil
		state.RoamForward = nil
		state.RoamRight = nil
		state.RoamForwardRadius = 0
		state.RoamRightRadius = 0
		return
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return
	end
	state.PlotModel = plotModel
	state.ResidentsFolder = ensureResidentsFolder(plotModel)
	local spawnPoints, center, forward, right, forwardRadius, rightRadius = resolveSpawnPoints(plotModel)
	state.SpawnPoints = spawnPoints
	state.RoamCenter = center
	state.RoamForward = forward
	state.RoamRight = right
	state.RoamForwardRadius = forwardRadius
	state.RoamRightRadius = rightRadius
end

local function cleanupPlayer(userId: number)
	local state = TrackedPlayers[userId]
	if not state then
		return
	end
	for slot = 1, MAX_PROSPECTS do
		destroyProspect(state, slot, "Cleanup", true)
	end
	TrackedPlayers[userId] = nil
end

local function moveProspect(state: PlayerProspectState, record: ProspectRecord, now: number)
	if record.EscortPlayer then
		return
	end
	if record.Leaving then
		return
	end
	local target = pickRoamTarget(state)
	if not target then
		return
	end
	record.TargetPosition = target
	record.Part:PivotTo(CFrame.new(target + Vector3.new(0, record.Part.Size.Y * 0.5, 0)))
	record.NextMoveUnix = now + randomBetween(ROAM_MIN_SECONDS, ROAM_MAX_SECONDS)
	setTargetAttribute(state, record.Slot, target)
end

local function steerEscortProspect(state: PlayerProspectState, record: ProspectRecord, now: number)
	local escortPlayer = record.EscortPlayer
	if not escortPlayer then
		return
	end
	if not escortPlayer.Parent then
		destroyProspect(state, record.Slot, "EscortCancelled")
		return
	end
	if now >= record.EscortDeadline then
		destroyProspect(state, record.Slot, "EscortTimeout")
		return
	end
	local character = escortPlayer.Character
	local rootPart = character and character.PrimaryPart
	if not rootPart then
		return
	end
	record.TargetPosition = rootPart.Position
	setTargetAttribute(state, record.Slot, record.TargetPosition)
	record.NextMoveUnix = now + ESCORT_TARGET_REFRESH
	record.EscortDeadline = now + ESCORT_TIMEOUT_SECONDS
end

local function onStep(_dt: number)
	local now = serverNow()
	for userId, state in pairs(TrackedPlayers) do
		local player = state.Player
		if not player.Parent then
			cleanupPlayer(userId)
			continue
		end
		if not state.ResidentsFolder or (#state.SpawnPoints == 0 and state.RoamCenter == nil) then
			refreshPlotContext(state)
		end
		for slot = 1, MAX_PROSPECTS do
			local record = state.Prospects[slot]
			if record then
				if record.Leaving then
					if now >= record.ExitDeadline then
						destroyProspect(state, slot, record.ExitReason or "Removed", true)
					end
				elseif record.EscortPlayer then
					steerEscortProspect(state, record, now)
				elseif now >= record.ExpireUnix then
					destroyProspect(state, slot, "Expired")
				elseif now >= record.NextMoveUnix then
					moveProspect(state, record, now)
				end
			else
				if now >= state.NextSpawnUnix[slot] then
					spawnProspect(state, slot)
				end
			end
		end
	end
end

local function canAcceptTenant(player: Player): (boolean, string?)
	local totalRooms, availableRooms, reason = TenantService.GetRoomAvailabilityReport(player)
	if totalRooms <= 0 then
		return false, reason or "Build an enclosed bedroom with a bed before inviting tenants."
	end
	if availableRooms <= 0 then
		return false, "All tenant rooms are occupied. Add another tenant-ready room or free one up."
	end
	return true
end

local function acceptProspect(player: Player, record: ProspectRecord, requestedRoomKey: string?): (boolean, string)
	local prospectSpawnCFrame = record.Part.CFrame
	local desiredName = record.Offer.TenantName or "Tenant"

	local existing = ResidentService.GetResidents(player)
	local candidateName = desiredName
	local nameIndex = 1
	while existing and existing[candidateName] do
		nameIndex += 1
		candidateName = string.format("%s %d", desiredName, nameIndex)
	end

	local residentData = {
		Name = candidateName,
		Traits = { "Balanced" },
		Needs = {
			Hunger = 100,
			Bladder = 100,
			Energy = 100,
			Hygiene = 100,
			Fun = 100,
			Social = 100,
		},
	}

	local created, createMessage = ResidentService.CreateResident(player, residentData, prospectSpawnCFrame)
	if not created then
		return false, createMessage or "Unable to add tenant as resident."
	end

	local leaseStarted, leaseMessage, tenantId =
		TenantService.BeginLeaseFromOffer(player, record.Offer, requestedRoomKey)
	if not leaseStarted then
		ResidentService.DeleteResident(player, residentData.Name)
		-- Check if it's a "room full" error - return special message to keep escort active
		if leaseMessage and string.find(string.lower(leaseMessage), "full") then
			return false, "RoomFull:" .. (leaseMessage or "")
		end
		return false, leaseMessage or "Unable to start lease."
	end

	if tenantId then
		ResidentService.SetResidentTenantData(player, residentData.Name, tenantId)
	end

	return true, "Tenant joined your household!"
end

local function onDecision(player: Player, prospectId: string, decision: string, roomKey: string?): (boolean, string)
	local state = ensureStateForPlayer(player)
	local targetSlot = nil
	local record: ProspectRecord? = nil
	for slot = 1, MAX_PROSPECTS do
		local candidate = state.Prospects[slot]
		if candidate and candidate.Id == prospectId then
			targetSlot = slot
			record = candidate
			break
		end
	end
	if not targetSlot or not record then
		return false, "This tenant already left."
	end

	local lowerDecision = string.lower(decision)
	if lowerDecision == "accept" then
		if record.EscortPlayer then
			print(
				string.format(
					"[TenantProspect] Escort room submission: Player=%s, RoomKey=%s",
					player.Name,
					tostring(roomKey)
				)
			)
			if record.EscortPlayer ~= player then
				return false, "This tenant is already following someone."
			end
			local resolvedRoomKey = if typeof(roomKey) == "string" and roomKey ~= "" then roomKey else nil
			if not resolvedRoomKey then
				return false, "Walk them into a finished room to finalize."
			end
			print(string.format("[TenantProspect] Calling acceptProspect for room: %s", resolvedRoomKey))
			local success, msg = acceptProspect(player, record, resolvedRoomKey)
			print(
				string.format(
					"[TenantProspect] acceptProspect result: success=%s, msg=%s",
					tostring(success),
					tostring(msg)
				)
			)
			if success then
				destroyProspect(state, targetSlot, "Accepted", true)
				return true, msg
			end
			-- Check if it's a "room full" error - keep escort active
			if msg and string.find(msg, "RoomFull:") then
				print("[TenantProspect] Detected RoomFull error, keeping escort active")
				local cleanMessage = string.gsub(msg, "RoomFull:", "")
				return false, cleanMessage ~= "" and cleanMessage or "That room is full. Try a different room."
			end
			-- Other errors - cancel escort
			print("[TenantProspect] Non-RoomFull error, canceling escort")
			return false, msg or "Failed to assign room."
		end

		local canAccept, reason = canAcceptTenant(player)
		if not canAccept then
			return false, reason or "Cannot accept tenant."
		end

		record.EscortPlayer = player
		record.EscortDeadline = serverNow() + ESCORT_TIMEOUT_SECONDS
		record.NextMoveUnix = 0
		record.TargetPosition = player.Character
				and player.Character.PrimaryPart
				and player.Character.PrimaryPart.Position
			or record.TargetPosition
		setTargetAttribute(state, record.Slot, record.TargetPosition)
		return true, "EscortStart"
	elseif lowerDecision == "decline" then
		destroyProspect(state, targetSlot, "Declined")
		return true, "You declined the tenant."
	end

	return false, "Unknown decision."
end

function TenantProspectService.Init()
	PlotService.PlotClaimed:Connect(function(player: Player)
		local state = ensureStateForPlayer(player)
		if state then
			refreshPlotContext(state)
		end
	end)

	PlotService.PlotUnclaimed:Connect(function(player: Player)
		cleanupPlayer(player.UserId)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		cleanupPlayer(player.UserId)
	end)

	TenantPackets.ProspectDecision.OnServerInvoke = function(
		player: Player,
		prospectId: string,
		decision: string,
		roomKey: string
	)
		return onDecision(player, prospectId, decision, roomKey)
	end

	WorldUpdate.Subscribe(UPDATE_TASK_NAME, 1, onStep)
end

return TenantProspectService
