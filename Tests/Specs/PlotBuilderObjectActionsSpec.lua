-- Tests/Specs/PlotBuilderObjectActionsSpec.lua
-- Verifies that PlotBuilder exposes RotateObject, DeleteObject, and SelectObject
-- via handler injection, and that ObjectAction.Init registers the handlers.

local function readFile(path)
	local f = io.open(path, "r")
	assert(f, "Could not open file: " .. path)
	local contents = f:read("*a")
	f:close()
	return contents
end

describe("PlotBuilder object action functions", function()
	local src

	before_each(function()
		src = readFile("src/Client/Modules/PlotBuilder.luau")
	end)

	it("defines PlotBuilder.DeleteObject", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.DeleteObject", 1, true),
			"PlotBuilder.DeleteObject should be defined"
		)
	end)

	it("defines PlotBuilder.RotateObject", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.RotateObject", 1, true),
			"PlotBuilder.RotateObject should be defined"
		)
	end)

	it("defines PlotBuilder.SelectObject", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.SelectObject", 1, true),
			"PlotBuilder.SelectObject should be defined"
		)
	end)

	it("defines setter for delete handler", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.SetDeleteObjectHandler", 1, true),
			"PlotBuilder.SetDeleteObjectHandler should be defined"
		)
	end)

	it("defines setter for rotate handler", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.SetRotateObjectHandler", 1, true),
			"PlotBuilder.SetRotateObjectHandler should be defined"
		)
	end)

	it("defines setter for select handler", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.SetSelectObjectHandler", 1, true),
			"PlotBuilder.SetSelectObjectHandler should be defined"
		)
	end)

	it("does not contain the stale object-action TODO", function()
		assert.is_nil(
			string.find(src, "#TODO: More functions for rotating", 1, true),
			"object action TODO should be removed once implemented"
		)
	end)

	it("guards against nil handlers with a warn", function()
		assert.is_truthy(
			string.find(src, "no handler registered", 1, true),
			"nil-handler guard warn should be present"
		)
	end)
end)

describe("ObjectAction.Init registers PlotBuilder handlers", function()
	local src

	before_each(function()
		src = readFile("src/Client/Modules/ObjectAction.luau")
	end)

	it("registers delete handler into PlotBuilder", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.SetDeleteObjectHandler", 1, true),
			"ObjectAction.Init should register delete handler"
		)
	end)

	it("registers rotate handler into PlotBuilder", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.SetRotateObjectHandler", 1, true),
			"ObjectAction.Init should register rotate handler"
		)
	end)

	it("registers select handler into PlotBuilder", function()
		assert.is_truthy(
			string.find(src, "PlotBuilder.SetSelectObjectHandler", 1, true),
			"ObjectAction.Init should register select handler"
		)
	end)
end)
