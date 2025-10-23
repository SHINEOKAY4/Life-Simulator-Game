--!strict
-- ServerScriptService/Server/Services/CurrencyService.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyPackets = require(ReplicatedStorage.Network.CurrencyPackets)

export type CurrencyDeltaContext = {
	Source: string?,
	ResidentName: string?,
}

export type CurrencyModule = {
	Add: (
		player: Player,
		currencyName: string,
		amount: number,
		data: { [string]: number },
		context: CurrencyDeltaContext?
	) -> number,
	Remove: (player: Player, currencyName: string, amount: number, data: { [string]: number }) -> number,
	Set: (player: Player, currencyName: string, amount: number, data: { [string]: number }) -> number,
	Get: (player: Player, currencyName: string?, data: { [string]: number }) -> number,
}

local function EnsurePositiveInteger(amount: number, source: string)
	assert(typeof(amount) == "number", source .. ": amount must be a number")
	assert(amount == amount, source .. ": amount must be a valid number (not NaN)")
	assert(amount > -math.huge and amount < math.huge, source .. ": amount must be finite")
	assert(amount >= 0, source .. ": amount must be >= 0")
	assert(math.floor(amount) == amount, source .. ": amount must be an integer")
end

local function AssertParameters(
	player: any,
	currencyName: any,
	amount: number,
	data: { [string]: number },
	source: string
)
	assert(
		typeof(player) == "Instance" and (player :: any):IsA("Player"),
		source .. ": player must be a Player instance"
	)
	assert(typeof(currencyName) == "string", source .. ": currencyName must be a string")
	assert(#currencyName > 0, source .. ": currencyName must be non-empty")
	assert(typeof(data) == "table", source .. ": data must be a table {[string]: number}")
	EnsurePositiveInteger(amount, source)
end

local CurrencyService = {}

local function dispatchCurrencyDelta(
	player: Player,
	currencyName: string,
	amount: number,
	context: CurrencyDeltaContext?
)
	if amount <= 0 then
		return
	end
	local payloadSource = ""
	local payloadResidentName = ""
	if context then
		local contextSource = context.Source
		if typeof(contextSource) == "string" then
			payloadSource = contextSource
		end
		local contextResidentName = context.ResidentName
		if typeof(contextResidentName) == "string" then
			payloadResidentName = contextResidentName
		end
	end
	CurrencyPackets.PlayerCurrencyDelta:FireClient(player, {
		CurrencyName = currencyName,
		Amount = amount,
		Source = payloadSource,
		ResidentName = payloadResidentName,
	})
end

--[=[
	Adds currency to the player's balance.

	@param player Player -- The player whose balance is modified.
	@param currencyName string -- The currency key (e.g. "Coins").
	@param amount number -- Amount to add (non-negative integer).
	@param data {[string]: number} -- Player's currency table.
	@return number -- New balance after addition.
]=]
function CurrencyService.Add(
	player: Player,
	currencyName: string,
	amount: number,
	data: { [string]: number },
	context: CurrencyDeltaContext?
)
	AssertParameters(player, currencyName, amount, data, "CurrencyService.Add")

	local current = data[currencyName] or 0
	local sum = current + amount

	data[currencyName] = sum
	player:SetAttribute(currencyName, sum)
	dispatchCurrencyDelta(player, currencyName, amount, context)
	return sum
end

--[=[
	Removes currency from the player's balance (clamped to 0).

	@param player Player
	@param currencyName string
	@param amount number -- Amount to remove.
	@param data {[string]: number}
	@return number -- New balance after removal.
]=]
function CurrencyService.Remove(player: Player, currencyName: string, amount: number, data: { [string]: number })
	AssertParameters(player, currencyName, amount, data, "Currency.Remove")

	local current = data[currencyName] or 0
	local nextValue = current - amount
	if nextValue < 0 then
		nextValue = 0
	end

	data[currencyName] = nextValue
	player:SetAttribute(currencyName, nextValue)
	return nextValue
end

--[=[
	Sets the player's balance for a currency.

	@param player Player
	@param currencyName string
	@param amount number -- New balance value.
	@param data {[string]: number}
	@return number -- The set balance.
]=]
function CurrencyService.Set(player: Player, currencyName: string, amount: number, data: { [string]: number })
	AssertParameters(player, currencyName, amount, data, "CurrencyService.Set")

	data[currencyName] = amount
	player:SetAttribute(currencyName, amount)
	return amount
end

--[=[
	Gets the player's balance for a currency.

	@param player Player
	@param currencyName string? -- The currency to query. Optional.
	@param data {[string]: number}
	@return number -- Balance (0 if missing).
]=]
function CurrencyService.Get(player: Player, currencyName: string?, data: { [string]: number })
	assert(
		typeof(player) == "Instance" and (player :: any):IsA("Player"),
		"CurrencyService.Get" .. ": player must be a Player instance"
	)
	assert(typeof(data) == "table", "CurrencyService.Get" .. ": data must be a table {[string]: number}")

	if currencyName ~= nil then
		assert(typeof(currencyName) == "string", "CurrencyService.Get" .. ": currencyName must be a string")
		assert(#currencyName > 0, "CurrencyService.Get" .. ": currencyName must be non-empty")

		local v = data[currencyName]
		if v == nil then
			warn("CurrencyService.Get: '" .. currencyName .. "' does not exist in data")
			return 0
		end
		return v
	end

	return 0
end

return CurrencyService
