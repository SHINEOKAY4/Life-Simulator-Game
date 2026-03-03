local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

describe("Iter 5 review: StartupDiagnostics nil callback guard", function()
	it("asserts non-nil callback before emitting BEGIN", function()
		local contents = readFile("src/Shared/Utilities/StartupDiagnostics.luau")
		-- The guard must come BEFORE the _emit("BEGIN") call so the sequence counter
		-- is not incremented for a boundary that never completes.
		local guardPos = string.find(contents, 'assert(type(callback) == "function"', 1, true)
		local beginPos = string.find(contents, '_emit("BEGIN"', 1, true)
		assert.is_truthy(guardPos, "missing nil-callback assert in Boundary")
		assert.is_truthy(beginPos, "missing BEGIN emit in Boundary")
		assert.is_true(guardPos < beginPos, "nil-callback guard must precede BEGIN emit")
	end)

	it("includes channel and step name in the nil-callback error message", function()
		local contents = readFile("src/Shared/Utilities/StartupDiagnostics.luau")
		assert.is_truthy(string.find(contents, "self.Channel", 1, true))
		assert.is_truthy(string.find(contents, "received a nil callback", 1, true))
	end)
end)

describe("Iter 5 review: MainHUD bill notifier tween does not compound", function()
	it("saves the original NotifierSymbol size before tweening", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		assert.is_truthy(
			string.find(contents, "notifierOriginalSize", 1, true),
			"must capture the original notifier size into a stable local"
		)
	end)

	it("resets NotifierSymbol to original size before creating a new tween", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		-- When billDue is true, the size must be reset to notifierOriginalSize
		-- before a new tween is created, to avoid compounding.
		local resetPos = string.find(contents, "NotifierSymbol.Size = notifierOriginalSize", 1, true)
		local tweenCreatePos = string.find(contents, "TweenService:Create(NotifierSymbol, tweenInfo", 1, true)
		assert.is_truthy(resetPos, "must reset size to original before creating tween")
		assert.is_truthy(tweenCreatePos, "must create tween on NotifierSymbol")
		assert.is_true(resetPos < tweenCreatePos, "size reset must happen before tween creation")
	end)

	it("computes tween target from notifierOriginalSize not live Size", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		assert.is_truthy(
			string.find(contents, "notifierOriginalSize.X.Scale * 1.2", 1, true),
			"tween target X must derive from saved original size"
		)
		assert.is_truthy(
			string.find(contents, "notifierOriginalSize.Y.Scale * 1.2", 1, true),
			"tween target Y must derive from saved original size"
		)
	end)

	it("uses original size (not hardcoded 1,1) when resetting on bill paid", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		-- Find just the updateBillNotifier function body
		local fnStart = string.find(contents, "local function updateBillNotifier", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 1500)
		-- In the bill-paid else branch, the reset must use notifierOriginalSize, not a hardcoded (1,1)
		assert.is_falsy(
			string.find(fnBody, "UDim2.fromScale(1, 1)", 1, true),
			"must not hardcode size reset to (1,1); should use notifierOriginalSize"
		)
	end)
end)

describe("Iter 5 review: client collision group for characterless players", function()
	it("connects CharacterAdded for all other players regardless of current character", function()
		local contents = readFile("src/Client/Main.client.luau")
		-- Find the loop that iterates existing players
		local loopStart = string.find(contents, "for _, player in ipairs(Players:GetPlayers())", 1, true)
		assert.is_truthy(loopStart, "must iterate existing players")
		local loopBody = string.sub(contents, loopStart, loopStart + 400)
		-- The CharacterAdded:Connect must exist
		local connectCall = string.find(loopBody, "player.CharacterAdded:Connect(SetCollisionGroup)", 1, true)
		assert.is_truthy(connectCall, "must connect CharacterAdded for other players")
		-- The character check gates only SetCollisionGroup, not the Connect
		local characterCheck = string.find(loopBody, "if player.Character then", 1, true)
		assert.is_truthy(characterCheck, "must check for existing character before calling SetCollisionGroup")
		-- The Connect must be after the end of the character check block
		local endAfterCharCheck = string.find(loopBody, "end", characterCheck + 1, true)
		assert.is_truthy(endAfterCharCheck)
		assert.is_true(connectCall > endAfterCharCheck,
			"CharacterAdded:Connect must be outside the character-exists block")
	end)
end)

describe("Iter 5 review: server uses ipairs for array iteration", function()
	it("uses ipairs (not pairs) for GetDescendants in OnPlayerAdded", function()
		local contents = readFile("src/Server/Main.server.luau")
		local fnStart = string.find(contents, "local function OnPlayerAdded", 1, true)
		assert.is_truthy(fnStart)
		local fnEnd = string.find(contents, "\nend", fnStart + 1, true)
		local fnBody = string.sub(contents, fnStart, fnEnd or (fnStart + 1200))
		assert.is_falsy(
			string.find(fnBody, "in pairs(character:GetDescendants", 1, true),
			"must not use pairs() for array iteration on GetDescendants"
		)
		assert.is_truthy(
			string.find(fnBody, "in ipairs(character:GetDescendants", 1, true),
			"must use ipairs() for array iteration on GetDescendants"
		)
	end)
end)

describe("Iter 5 review: MainHUD button types are GuiButton not TextButton", function()
	it("declares HUD action buttons as GuiButton", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		-- All HUD action buttons should be typed as GuiButton
		assert.is_truthy(string.find(contents, ":: GuiButton", 1, true))
		-- Check specific button declarations - these are the ones changed in the ImageButton fix
		local hudButtons = {
			"BuildButton", "ProfileButton", "ReviewsButton", "BillsButton",
		}
		for _, name in ipairs(hudButtons) do
			local pattern = name .. '") :: GuiButton'
			assert.is_truthy(
				string.find(contents, pattern, 1, true),
				name .. " must be typed as GuiButton"
			)
		end
	end)

	it("uses setButtonText helper for dynamically created buttons", function()
		local contents = readFile("src/Client/UserInterface/MainHUD.luau")
		assert.is_truthy(string.find(contents, 'setButtonText(button, "Reputation")', 1, true))
		assert.is_truthy(string.find(contents, 'setButtonText(button, "Achievements")', 1, true))
		assert.is_truthy(string.find(contents, 'setButtonText(button, "Daily Rewards")', 1, true))
		assert.is_truthy(string.find(contents, 'setButtonText(button, "Seasons")', 1, true))
	end)
end)

describe("Iter 5 review: PropConfig legacy compat structure", function()
	it("exposes both Furniture and Furnitures keys", function()
		local contents = readFile("src/Shared/Definitions/PropConfig.luau")
		assert.is_truthy(string.find(contents, "Furniture = Furniture", 1, true))
		assert.is_truthy(string.find(contents, "Furnitures = Furniture", 1, true))
	end)

	it("shim module delegates to Definitions.PropConfig", function()
		local contents = readFile("src/Shared/Modules/PropConfig.luau")
		assert.is_truthy(string.find(contents, "Shared.Definitions.PropConfig", 1, true))
	end)

	it("aggregates all catalog categories", function()
		local contents = readFile("src/Shared/Definitions/PropConfig.luau")
		local expectedCategories = {
			"Build", "Furniture", "Appliances", "Decorations",
			"Electronics", "Utilities", "Outdoor", "Rooms",
		}
		for _, cat in ipairs(expectedCategories) do
			assert.is_truthy(
				string.find(contents, cat, 1, true),
				"PropConfig must include category: " .. cat
			)
		end
	end)
end)
