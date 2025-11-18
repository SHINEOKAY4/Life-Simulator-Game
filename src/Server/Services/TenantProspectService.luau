--!strict
-- Server/Services/TenantProspectService.luau
-- Manages roaming tenant prospects per plot and routes accept/decline decisions.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
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
local UPDATE_TASK_NAME = "TenantProspects"

local rng = Random.new()

type TenantOffer = {
	OfferId: string,
	TierId: string,
	RentPerInterval: number,
	RentIntervalSeconds: number,
	LeaseSeconds: number,
	Deposit: number,
	TenantName: string?,
}

export type ProspectRecord = {
	Id: string,
	Slot: number,
	Player: Player,
	Part: BasePart,
	Offer: TenantOffer,
	CreatedUnix: number,
	ExpireUnix: number,
	NextMoveUnix: number,
	TargetPosition: Vector3,
	ClickConnection: RBXScriptConnection?,
}

export type PlayerProspectState = {
	Player: Player,
	Prospects: { ProspectRecord? },
	NextSpawnUnix: { number },
	ResidentsFolder: Folder?,
	PlotModel: Model?,
	SpawnCFrame: CFrame?,
}

local TenantProspectService = {}
local TrackedPlayers: { [number]: PlayerProspectState } = {}

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function randomBetween(minValue: number, maxValue: number): number
	return minValue + rng:NextNumber() * (maxValue - minValue)
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

local function resolveSpawnCFrame(plotModel: Model?): CFrame?
	if not plotModel then
		return nil
	end
	local spawnPart = plotModel:FindFirstChild("Spawn")
	if spawnPart and spawnPart:IsA("BasePart") then
		return spawnPart.CFrame
	end
	local surface = plotModel:FindFirstChild("Surface")
	if surface and surface:IsA("BasePart") then
		local up = surface.CFrame.UpVector
		return CFrame.new(surface.Position + up * 4)
	end
	return nil
end

local function setTargetAttribute(state: PlayerProspectState, slot: number, position: Vector3?)
	local folder = state.ResidentsFolder
	local attrName = TARGET_ATTRIBUTE_NAMES[slot]
	if not folder or not attrName then
		return
	end
	if position then
		folder:SetAttribute(attrName, position)
	else
		folder:SetAttribute(attrName, nil)
	end
end

local function pickRoamTarget(spawnCFrame: CFrame?): Vector3?
	if not spawnCFrame then
		return nil
	end
	local forward = spawnCFrame.LookVector
	local right = spawnCFrame.RightVector
	local origin = spawnCFrame.Position
	local forwardOffset = rng:NextNumber(4, 12)
	local lateralOffset = rng:NextNumber(-7, 7)
	local height = rng:NextNumber(1.5, 2.5)
	return origin + forward * forwardOffset + right * lateralOffset + Vector3.new(0, height, 0)
end

local function destroyProspect(state: PlayerProspectState, slot: number, reason: string)
	local record = state.Prospects[slot]
	if not record then
		return
	end
	state.Prospects[slot] = nil
	if record.ClickConnection then
		record.ClickConnection:Disconnect()
		record.ClickConnection = nil
	end
	record.Part:Destroy()
	setTargetAttribute(state, slot, nil)
	TenantPackets.ProspectRemoved:FireClient(state.Player, {
		ProspectId = record.Id,
		Slot = record.Slot,
		Reason = reason,
	})
	state.NextSpawnUnix[slot] = serverNow() + randomBetween(SPAWN_DELAY_MIN, SPAWN_DELAY_MAX)
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
	}
end

local function onProspectClicked(record: ProspectRecord)
	TenantPackets.ProspectPrompt:FireClient(record.Player, buildProspectSpawnPayload(record))
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
	local spawnCFrame = state.SpawnCFrame
	if not spawnCFrame then
		state.NextSpawnUnix[slot] = serverNow() + 10
		return
	end

	local part = Instance.new("Part")
	part.Name = string.format("TenantProspectSlot%d", slot)
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Size = Vector3.new(2, 5, 2)
	part.Transparency = 1
	part.CFrame = spawnCFrame
	part.Parent = residentsFolder

	local clickDetector = Instance.new("ClickDetector")
	clickDetector.MaxActivationDistance = 18
	clickDetector.CursorIcon = "rbxassetid://11828380792"
	clickDetector.Parent = part

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
	}

	record.ClickConnection = clickDetector.MouseClick:Connect(function(clickedPlayer: Player)
		if clickedPlayer ~= player then
			return
		end
		onProspectClicked(record)
	end)

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
		PlotModel = nil,
		SpawnCFrame = nil,
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
		state.SpawnCFrame = nil
		return
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return
	end
	state.PlotModel = plotModel
	state.ResidentsFolder = ensureResidentsFolder(plotModel)
	state.SpawnCFrame = resolveSpawnCFrame(plotModel)
end

local function cleanupPlayer(userId: number)
	local state = TrackedPlayers[userId]
	if not state then
		return
	end
	for slot = 1, MAX_PROSPECTS do
		destroyProspect(state, slot, "Cleanup")
	end
	TrackedPlayers[userId] = nil
end

local function moveProspect(state: PlayerProspectState, record: ProspectRecord, now: number)
	local spawnCFrame = state.SpawnCFrame
	if not spawnCFrame then
		return
	end
	local target = pickRoamTarget(spawnCFrame)
	if not target then
		return
	end
	record.TargetPosition = target
	record.Part:PivotTo(CFrame.new(target + Vector3.new(0, record.Part.Size.Y * 0.5, 0)))
	record.NextMoveUnix = now + randomBetween(ROAM_MIN_SECONDS, ROAM_MAX_SECONDS)
	setTargetAttribute(state, record.Slot, target)
end

local function onStep(_dt: number)
	local now = serverNow()
	for userId, state in pairs(TrackedPlayers) do
		local player = state.Player
		if not player.Parent then
			cleanupPlayer(userId)
			continue
		end
		if not state.SpawnCFrame then
			refreshPlotContext(state)
		end
		for slot = 1, MAX_PROSPECTS do
			local record = state.Prospects[slot]
			if record then
				if now >= record.ExpireUnix then
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

local function onDecision(player: Player, prospectId: string, decision: string): (boolean, string)
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
		local householdState = PlayerSession.TryGetData(player, "HouseholdState")
		if householdState and householdState.MaxResidents and householdState.ResidentsCount then
			if householdState.ResidentsCount >= householdState.MaxResidents then
				return false, "Household capacity reached."
			end
		end

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
			Age = 2,
			Gender = "Male",
			Traits = { "Balanced" },
			Statistics = {
				Intelligence = 1,
				Discipline = 1,
				Creativity = 1,
				Fitness = 1,
			},
			Needs = {
				Hunger = 100,
				Bladder = 100,
				Energy = 100,
				Hygiene = 100,
				Fun = 100,
				Social = 100,
			},
		}

		local created, createMessage = ResidentService.CreateResident(player, residentData)
		if not created then
			return false, createMessage or "Unable to add tenant as resident."
		end

		local leaseStarted, leaseMessage = TenantService.BeginLeaseFromOffer(player, record.Offer)
		if not leaseStarted then
			ResidentService.DeleteResident(player, residentData.Name)
			return false, leaseMessage or "Unable to start lease."
		end

		destroyProspect(state, targetSlot, "Accepted")
		return true, "Tenant joined your household!"
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

	TenantPackets.ProspectDecision.OnServerInvoke = function(player: Player, prospectId: string, decision: string)
		return onDecision(player, prospectId, decision)
	end

	WorldUpdate.Subscribe(UPDATE_TASK_NAME, 1, onStep)
end

return TenantProspectService
