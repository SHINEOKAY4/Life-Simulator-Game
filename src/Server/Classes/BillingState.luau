--!strict
-- ServerScriptService/Server/Classes/BillingState.lua

local BillingState = {}
BillingState.__index = BillingState

export type CycleState = "Active" | "Grace" | "Overdue"

type OutstandingBreakdown = {
	PlotTax: number,
	Electric: number,
	Food: number,
	Interest: number,
}

export type BillingStateData = {
	lastPaymentTime: number,
	BillingGraceActive: boolean,
	GraceElapsedSeconds: number,
	OverduePayments: number,
	CurrentCycleRecordedOverdue: boolean,
	CycleState: CycleState?,
	OutstandingBreakdown: OutstandingBreakdown?,
}

export type BillingState = typeof(setmetatable(
	{} :: {
		DurationSeconds: number,
		GracePeriodSeconds: number,
		IsActive: boolean,
		Save: BillingStateData,
	},
	BillingState
))

local CYCLE_ACTIVE: CycleState = "Active"
local CYCLE_GRACE: CycleState = "Grace"
local CYCLE_OVERDUE: CycleState = "Overdue"

local function sanitizeNonNegativeNumber(value: number?, defaultValue: number): number
	if typeof(value) ~= "number" then
		return defaultValue
	end
	if value ~= value or value < 0 then
		return defaultValue
	end
	return value
end

local function sanitizeOutstandingValue(value: number?): number
	if typeof(value) ~= "number" or value ~= value or value < 0 then
		return 0
	end
	local rounded = math.round(value)
	if rounded < 0 then
		return 0
	end
	return rounded
end

local function sanitizeOutstandingBreakdown(raw: any): OutstandingBreakdown
	local normalized: OutstandingBreakdown = {
		PlotTax = 0,
		Electric = 0,
		Food = 0,
		Interest = 0,
	}
	if typeof(raw) ~= "table" then
		return normalized
	end

	local candidate = raw :: { [string]: any }
	normalized.PlotTax = sanitizeOutstandingValue(candidate.PlotTax)
	normalized.Electric = sanitizeOutstandingValue(candidate.Electric)
	normalized.Food = sanitizeOutstandingValue(candidate.Food)
	normalized.Interest = sanitizeOutstandingValue(candidate.Interest)
	return normalized
end

function BillingState.new(durationSeconds: number, gracePeriodSeconds: number, save: BillingStateData?): BillingState
	local resolvedSave: BillingStateData = save
		or {
			lastPaymentTime = 0,
			BillingGraceActive = false,
			GraceElapsedSeconds = 0,
			OverduePayments = 0,
			CurrentCycleRecordedOverdue = false,
			CycleState = CYCLE_ACTIVE,
			OutstandingBreakdown = {
				PlotTax = 0,
				Electric = 0,
				Food = 0,
				Interest = 0,
			},
		}

	resolvedSave.lastPaymentTime = sanitizeNonNegativeNumber(resolvedSave.lastPaymentTime, 0)
	resolvedSave.GraceElapsedSeconds = sanitizeNonNegativeNumber(resolvedSave.GraceElapsedSeconds, 0)
	resolvedSave.OverduePayments = sanitizeNonNegativeNumber(resolvedSave.OverduePayments, 0)
	resolvedSave.CurrentCycleRecordedOverdue = resolvedSave.CurrentCycleRecordedOverdue == true
	resolvedSave.OutstandingBreakdown = sanitizeOutstandingBreakdown(resolvedSave.OutstandingBreakdown)

	local savedCycleStateValue = resolvedSave.CycleState
	local normalizedCycleState: CycleState
	if savedCycleStateValue == CYCLE_GRACE then
		normalizedCycleState = CYCLE_GRACE
	elseif savedCycleStateValue == CYCLE_OVERDUE then
		normalizedCycleState = CYCLE_OVERDUE
	elseif savedCycleStateValue == CYCLE_ACTIVE then
		normalizedCycleState = CYCLE_ACTIVE
	else
		if resolvedSave.BillingGraceActive then
			normalizedCycleState = CYCLE_GRACE
		elseif resolvedSave.CurrentCycleRecordedOverdue then
			normalizedCycleState = CYCLE_OVERDUE
		else
			normalizedCycleState = CYCLE_ACTIVE
		end
	end
	resolvedSave.CycleState = normalizedCycleState
	resolvedSave.BillingGraceActive = normalizedCycleState == CYCLE_GRACE

	local self = setmetatable({}, BillingState)
	self.DurationSeconds = durationSeconds
	self.GracePeriodSeconds = gracePeriodSeconds
	self.IsActive = true
	self.Save = resolvedSave

	if normalizedCycleState ~= CYCLE_GRACE then
		resolvedSave.GraceElapsedSeconds = 0
	elseif resolvedSave.GraceElapsedSeconds > gracePeriodSeconds then
		resolvedSave.GraceElapsedSeconds = gracePeriodSeconds
	end

	return self
end

function BillingState:GetCycleState(): CycleState
	local billingState = self :: BillingState
	local cycleStateValue = billingState.Save.CycleState
	local cycleState: CycleState
	if cycleStateValue == CYCLE_GRACE then
		cycleState = CYCLE_GRACE
	elseif cycleStateValue == CYCLE_OVERDUE then
		cycleState = CYCLE_OVERDUE
	elseif cycleStateValue == CYCLE_ACTIVE then
		cycleState = CYCLE_ACTIVE
	else
		cycleState = CYCLE_ACTIVE
		billingState.Save.BillingGraceActive = false
		billingState.Save.GraceElapsedSeconds = 0
	end
	billingState.Save.CycleState = cycleState
	return cycleState
end

function BillingState:Update(deltaSeconds: number)
	local billingState = self :: BillingState
	if not billingState.IsActive then
		return
	end
	if deltaSeconds <= 0 then
		return
	end
	billingState.Save.lastPaymentTime += deltaSeconds

	local cycleState = billingState:GetCycleState()
	if cycleState == CYCLE_GRACE then
		local nextGraceElapsed = billingState.Save.GraceElapsedSeconds + deltaSeconds
		if nextGraceElapsed > billingState.GracePeriodSeconds then
			nextGraceElapsed = billingState.GracePeriodSeconds
		end
		billingState.Save.GraceElapsedSeconds = nextGraceElapsed
	else
		billingState.Save.GraceElapsedSeconds = 0
	end
end

function BillingState:IsDue(): boolean
	local billingState = self :: BillingState
	if not billingState.IsActive then
		return false
	end
	if billingState:IsInGrace() or billingState:IsOverdue() then
		return false
	end
	return billingState.Save.lastPaymentTime >= billingState.DurationSeconds
end

function BillingState:IsInGrace(): boolean
	local billingState = self :: BillingState
	return billingState:GetCycleState() == CYCLE_GRACE
end

function BillingState:IsGraceExpired(): boolean
	local billingState = self :: BillingState
	if not billingState:IsInGrace() then
		return false
	end
	return billingState.Save.GraceElapsedSeconds >= billingState.GracePeriodSeconds
end

function BillingState:EnterGrace(): boolean
	local billingState = self :: BillingState
	if not billingState.IsActive then
		return false
	end
	if billingState:GetCycleState() == CYCLE_GRACE then
		return false
	end
	billingState.Save.CycleState = CYCLE_GRACE
	billingState.Save.BillingGraceActive = true
	billingState.Save.GraceElapsedSeconds = 0
	return true
end

function BillingState:EnterOverdue(): boolean
	local billingState = self :: BillingState
	if billingState:GetCycleState() == CYCLE_OVERDUE then
		return false
	end
	billingState.Save.CycleState = CYCLE_OVERDUE
	billingState.Save.BillingGraceActive = false
	billingState.Save.GraceElapsedSeconds = billingState.GracePeriodSeconds
	billingState.Save.CurrentCycleRecordedOverdue = true
	return true
end

function BillingState:IsOverdue(): boolean
	local billingState = self :: BillingState
	return billingState:GetCycleState() == CYCLE_OVERDUE
end

function BillingState:HasRecordedOverdue(): boolean
	local billingState = self :: BillingState
	return billingState.Save.CurrentCycleRecordedOverdue == true
end

function BillingState:IncrementOverdueCount(): number
	local billingState = self :: BillingState
	local nextValue = billingState.Save.OverduePayments + 1
	billingState.Save.OverduePayments = nextValue
	return nextValue
end

function BillingState:GetOverdueCount(): number
	local billingState = self :: BillingState
	return billingState.Save.OverduePayments
end

function BillingState:ResetCycle(): boolean
	local billingState = self :: BillingState
	local previousState = billingState:GetCycleState()
	billingState.Save.CycleState = CYCLE_ACTIVE
	billingState.Save.BillingGraceActive = false
	billingState.Save.GraceElapsedSeconds = 0
	billingState.Save.CurrentCycleRecordedOverdue = false
	billingState.Save.lastPaymentTime = 0
	billingState.IsActive = true
	return previousState ~= CYCLE_ACTIVE
end

function BillingState:GetElapsedSeconds(): number
	local billingState = self :: BillingState
	return billingState.Save.lastPaymentTime
end

function BillingState:GetTimeRemaining(): number
	local billingState = self :: BillingState
	local cycleState = billingState:GetCycleState()

	if cycleState == CYCLE_GRACE then
		return math.max(0, billingState.GracePeriodSeconds - billingState.Save.GraceElapsedSeconds)
	elseif cycleState == CYCLE_OVERDUE then
		return 0
	else
		return math.max(0, billingState.DurationSeconds - billingState.Save.lastPaymentTime)
	end
end

function BillingState:GetGraceElapsedSeconds(): number
	local billingState = self :: BillingState
	return billingState.Save.GraceElapsedSeconds
end

function BillingState:Renew(): boolean
	local billingState = self :: BillingState
	if not billingState.IsActive then
		return false
	end
	return billingState:ResetCycle()
end

function BillingState:Reset()
	local billingState = self :: BillingState
	billingState:ResetCycle()
end

BillingState.CycleStates = {
	Active = CYCLE_ACTIVE,
	Grace = CYCLE_GRACE,
	Overdue = CYCLE_OVERDUE,
}

return BillingState
