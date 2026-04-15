-- Structural checks for BuildService action dispatch caching (Iter 6)
local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

describe("BuildService action dispatch cache", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/BuildService/init.luau")
	end)

	it("defines an ActionCache for resolved modules", function()
		assert.is_truthy(
			string.find(src, "ActionCache", 1, true),
			"ActionCache table should exist for cached action modules"
		)
	end)

	it("resolveAction caches modules after requiring", function()
		assert.is_truthy(string.find(src, "resolveAction", 1, true))
		assert.is_truthy(string.find(src, "require(actionModule)", 1, true))
		assert.is_truthy(string.find(src, "ActionCache[actionName]", 1, true))
		assert.is_truthy(string.find(src, "ActionCache[actionName] = resolved", 1, true))
	end)

	it("dispatchAction delegates to resolveAction for module caching", function()
		local dispatchPos = string.find(src, "local function dispatchAction", 1, true)
		assert.is_truthy(dispatchPos, "dispatchAction helper must exist")
		local snippet = string.sub(src, dispatchPos, dispatchPos + 300)
		assert.is_truthy(
			string.find(snippet, "resolveAction(actionName)", 1, true),
			"dispatchAction should call resolveAction for cached module lookup"
		)
	end)

	it("BuildService handlers use dispatchAction", function()
		assert.is_truthy(string.find(src, "BuildService.Build = dispatchAction(\"Build\")", 1, true))
		assert.is_truthy(string.find(src, "BuildService.Destroy = dispatchAction(\"DestroyAction\")", 1, true))
	end)
end)
