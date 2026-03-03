local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

describe("Legacy module compatibility", function()
	it("provides Shared.Modules.RNGUtil shim", function()
		local shimContents = readFile("src/Shared/Modules/RNGUtil.luau")
		assert.is_truthy(string.find(shimContents, "Shared.Utilities.RNGUtil", 1, true))
	end)

	it("provides Shared.Modules.PropConfig shim", function()
		local shimContents = readFile("src/Shared/Modules/PropConfig.luau")
		assert.is_truthy(string.find(shimContents, "Shared.Definitions.PropConfig", 1, true))
	end)

	it("provides Shared.Definitions.PropConfig aggregate", function()
		local definitionContents = readFile("src/Shared/Definitions/PropConfig.luau")
		assert.is_truthy(string.find(definitionContents, "CatalogFolder.Build", 1, true))
		assert.is_truthy(string.find(definitionContents, "CatalogFolder.Furniture", 1, true))
		assert.is_truthy(string.find(definitionContents, "Furnitures = Furniture", 1, true))
	end)

	it("provides Shared.Utilities.RNGUtil implementation", function()
		local utilContents = readFile("src/Shared/Utilities/RNGUtil.luau")
		assert.is_truthy(string.find(utilContents, "function RNGUtil.PickWeighted", 1, true))
	end)
end)
