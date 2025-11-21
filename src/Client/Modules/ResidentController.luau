--!strict
-- Client/Modules/ResidentController.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)
local ClientResidentPlacer = require(script.Parent.ClientResidentPlacer)
local ClientResidentMovement = require(script.Parent.ClientResidentMovement)
local ResidentReactions = require(script.Parent.ResidentReactions)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)

local ResidentController = {}

type ResidentState = {
	OwnerUserId: number,
	Model: Model,
	Data: any,
	CurrentAction: string?,
	ActionThread: thread?,
	CancelToken: ClientResidentMovement.CancelToken?,
}

local ClientResidents: { [number]: { [string]: ResidentState } } = {} -- [userId][residentName] = State
local LocalPlayer = Players.LocalPlayer
local LOCAL_USER_ID = if LocalPlayer then LocalPlayer.UserId else 0

local function applyModelMetadata(model: Model?, data: any)
	if not model or typeof(data) ~= "table" then
		return
	end

	local nameValue = data.Name
	if type(nameValue) == "string" and nameValue ~= "" then
		model.Name = nameValue
		model:SetAttribute("ResidentName", nameValue)
	end

	local tenantIdValue = data.TenantId
	if type(tenantIdValue) == "string" and tenantIdValue ~= "" then
		model:SetAttribute("TenantId", tenantIdValue)
	else
		model:SetAttribute("TenantId", nil)
	end
end

local function stopResidentAction(state: ResidentState)
	if state.CancelToken then
		state.CancelToken.Cancelled = true
	end
	state.CancelToken = nil
	state.CurrentAction = nil
	state.ActionThread = nil
end

local function chunkIndexToCoord(chunkIndex: number, chunkColumns: number): (number, number)
	local zeroBased = chunkIndex - 1
	local chunkX = (zeroBased % chunkColumns) + 1
	local chunkZ = math.floor(zeroBased / chunkColumns) + 1
	return chunkX, chunkZ
end

local function findNearestUnlockedChunk(
	targetChunkX: number,
	targetChunkZ: number,
	chunkColumns: number,
	chunkUnlocked: { [number]: boolean }
): (number?, number?)
	local bestChunkX: number? = nil
	local bestChunkZ: number? = nil
	local bestDistSq = math.huge
	for index = 1, #chunkUnlocked do
		if chunkUnlocked[index] == true then
			local unlockedChunkX, unlockedChunkZ = chunkIndexToCoord(index, chunkColumns)
			local dx = unlockedChunkX - targetChunkX
			local dz = unlockedChunkZ - targetChunkZ
			local distSq = dx * dx + dz * dz
			if distSq < bestDistSq then
				bestDistSq = distSq
				bestChunkX = unlockedChunkX
				bestChunkZ = unlockedChunkZ
			end
		end
	end
	return bestChunkX, bestChunkZ
end

local function restrictTargetToUnlocked(userId: number?, desiredWorld: Vector3): Vector3?
	if userId ~= LOCAL_USER_ID then
		return nil
	end
	if not PlotStateStore.IsReady() then
		return nil
	end
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return nil
	end
	local snapshot = PlotStateStore.GetStateSnapshot()
	local chunkInfo = snapshot.ChunkInfo
	local chunkUnlocked = snapshot.ChunkUnlocked
	if not chunkInfo or not chunkUnlocked then
		return nil
	end
	local chunkSize = tonumber(chunkInfo.ChunkSizeInCells)
	local chunkColumns = tonumber(chunkInfo.ChunkColumns)
	local chunkRows = tonumber(chunkInfo.ChunkRows)
	if not chunkSize or chunkSize <= 0 or not chunkColumns or chunkColumns <= 0 or not chunkRows or chunkRows <= 0 then
		return nil
	end

	local inBounds, cellX, cellZ = grid:WorldPointToCell(desiredWorld)
	if not inBounds then
		cellX, cellZ = grid:WorldPointToClampedCell(desiredWorld)
	end
	local chunkX, chunkZ = grid:CellToChunk(cellX, cellZ, chunkSize)
	if chunkX >= 1 and chunkX <= chunkColumns and chunkZ >= 1 and chunkZ <= chunkRows then
		local chunkIndex = (chunkZ - 1) * chunkColumns + chunkX
		if chunkUnlocked[chunkIndex] == true then
			return grid:CellToWorldCenter(cellX, cellZ)
		end
	end

	local fallbackChunkX, fallbackChunkZ = findNearestUnlockedChunk(chunkX, chunkZ, chunkColumns, chunkUnlocked)
	if not fallbackChunkX or not fallbackChunkZ then
		return nil
	end

	local minCellX = (fallbackChunkX - 1) * chunkSize + 1
	local maxCellX = minCellX + chunkSize - 1
	local minCellZ = (fallbackChunkZ - 1) * chunkSize + 1
	local maxCellZ = minCellZ + chunkSize - 1

	local clampedCellX = math.clamp(cellX, minCellX, maxCellX)
	local clampedCellZ = math.clamp(cellZ, minCellZ, maxCellZ)
	local centerPos = grid:CellToWorldCenter(clampedCellX, clampedCellZ)
	local jitterRange = math.min((grid.CellSize or 0) * 0.25, 2)
	if jitterRange > 0 then
		local jitter = Vector3.new((math.random() * 2 - 1) * jitterRange, 0, (math.random() * 2 - 1) * jitterRange)
		return centerPos + jitter
	end
	return centerPos
end

local function computeWanderTarget(state: ResidentState, origin: Vector3): Vector3
	local randomOffset = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
	local desired = origin + randomOffset
	local restricted = restrictTargetToUnlocked(state.OwnerUserId, desired)
	if restricted then
		return restricted
	end
	return desired
end

local function startWanderLoop(state: ResidentState)
	if state.ActionThread then
		return
	end

	state.CancelToken = { Cancelled = false, Reason = nil }
	local token = state.CancelToken
	if not token then
		return
	end

	state.ActionThread = task.spawn(function()
		while not token.Cancelled do
			if not state.Model or not state.Model.Parent then
				break
			end

			-- Simple wander logic
			local root = state.Model:FindFirstChild("HumanoidRootPart") :: BasePart
			if root then
				local origin = root.Position
				local target = computeWanderTarget(state, origin)

				ClientResidentMovement.GoToWorldPosition(state.Model, target, {
					CancelToken = token,
					TimeoutSeconds = 10,
				})
			end

			if token.Cancelled then
				break
			end
			task.wait(math.random(3, 8))
		end
	end)
end

local function onResidentDelta(userId: number, residentName: string, deltaList: { any })
	if not ClientResidents[userId] then
		ClientResidents[userId] = {}
	end

	local residentsMap = ClientResidents[userId]

	-- If deltaList is empty, it's a deletion
	if #deltaList == 0 then
		local existing = residentsMap[residentName]
		if existing then
			stopResidentAction(existing)
			if existing.Model then
				ResidentReactions.Unregister(existing.Model)
				ClientResidentPlacer.Despawn(existing.Model)
			end
			residentsMap[residentName] = nil
		end
		return
	end

	-- Otherwise it's an update or creation
	for _, data in ipairs(deltaList) do
		local existing = residentsMap[residentName]
		if not existing then
			-- Create new
			local model = ClientResidentPlacer.Spawn(userId, data)
			if model then
				local state = {
					OwnerUserId = userId,
					Model = model,
					Data = data,
				}
				applyModelMetadata(model, data)
				residentsMap[residentName] = state
				ResidentReactions.Register(model)
				startWanderLoop(state)
			end
		else
			existing.OwnerUserId = existing.OwnerUserId or userId
			-- Update existing data
			existing.Data = data
			applyModelMetadata(existing.Model, data)
			-- If model is missing (e.g. streamed out), try to respawn?
			if not existing.Model or not existing.Model.Parent then
				local model = ClientResidentPlacer.Spawn(userId, data)
				if model then
					existing.Model = model
					applyModelMetadata(model, data)
					ResidentReactions.Register(model)
					startWanderLoop(existing)
				end
			end
		end
	end
end

local function onResidentsSync(payload: any)
	local userId = payload.UserId
	local newResidentsList = payload.Residents

	if not ClientResidents[userId] then
		ClientResidents[userId] = {}
	end

	local residentsMap = ClientResidents[userId]
	local newNames = {}

	-- Sync incoming
	for _, data in ipairs(newResidentsList) do
		local name = data.Name
		newNames[name] = true

		local existing = residentsMap[name]
		if not existing then
			local model = ClientResidentPlacer.Spawn(userId, data)
			if model then
				local state = {
					OwnerUserId = userId,
					Model = model,
					Data = data,
				}
				applyModelMetadata(model, data)
				residentsMap[name] = state
				ResidentReactions.Register(model)
				startWanderLoop(state)
			end
		else
			existing.OwnerUserId = existing.OwnerUserId or userId
			existing.Data = data
			applyModelMetadata(existing.Model, data)
			if not existing.Model or not existing.Model.Parent then
				local model = ClientResidentPlacer.Spawn(userId, data)
				if model then
					existing.Model = model
					applyModelMetadata(model, data)
					ResidentReactions.Register(model)
					startWanderLoop(existing)
				end
			end
		end
	end

	-- Remove stale
	for name, state in pairs(residentsMap) do
		if not newNames[name] then
			stopResidentAction(state)
			if state.Model then
				ResidentReactions.Unregister(state.Model)
				ClientResidentPlacer.Despawn(state.Model)
			end
			residentsMap[name] = nil
		end
	end
end

function ResidentController.Init()
	ResidentsPackets.PlayerResidentDelta.OnClientEvent:Connect(function(payload)
		onResidentDelta(payload.UserId, payload.ResidentName, payload.ResidentDelta)
	end)

	ResidentsPackets.PlayersResidentsSync.OnClientEvent:Connect(function(payload)
		onResidentsSync(payload)
	end)

	RunService.Heartbeat:Connect(function(dt)
		for _, residentsMap in pairs(ClientResidents) do
			for _, state in pairs(residentsMap) do
				if state.Model and state.Model.Parent then
					ResidentReactions.Update(state.Model, dt)
				end
			end
		end
	end)
end

return ResidentController
