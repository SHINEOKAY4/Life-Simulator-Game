-- SeasonalEventUISpec: Structural tests validating SeasonalEventUI module API.
-- These verify the exported interface without requiring a live Roblox environment.

describe("SeasonalEventUI module shape", function()
	-- The client-side module depends on Roblox APIs (Players, ScreenGui, etc.)
	-- so we cannot require it in busted. Instead we parse the source to confirm
	-- the public API is present, matching the contract MainHUD relies on.

	local source

	before_each(function()
		local f = io.open("src/Client/UserInterface/SeasonalEventUI.luau", "r")
		assert.is_not_nil(f, "SeasonalEventUI.luau must exist")
		source = f:read("*a")
		f:close()
	end)

	it("exports Init function", function()
		assert.is_truthy(source:find("function SeasonalEventUI%.Init%("))
	end)

	it("exports SetVisible function", function()
		assert.is_truthy(source:find("function SeasonalEventUI%.SetVisible%("))
	end)

	it("exports Toggle function", function()
		assert.is_truthy(source:find("function SeasonalEventUI%.Toggle%("))
	end)

	it("exports RefreshStatus function", function()
		assert.is_truthy(source:find("function SeasonalEventUI%.RefreshStatus%("))
	end)

	it("uses overlay + window pattern", function()
		assert.is_truthy(source:find('overlay%.Name = "Overlay"') or source:find("Overlay"))
		assert.is_truthy(source:find('window%.Name = "Window"') or source:find("Window"))
	end)

	it("has close button", function()
		assert.is_truthy(source:find("Close"))
		assert.is_truthy(source:find("SetVisible%(false%)"))
	end)

	it("supports challenge reward claiming", function()
		assert.is_truthy(source:find("ClaimChallengeReward"))
	end)

	it("supports milestone reward claiming", function()
		assert.is_truthy(source:find("ClaimMilestoneReward"))
	end)

	it("supports distribute all rewards", function()
		assert.is_truthy(source:find("DistributeAllRewards"))
	end)

	it("listens for SeasonTransitioned events", function()
		assert.is_truthy(source:find("SeasonTransitioned%.OnClientEvent"))
	end)

	it("listens for ChallengeCompleted events", function()
		assert.is_truthy(source:find("ChallengeCompleted%.OnClientEvent"))
	end)

	it("displays season milestones", function()
		assert.is_truthy(source:find("MilestoneList") or source:find("milestoneList"))
	end)

	it("displays active buffs", function()
		assert.is_truthy(source:find("BuffsList") or source:find("buffsList"))
	end)

	it("displays challenge tracker", function()
		assert.is_truthy(source:find("ChallengeList") or source:find("challengeList"))
	end)
end)

describe("MainHUD Seasons button integration", function()
	local source

	before_each(function()
		local f = io.open("src/Client/UserInterface/MainHUD.luau", "r")
		assert.is_not_nil(f, "MainHUD.luau must exist")
		source = f:read("*a")
		f:close()
	end)

	it("requires SeasonalEventUI", function()
		assert.is_truthy(source:find('require%(script%.Parent%.SeasonalEventUI%)'))
	end)

	it("creates SeasonsButton", function()
		assert.is_truthy(source:find("SeasonsButton"))
	end)

	it("wires SeasonsButton to SeasonalEventUI.Toggle", function()
		assert.is_truthy(source:find("SeasonalEventUI%.Toggle%(%)"))
	end)

	it("includes SeasonsButton in configureButtonVisuals loop", function()
		assert.is_truthy(source:find("SeasonsButton }%) do"))
	end)
end)

describe("SeasonalEventPackets schema contract", function()
	local source

	before_each(function()
		local f = io.open("src/Network/SeasonalEventPackets.luau", "r")
		assert.is_not_nil(f, "SeasonalEventPackets.luau must exist")
		source = f:read("*a")
		f:close()
	end)

	it("includes RewardClaimed in challenge status schema", function()
		assert.is_truthy(source:find("RewardClaimed%s*=%s*Packet%.Boolean8"))
	end)

	it("includes claimed milestone reward seasons in season status schema", function()
		assert.is_truthy(source:find("ClaimedMilestoneRewardSeasons%s*=%s*{%s*Packet%.NumberU16%s*}"))
	end)
end)
