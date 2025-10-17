local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local HttpService = game:GetService("HttpService")

local JobPackets = require(ReplicatedStorage.Network.JobPackets)
local JobCatalog = require(ReplicatedStorage.Shared.Configurations.JobCatalog)
local DataStore = require(ServerStorage.ServerPackages.DataStore)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)

type JobRarity = JobCatalog.JobRarity
type JobEntry = JobCatalog.JobEntry

type ListingMetrics = {
	Listings: number,
	SlotsRemaining: number,
}

type Metrics = {
	TotalListings: number,
	TotalSlotsRemaining: number,
	ByRarity: { [JobRarity]: ListingMetrics },
}

type ListingState = {
	JobId: string,
	Rarity: JobRarity,
	Type: "Gig" | "Profession",
	SlotsRemaining: number?,
	MaxSlots: number?,
	PostedAt: number,
	LastTakenAt: number?,
	LastTakenBy: number?,
	Unlimited: boolean,
}

type BoardState = {
	Version: number,
	RestockId: string,
	LastRestock: number,
	NextRestock: number,
	Listings: { ListingState },
	Metrics: Metrics,
}

type DataStoreObject = DataStore.DataStore

local RARITIES: { JobRarity } = { "Common", "Uncommon", "Rare", "Elite" }
local DEBUG_LOGGING = true

local RESTOCK_CONFIG = {
	IntervalSeconds = 45 * 60,
	JitterSeconds = 5 * 60,
	TotalListings = 12,
	Rarity = {
		Common = { Slots = { Min = 6, Max = 12 } },
		Uncommon = { Slots = { Min = 4, Max = 8 } },
		Rare = { Slots = { Min = 3, Max = 5 } },
		Elite = { Slots = { Min = 1, Max = 2 } },
	},
}

local BOARD_STORE_NAME = "GlobalJobBoard"
local BOARD_SCOPE = "Public"
local BOARD_KEY = "Current"

local SYNC_INTERVAL_SECONDS = 45
local LOCKED_BACKOFF_SECONDS = 5
local MIN_SYNC_WAIT = 15
local POST_RESTOCK_SYNC_DELAY = 5

local function createEmptyMetrics(): Metrics
	local byRarity = {} :: { [JobRarity]: ListingMetrics }
	for _, rarity in ipairs(RARITIES) do
		byRarity[rarity] = { Listings = 0, SlotsRemaining = 0 }
	end
	return {
		TotalListings = 0,
		TotalSlotsRemaining = 0,
		ByRarity = byRarity,
	}
end

local BOARD_TEMPLATE: BoardState = {
	Version = 1,
	RestockId = "",
	LastRestock = 0,
	NextRestock = 0,
	Listings = {},
	Metrics = createEmptyMetrics(),
}

local JobListingService = {}

local jobListingFolder: Folder? = nil
local store: DataStoreObject? = nil
local running = false
local maintenanceThread: thread? = nil
local currentBoard: BoardState? = nil
local currentBoardHash = ""

local JOBS_BY_ID: { [string]: JobEntry } = {}
for _, job in JobCatalog.Jobs do
	JOBS_BY_ID[job.Id] = job
end

local DataStoreResponse = DataStore.Response

local function formatTimestamp(timestamp: number): string
	if timestamp <= 0 then
		return "n/a"
	end
	return os.date("%Y-%m-%d %H:%M:%S", timestamp)
end

local function debugPrintBoard(context: string, board: BoardState)
	if not DEBUG_LOGGING then
		return
	end
	local summary = ("[JobListingService] %s | RestockId=%s | Listings=%d | SlotsRemaining=%d | NextRestock=%s"):format(
		context,
		board.RestockId ~= "" and board.RestockId or "<none>",
		board.Metrics.TotalListings,
		board.Metrics.TotalSlotsRemaining,
		formatTimestamp(board.NextRestock)
	)
	print(summary)
	for _, rarity in ipairs(RARITIES) do
		local rarityMetrics = board.Metrics.ByRarity[rarity]
		if rarityMetrics.Listings > 0 then
			print(("  - %s: listings=%d slots=%d"):format(rarity, rarityMetrics.Listings, rarityMetrics.SlotsRemaining))
		end
	end
	for index, listing in ipairs(board.Listings) do
		if index > 5 then
			print("  … (additional listings truncated)")
			break
		end
		if listing.Unlimited then
			print(("    * %s (Gig) unlimited"):format(listing.JobId))
		else
			print(
				("    * %s (%s) slots=%d/%d"):format(
					listing.JobId,
					listing.Rarity,
					listing.SlotsRemaining or 0,
					listing.MaxSlots or 0
				)
			)
		end
	end
end

local function deepCopyMetrics(source: Metrics): Metrics
	local byRarity = {} :: { [JobRarity]: ListingMetrics }
	for _, rarity in ipairs(RARITIES) do
		local data = source.ByRarity[rarity]
		if data then
			byRarity[rarity] = {
				Listings = data.Listings,
				SlotsRemaining = data.SlotsRemaining,
			}
		else
			byRarity[rarity] = { Listings = 0, SlotsRemaining = 0 }
		end
	end
	return {
		TotalListings = source.TotalListings,
		TotalSlotsRemaining = source.TotalSlotsRemaining,
		ByRarity = byRarity,
	}
end

local function validateResidentForJob(player: Player, residentName: string?, job: JobEntry): (boolean, string?)
	if job.Requirements == nil or #job.Requirements == 0 then
		return true, nil
	end
	if residentName == nil or residentName == "" then
		return false, "Select a resident to apply for this job."
	end
	local residentState = ResidentService.GetResident(player, residentName)
	if residentState == nil then
		return false, "Resident not available. Make sure they are loaded."
	end
	local save = (residentState :: any).Save
	local statistics = if type(save) == "table" then save.Statistics else nil
	if type(statistics) ~= "table" then
		statistics = {}
	end
	for _, requirement in ipairs(job.Requirements) do
		local statName = requirement.Stat
		local requiredLevel = requirement.Level
		local current = statistics[statName]
		if type(current) ~= "number" then
			current = 0
		end
		if current < requiredLevel then
			return false, ("%s requires %s %d."):format(job.Name, statName, requiredLevel)
		end
	end
	return true, nil
end

local function computeMetrics(listings: { ListingState }): Metrics
	local metrics = createEmptyMetrics()
	metrics.TotalListings = #listings
	for _, listing in ipairs(listings) do
		local entry = metrics.ByRarity[listing.Rarity]
		entry.Listings += 1
		if not listing.Unlimited then
			local remaining = listing.SlotsRemaining or 0
			metrics.TotalSlotsRemaining += remaining
			entry.SlotsRemaining += remaining
		end
	end
	return metrics
end

local function sanitizeListing(rawListing: any): ListingState?
	if type(rawListing) ~= "table" then
		return nil
	end
	local jobId = rawListing.JobId
	if type(jobId) ~= "string" or jobId == "" then
		return nil
	end
	local job = JOBS_BY_ID[jobId]
	if job == nil then
		return nil
	end
	local isUnlimited = job.Type == "Gig"
	if typeof(rawListing.Unlimited) == "boolean" then
		isUnlimited = rawListing.Unlimited
	end
	local function asInteger(value: any, fallback: number): number
		local numeric = tonumber(value)
		if numeric == nil then
			return fallback
		end
		numeric = math.floor(numeric)
		if numeric < 0 then
			numeric = 0
		end
		return numeric
	end
	local postedAt = asInteger(rawListing.PostedAt, os.time())
	local lastTakenAt = rawListing.LastTakenAt and asInteger(rawListing.LastTakenAt, 0) or nil
	local lastTakenBy = rawListing.LastTakenBy and asInteger(rawListing.LastTakenBy, 0) or nil
	if isUnlimited then
		return {
			JobId = job.Id,
			Rarity = job.Rarity,
			Type = job.Type,
			SlotsRemaining = nil,
			MaxSlots = nil,
			PostedAt = postedAt,
			LastTakenAt = lastTakenAt,
			LastTakenBy = lastTakenBy,
			Unlimited = true,
		}
	end
	local maxSlots = asInteger(rawListing.MaxSlots, 0)
	if maxSlots <= 0 then
		return nil
	end
	local slotsRemaining = asInteger(rawListing.SlotsRemaining, maxSlots)
	if slotsRemaining > maxSlots then
		slotsRemaining = maxSlots
	end
	if slotsRemaining <= 0 then
		return nil
	end
	return {
		JobId = job.Id,
		Rarity = job.Rarity,
		Type = job.Type,
		SlotsRemaining = slotsRemaining,
		MaxSlots = maxSlots,
		PostedAt = postedAt,
		LastTakenAt = lastTakenAt,
		LastTakenBy = lastTakenBy,
		Unlimited = false,
	}
end

local function sanitizeBoard(raw: any): BoardState
	local board: BoardState = {
		Version = BOARD_TEMPLATE.Version,
		RestockId = "",
		LastRestock = 0,
		NextRestock = 0,
		Listings = {},
		Metrics = createEmptyMetrics(),
	}
	if type(raw) == "table" then
		if type(raw.Version) == "number" then
			board.Version = raw.Version
		end
		if type(raw.RestockId) == "string" then
			board.RestockId = raw.RestockId
		end
		if type(raw.LastRestock) == "number" then
			board.LastRestock = raw.LastRestock
		end
		if type(raw.NextRestock) == "number" then
			board.NextRestock = raw.NextRestock
		end
		if type(raw.Listings) == "table" then
			for _, listing in ipairs(raw.Listings) do
				local cleaned = sanitizeListing(listing)
				if cleaned then
					table.insert(board.Listings, cleaned)
				end
			end
		end
	end
	if board.Version ~= BOARD_TEMPLATE.Version then
		board.Version = BOARD_TEMPLATE.Version
		board.RestockId = ""
		board.LastRestock = 0
		board.NextRestock = 0
		board.Listings = {}
	end
	board.Metrics = computeMetrics(board.Listings)
	return board
end

local function cloneBoard(board: BoardState): BoardState
	local listingsCopy = table.create(#board.Listings)
	for index, listing in ipairs(board.Listings) do
		listingsCopy[index] = {
			JobId = listing.JobId,
			Rarity = listing.Rarity,
			Type = listing.Type,
			SlotsRemaining = listing.SlotsRemaining,
			MaxSlots = listing.MaxSlots,
			PostedAt = listing.PostedAt,
			LastTakenAt = listing.LastTakenAt,
			LastTakenBy = listing.LastTakenBy,
			Unlimited = listing.Unlimited,
		}
	end
	return {
		Version = board.Version,
		RestockId = board.RestockId,
		LastRestock = board.LastRestock,
		NextRestock = board.NextRestock,
		Listings = listingsCopy,
		Metrics = deepCopyMetrics(board.Metrics),
	}
end

local function ensureStore(): DataStoreObject
	if store ~= nil then
		return store
	end
	local created = DataStore.new(BOARD_STORE_NAME, BOARD_SCOPE, BOARD_KEY)
	created.SaveInterval = 0
	store = created
	return created
end

local function computeBoardHash(board: BoardState): string
	local parts = table.create(#board.Listings * 3 + 4)
	parts[#parts + 1] = tostring(board.Version)
	parts[#parts + 1] = board.RestockId
	parts[#parts + 1] = tostring(board.LastRestock)
	parts[#parts + 1] = tostring(board.NextRestock)
	for _, listing in ipairs(board.Listings) do
		parts[#parts + 1] = listing.JobId
		parts[#parts + 1] = tostring(listing.SlotsRemaining or -1)
		parts[#parts + 1] = tostring(listing.MaxSlots or -1)
		parts[#parts + 1] = listing.Unlimited and "1" or "0"
	end
	return table.concat(parts, "|")
end

local function applyBoard(board: BoardState)
	local boardCopy = cloneBoard(board)
	local hash = computeBoardHash(boardCopy)
	currentBoard = boardCopy
	if hash == currentBoardHash then
		return
	end
	currentBoardHash = hash
	if not jobListingFolder then
		return
	end
	jobListingFolder:SetAttribute("RestockId", boardCopy.RestockId)
	jobListingFolder:SetAttribute("LastRestock", boardCopy.LastRestock)
	jobListingFolder:SetAttribute("NextRestock", boardCopy.NextRestock)
	jobListingFolder:SetAttribute("TotalListings", boardCopy.Metrics.TotalListings)
	jobListingFolder:SetAttribute("TotalSlotsRemaining", boardCopy.Metrics.TotalSlotsRemaining)
	for _, rarity in ipairs(RARITIES) do
		local data = boardCopy.Metrics.ByRarity[rarity]
		jobListingFolder:SetAttribute(rarity .. "Listings", data and data.Listings or 0)
		jobListingFolder:SetAttribute(rarity .. "Slots", data and data.SlotsRemaining or 0)
	end
	local seenFolders: { [Instance]: boolean } = {}
	for _, listing in ipairs(boardCopy.Listings) do
		local listingFolder = jobListingFolder:FindFirstChild(listing.JobId)
		if listingFolder == nil or not listingFolder:IsA("Folder") then
			if listingFolder then
				listingFolder:Destroy()
			end
			listingFolder = Instance.new("Folder")
			listingFolder.Name = listing.JobId
			listingFolder.Parent = jobListingFolder
		end
		listingFolder:SetAttribute("JobId", listing.JobId)
		listingFolder:SetAttribute("Rarity", listing.Rarity)
		listingFolder:SetAttribute("Type", listing.Type)
		listingFolder:SetAttribute("SlotsRemaining", listing.SlotsRemaining or -1)
		listingFolder:SetAttribute("MaxSlots", listing.MaxSlots or -1)
		listingFolder:SetAttribute("PostedAt", listing.PostedAt)
		listingFolder:SetAttribute("LastTakenAt", listing.LastTakenAt or 0)
		listingFolder:SetAttribute("LastTakenBy", listing.LastTakenBy or 0)
		listingFolder:SetAttribute("RestockId", boardCopy.RestockId)
		listingFolder:SetAttribute("Unlimited", listing.Unlimited)
		seenFolders[listingFolder] = true
	end
	for _, child in ipairs(jobListingFolder:GetChildren()) do
		if not seenFolders[child] and child:IsA("Folder") then
			child:Destroy()
		end
	end
	debugPrintBoard("BoardApplied", boardCopy)
end

local function needsRestock(board: BoardState, now: number): boolean
	if #board.Listings == 0 then
		return true
	end
	if board.Metrics.TotalSlotsRemaining <= 0 then
		return true
	end
	if board.NextRestock <= now then
		return true
	end
	return false
end

local function buildRestockBoard(now: number, previous: BoardState?): BoardState
	local listings = {} :: { ListingState }
	local seed = HttpService:GenerateGUID(false)
	local rng = Random.new(now + #seed)
	local catalogWeights = JobCatalog.RarityWeights
	local availableByRarity = {} :: { [JobRarity]: { JobEntry } }

	for _, rarity in ipairs(RARITIES) do
		local options = JobCatalog.JobsByRarity[rarity]
		if options and #options > 0 then
			local copy = table.create(#options)
			for index, job in ipairs(options) do
				copy[index] = job
			end
			availableByRarity[rarity] = copy
		end
	end

	local function getRarityWeight(rarity: JobRarity): number
		local rules = RESTOCK_CONFIG.Rarity[rarity]
		if rules and type(rules.Weight) == "number" then
			return math.max(rules.Weight, 0)
		end
		local weight = catalogWeights[rarity]
		if type(weight) == "number" then
			return math.max(weight, 0)
		end
		return 0
	end

	local function resolveSlotRange(rarity: JobRarity): (number, number)
		local rules = RESTOCK_CONFIG.Rarity[rarity]
		local slotsConfig = if rules then rules.Slots else nil
		local minSlots = if slotsConfig and type(slotsConfig.Min) == "number" then math.max(slotsConfig.Min, 1) else 1
		local maxSlots = if slotsConfig and type(slotsConfig.Max) == "number"
			then math.max(slotsConfig.Max, minSlots)
			else minSlots
		if maxSlots < minSlots then
			maxSlots = minSlots
		end
		return minSlots, maxSlots
	end

	local function pickWeightedRarity(): JobRarity?
		local totalWeight = 0
		for _, rarity in ipairs(RARITIES) do
			local pool = availableByRarity[rarity]
			if pool and #pool > 0 then
				totalWeight += getRarityWeight(rarity)
			end
		end
		if totalWeight <= 0 then
			return nil
		end
		local roll = rng:NextNumber(0, totalWeight)
		local cumulative = 0
		for _, rarity in ipairs(RARITIES) do
			local pool = availableByRarity[rarity]
			if pool and #pool > 0 then
				cumulative += getRarityWeight(rarity)
				if roll <= cumulative then
					return rarity
				end
			end
		end
		return nil
	end

	local targetCountValue = RESTOCK_CONFIG.TotalListings or 10
	local targetCount = math.max(1, math.floor(targetCountValue))

	while #listings < targetCount do
		local rarity = pickWeightedRarity()
		if not rarity then
			break
		end

		local pool = availableByRarity[rarity]
		if not pool or #pool == 0 then
			break
		end

		local jobIndex = rng:NextInteger(1, #pool)
		local job = table.remove(pool, jobIndex)
		local listing: ListingState

		if job.Type == "Gig" then
			listing = {
				JobId = job.Id,
				Rarity = job.Rarity,
				Type = job.Type,
				SlotsRemaining = nil,
				MaxSlots = nil,
				PostedAt = now,
				LastTakenAt = nil,
				LastTakenBy = nil,
				Unlimited = true,
			}
		else
			local minSlots, maxSlots = resolveSlotRange(job.Rarity)
			local slots = rng:NextInteger(minSlots, maxSlots)
			listing = {
				JobId = job.Id,
				Rarity = job.Rarity,
				Type = job.Type,
				SlotsRemaining = slots,
				MaxSlots = slots,
				PostedAt = now,
				LastTakenAt = nil,
				LastTakenBy = nil,
				Unlimited = false,
			}
		end

		listings[#listings + 1] = listing
	end

	for index = #listings, 2, -1 do
		local swapIndex = rng:NextInteger(1, index)
		listings[index], listings[swapIndex] = listings[swapIndex], listings[index]
	end
	local interval = RESTOCK_CONFIG.IntervalSeconds
	local jitter = RESTOCK_CONFIG.JitterSeconds
	local nextRestock = now + interval
	if jitter > 0 then
		nextRestock += rng:NextInteger(-jitter, jitter)
		local minimumNext = now + math.floor(interval * 0.5)
		if nextRestock < minimumNext then
			nextRestock = minimumNext
		end
	end
	local board: BoardState = {
		Version = BOARD_TEMPLATE.Version,
		RestockId = HttpService:GenerateGUID(false),
		LastRestock = now,
		NextRestock = nextRestock,
		Listings = listings,
		Metrics = computeMetrics(listings),
	}
	if previous and previous.Version ~= BOARD_TEMPLATE.Version then
		board.Version = BOARD_TEMPLATE.Version
	end
	return board
end

local function readBoard(forceApply: boolean): string
	local dataStore = ensureStore()
	local response = dataStore:Read(BOARD_TEMPLATE)
	if response == DataStoreResponse.Success then
		local board = sanitizeBoard(dataStore.Value)
		if forceApply or currentBoard == nil or computeBoardHash(board) ~= currentBoardHash then
			applyBoard(board)
		end
		return "Success"
	elseif response == DataStoreResponse.Locked then
		return "Locked"
	else
		warn("[JobListingService] Failed to read global job board:", response)
		return "Error"
	end
end

local function closeStore(dataStore: DataStoreObject)
	local ok, errorMessage = pcall(function()
		dataStore:Close()
	end)
	if not ok then
		warn("[JobListingService] Failed to close job board store:", errorMessage)
	end
end

local function saveStore(dataStore: DataStoreObject): string
	local response = dataStore:Save()
	if response ~= DataStoreResponse.Saved then
		warn("[JobListingService] Failed to save job board:", response)
	end
	return response
end

local function tryRestock(now: number?): string
	local dataStore = ensureStore()
	local response = dataStore:Open(BOARD_TEMPLATE)
	if response == DataStoreResponse.Success then
		local board = sanitizeBoard(dataStore.Value)
		local currentTime = if now ~= nil then now else os.time()
		if not needsRestock(board, currentTime) then
			closeStore(dataStore)
			applyBoard(board)
			return "Noop"
		end
		local nextBoard = buildRestockBoard(currentTime, board)
		dataStore.Value = nextBoard
		local saveResponse = saveStore(dataStore)
		closeStore(dataStore)
		if saveResponse == DataStoreResponse.Saved then
			applyBoard(nextBoard)
			return "Restocked"
		end
		return "Error"
	elseif response == DataStoreResponse.Locked then
		return "Locked"
	else
		warn("[JobListingService] Failed to open job board for restock:", response)
		return "Error"
	end
end

local function maintenanceLoop()
	while running do
		local now = os.time()
		local boardSnapshot = currentBoard
		if boardSnapshot == nil then
			local status = readBoard(true)
			if status == "Locked" then
				task.wait(LOCKED_BACKOFF_SECONDS)
			else
				task.wait(SYNC_INTERVAL_SECONDS)
			end
		else
			if needsRestock(boardSnapshot, now) then
				local status = tryRestock(now)
				if status == "Restocked" then
					task.wait(POST_RESTOCK_SYNC_DELAY)
				elseif status == "Locked" then
					task.wait(LOCKED_BACKOFF_SECONDS)
				else
					task.wait(SYNC_INTERVAL_SECONDS)
				end
			else
				local status = readBoard(false)
				if status == "Locked" then
					task.wait(LOCKED_BACKOFF_SECONDS)
				else
					local waitUntil = math.max(boardSnapshot.NextRestock - now, MIN_SYNC_WAIT)
					local waitTime = math.min(waitUntil, SYNC_INTERVAL_SECONDS)
					task.wait(waitTime)
				end
			end
		end
	end
end

local function ensureMaintenanceRunning()
	if maintenanceThread == nil or coroutine.status(maintenanceThread) == "dead" then
		maintenanceThread = task.spawn(maintenanceLoop)
	end
end

local function reserveJobSlot(player: Player, jobId: string, residentName: string?): (boolean, string)
	if jobId == "" then
		return false, "Select a job before applying."
	end
	local job = JOBS_BY_ID[jobId]
	if job == nil then
		return false, "That posting does not exist anymore."
	end
	local allowed, denial = validateResidentForJob(player, residentName, job)
	if not allowed then
		return false, denial or "Resident does not meet the requirements."
	end
	local dataStore = ensureStore()
	local response = dataStore:Open(BOARD_TEMPLATE)
	if response ~= DataStoreResponse.Success then
		if response == DataStoreResponse.Locked then
			return false, "The hiring board is busy. Please try again."
		end
		warn("[JobListingService] Failed to open job board for request:", response)
		return false, "Job board temporarily unavailable."
	end
	local now = os.time()
	local board = sanitizeBoard(dataStore.Value)
	if needsRestock(board, now) then
		board = buildRestockBoard(now, board)
	end
	local listingIndex = nil
	for index, listing in ipairs(board.Listings) do
		if listing.JobId == jobId then
			listingIndex = index
			break
		end
	end
	if listingIndex == nil then
		dataStore.Value = board
		saveStore(dataStore)
		closeStore(dataStore)
		applyBoard(board)
		task.defer(function()
			tryRestock()
		end)
		return false, "Positions for that listing are gone."
	end
	local listing = board.Listings[listingIndex]
	if listing.Unlimited then
		listing.LastTakenAt = now
		listing.LastTakenBy = player.UserId
		board.Metrics = computeMetrics(board.Listings)
		dataStore.Value = board
		local saveResponse = saveStore(dataStore)
		closeStore(dataStore)
		if saveResponse ~= DataStoreResponse.Saved then
			return false, "Could not secure the job. Please try again."
		end
		applyBoard(board)
		return true, job.Name .. " secured!"
	end
	if (listing.SlotsRemaining or 0) <= 0 then
		table.remove(board.Listings, listingIndex)
		board.Metrics = computeMetrics(board.Listings)
		dataStore.Value = board
		saveStore(dataStore)
		closeStore(dataStore)
		applyBoard(board)
		task.defer(function()
			tryRestock()
		end)
		return false, "That job has just been filled."
	end
	listing.SlotsRemaining = (listing.SlotsRemaining or 0) - 1
	listing.LastTakenAt = now
	listing.LastTakenBy = player.UserId
	if listing.SlotsRemaining <= 0 then
		table.remove(board.Listings, listingIndex)
	end
	board.Metrics = computeMetrics(board.Listings)
	if board.Metrics.TotalListings == 0 or board.Metrics.TotalSlotsRemaining == 0 then
		board.NextRestock = now
	end
	dataStore.Value = board
	local saveResponse = saveStore(dataStore)
	closeStore(dataStore)
	if saveResponse ~= DataStoreResponse.Saved then
		return false, "Could not secure the job. Please try again."
	end
	applyBoard(board)
	if needsRestock(board, now) then
		task.defer(function()
			tryRestock()
		end)
	end
	return true, job.Name .. " secured!"
end

function JobListingService.Init()
	if jobListingFolder == nil then
		local folder = Instance.new("Folder")
		folder.Name = "JobListings"
		folder.Parent = workspace
		jobListingFolder = folder
	end
	ensureStore()
	JobPackets.RequestJob.OnServerInvoke = function(
		player: Player,
		jobId: string,
		residentName: string?
	): (boolean, string)
		return reserveJobSlot(player, jobId, residentName)
	end
end

function JobListingService.Start()
	if running then
		return
	end
	running = true
	readBoard(true)
	ensureMaintenanceRunning()
end

function JobListingService.Stop()
	if not running then
		return
	end
	running = false
	if maintenanceThread and coroutine.status(maintenanceThread) ~= "dead" then
		task.cancel(maintenanceThread)
	end
	maintenanceThread = nil
end

function JobListingService.GetBoardSnapshot(): BoardState?
	if currentBoard == nil then
		return nil
	end
	return cloneBoard(currentBoard)
end

return JobListingService
