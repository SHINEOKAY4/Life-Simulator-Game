--!strict
-- Billing state management class

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local BillingConstants = require(ReplicatedStorage.Shared.Definitions.BillingConstants)

export type BillingStateData = {
	LastBillTime: number,
	UnpaidTime: number?, -- When bill became due (os.time), nil if paid
	CurrentCycle: {
		PropertyTax: number,
		Electricity: number,
		Water: number,
		Internet: number,
	},
	InternetTier: string,
}

export type BillingState = {
	Save: BillingStateData,
	GetElapsedSeconds: (self: BillingState) -> number,
	ResetCycle: (self: BillingState) -> (),
	SetInternetTier: (self: BillingState, tier: string) -> (),
	MarkUnpaid: (self: BillingState) -> (),
	GetUnpaidDuration: (self: BillingState) -> number,
	IsGracePeriodExpired: (self: BillingState, gracePeriodSeconds: number) -> boolean,
}

local BillingState = {}
BillingState.__index = BillingState

function BillingState.new(saveData: BillingStateData): BillingState
	local self = setmetatable({}, BillingState)
	self.Save = saveData
	return self :: any
end

function BillingState:GetElapsedSeconds(): number
	return os.time() - self.Save.LastBillTime
end

function BillingState:ResetCycle()
	self.Save.LastBillTime = os.time()
	self.Save.UnpaidTime = nil -- Clear unpaid flag
	self.Save.CurrentCycle = {
		PropertyTax = 0,
		Electricity = 0,
		Water = 0,
		Internet = 0,
	}
end

function BillingState:SetInternetTier(tier: string)
	if BillingConstants.InternetTiers[tier] then
		self.Save.InternetTier = tier
	end
end

function BillingState:MarkUnpaid()
	if not self.Save.UnpaidTime then
		self.Save.UnpaidTime = os.time()
	end
end

function BillingState:GetUnpaidDuration(): number
	if not self.Save.UnpaidTime then
		return 0
	end
	return os.time() - self.Save.UnpaidTime
end

function BillingState:IsGracePeriodExpired(gracePeriodSeconds: number): boolean
	return self:GetUnpaidDuration() >= gracePeriodSeconds
end

return BillingState
