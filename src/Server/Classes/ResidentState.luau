--!strict
-- ServerScriptService/Server/Classes/ResidentState.lua

export type ResidentData = {
	Name: string,
	Traits: { string },
	TenantId: string?,
}

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local ResidentState = {}
ResidentState.__index = ResidentState

function ResidentState.new(save: ResidentData)
	local self = setmetatable({}, ResidentState)

	self.Save = save
	self.Model = nil :: Model? -- Kept for compatibility, but will be nil on server

	-- Signals kept for compatibility if needed, but mostly unused now
	self.ActionChanged = GoodSignal.new()
	self.ActionCompleted = GoodSignal.new()

	return self
end

function ResidentState:GetTraits(): { string }
	local traits = self.Save.Traits
	if typeof(traits) ~= "table" then
		return {}
	end
	return traits
end

-- Stub methods to prevent errors if called
function ResidentState:ClearManualOverrideState() end
function ResidentState:CancelCurrentAction(_reason: string?) end
function ResidentState:ResetCancelToken() end
function ResidentState:WaitUntilIdle(_timeout: number?)
	return true
end
function ResidentState:ClearQueuedActions() end

function ResidentState:Destroy()
	if self.ActionChanged then
		self.ActionChanged:DisconnectAll()
		self.ActionChanged = nil
	end
	if self.ActionCompleted then
		self.ActionCompleted:DisconnectAll()
		self.ActionCompleted = nil
	end
	if self.Model then
		self.Model:Destroy()
		self.Model = nil
	end
end

return ResidentState
