--!strict

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

local SRC_PATH = "src/Client/UserInterface/BillboardRadialUI.luau"

describe("BillboardRadialUI move action wiring", function()
	it("does not contain the stale move-action TODO", function()
		local contents = readFile(SRC_PATH)
		assert.is_falsy(
			string.find(contents, "TODO: You can add functionality here to handle the move action", 1, true),
			"move action TODO should be removed once implemented"
		)
	end)

	it("hides radial UI before entering move mode", function()
		local contents = readFile(SRC_PATH)
		local moveHandlerStart = string.find(contents, "ObjectSelectorContext.MoveObject.Pressed:Connect(function()", 1, true)
		assert.is_truthy(moveHandlerStart, "move action handler must exist")
		local moveHandlerBody = string.sub(contents, moveHandlerStart, moveHandlerStart + 700)
		local hideIndex = string.find(moveHandlerBody, "BillboardRadialUI.Hide()", 1, true)
		local moveIndex = string.find(moveHandlerBody, "ObjectAction.Move(selectedModel, selectedModel:GetPivot().Position)", 1, true)
		assert.is_truthy(hideIndex, "move handler must hide radial ui")
		assert.is_truthy(moveIndex, "move handler must start object move flow")
		assert.is_true(hideIndex < moveIndex, "radial ui should hide before move mode starts")
	end)
end)
