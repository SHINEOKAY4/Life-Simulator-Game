local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ═══════════════════════════════════════════════════════════════════════════
-- BUG FIX: ItemFinder.SearchCatalog case-sensitivity mismatch
--
-- The SearchBlob for each item is built from sanitizeComponent() which
-- lowercases everything.  extractQueryTokens() also lowercases tokens for
-- the token-index lookup.  However, the final string.find verification
-- previously used the raw normalizedQuery against the lowered SearchBlob.
-- Any mixed-case query would pass token filtering but fail string.find.
-- ═══════════════════════════════════════════════════════════════════════════

describe("Iter 5b review: ItemFinder.SearchCatalog case-insensitive matching", function()
	it("lowercases the query before using it in string.find against SearchBlob", function()
		local contents = readFile("src/Shared/Utilities/ItemFinder.luau")
		-- Must create a lowered copy of the query
		local lowerAssign = string.find(contents, "local loweredQuery = string.lower(normalizedQuery)", 1, true)
		assert.is_truthy(lowerAssign, "must lowercase the query before blob matching")
	end)

	it("uses loweredQuery (not normalizedQuery) in string.find for blob search", function()
		local contents = readFile("src/Shared/Utilities/ItemFinder.luau")
		-- The string.find call must reference loweredQuery, not normalizedQuery
		assert.is_truthy(
			string.find(contents, "string.find(entry.SearchBlob, loweredQuery, 1, true)", 1, true),
			"string.find must use loweredQuery for case-insensitive matching"
		)
		-- Must NOT use normalizedQuery directly in string.find
		assert.is_falsy(
			string.find(contents, "string.find(entry.SearchBlob, normalizedQuery, 1, true)", 1, true),
			"must not use raw normalizedQuery in string.find"
		)
	end)

	it("SearchBlob components are lowered via sanitizeComponent", function()
		local contents = readFile("src/Shared/Utilities/ItemFinder.luau")
		-- sanitizeComponent must lowercase
		assert.is_truthy(
			string.find(contents, "return string.lower(trimmed)", 1, true),
			"sanitizeComponent must lowercase its output"
		)
	end)

	it("extractQueryTokens lowercases tokens for index lookup", function()
		local contents = readFile("src/Shared/Utilities/ItemFinder.luau")
		-- extractQueryTokens must lowercase tokens
		local fnStart = string.find(contents, "local function extractQueryTokens", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 500)
		assert.is_truthy(
			string.find(fnBody, "local lowered = string.lower(token)", 1, true),
			"extractQueryTokens must lowercase tokens"
		)
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- BUG FIX: MainHUD bill notifier tween target drops Offset components
--
-- The pulsing tween for the bill NotifierSymbol previously used
-- UDim2.fromScale(original.X.Scale * 1.2, original.Y.Scale * 1.2)
-- which zeroes out Offset components.  If the NotifierSymbol uses
-- offset-based sizing (e.g., UDim2.fromOffset(24, 24)), the tween
-- target becomes UDim2.fromScale(0, 0) — effectively invisible.
-- The fix uses UDim2.new() to scale both Scale and Offset components.
-- ═══════════════════════════════════════════════════════════════════════════

describe("Iter 5b review: MainHUD notifier tween preserves Offset components", function()
	it("uses UDim2.new() not UDim2.fromScale() for tween target Size", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		-- Find the tween creation for NotifierSymbol
		local tweenStart = string.find(contents, "TweenService:Create(NotifierSymbol, tweenInfo", 1, true)
		assert.is_truthy(tweenStart)
		-- Get the tween properties block
		local tweenBlock = string.sub(contents, tweenStart, tweenStart + 400)
		-- Must NOT use UDim2.fromScale for the tween target
		assert.is_falsy(
			string.find(tweenBlock, "UDim2.fromScale(notifierOriginalSize", 1, true),
			"must not use UDim2.fromScale which drops Offset components"
		)
		-- Must use UDim2.new to preserve both Scale and Offset
		assert.is_truthy(
			string.find(tweenBlock, "UDim2.new(", 1, true),
			"must use UDim2.new() to preserve both Scale and Offset"
		)
	end)

	it("scales both X.Scale and X.Offset by the same factor", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		assert.is_truthy(
			string.find(contents, "notifierOriginalSize.X.Scale * 1.2", 1, true),
			"must scale X.Scale by 1.2"
		)
		assert.is_truthy(
			string.find(contents, "notifierOriginalSize.X.Offset * 1.2", 1, true),
			"must scale X.Offset by 1.2"
		)
	end)

	it("scales both Y.Scale and Y.Offset by the same factor", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		assert.is_truthy(
			string.find(contents, "notifierOriginalSize.Y.Scale * 1.2", 1, true),
			"must scale Y.Scale by 1.2"
		)
		assert.is_truthy(
			string.find(contents, "notifierOriginalSize.Y.Offset * 1.2", 1, true),
			"must scale Y.Offset by 1.2"
		)
	end)

	it("rounds Offset values to avoid sub-pixel artifacts", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		-- Offset should be rounded to avoid sub-pixel rendering issues
		assert.is_truthy(
			string.find(contents, "math.round(notifierOriginalSize.X.Offset * 1.2)", 1, true),
			"must round X.Offset to nearest integer"
		)
		assert.is_truthy(
			string.find(contents, "math.round(notifierOriginalSize.Y.Offset * 1.2)", 1, true),
			"must round Y.Offset to nearest integer"
		)
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Edge case: StartupDiagnostics Boundary with yielding callbacks
-- ═══════════════════════════════════════════════════════════════════════════

describe("Iter 5b review: StartupDiagnostics edge cases", function()
	it("Boundary returns all values from a successful callback", function()
		local contents = readFile("src/Shared/Utilities/StartupDiagnostics.luau")
		-- table.unpack must start from index 2 (skipping pcall ok boolean)
		assert.is_truthy(
			string.find(contents, "table.unpack(result, 2, result.n)", 1, true),
			"must unpack from index 2 to preserve all callback return values"
		)
	end)

	it("Boundary re-raises the original error after logging", function()
		local contents = readFile("src/Shared/Utilities/StartupDiagnostics.luau")
		local errorPos = string.find(contents, "error(result[2], 0)", 1, true)
		assert.is_truthy(errorPos, "must re-raise the original error with level 0")
		-- The error emission must precede the re-raise
		local emitErrorPos = string.find(contents, '_emit("ERROR"', 1, true)
		assert.is_truthy(emitErrorPos, "must emit ERROR event")
		assert.is_true(emitErrorPos < errorPos, "ERROR emit must precede the re-raise")
	end)

	it("clock measurement uses subtraction, not absolute", function()
		local contents = readFile("src/Shared/Utilities/StartupDiagnostics.luau")
		assert.is_truthy(
			string.find(contents, "self._clock() - startedAt", 1, true),
			"elapsed must be computed as clock() - startedAt"
		)
	end)

	it("toMilliseconds rounds instead of truncating", function()
		local contents = readFile("src/Shared/Utilities/StartupDiagnostics.luau")
		-- math.floor(x + 0.5) is rounding, not truncating (math.floor(x) alone)
		assert.is_truthy(
			string.find(contents, "math.floor(seconds * 1000 + 0.5)", 1, true),
			"toMilliseconds must round (floor(x+0.5)) not truncate (floor(x))"
		)
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Edge case: Client Main.client.luau startup ordering
-- ═══════════════════════════════════════════════════════════════════════════

describe("Iter 5b review: Client Main startup ordering safety", function()
	it("resolves NetworkFolder before preloading packet modules", function()
		local contents = readFile("src/Client/Main.client.luau")
		local resolvePos = string.find(contents, 'ResolveDependency("ReplicatedStorage.Network"', 1, true)
		local preloadPos = string.find(contents, 'runStartupStep("PreloadNetworkPackets"', 1, true)
		assert.is_truthy(resolvePos)
		assert.is_truthy(preloadPos)
		assert.is_true(resolvePos < preloadPos,
			"NetworkFolder resolution must happen before preloading packet modules")
	end)

	it("asserts Network folder existence with timeout context", function()
		local contents = readFile("src/Client/Main.client.luau")
		assert.is_truthy(
			string.find(contents, "Missing required folder ReplicatedStorage.Network after", 1, true),
			"timeout assertion must include context about what was being waited for"
		)
	end)

	it("preloadPacketModules recurses into subfolders", function()
		local contents = readFile("src/Client/Main.client.luau")
		local fnStart = string.find(contents, "local function preloadPacketModules", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 400)
		-- Must recurse into child folders
		assert.is_truthy(
			string.find(fnBody, "preloadPacketModules(child)", 1, true),
			"must recurse into child folders"
		)
		-- Must only require ModuleScripts, not other instances
		assert.is_truthy(
			string.find(fnBody, 'child:IsA("ModuleScript")', 1, true),
			"must check IsA ModuleScript before requiring"
		)
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Edge case: Server OnPlayerAdded / OnPlayerRemoving ordering
-- ═══════════════════════════════════════════════════════════════════════════

describe("Iter 5b review: Server player lifecycle ordering", function()
	it("OnPlayerRemoving unloads residents before unclaiming plot", function()
		local contents = readFile("src/Server/Main.server.luau")
		local fnStart = string.find(contents, "local function OnPlayerRemoving", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 600)
		local residentUnloadPos = string.find(fnBody, "ResidentService.Unload(player)", 1, true)
		local plotUnclaimPos = string.find(fnBody, "PlotService.Unclaim(player)", 1, true)
		assert.is_truthy(residentUnloadPos, "must unload residents")
		assert.is_truthy(plotUnclaimPos, "must unclaim plot")
		assert.is_true(residentUnloadPos < plotUnclaimPos,
			"ResidentService.Unload must happen before PlotService.Unclaim to prevent dangling references")
	end)

	it("clears utility cache after unclaiming plot", function()
		local contents = readFile("src/Server/Main.server.luau")
		local fnStart = string.find(contents, "local function OnPlayerRemoving", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 600)
		local utilClearPos = string.find(fnBody, "UtilityService.ClearCache(player)", 1, true)
		local plotUnclaimPos = string.find(fnBody, "PlotService.Unclaim(player)", 1, true)
		assert.is_truthy(utilClearPos, "must clear utility cache")
		assert.is_true(utilClearPos > plotUnclaimPos,
			"UtilityService.ClearCache should happen after PlotService.Unclaim")
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Edge case: ItemFinder model resolution fallback
-- ═══════════════════════════════════════════════════════════════════════════

describe("Iter 5b review: ItemFinder model fallback correctness", function()
	it("fallback model uses magenta neon for visibility during development", function()
		local contents = readFile("src/Shared/Utilities/ItemFinder.luau")
		local fnStart = string.find(contents, "function ItemFinder.ResolveItemModel", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 1500)
		assert.is_truthy(
			string.find(fnBody, "Color3.fromRGB(255, 0, 255)", 1, true),
			"fallback part should use magenta for debug visibility"
		)
		assert.is_truthy(
			string.find(fnBody, "Enum.Material.Neon", 1, true),
			"fallback part should use Neon material for visibility"
		)
	end)

	it("fallback model sets PrimaryPart", function()
		local contents = readFile("src/Shared/Utilities/ItemFinder.luau")
		local fnStart = string.find(contents, "function ItemFinder.ResolveItemModel", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 1500)
		assert.is_truthy(
			string.find(fnBody, "model.PrimaryPart = part", 1, true),
			"fallback model must set PrimaryPart to avoid nil access downstream"
		)
	end)

	it("checks IsA Model after path traversal to avoid returning a Folder", function()
		local contents = readFile("src/Shared/Utilities/ItemFinder.luau")
		assert.is_truthy(
			string.find(contents, 'node:IsA("Model")', 1, true),
			"must verify resolved node IsA Model before returning"
		)
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Edge case: MainHUD cash delta handling
-- ═══════════════════════════════════════════════════════════════════════════

describe("Iter 5b review: MainHUD cash delta edge cases", function()
	it("guards against non-number cash attribute values", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		-- The cash attribute handler must guard typeof(newValue) ~= "number"
		assert.is_truthy(
			string.find(contents, 'typeof(newValue) ~= "number"', 1, true),
			"must guard against non-number cash attribute values"
		)
	end)

	it("validates CurrencyDelta payload type before processing", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		assert.is_truthy(
			string.find(contents, 'typeof(payload) ~= "table"', 1, true),
			"must validate payload is a table"
		)
	end)

	it("rejects negative amounts in currency delta events", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		-- amount <= 0 should be rejected
		assert.is_truthy(
			string.find(contents, "amount <= 0", 1, true),
			"must reject non-positive amounts in delta events"
		)
	end)

	it("tracks pendingCashIncrease to avoid double-counting server deltas", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		assert.is_truthy(
			string.find(contents, "pendingCashIncrease += amount", 1, true),
			"must accumulate pending cash increase"
		)
		assert.is_truthy(
			string.find(contents, "pendingCashIncrease = 0", 1, true),
			"must reset pending cash when fully consumed"
		)
	end)
end)

-- ═══════════════════════════════════════════════════════════════════════════
-- Edge case: MainHUD income per second NaN guard
-- ═══════════════════════════════════════════════════════════════════════════

describe("Iter 5b review: MainHUD income display NaN guard", function()
	it("guards against NaN in formatIncomePerSecond", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		-- NaN check: amount ~= amount is true only for NaN
		assert.is_truthy(
			string.find(contents, "amount ~= amount", 1, true),
			"must guard against NaN (amount ~= amount)"
		)
	end)

	it("clamps negative income to zero", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		assert.is_truthy(
			string.find(contents, "math.max(amount, 0)", 1, true),
			"must clamp negative income values to 0"
		)
	end)
end)
