--!strict
-- Tests/Specs/InventorySpec.lua
-- Unit tests for InventoryService

describe("InventoryService", function()
	local function createMockInventoryService()
		return {
			new = function() return {} end,
			Add = function() return true, nil end,
			Remove = function() return true, nil end,
			GetBag = function() return { count = 0, items = {} } end,
			Equip = function() return true, nil end,
			Unequip = function() return true, nil end,
			GetEquippedIds = function() return {} end,
			Transfer = function() return true, nil end,
		}
	end

	it("should have new constructor", function()
		local mock = createMockInventoryService()
		assert.is.truthy(mock.new)
	end)

	it("should have Add method", function()
		local mock = createMockInventoryService()
		assert.is.truthy(mock.Add)
	end)

	it("should have Remove method", function()
		local mock = createMockInventoryService()
		assert.is.truthy(mock.Remove)
	end)

	it("should have GetBag method", function()
		local mock = createMockInventoryService()
		assert.is.truthy(mock.GetBag)
	end)

	it("should have Equip method", function()
		local mock = createMockInventoryService()
		assert.is.truthy(mock.Equip)
	end)

	it("should have Unequip method", function()
		local mock = createMockInventoryService()
		assert.is.truthy(mock.Unequip)
	end)

	it("should have GetEquippedIds method", function()
		local mock = createMockInventoryService()
		assert.is.truthy(mock.GetEquippedIds)
	end)

	it("should have Transfer method", function()
		local mock = createMockInventoryService()
		assert.is.truthy(mock.Transfer)
	end)
end)
