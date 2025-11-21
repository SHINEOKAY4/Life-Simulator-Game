--!strict
-- Client/Modules/ResidentController.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)
local ClientResidentPlacer = require(script.Parent.ClientResidentPlacer)
local ClientResidentMovement = require(script.Parent.ClientResidentMovement)
local ResidentReactions = require(script.Parent.ResidentReactions)

local ResidentController = {}

type ResidentState = {
	Model: Model,
	Data: any,
	CurrentAction: string?,
	ActionThread: thread?,
	CancelToken: { Cancelled: boolean }?,
}

local ClientResidents: { [number]: { [string]: ResidentState } } = {} -- [userId][residentName] = State

local function stopResidentAction(state: ResidentState)
	if state.CancelToken then
		state.CancelToken.Cancelled = true
	end
	state.CancelToken = nil
	state.CurrentAction = nil
	state.ActionThread = nil
end

local function startWanderLoop(state: ResidentState)
	if state.ActionThread then
		return
	end

	state.CancelToken = { Cancelled = false }
	local token = state.CancelToken

	state.ActionThread = task.spawn(function()
		while not token.Cancelled do
			if not state.Model or not state.Model.Parent then
				break
			end

			-- Simple wander logic
			local root = state.Model:FindFirstChild("HumanoidRootPart") :: BasePart
			if root then
				local origin = root.Position
				local randomOffset = Vector3.new(math.random(-15, 15), 0, math.random(-15, 15))
				local target = origin + randomOffset

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
					Model = model,
					Data = data,
				}
				residentsMap[residentName] = state
				ResidentReactions.Register(model)
				startWanderLoop(state)
			end
		else
			-- Update existing data
			existing.Data = data
			-- If model is missing (e.g. streamed out), try to respawn?
			if not existing.Model or not existing.Model.Parent then
				local model = ClientResidentPlacer.Spawn(userId, data)
				if model then
					existing.Model = model
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
					Model = model,
					Data = data,
				}
				residentsMap[name] = state
				ResidentReactions.Register(model)
				startWanderLoop(state)
			end
		else
			existing.Data = data
			if not existing.Model or not existing.Model.Parent then
				local model = ClientResidentPlacer.Spawn(userId, data)
				if model then
					existing.Model = model
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
