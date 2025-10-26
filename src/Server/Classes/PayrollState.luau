--!strict
-- ServerScriptService/Server/Classes/PayrollState.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

local function secondsPerGameMinute(): number
	local secondsPerDay = TimeScale.GetSecondsPerFullDay()
	local value = secondsPerDay / (24 * 60)
	if value <= 0 then
		return 60
	end
	return value
end

local PayrollState = {}
PayrollState.__index = PayrollState

type ResidentEarnings = {
	WorkMinutes: number,
	JobId: string,
	BasePayPerMinute: number,
}

export type PayrollStateData = {
	LastPayoutTime: number,
	ResidentEarnings: { [string]: ResidentEarnings },
}

export type PayrollState = typeof(setmetatable(
	{} :: {
		CycleDurationSeconds: number,
		IsActive: boolean,
		Save: PayrollStateData,
	},
	PayrollState
))

local function sanitizeNonNegativeNumber(value: number?, defaultValue: number): number
	if typeof(value) ~= "number" then
		return defaultValue
	end
	if value ~= value or value < 0 then
		return defaultValue
	end
	return value
end

local function sanitizeResidentEarnings(raw: any): { [string]: ResidentEarnings }
	if typeof(raw) ~= "table" then
		return {}
	end

	local sanitized: { [string]: ResidentEarnings } = {}
	for residentName, data in pairs(raw :: { [string]: any }) do
		if typeof(residentName) == "string" and typeof(data) == "table" then
			local workMinutes = sanitizeNonNegativeNumber((data :: any).WorkMinutes, -1)
			local legacySeconds = sanitizeNonNegativeNumber((data :: any).SecondsWorked, 0)
			if workMinutes < 0 then
				-- Legacy saves stored real seconds; convert using the active time scale.
				if legacySeconds > 0 then
					workMinutes = legacySeconds / secondsPerGameMinute()
				else
					workMinutes = 0
				end
			end

			local basePayPerMinute = sanitizeNonNegativeNumber((data :: any).BasePayPerMinute, -1)
			if basePayPerMinute < 0 then
				local legacyPerSecond = sanitizeNonNegativeNumber((data :: any).BasePay, 0)
				if legacyPerSecond > 0 then
					basePayPerMinute = legacyPerSecond * 60
				else
					basePayPerMinute = 0
				end
			end

			sanitized[residentName] = {
				WorkMinutes = workMinutes,
				JobId = if typeof((data :: any).JobId) == "string" then (data :: any).JobId else "",
				BasePayPerMinute = basePayPerMinute,
			}
		end
	end
	return sanitized
end

function PayrollState.new(cycleDurationSeconds: number, save: PayrollStateData?): PayrollState
	local resolvedSave: PayrollStateData = save or {
		LastPayoutTime = 0,
		ResidentEarnings = {},
	}

	resolvedSave.LastPayoutTime = sanitizeNonNegativeNumber(resolvedSave.LastPayoutTime, 0)
	resolvedSave.ResidentEarnings = sanitizeResidentEarnings(resolvedSave.ResidentEarnings)

	local self = setmetatable({}, PayrollState)
	self.CycleDurationSeconds = cycleDurationSeconds
	self.IsActive = true
	self.Save = resolvedSave

	return self
end

function PayrollState:Update(deltaSeconds: number)
	local payrollState = self :: PayrollState
	if not payrollState.IsActive then
		return
	end
	if deltaSeconds <= 0 then
		return
	end
	payrollState.Save.LastPayoutTime += deltaSeconds
end

function PayrollState:IsDue(): boolean
	local payrollState = self :: PayrollState
	if not payrollState.IsActive then
		return false
	end
	return payrollState.Save.LastPayoutTime >= payrollState.CycleDurationSeconds
end

function PayrollState:GetElapsedSeconds(): number
	local payrollState = self :: PayrollState
	return payrollState.Save.LastPayoutTime
end

function PayrollState:GetTimeRemaining(): number
	local payrollState = self :: PayrollState
	return math.max(0, payrollState.CycleDurationSeconds - payrollState.Save.LastPayoutTime)
end

function PayrollState:ResetCycle()
	local payrollState = self :: PayrollState
	payrollState.Save.LastPayoutTime = 0
end

function PayrollState:AddWorkTime(residentName: string, minutesWorked: number, jobId: string, basePayPerMinute: number)
	local payrollState = self :: PayrollState
	if typeof(residentName) ~= "string" or residentName == "" then
		return
	end
	if minutesWorked <= 0 then
		return
	end

	local existing = payrollState.Save.ResidentEarnings[residentName]
	if existing then
		existing.WorkMinutes += minutesWorked
		existing.JobId = jobId
		existing.BasePayPerMinute = basePayPerMinute
	else
		payrollState.Save.ResidentEarnings[residentName] = {
			WorkMinutes = minutesWorked,
			JobId = jobId,
			BasePayPerMinute = basePayPerMinute,
		}
	end
end

function PayrollState:GetResidentEarnings(residentName: string): ResidentEarnings?
	local payrollState = self :: PayrollState
	return payrollState.Save.ResidentEarnings[residentName]
end

function PayrollState:GetAllEarnings(): { [string]: ResidentEarnings }
	local payrollState = self :: PayrollState
	return payrollState.Save.ResidentEarnings
end

function PayrollState:ClearAllEarnings()
	local payrollState = self :: PayrollState
	table.clear(payrollState.Save.ResidentEarnings)
end

function PayrollState:ClearResidentEarnings(residentName: string)
	local payrollState = self :: PayrollState
	payrollState.Save.ResidentEarnings[residentName] = nil
end

return PayrollState
