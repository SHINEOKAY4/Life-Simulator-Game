-- Tests/Specs/ObjectActionCleanupSpec.lua
-- Regression guard: verifies that debug print scaffolding removed in the
-- Iter 8 cleanup sweep does not regress back into ObjectAction.luau or
-- TutorialService.luau, and that the dead-code no-op in Rotate is gone.

local function readFile(path)
	local f = io.open(path, "r")
	assert(f, "Could not open file: " .. path)
	local contents = f:read("*a")
	f:close()
	return contents
end

describe("ObjectAction debug-print cleanup", function()
	local src

	before_each(function()
		src = readFile("src/Client/Modules/ObjectAction.luau")
	end)

	it("does not contain Move debug print", function()
		assert.is_nil(
			string.find(src, 'print("Moving object:', 1, true),
			"ObjectAction.Move debug print should be removed"
		)
	end)

	it("does not contain Rotate debug print", function()
		assert.is_nil(
			string.find(src, 'print("Rotating object:', 1, true),
			"ObjectAction.Rotate debug print should be removed"
		)
	end)

	it("does not contain Delete debug print", function()
		assert.is_nil(
			string.find(src, 'print("Deleting object:', 1, true),
			"ObjectAction.Delete debug print should be removed"
		)
	end)

	it("does not contain Copy debug print", function()
		assert.is_nil(
			string.find(src, 'print("Copying object:', 1, true),
			"ObjectAction.Copy debug print should be removed"
		)
	end)

	it("does not contain PickUp success print", function()
		assert.is_nil(
			string.find(src, 'print("[ObjectAction.PickUp] Stashed"', 1, true),
			"ObjectAction.PickUp success print should be removed"
		)
	end)

	it("does not contain the no-op nextFacing self-assignment", function()
		assert.is_nil(
			string.find(src, "nextFacing = currentFacing", 1, true),
			"dead-code no-op nextFacing self-assignment should be removed"
		)
	end)

	it("still defines ObjectAction.Move", function()
		assert.is_truthy(
			string.find(src, "ObjectAction.Move", 1, true),
			"ObjectAction.Move should still be defined"
		)
	end)

	it("still defines ObjectAction.Rotate", function()
		assert.is_truthy(
			string.find(src, "ObjectAction.Rotate", 1, true),
			"ObjectAction.Rotate should still be defined"
		)
	end)

	it("still defines ObjectAction.Delete", function()
		assert.is_truthy(
			string.find(src, "ObjectAction.Delete", 1, true),
			"ObjectAction.Delete should still be defined"
		)
	end)

	it("still defines ObjectAction.Copy", function()
		assert.is_truthy(
			string.find(src, "ObjectAction.Copy", 1, true),
			"ObjectAction.Copy should still be defined"
		)
	end)

	it("still defines ObjectAction.PickUp", function()
		assert.is_truthy(
			string.find(src, "ObjectAction.PickUp", 1, true),
			"ObjectAction.PickUp should still be defined"
		)
	end)
end)

describe("TutorialService debug-print cleanup", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/TutorialService.luau")
	end)

	it("does not contain starting-cash debug print", function()
		assert.is_nil(
			string.find(src, 'print("Given starting cash', 1, true),
			"TutorialService starting-cash debug print should be removed"
		)
	end)

	it("still grants starting cash on OnPlayerAdded", function()
		assert.is_truthy(
			string.find(src, "TutorialStartingCash", 1, true),
			"TutorialService should still grant starting cash"
		)
	end)
end)

describe("BillingConstants internet stub comment removed", function()
	local src

	before_each(function()
		src = readFile("src/Shared/Definitions/BillingConstants.luau")
	end)

	it("does not say 'stub for now'", function()
		assert.is_nil(
			string.find(src, "stub for now", 1, true),
			"BillingConstants internet comment should no longer say 'stub for now'"
		)
	end)

	it("still defines InternetTiers", function()
		assert.is_truthy(
			string.find(src, "InternetTiers", 1, true),
			"BillingConstants should still define InternetTiers"
		)
	end)
end)
