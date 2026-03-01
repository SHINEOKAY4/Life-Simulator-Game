--!strict

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

local SRC_PATH = "src/Client/Modules/PlotSelector.luau"

describe("PlotSelector input debounce wiring", function()
	it("does not contain the stale input debounce TODO", function()
		local contents = readFile(SRC_PATH)
		assert.is_falsy(
			string.find(contents, "TODO: Throttle or debounce input to prevent multiple rapid inputs", 1, true),
			"input debounce TODO should be removed once runDebounced wiring exists"
		)
	end)

	it("debounces next, previous, and select input actions", function()
		local contents = readFile(SRC_PATH)
		assert.is_truthy(string.find(contents, 'runDebounced("Next"', 1, true), "next action should be debounced")
		assert.is_truthy(
			string.find(contents, 'runDebounced("Previous"', 1, true),
			"previous action should be debounced"
		)
		assert.is_truthy(
			string.find(contents, 'runDebounced("Select"', 1, true),
			"select action should be debounced"
		)
	end)
end)
