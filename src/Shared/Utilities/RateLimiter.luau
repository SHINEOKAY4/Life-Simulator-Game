--!strict
-- ReplicatedStorage/Shared/Utilities/RateLimiter.lua
-- Per-player token-bucket limiter with named buckets (pure prototype style, explicit variable names).

-- ====================================================================
-- Public Types
-- ====================================================================

export type BucketConfig = {
	ratePerSecond: number, -- tokens/sec
	burst: number, -- max bucket size
}

export type PlayerBucketState = {
	tokens: number,
	lastRefillTime: number,
}

export type Bucket = {
	Name: string,
	Config: BucketConfig,
	PerPlayer: { [number]: PlayerBucketState },

	Allow: (self: Bucket, player: Player, tokens: number?) -> boolean,
	Refund: (self: Bucket, player: Player, tokens: number?) -> (),
	GetTokens: (self: Bucket, player: Player) -> number,
	SecondsUntilNextToken: (self: Bucket, player: Player) -> number,
	TimeUntilAllow: (self: Bucket, player: Player, tokens: number?) -> number,
	Clear: (self: Bucket, player: Player) -> (),
	PurgeIdle: (self: Bucket, idleSeconds: number) -> number,
	Reconfigure: (self: Bucket, config: BucketConfig) -> (),
	Reset: (self: Bucket) -> (),
}

export type RateLimiter = {
	Bucket: (self: RateLimiter, name: string, config: BucketConfig) -> Bucket,
	GetBucket: (self: RateLimiter, name: string) -> Bucket?,
	ReconfigureBucket: (self: RateLimiter, name: string, config: BucketConfig) -> (),
	ClearPlayer: (self: RateLimiter, player: Player) -> (),
	PurgeIdleAll: (self: RateLimiter, idleSeconds: number) -> number,
	Destroy: (self: RateLimiter) -> (),
}

type RateLimiterInternal = RateLimiter & {
	_buckets: { [string]: Bucket },
}

-- ====================================================================
-- Internals
-- ====================================================================

local function GetUserId(player: Player): number
	return player.UserId
end

local function RefillTokens(state: PlayerBucketState, config: BucketConfig, now: number)
	local elapsedSeconds = now - state.lastRefillTime
	if elapsedSeconds <= 0 then
		return
	end
	state.lastRefillTime = now
	state.tokens = math.clamp(state.tokens + elapsedSeconds * config.ratePerSecond, 0, config.burst)
end

-- ====================================================================
-- Bucket class
-- ====================================================================

local BucketClass = {}
BucketClass.__index = BucketClass

--- Creates a new Bucket instance.
--- @param name string A unique name for the bucket for identification.
--- @param config BucketConfig The configuration for rate and burst size.
--- @return Bucket The new Bucket object.
function BucketClass.new(name: string, config: BucketConfig): Bucket
	assert(config.ratePerSecond > 0, (`[%s] ratePerSecond must be > 0`):format(name))
	assert(config.burst > 0, (`[%s] burst must be > 0`):format(name))

	local frozenConfig: BucketConfig = table.freeze({
		ratePerSecond = config.ratePerSecond,
		burst = config.burst,
	})

	local rawTable = setmetatable({}, BucketClass)
	rawTable.Name = name
	rawTable.Config = frozenConfig
	rawTable.PerPlayer = {} :: { [number]: PlayerBucketState }
	return (rawTable :: any) :: Bucket
end

--- Updates the configuration of an existing bucket.
--- @param config BucketConfig The new configuration to apply.
function BucketClass:Reconfigure(config: BucketConfig)
	assert(config.ratePerSecond > 0, (`[%s] ratePerSecond must be > 0`):format(self.Name))
	assert(config.burst > 0, (`[%s] burst must be > 0`):format(self.Name))
	self.Config = table.freeze({
		ratePerSecond = config.ratePerSecond,
		burst = config.burst,
	})
end

--- Attempts to consume a number of tokens for a player.
--- If the player has enough tokens, they are consumed and it returns true.
--- Otherwise, it returns false.
--- @param player Player The player performing the action.
--- @param tokens number? The number of tokens to consume (defaults to 1).
--- @return boolean True if the tokens were successfully consumed, false otherwise.
function BucketClass:Allow(player: Player, tokens: number?): boolean
	local requestedTokens = tokens or 1
	assert(requestedTokens > 0, "requested tokens must be > 0")

	local config = self.Config
	if requestedTokens > config.burst then
		return false
	end

	local userId = GetUserId(player)
	local state = self.PerPlayer[userId]
	local now = os.clock()
	
	if state == nil then
		state = { tokens = config.burst, lastRefillTime = now }
		self.PerPlayer[userId] = state
	else
		RefillTokens(state, config, now)
	end

	if state.tokens >= requestedTokens then
		state.tokens -= requestedTokens
		return true
	end
	return false
end

--- Returns tokens to a player's bucket. Does not exceed the burst limit.
--- @param player Player The player to refund tokens to.
--- @param tokens number? The number of tokens to refund (defaults to 1).
function BucketClass:Refund(player: Player, tokens: number?)
	local tokensToRefund = tokens or 1
	assert(tokensToRefund >= 0, "refund tokens must be >= 0")
	if tokensToRefund == 0 then
		return
	end

	local userId = GetUserId(player)
	local state = self.PerPlayer[userId]
	if state == nil then
		-- No prior state; ignore rather than implicitly creating state.
		return
	end

	local now = os.clock()
	local config = self.Config
	RefillTokens(state, config, now)
	state.tokens = math.clamp(state.tokens + tokensToRefund, 0, config.burst)
end

--- Gets the current number of available tokens for a player after refilling.
--- @param player Player The player to check.
--- @return number The current number of tokens, up to the burst limit.
function BucketClass:GetTokens(player: Player): number
	local userId = GetUserId(player)
	local state = self.PerPlayer[userId]
	if state == nil then
		return self.Config.burst
	end
	local now = os.clock()
	RefillTokens(state, self.Config, now)
	return state.tokens
end

--- Calculates how many seconds until the player has at least one token.
--- Returns 0 if the player already has one or more tokens.
--- @param player Player The player to check.
--- @return number The time in seconds until the next token is available.
function BucketClass:SecondsUntilNextToken(player: Player): number
	local userId = GetUserId(player)
	local state = self.PerPlayer[userId]
	if state == nil then
		return 0
	end
	local now = os.clock()
	local config = self.Config
	RefillTokens(state, config, now)
	if state.tokens >= 1 then
		return 0
	end
	return (1 - state.tokens) / config.ratePerSecond
end

--- Calculates how many seconds until the player can afford a specific cost.
--- Returns 0 if they can already afford it.
--- Returns math.huge if the cost is greater than the bucket's burst size.
--- @param player Player The player to check.
--- @param tokens number? The number of tokens required (defaults to 1).
--- @return number The time in seconds until the requested tokens are available.
function BucketClass:TimeUntilAllow(player: Player, tokens: number?): number
	local requestedTokens = tokens or 1
	if requestedTokens <= 0 then
		return 0
	end

	local config = self.Config
	if requestedTokens > config.burst then
		return math.huge
	end

	local userId = GetUserId(player)
	local state = self.PerPlayer[userId]
	if state == nil then
		return 0
	end
	local now = os.clock()
	RefillTokens(state, config, now)

	local missingTokens = requestedTokens - state.tokens
	if missingTokens <= 0 then
		return 0
	end
	return missingTokens / config.ratePerSecond
end

--- Removes a single player's state from the bucket.
--- @param player Player The player to clear.
function BucketClass:Clear(player: Player)
	self.PerPlayer[GetUserId(player)] = nil
end

--- Removes all player states that have been idle for a given duration.
--- @param idleSeconds number The minimum number of seconds a player must be idle to be purged.
--- @return number The number of player states that were removed.
function BucketClass:PurgeIdle(idleSeconds: number): number
	assert(idleSeconds >= 0, "idleSeconds must be >= 0")
	local now = os.clock()
	local cutoff = now - idleSeconds
	local removedCount = 0
	for userId, state in pairs(self.PerPlayer) do
		if state.lastRefillTime < cutoff then
			self.PerPlayer[userId] = nil
			removedCount += 1
		end
	end
	return removedCount
end

--- Clears all player states from the bucket.
function BucketClass:Reset()
	for userId in pairs(self.PerPlayer) do
		self.PerPlayer[userId] = nil
	end
end

-- ====================================================================
-- RateLimiter class
-- ====================================================================

local RateLimiterClass = {}
RateLimiterClass.__index = RateLimiterClass

--- Creates a new RateLimiter instance to manage multiple buckets.
--- @return RateLimiter The new RateLimiter object.
function RateLimiterClass.new(): RateLimiter
	local newTable = setmetatable({}, RateLimiterClass)
	newTable._buckets = {} :: { [string]: Bucket }
	return (newTable :: any) :: RateLimiter
end

--- Gets or creates a bucket with the given name and configuration.
--- If a bucket with the name already exists, it will be reconfigured.
--- @param name string The unique name of the bucket.
--- @param config BucketConfig The configuration for the bucket.
--- @return Bucket The existing or newly created bucket.
function RateLimiterClass:Bucket(name: string, config: BucketConfig): Bucket
	local existingBucket = self._buckets[name]
	if existingBucket ~= nil then
		existingBucket:Reconfigure(config)
		return existingBucket
	end
	local createdBucket = BucketClass.new(name, config)
	self._buckets[name] = createdBucket
	return createdBucket
end

--- Retrieves an existing bucket by name.
--- @param name string The name of the bucket to retrieve.
--- @return Bucket? The bucket if it exists, otherwise nil.
function RateLimiterClass:GetBucket(name: string): Bucket?
	return self._buckets[name]
end

--- Updates the configuration of an existing bucket by name.
--- Does nothing if the bucket does not exist.
--- @param name string The name of the bucket to reconfigure.
--- @param config BucketConfig The new configuration.
function RateLimiterClass:ReconfigureBucket(name: string, config: BucketConfig)
	local bucket = self._buckets[name]
	if bucket ~= nil then
		bucket:Reconfigure(config)
	end
end

--- Clears a specific player's state from all managed buckets.
--- Useful when a player leaves the game.
--- @param player Player The player whose state should be cleared.
function RateLimiterClass:ClearPlayer(player: Player)
	self = self :: RateLimiterInternal
	for _, bucket in pairs(self._buckets) do
		bucket:Clear(player)
	end
end

--- Runs PurgeIdle on all managed buckets with the given duration.
--- @param idleSeconds number The minimum number of seconds a player must be idle to be purged.
--- @return number The total number of player states removed across all buckets.
function RateLimiterClass:PurgeIdleAll(idleSeconds: number): number
	self = self :: RateLimiterInternal
	local totalRemoved = 0
	for _, bucket in pairs(self._buckets) do
		totalRemoved += bucket:PurgeIdle(idleSeconds)
	end
	return totalRemoved
end

--- Clears all buckets from the RateLimiter, effectively resetting it.
function RateLimiterClass:Destroy()
	self = self :: RateLimiterInternal
	for key in pairs(self._buckets) do
		self._buckets[key] = nil
	end
end

return RateLimiterClass
