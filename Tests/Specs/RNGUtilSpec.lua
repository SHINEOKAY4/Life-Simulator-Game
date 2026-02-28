local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

describe("RNGUtil weighted selection", function()
	it("guards against selecting zero-weight entries at range boundaries", function()
		local utilContents = readFile("src/Shared/Utilities/RNGUtil.luau")

		assert.is_truthy(string.find(utilContents, "item.weight > 0 and target < runningWeight", 1, true))
		assert.is_falsy(string.find(utilContents, "target <= runningWeight", 1, true))
	end)
end)
