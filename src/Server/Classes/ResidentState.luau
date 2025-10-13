--!strict
-- ServerScriptService/Server/Classes/ResidentState.lua

export type ResidentData = {
	Name: string,
	Age: number,
	Gender: string,
	Needs: { [string]: number },
	Traits: { string },
	Occupation: string,
}

type MoodletRuntime = {
	ExpiresAt: number,
	NeedBias: { [string]: number },
}

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionQueue = require(ServerScriptService.Server.Classes.ActionQueue)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

-- This is not set in stone (figuring out how things will play out in this module)
local function _WaitOnSignalWithTimeout<A...>(signal, timeoutSeconds: number?): (boolean, A...)
	-- Fast path: no timeout requested
	if timeoutSeconds == nil or timeoutSeconds == math.huge then
		return true, signal:Wait()
	end

	-- Immediate timeout (<= 0) – fail without waiting
	if timeoutSeconds <= 0 then
		return false
	end

	local waitingThread = coroutine.running()
	local finished = false
	local connection: RBXScriptConnection? = nil

	-- Resolve via the signal (success = true, plus payload)
	connection = signal:Once(function(...: A...)
		if finished then
			return
		end
		finished = true
		-- No need to keep the handle around after we decide the race
		if connection then
			connection:Disconnect()
		end
		-- Resume the waiter with success=true and payload
		task.spawn(waitingThread, true, ...)
	end)

	-- Resolve via timeout (success = false)
	task.delay(timeoutSeconds, function()
		if finished then
			return
		end
		finished = true
		if connection then
			connection:Disconnect()
		end
		task.spawn(waitingThread, false)
	end)

	-- Yield until one of the above resumes us
	return coroutine.yield()
end

local ResidentState = {}
ResidentState.__index = ResidentState

function ResidentState.new(save: ResidentData)
	local AssetsFolder = ReplicatedStorage.Assets
	local ResidentsTemplateFolder = AssetsFolder.Residents
	local self = setmetatable({}, ResidentState)

	self.Save = save
	self.ActionContext = {
		Resident = self,
		CancelToken = {
			Cancelled = false,
			Reason = nil,
		},
	}
	self.ActionQueue = ActionQueue.new(self.ActionContext) -- Queue of actions to perform
	self.CurrentAction = nil -- The current action being performed
	self.Destination = nil -- Current movement destination
	self.IsMoving = false -- Whether the resident is currently moving
	self.IsBusy = false -- Whether the resident is currently busy (performing an action)
	self.AutoActionsEnabled = true -- Whether the resident can perform auto actions
	self.AutoJobEnabled = true -- Whether the resident can perform auto job actions
	self.CurrentOverride = nil
	self.DestinationChanged = GoodSignal.new()
	self.DestinationCompleted = GoodSignal.new()
	self.ActionChanged = GoodSignal.new()
	self.ActionCompleted = GoodSignal.new()
	self.NeedsChanged = GoodSignal.new() -- Fired when any need changes
	self.ActiveMoodlets = {} :: { [string]: MoodletRuntime }
	self.Model = ResidentsTemplateFolder:FindFirstChild(self.Save.Gender):Clone() :: Model
	self.Model.Name = self.Save.Name
	self.Connections = self:BindConnections()
	return self
end

function ResidentState:GetCancelToken()
	return self.ActionContext and self.ActionContext.CancelToken or { Cancelled = false, Reason = nil }
end

function ResidentState:CancelCurrentAction(reason: string?)
	local actionContext = self.ActionContext
	if not actionContext then
		return
	end
	local token = actionContext.CancelToken
	token.Cancelled = true
	token.Reason = reason
end

function ResidentState:ResetCancelToken()
	local actionContext = self.ActionContext
	if not actionContext then
		return
	end
	local token = actionContext.CancelToken
	token.Cancelled = false
	token.Reason = nil
end

function ResidentState:WaitUntilIdle(timeoutSeconds: number?)
	if not self.IsBusy and self.ActionQueue:IsEmpty() then
		return true
	end
	local deadline = if timeoutSeconds ~= nil then os.clock() + math.max(timeoutSeconds, 0) else nil
	while true do
		local waitTime = if deadline ~= nil then math.max(deadline - os.clock(), 0) else nil
		local success = _WaitOnSignalWithTimeout(self.ActionCompleted, waitTime)
		if not success then
			return false
		end
		if not self.IsBusy and self.ActionQueue:IsEmpty() then
			return true
		end
		if deadline ~= nil and os.clock() >= deadline then
			return not self.IsBusy and self.ActionQueue:IsEmpty()
		end
	end
end

function ResidentState:ClearQueuedActions()
	if self.ActionQueue then
		self.ActionQueue:Clear()
	end
end

function ResidentState:SetManualOverrideState(state: { [string]: any }?)
	self.CurrentOverride = state
end

function ResidentState:ClearManualOverrideState()
	self.CurrentOverride = nil
end

function ResidentState:SetDestination(destination)
	self.Destination = destination
	self.DestinationChanged:Fire(destination)
end

function ResidentState:EnqueueMoveTo() end

function ResidentState:EnqueueAction(actionName: string, actionFunction: (context: any?) -> ())
	self.ActionQueue:Enqueue(actionName, actionFunction)
end

function ResidentState:BindConnections()
	local connections = {}

	-- ActionQueue lifecycle -> resident flags + signals
	table.insert(
		connections,
		self.ActionQueue.ActionStarted:Connect(function(actionName: string)
			self:ResetCancelToken()
			self.CurrentAction = actionName
			self.IsBusy = true
			self.ActionChanged:Fire(actionName)
		end)
	)

	table.insert(
		connections,
		self.ActionQueue.ActionFinished:Connect(function(actionName: string, succeeded: boolean, errorMessage: string?)
			self.IsBusy = false
			self.ActionCompleted:Fire(actionName, succeeded, errorMessage)
			self.CurrentAction = nil
			self:ResetCancelToken()
		end)
	)
	table.insert(
		connections,
		self.ActionQueue.QueueEmptied:Connect(function()
			self.CurrentAction = nil
			self.IsBusy = false
			self.ActionChanged:Fire(nil)
		end)
	)
	return connections
end

function ResidentState:GetNeed(needName: string): number
	return self.Save.Needs[needName] or 0
end

function ResidentState:SetNeed(needName: string, value: number)
	local old = self.Save.Needs[needName] or 0
	if value == old then
		return
	end
	self.Save.Needs[needName] = value
	self.NeedsChanged:Fire(needName, value, old)
end

function ResidentState:SetAutoActionEnabled(enabled: boolean)
	self.AutoActionsEnabled = enabled
end

function ResidentState:SetAutoJobEnabled(enabled: boolean)
	self.AutoJobEnabled = enabled
end

function ResidentState:GetTraits(): { string }
	local traits = self.Save.Traits
	if typeof(traits) ~= "table" then
		return {}
	end
	return traits
end

type MoodletDefinition = { Name: string, DurationSeconds: number, NeedBias: { [string]: number }? }

function ResidentState:AddMoodlet(moodlet: MoodletDefinition)
	local name = moodlet.Name
	local duration = moodlet.DurationSeconds
	if type(name) ~= "string" or name == "" or type(duration) ~= "number" or duration <= 0 then
		return
	end
	if not self.ActiveMoodlets then
		return
	end
	local expiresAt = os.clock() + duration
	local bias = moodlet.NeedBias or {}
	self.ActiveMoodlets[name] = {
		ExpiresAt = expiresAt,
		NeedBias = bias,
	}
end

function ResidentState:GetMoodBias(needName: string, nowClock: number?): number
	local now = nowClock or os.clock()
	local total = 0
	for name, entry in pairs(self.ActiveMoodlets or {}) do
		if entry.ExpiresAt <= now then
			if self.ActiveMoodlets then
				self.ActiveMoodlets[name] = nil
			end
		else
			local bias = entry.NeedBias
			local value = bias and bias[needName]
			if value then
				total += value
			end
		end
	end
	return total
end

function ResidentState:ClearMoodlets()
	self.ActiveMoodlets = {} :: { [string]: MoodletRuntime }
end

function ResidentState:DisableAutomation()
	self:SetAutoActionEnabled(false)
	self:SetAutoJobEnabled(false)
end

function ResidentState:EnableAutomation()
	self:SetAutoActionEnabled(true)
	self:SetAutoJobEnabled(true)
end

function ResidentState:Destroy()
	-- Disconnect external connections first
	if self.Connections then
		for _, connection in ipairs(self.Connections) do
			connection:Disconnect()
		end
		self.Connections = nil
	end

	-- Tear down queue and signals
	if self.ActionQueue then
		self.ActionQueue:Destroy()
		self.ActionQueue = nil
	end

	if self.DestinationChanged then
		self.DestinationChanged:DisconnectAll()
		self.DestinationChanged = nil
	end
	if self.DestinationCompleted then
		self.DestinationCompleted:DisconnectAll()
		self.DestinationCompleted = nil
	end
	if self.ActionChanged then
		self.ActionChanged:DisconnectAll()
		self.ActionChanged = nil
	end
	if self.ActionCompleted then
		self.ActionCompleted:DisconnectAll()
		self.ActionCompleted = nil
	end
	if self.NeedsChanged then
		self.NeedsChanged:DisconnectAll()
		self.NeedsChanged = nil
	end
	self.ActiveMoodlets = nil
	-- Destroy model last
	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end

	self.CurrentAction = nil
	self.Destination = nil
	self.ActionContext = nil
end

return ResidentState
