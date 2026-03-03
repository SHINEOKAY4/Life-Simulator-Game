local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

describe("Debounce WaitUntilInactive timing", function()
	local src

	before_each(function()
		src = readFile("src/Shared/Utilities/Debounce.luau")
	end)

	it("waits using expiration delta rather than repeated TimeRemaining", function()
		local fnStart = string.find(src, "function Debounce.WaitUntilInactive", 1, true)
		assert.is_truthy(fnStart, "WaitUntilInactive must exist")
		local fnBody = string.sub(src, fnStart, fnStart + 1200)
		assert.is_truthy(string.find(fnBody, "expirationTime - now()", 1, true))
		assert.is_truthy(string.find(fnBody, "task.wait(remaining)", 1, true))
		assert.is_falsy(string.find(fnBody, "Debounce.TimeRemaining", 1, true))
	end)

	it("rechecks for extensions before returning", function()
		local fnStart = string.find(src, "function Debounce.WaitUntilInactive", 1, true)
		assert.is_truthy(fnStart, "WaitUntilInactive must exist")
		local fnBody = string.sub(src, fnStart, fnStart + 1200)
		assert.is_truthy(string.find(fnBody, "latestExpiration", 1, true))
		assert.is_truthy(string.find(fnBody, "state[scopedKey]", 1, true))
		assert.is_truthy(string.find(fnBody, "latestExpiration <= expirationTime", 1, true))
	end)
end)
