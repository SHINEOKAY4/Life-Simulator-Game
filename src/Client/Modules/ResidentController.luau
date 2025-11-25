--!strict
-- Client/Modules/ResidentController.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)
local ClientResidentPlacer = require(script.Parent.ClientResidentPlacer)
local ClientResidentMovement = require(script.Parent.ClientResidentMovement)
local ResidentReactions = require(script.Parent.ResidentReactions)
local TenantRoomTracker = require(script.Parent.TenantRoomTracker)
local TenantProspectController = require(script.Parent.TenantProspectController)

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

-- Forward declaration
local startWanderLoop

local function resolveTenantId(data: any): string?
	local tenantId = data and data.TenantId
	if type(tenantId) == "string" and tenantId ~= "" then
		return tenantId
	end
	return nil
end

local function updateResidentData(state: ResidentState, newData: any)
	state.Data = newData
end

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

-- Move a tenant within their assigned room
local function startTenantRoomWander(state: ResidentState)
	local tenantId = resolveTenantId(state.Data)
	if not tenantId or state.OwnerUserId ~= LOCAL_USER_ID then
		return
	end

	stopResidentAction(state)

	local cancelToken = { Cancelled = false }
	state.CancelToken = cancelToken
	state.CurrentAction = "RoomWander"

	state.ActionThread = task.spawn(function()
		-- Wait for room data (max 5s)
		local maxAttempts = 10
		for attempt = 1, maxAttempts do
			if cancelToken.Cancelled then
				return
			end

			local roomTarget = TenantRoomTracker.GetRandomTargetForTenant(tenantId)
			if roomTarget then
				-- Room data available, start wandering
				while not cancelToken.Cancelled do
					local model = state.Model
					if not model or not model.Parent then
						break
					end

					roomTarget = TenantRoomTracker.GetRandomTargetForTenant(tenantId)
					if not roomTarget then
						break
					end

					ClientResidentMovement.GoToWorldPosition(model, roomTarget, {
						CancelToken = cancelToken,
						TimeoutSeconds = 10,
					})

					if not cancelToken.Cancelled then
						task.wait(math.random(3, 8))
					end
				end
				return
			end

			if attempt < maxAttempts then
				task.wait(0.5)
			end
		end
	end)
end

-- Non-tenant residents wander across unlocked chunks
function startWanderLoop(state: ResidentState)
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
			local model = state.Model
			if not model or not model.Parent then
				break
			end

			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
			if root then
				local origin = root.Position
				local randomOffset = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
				local target = origin + randomOffset

				ClientResidentMovement.GoToWorldPosition(model, target, {
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
			-- Create new - try to reuse prospect position for seamless transition
			local spawnCFrame: CFrame? = nil
			local tenantId = resolveTenantId(data)

			-- For tenants, get position from TenantProspectController (seamless handoff)
			if tenantId then
				-- TenantId matches ProspectId, so we can look it up
				local prospectPosition = TenantProspectController.GetProspectPosition(tenantId)
				if prospectPosition then
					spawnCFrame = prospectPosition
					-- Remove prospect model now that we have position
					TenantProspectController.RemoveProspect(tenantId)
				end
			end

			local model = ClientResidentPlacer.Spawn(userId, data, spawnCFrame)
			if model then
				local state = {
					OwnerUserId = userId,
					Model = model,
					Data = data,
				}
				applyModelMetadata(model, data)
				updateResidentData(state, data)
				residentsMap[residentName] = state
				ResidentReactions.Register(model)
				-- Tenants wander in their room, non-tenants wander plot
				if tenantId then
					startTenantRoomWander(state)
				else
					startWanderLoop(state)
				end
			end
		else
			existing.OwnerUserId = existing.OwnerUserId or userId
			-- Check if TenantId changed
			local oldTenantId = resolveTenantId(existing.Data)
			local newTenantId = resolveTenantId(data)
			local tenantIdChanged = oldTenantId ~= newTenantId
			-- Update existing data
			updateResidentData(existing, data)
			applyModelMetadata(existing.Model, data)
			-- If TenantId changed, restart wander behavior
			if tenantIdChanged then
				print(
					"[ResidentController] TenantId changed from",
					oldTenantId,
					"to",
					newTenantId,
					"for:",
					residentName
				)
				stopResidentAction(existing)

				-- If becoming a tenant, teleport to prospect position for seamless transition
				if newTenantId and not oldTenantId then
					print("[ResidentController] Resident becoming tenant, looking for prospect position:", newTenantId)
					local prospectPosition = TenantProspectController.GetProspectPosition(newTenantId)
					if prospectPosition and existing.Model then
						print("[ResidentController] Teleporting to prospect position:", prospectPosition)
						existing.Model:PivotTo(prospectPosition)
						TenantProspectController.RemoveProspect(newTenantId)
					else
						print("[ResidentController] WARNING: No prospect position found for seamless handoff")
					end
				end

				if newTenantId then
					startTenantRoomWander(existing)
				else
					startWanderLoop(existing)
				end
			end
			-- If model is missing (e.g. streamed out), try to respawn?
			if not existing.Model or not existing.Model.Parent then
				local model = ClientResidentPlacer.Spawn(userId, data)
				if model then
					existing.Model = model
					applyModelMetadata(model, data)
					ResidentReactions.Register(model)
					if resolveTenantId(data) then
						startTenantRoomWander(existing)
					else
						startWanderLoop(existing)
					end
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
			-- Try to reuse prospect position for seamless transition
			local spawnCFrame: CFrame? = nil
			local tenantId = resolveTenantId(data)

			if tenantId then
				local prospectPosition = TenantProspectController.GetProspectPosition(tenantId)
				if prospectPosition then
					spawnCFrame = prospectPosition
					TenantProspectController.RemoveProspect(tenantId)
				end
			end

			local model = ClientResidentPlacer.Spawn(userId, data, spawnCFrame)
			if model then
				local state = {
					OwnerUserId = userId,
					Model = model,
					Data = data,
				}
				applyModelMetadata(model, data)
				updateResidentData(state, data)
				residentsMap[name] = state
				ResidentReactions.Register(model)
				if tenantId then
					startTenantRoomWander(state)
				else
					startWanderLoop(state)
				end
			end
		else
			existing.OwnerUserId = existing.OwnerUserId or userId
			updateResidentData(existing, data)
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
	TenantRoomTracker.Init()

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
