-- InventoryService Behavior Tests (Luau-style)
-- Notes: This spec assumes a Roblox-style Luau environment or a compatible loader.
-- It is written to exercise the core InventoryService API implemented in
-- src/Server/Services/InventoryService.luau

local function safeRequireInventory()
    local InventoryModule = nil
    -- Try typical Roblox-style require paths
    local ok, mod = pcall(function()
        return require(script.Parent.Parent:FindFirstChild("InventoryService") or script.Parent.Parent:FindFirstChild("InventoryService.luau"))
    end)
    if ok and mod then
        return mod
    end
    -- Fallback: attempt a direct load from filesystem (for local testing)
    local ok2, mod2 = pcall(function()
        return dofile("src/Server/Services/InventoryService.luau")
    end)
    if ok2 and mod2 then
        return mod2
    end
    error("Unable to load InventoryService module for tests")
end

local InventoryModule = safeRequireInventory()

local function run()
    local function assertEq(a, b, msg)
        if a ~= b then
            error((msg or "Assertion failed") .. (": expected " .. tostring(b) .. ", got " .. tostring(a)))
        end
    end

    -- Simple item definitions for testing
    local definitions = {
        sword = { defId = "sword", itemType = "Equipment", maxStack = nil, canDelete = true },
        potion = { defId = "potion", itemType = "Consumable", maxStack = 20, canDelete = true, defaultProps = { quality = "standard" } },
    }

    -- Create two separate inventories to test transfer between players
    local inv1 = InventoryModule.new("Default", 50, 5, definitions)
    local inv2 = InventoryModule.new("Default", 50, 5, definitions)

    -- Mock players and their data stores
    local player1 = { Name = "Tester1" }
    local pdata1 = {}
    local player2 = { Name = "Tester2" }
    local pdata2 = {}

    -- 1) Add 3 swords to inv1
    local ok, err = inv1:Add(player1, "sword", 3, pdata1)
    assertEq(ok, true, "Failed to add swords: " .. tostring(err))
    local bag1 = inv1:GetBag(pdata1)
    assertEq(bag1.count, 3, "Inventory1 should have 3 sword records")

    -- 2) Equip the first sword
    local firstId
    for id, _ in pairs(bag1.items) do firstId = id; break end
    local ok2, err2 = inv1:Equip(player1, firstId, pdata1)
    assertEq(ok2, true, "Equip should succeed: " .. tostring(err2))
    local equippedIds = inv1:GetEquippedIds(player1, pdata1)
    local equippedAny = false
    for _ in pairs(equippedIds) do equippedAny = true; break end
    assertEq(equippedAny, true, "Equip state should be recorded")

    -- 3) Transfer one sword from inv1 to inv2
    local transferOk, transferErr = inv1:Transfer(player1, firstId, pdata1, player2, pdata2)
    assertEq(transferOk, true, "Transfer should succeed: " .. tostring(transferErr))
    -- Validate source and destination counts
    local bag1After = inv1:GetBag(pdata1)
    local bag2After = inv2:GetBag(pdata2)
    -- Source should have 2 remaining records
    assertEq(bag1After.count, 2, "Source bag should have 2 items after transfer")
    -- Destination should have 1 item now
    assertEq(bag2After.count, 1, "Destination bag should have 1 item after transfer")

    -- 4) Capacity test: new small bag should reject overflow
    local smallInv = InventoryModule.new("Default", 2, 1, definitions)
    local okSmall, errSmall = smallInv:Add(player1, "sword", 3, pdata1)
    assertEq(okSmall, false, "Expected capacity error when exceeding bag capacity; err=" .. tostring(errSmall))
end

return { run = run }
