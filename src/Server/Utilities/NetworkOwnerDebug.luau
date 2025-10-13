--!strict
-- NetworkOwnerDebug.lua
-- Tracks network ownership for collections of parts and emits ResidentDebug traces when changes occur.

local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")

local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)

local CHANNEL = "NetworkOwner"
local POLL_INTERVAL_SECONDS = 0.5

export type Tracker = {
	Model: Model,
	Label: string,
	Parts: { BasePart },
	PartSet: { [BasePart]: boolean },
	LastOwner: { [BasePart]: Player? },
	LastAuto: { [BasePart]: boolean? },
}

local NetworkOwnerDebug = {}
local trackers: { [Model]: Tracker } = {}
local heartbeatConn: RBXScriptConnection? = nil
local accumulated = 0

local function ownerToLabel(owner: Player?): string
	if owner then
		return owner.Name
	end
	return "Server"
end

local function safeFullName(instance: Instance?): string
	if not instance then
		return "<nil>"
	end
	local ok, value = pcall(function()
		return instance:GetFullName()
	end)
	if ok then
		return value
	end
	return instance.Name
end

local function ensureParts(tracker: Tracker)
	for index = #tracker.Parts, 1, -1 do
		local part = tracker.Parts[index]
		if not part.Parent then
			tracker.PartSet[part] = nil
			tracker.LastOwner[part] = nil
			tracker.LastAuto[part] = nil
			table.remove(tracker.Parts, index)
		end
	end
	for _, descendant in ipairs(tracker.Model:GetDescendants()) do
		if descendant:IsA("BasePart") and not tracker.PartSet[descendant] then
			tracker.PartSet[descendant] = true
			tracker.Parts[#tracker.Parts + 1] = descendant
		end
	end
end

local function getOwnershipAuto(part: BasePart): boolean?
	local ok, value = pcall(function()
		return part:GetNetworkOwnershipAuto()
	end)
	if ok and typeof(value) == "boolean" then
		return value
	end
	return nil
end

local function pushChange(tracker: Tracker, part: BasePart, owner: Player?, auto: boolean?)
	local ownerLabel = ownerToLabel(owner)
	ResidentDebug.Trace(CHANNEL, string.format("%s -> %s (%s)", tracker.Label, ownerLabel, part.Name), {
		Tracker = tracker.Label,
		Part = safeFullName(part),
		OwnerName = ownerLabel,
		OwnerUserId = owner and owner.UserId or nil,
		NetworkOwnershipAuto = auto,
		Anchored = part.Anchored,
		AssemblyLinearVelocity = part.AssemblyLinearVelocity,
		AssemblyAngularVelocity = part.AssemblyAngularVelocity,
	})
end

local function updateTracker(tracker: Tracker)
	if not tracker.Model.Parent then
		trackers[tracker.Model] = nil
		return
	end
	ensureParts(tracker)
	for _, part in ipairs(tracker.Parts) do
		if part.Parent then
			local okOwner, ownerOrNil = pcall(function()
				return part:GetNetworkOwner()
			end)
			if not okOwner then
				ownerOrNil = nil
			end
			local owner = ownerOrNil :: Player?
			local auto = getOwnershipAuto(part)
			local previousOwner = tracker.LastOwner[part]
			local previousAuto = tracker.LastAuto[part]
			if previousOwner ~= owner or previousAuto ~= auto then
				tracker.LastOwner[part] = owner
				tracker.LastAuto[part] = auto
				pushChange(tracker, part, owner, auto)
			end
		end
	end
end

local function heartbeatStep(dt: number)
	accumulated += dt
	if accumulated < POLL_INTERVAL_SECONDS then
		return
	end
	accumulated = 0
	for _, tracker in pairs(trackers) do
		updateTracker(tracker)
	end
	if next(trackers) == nil and heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

local function ensureHeartbeat()
	if heartbeatConn then
		return
	end
	accumulated = 0
	heartbeatConn = RunService.Heartbeat:Connect(heartbeatStep)
end

function NetworkOwnerDebug.Observe(model: Model, label: string?): () -> ()
	local existing = trackers[model]
	if existing then
		if label then
			existing.Label = label
		end
		return function()
			trackers[model] = nil
			if next(trackers) == nil and heartbeatConn then
				heartbeatConn:Disconnect()
				heartbeatConn = nil
			end
		end
	end
	local tracker: Tracker = {
		Model = model,
		Label = label or safeFullName(model),
		Parts = {},
		PartSet = {},
		LastOwner = {},
		LastAuto = {},
	}
	trackers[model] = tracker
	ensureParts(tracker)
	updateTracker(tracker)
	ensureHeartbeat()
	return function()
		trackers[model] = nil
		if next(trackers) == nil and heartbeatConn then
			heartbeatConn:Disconnect()
			heartbeatConn = nil
		end
	end
end

function NetworkOwnerDebug.Report(model: Model, label: string?)
	local tracker: Tracker = {
		Model = model,
		Label = label or safeFullName(model),
		Parts = {},
		PartSet = {},
		LastOwner = {},
		LastAuto = {},
	}
	ensureParts(tracker)
	for _, part in ipairs(tracker.Parts) do
		if part.Parent then
			local okOwner, ownerOrNil = pcall(function()
				return part:GetNetworkOwner()
			end)
			if not okOwner then
				ownerOrNil = nil
			end
			local owner = ownerOrNil :: Player?
			pushChange(tracker, part, owner, getOwnershipAuto(part))
		end
	end
end

function NetworkOwnerDebug.Clear()
	for model in pairs(trackers) do
		trackers[model] = nil
	end
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end
end

return NetworkOwnerDebug
