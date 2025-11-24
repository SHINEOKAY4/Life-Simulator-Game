--!strict
-- Server/Services/TenantService/MailboxManager.luau
-- Manages mailbox balance, income accumulation, and collection

local AttributeManager = require(script.Parent.AttributeManager)

local MailboxManager = {}

function MailboxManager.EnsureBalance(save: any): number
	local rawValue = save.MailboxBalance
	local numeric = if typeof(rawValue) == "number" then rawValue else 0
	return AttributeManager.ClampMailboxAmount(numeric)
end

function MailboxManager.AddIncome(save: any, amount: number): number
	if amount <= 0 then
		return MailboxManager.EnsureBalance(save)
	end

	local currentBalance = MailboxManager.EnsureBalance(save)
	local updatedBalance = AttributeManager.ClampMailboxAmount(currentBalance + amount)
	save.MailboxBalance = updatedBalance
	save.OutstandingRent = 0
	return updatedBalance
end

function MailboxManager.Collect(
	save: any,
	currencyService: any,
	player: Player,
	currencyState: any
): (boolean, number, string)
	local balance = MailboxManager.EnsureBalance(save)

	if balance <= 0 then
		save.MailboxBalance = 0
		return false, 0, "Mailbox is empty."
	end

	if not currencyState then
		return false, 0, "Unable to access currency data."
	end

	save.MailboxBalance = 0
	currencyService.Add(player, "Cash", balance, currencyState, {
		Source = "TenantMailbox",
	})

	return true, balance, "Collected rent from mailbox."
end

function MailboxManager.SettleOutstanding(save: any)
	if save.OutstandingRent and save.OutstandingRent ~= 0 then
		save.OutstandingRent = 0
	end
end

return MailboxManager
