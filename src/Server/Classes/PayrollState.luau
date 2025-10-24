--!strict
-- ServerScriptService/Server/Classes/PayrollState.luau

local PayrollState = {}
PayrollState.__index = PayrollState

type ResidentEarnings = {
	SecondsWorked: number,
	JobId: string,
	BasePay: number,
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
			sanitized[residentName] = {
				SecondsWorked = sanitizeNonNegativeNumber(data.SecondsWorked, 0),
				JobId = if typeof(data.JobId) == "string" then data.JobId else "",
				BasePay = sanitizeNonNegativeNumber(data.BasePay, 0),
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

function PayrollState:AddWorkTime(residentName: string, secondsWorked: number, jobId: string, basePay: number)
	local payrollState = self :: PayrollState
	if typeof(residentName) ~= "string" or residentName == "" then
		return
	end
	if secondsWorked <= 0 then
		return
	end

	local existing = payrollState.Save.ResidentEarnings[residentName]
	if existing then
		existing.SecondsWorked += secondsWorked
		existing.JobId = jobId
		existing.BasePay = basePay
	else
		payrollState.Save.ResidentEarnings[residentName] = {
			SecondsWorked = secondsWorked,
			JobId = jobId,
			BasePay = basePay,
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
