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

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ActionQueue = require(ServerScriptService.Server.Classes.ActionQueue)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

-- This is not set in stone (figuring out how things will play out in this module)
local function WaitOnSignalWithTimeout<A...>(signal, timeoutSeconds: number?): (boolean, A...)
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
	self.ActionQueue = ActionQueue.new(self) -- Queue of actions to perform
	self.CurrentAction = nil -- The current action being performed
	self.Destination = nil -- Current movement destination
	self.IsMoving = false -- Whether the resident is currently moving
	self.IsBusy = false -- Whether the resident is currently busy (performing an action)
	self.AutoActionsEnabled = true -- Whether the resident can perform auto actions
	self.AutoJobEnabled = true -- Whether the resident can perform auto job actions
	self.DestinationChanged = GoodSignal.new()
	self.DestinationCompleted = GoodSignal.new()
	self.ActionChanged = GoodSignal.new()
	self.ActionCompleted = GoodSignal.new()
	self.Model = ResidentsTemplateFolder:FindFirstChild(self.Save.Gender):Clone() :: Model
	self.Model.Name = self.Save.Name
	self.Connections = self:BindConnections()
	return self
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

	-- Destroy model last
	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end

	self.CurrentAction = nil
	self.Destination = nil
end

return ResidentState
