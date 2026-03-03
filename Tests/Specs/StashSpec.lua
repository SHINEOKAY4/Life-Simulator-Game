--!strict
-- Tests/Specs/StashSpec.lua
-- Structural + behavioral tests for the stash system.
-- Covers: StashPackets definitions, Profile schema, StashAction logic,
-- Build.luau SkipCost support, BuildService wiring, StorageInventoryUI.

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

-- ====================================================================
-- StashPackets structural tests
-- ====================================================================

describe("StashPackets definitions", function()
	local src

	before_each(function()
		src = readFile("src/Network/StashPackets.luau")
	end)

	it("defines StashItem packet", function()
		assert.is_truthy(string.find(src, "StashItem", 1, true))
	end)

	it("defines GetStash packet", function()
		assert.is_truthy(string.find(src, "GetStash", 1, true))
	end)

	it("defines PlaceFromStash packet", function()
		assert.is_truthy(string.find(src, "PlaceFromStash", 1, true))
	end)

	it("defines StashUpdated push packet", function()
		assert.is_truthy(string.find(src, "StashUpdated", 1, true))
	end)

	it("StashItem has ItemId field", function()
		assert.is_truthy(string.find(src, "ItemId", 1, true))
	end)

	it("StashItem has CellX and CellZ fields", function()
		assert.is_truthy(string.find(src, "CellX", 1, true))
		assert.is_truthy(string.find(src, "CellZ", 1, true))
	end)

	it("StashItem has Response", function()
		assert.is_truthy(string.find(src, "StashItem.*:Response", 1, false))
	end)

	it("GetStash has Response", function()
		assert.is_truthy(string.find(src, "GetStash.*:Response", 1, false))
	end)

	it("PlaceFromStash has WallMount fields", function()
		assert.is_truthy(string.find(src, "WallMountEnabled", 1, true))
		assert.is_truthy(string.find(src, "WallMountCellX", 1, true))
	end)

	it("PlaceFromStash has CeilingMount fields", function()
		assert.is_truthy(string.find(src, "CeilingMountEnabled", 1, true))
	end)

	it("PlaceFromStash has Response", function()
		assert.is_truthy(string.find(src, "PlaceFromStash.*:Response", 1, false))
	end)

	it("StashUpdated carries Any payload", function()
		assert.is_truthy(string.find(src, "StashUpdated.*Packet%.Any", 1, false))
	end)

	it("returns StashPackets table", function()
		assert.is_truthy(string.find(src, "return StashPackets", 1, true))
	end)
end)

-- ====================================================================
-- Profile schema
-- ====================================================================

describe("Profile StashState schema", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/PlayerSession/Profile.luau")
	end)

	it("has StashState key", function()
		assert.is_truthy(string.find(src, "StashState", 1, true))
	end)

	it("has Items sub-key", function()
		-- Search near StashState
		local stashStart = string.find(src, "StashState", 1, true)
		assert.is_truthy(stashStart)
		local nearSrc = string.sub(src, stashStart, stashStart + 80)
		assert.is_truthy(string.find(nearSrc, "Items", 1, true))
	end)

	it("Items defaults to empty table", function()
		local stashStart = string.find(src, "StashState", 1, true)
		local nearSrc = string.sub(src, stashStart or 1, (stashStart or 1) + 80)
		assert.is_truthy(string.find(nearSrc, "Items%s*=%s*{}", 1, false))
	end)
end)

-- ====================================================================
-- StashAction structural tests
-- ====================================================================

describe("StashAction structure", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/BuildService/Actions/StashAction.luau")
	end)

	it("requires DestroyAction", function()
		assert.is_truthy(string.find(src, "DestroyAction", 1, true))
	end)

	it("requires StashPackets", function()
		assert.is_truthy(string.find(src, "StashPackets", 1, true))
	end)

	it("requires PlayerSession", function()
		assert.is_truthy(string.find(src, "PlayerSession", 1, true))
	end)

	it("has addToStash internal function", function()
		assert.is_truthy(string.find(src, "addToStash", 1, true))
	end)

	it("has deductFromStash internal function", function()
		assert.is_truthy(string.find(src, "deductFromStash", 1, true))
	end)

	it("exposes AddToStash on StashAction", function()
		assert.is_truthy(string.find(src, "StashAction.AddToStash", 1, true))
	end)

	it("exposes DeductFromStash on StashAction", function()
		assert.is_truthy(string.find(src, "StashAction.DeductFromStash", 1, true))
	end)

	it("exposes GetStashItems on StashAction", function()
		assert.is_truthy(string.find(src, "StashAction.GetStashItems", 1, true))
	end)

	it("pushes StashUpdated after adding to stash", function()
		assert.is_truthy(string.find(src, "StashUpdated", 1, true))
	end)

	it("calls DestroyAction before stashing (call order in StashAction body)", function()
		-- Search for the actual call to DestroyAction and addToStash inside the StashAction body.
		-- The function body starts after the function definition; both calls use (player, ...) form.
		local destroyCallPos = string.find(src, "DestroyAction%(player,", 1, false)
		local addCallPos = string.find(src, "addToStash%(player,", 1, false)
		assert.is_truthy(destroyCallPos, "DestroyAction(player, should be present")
		assert.is_truthy(addCallPos, "addToStash(player, should be present")
		assert.is_true(destroyCallPos < addCallPos, "DestroyAction must be called before addToStash")
	end)

	it("deductFromStash returns false for missing item", function()
		-- Structural: check boundary guard `count < 1`
		assert.is_truthy(string.find(src, "count < 1", 1, true))
	end)

	it("removes item key when count drops to zero", function()
		assert.is_truthy(string.find(src, "items%[itemId%]%s*=%s*nil", 1, false))
	end)
end)

-- ====================================================================
-- BuildService init wiring
-- ====================================================================

describe("BuildService stash packet wiring", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/BuildService/init.luau")
	end)

	it("requires StashPackets", function()
		assert.is_truthy(string.find(src, "StashPackets", 1, true))
	end)

	it("requires StashAction", function()
		assert.is_truthy(string.find(src, "StashAction", 1, true))
	end)

	it("registers StashItem handler", function()
		assert.is_truthy(string.find(src, "StashPackets%.StashItem%.OnServerInvoke", 1, false))
	end)

	it("registers GetStash handler", function()
		assert.is_truthy(string.find(src, "StashPackets%.GetStash%.OnServerInvoke", 1, false))
	end)

	it("registers PlaceFromStash handler", function()
		assert.is_truthy(string.find(src, "StashPackets%.PlaceFromStash%.OnServerInvoke", 1, false))
	end)

	it("PlaceFromStash sets SkipCost = true", function()
		assert.is_truthy(string.find(src, "SkipCost%s*=%s*true", 1, false))
	end)

	it("PlaceFromStash restores stash on build failure", function()
		assert.is_truthy(string.find(src, "AddToStash", 1, true))
	end)

	it("DeductFromStash is called before build", function()
		local deductPos = string.find(src, "DeductFromStash", 1, true)
		local buildPos = string.find(src, "Build%(player", 1, false)
		assert.is_truthy(deductPos)
		assert.is_truthy(buildPos)
		assert.is_true(deductPos < buildPos, "DeductFromStash must be called before Build")
	end)
end)

-- ====================================================================
-- Build.luau SkipCost support
-- ====================================================================

describe("Build.luau SkipCost support", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/BuildService/Actions/Build.luau")
	end)

	it("Payload type includes SkipCost field", function()
		assert.is_truthy(string.find(src, "SkipCost", 1, true))
	end)

	it("passes SkipCost to ensurePlacementFunds", function()
		assert.is_truthy(string.find(src, "ensurePlacementFunds.*payload%.SkipCost", 1, false))
	end)

	it("passes SkipCost in all fund-check calls (at least 4)", function()
		local count = 0
		for _ in string.gmatch(src, "ensurePlacementFunds.-payload%.SkipCost") do
			count = count + 1
		end
		assert.is_true(count >= 4, "expected >= 4 SkipCost-aware fund checks, got " .. count)
	end)
end)

-- ====================================================================
-- BuildService Helpers SkipCost / free support
-- ====================================================================

describe("BuildService Helpers free-placement support", function()
	local src

	before_each(function()
		src = readFile("src/Server/Services/BuildService/Helpers/init.luau")
	end)

	it("ensurePlacementFunds accepts a free parameter", function()
		assert.is_truthy(string.find(src, "free", 1, true))
	end)

	it("returns true immediately when free is set", function()
		assert.is_truthy(string.find(src, "if free then", 1, true))
	end)

	it("free early-return yields totalCost of 0", function()
		-- Look for the early-return line returning nil,0,nil near the `free` check
		local freeStart = string.find(src, "if free then", 1, true)
		assert.is_truthy(freeStart)
		local nearSrc = string.sub(src, freeStart, freeStart + 80)
		assert.is_truthy(string.find(nearSrc, "0", 1, true))
	end)
end)

-- ====================================================================
-- ObjectAction PickUp structural tests
-- ====================================================================

describe("ObjectAction.PickUp", function()
	local src

	before_each(function()
		src = readFile("src/Client/Modules/ObjectAction.luau")
	end)

	it("requires StashPackets", function()
		assert.is_truthy(string.find(src, "StashPackets", 1, true))
	end)

	it("defines ObjectAction.PickUp function", function()
		assert.is_truthy(string.find(src, "ObjectAction.PickUp", 1, true))
	end)

	it("fires StashItem packet", function()
		assert.is_truthy(string.find(src, "StashPackets%.StashItem:Fire", 1, false))
	end)

	it("guards against SurfaceMounted items", function()
		assert.is_truthy(string.find(src, "SurfaceMounted", 1, true))
	end)

	it("reads CellX and CellZ attributes", function()
		assert.is_truthy(string.find(src, "CellX", 1, true))
		assert.is_truthy(string.find(src, "CellZ", 1, true))
	end)
end)

-- ====================================================================
-- BillboardRadialUI PickUp wiring
-- ====================================================================

describe("BillboardRadialUI pick-up wiring", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/BillboardRadialUI.luau")
	end)

	it("CopyObject event now calls PickUp", function()
		assert.is_truthy(string.find(src, "ObjectAction%.PickUp", 1, false))
	end)

	it("does not still call ObjectAction.Copy from CopyObject handler", function()
		-- The CopyObject handler should have been updated to call PickUp.
		-- Verify the string 'ObjectAction.Copy' no longer appears in the CopyObject block.
		-- We accept ObjectAction.Copy still exists as a function definition, but it
		-- should not appear inside the CopyObject.Pressed callback.
		local copyPressed = string.find(src, "CopyObject%.Pressed", 1, false)
		assert.is_truthy(copyPressed)
		local handlerBlock = string.sub(src, copyPressed, copyPressed + 200)
		-- The handler should now use PickUp not Copy
		assert.is_falsy(string.find(handlerBlock, "ObjectAction%.Copy", 1, false))
	end)
end)

-- ====================================================================
-- PlotBuilder stash mode tests
-- ====================================================================

describe("PlotBuilder stash mode", function()
	local src

	before_each(function()
		src = readFile("src/Client/Modules/PlotBuilder.luau")
	end)

	it("requires StashPackets", function()
		assert.is_truthy(string.find(src, "StashPackets", 1, true))
	end)

	it("defines SetStashMode function", function()
		assert.is_truthy(string.find(src, "SetStashMode", 1, true))
	end)

	it("PlaceSelectedPreview checks stashModeItemId", function()
		assert.is_truthy(string.find(src, "stashModeItemId", 1, true))
	end)

	it("uses PlaceFromStash packet when stash mode is active", function()
		assert.is_truthy(string.find(src, "StashPackets%.PlaceFromStash", 1, false))
	end)

	it("clears stashModeItemId after use", function()
		assert.is_truthy(string.find(src, "stashModeItemId%s*=%s*nil", 1, false))
	end)
end)

-- ====================================================================
-- StorageInventoryUI structural tests
-- ====================================================================

describe("StorageInventoryUI structure", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/StorageInventoryUI.luau")
	end)

	it("requires StashPackets", function()
		assert.is_truthy(string.find(src, "StashPackets", 1, true))
	end)

	it("requires ItemFinder for display names", function()
		assert.is_truthy(string.find(src, "ItemFinder", 1, true))
	end)

	it("exposes Init function", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI%.Init", 1, false))
	end)

	it("exposes Show function", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI%.Show", 1, false))
	end)

	it("exposes Hide function", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI%.Hide", 1, false))
	end)

	it("exposes IsOpen function", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI%.IsOpen", 1, false))
	end)

	it("subscribes to StashUpdated on init", function()
		assert.is_truthy(string.find(src, "StashUpdated%.OnClientEvent", 1, false))
	end)

	it("fetches stash via GetStash on Show", function()
		assert.is_truthy(string.find(src, "GetStash:Fire", 1, false))
	end)

	it("place button calls SetStashMode + PreviewSelected", function()
		assert.is_truthy(string.find(src, "SetStashMode", 1, true))
		assert.is_truthy(string.find(src, "PreviewSelected", 1, true))
	end)

	it("builds a scrollable item list", function()
		assert.is_truthy(string.find(src, "ScrollingFrame", 1, true))
	end)

	it("shows empty label when stash is empty", function()
		assert.is_truthy(string.find(src, "EmptyLabel", 1, true))
	end)

	it("returns StorageInventoryUI table", function()
		assert.is_truthy(string.find(src, "return StorageInventoryUI", 1, true))
	end)
end)

-- ====================================================================
-- PlotBuilderUI storage toggle wiring
-- ====================================================================

describe("PlotBuilderUI storage toggle wiring", function()
	local src

	before_each(function()
		src = readFile("src/Client/UserInterface/PlotBuilderUI/init.luau")
	end)

	it("requires StorageInventoryUI", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI", 1, true))
	end)

	it("toggleStorageInventory calls StorageInventoryUI.Show", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI%.Show", 1, false))
	end)

	it("toggleStorageInventory calls StorageInventoryUI.Hide", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI%.Hide", 1, false))
	end)

	it("toggleStorageInventory checks IsOpen to toggle correctly", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI%.IsOpen", 1, false))
	end)

	it("sets storageMenuActive when opening", function()
		local toggleFn = string.find(src, "function toggleStorageInventory", 1, true)
		assert.is_truthy(toggleFn)
		local fnBlock = string.sub(src, toggleFn, toggleFn + 200)
		assert.is_truthy(string.find(fnBlock, "storageMenuActive", 1, true))
	end)

	it("no longer warns unimplemented", function()
		assert.is_falsy(string.find(src, "not implemented yet", 1, true))
	end)
end)

-- ====================================================================
-- Main.client.luau startup integration
-- ====================================================================

describe("Main.client.luau StorageInventoryUI startup", function()
	local src

	before_each(function()
		src = readFile("src/Client/Main.client.luau")
	end)

	it("requires StorageInventoryUI", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI", 1, true))
	end)

	it("calls StorageInventoryUI.Init in a startup step", function()
		assert.is_truthy(string.find(src, "StorageInventoryUI%.Init", 1, false))
	end)

	it("inits StorageInventoryUI before ObjectPreview.Init", function()
		local storagePos = string.find(src, "StorageInventoryUI%.Init", 1, false)
		local previewPos = string.find(src, "ObjectPreview%.Init", 1, false)
		assert.is_truthy(storagePos)
		assert.is_truthy(previewPos)
		assert.is_true(storagePos < previewPos, "StorageInventoryUI.Init should come before ObjectPreview.Init")
	end)
end)
