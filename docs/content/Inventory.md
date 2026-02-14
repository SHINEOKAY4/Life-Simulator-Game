Title: InventoryService API
Date: 2026-02-14
Authors: OpenCode

Overview
- InventoryService is a server-side module that manages per-player inventories with support for item stacking, categories, capacity limits, and item state (equipped/locked).
- Inventories are organized by category within each player's saved data object (playerData.Inventory).

Data Model
- Item: { id, defId, properties, equipped, locked, createdAt, updatedAt }
- ItemDef: { defId, itemType: "Equipment" | "Consumable" , maxStack, canDelete, tags, metadata, defaultProps }
- Bag: { items, indexByDef, count, equipped, equippedCount, consumed, consumedMeta, consumedCount, maxCapacity, maxEquipped }
- Inventory: a factory with new(category?, maxCapacity?, maxEquipped?, definitions) -> Inventory instance

Key Concepts
- Categories: logical namespaces under player Inventory (e.g., Default, Tools, Decorations).
- Capabilities: add/remove items, stack consumables, equip/unequip equipment, consume consumables, activate consumed effects, prune expired consumables, and snapshot bags.
- Transfer: move a single item between two players via a Transfer method (sourceData + destData are used to mutate inventories).

API surface (typical usage)
- InventoryModule = require("InventoryService").new(category, maxCapacity, maxEquipped, itemDefinitions)
- Inventory:Add(player, defId, qty, playerData) -> (boolean ok, ErrCode?)
- Inventory:Remove(player, itemId, playerData) -> (boolean ok, ErrCode?)
- Inventory:Lock/Unlock(player, itemId, playerData) -> (boolean ok, ErrCode?)
- Inventory:Equip/Unequip(player, itemId, playerData) -> (boolean ok, ErrCode?)
- Inventory:Consume(player, itemId, qty, playerData) -> (boolean ok, ErrCode?)
- Inventory:ActivateConsumed(player, itemId, meta, playerData) -> (ActivationId?, ErrCode?)
- Inventory:DeactivateConsumed(player, activationId, reason, playerData) -> (boolean ok, ErrCode?)
- Inventory:PruneExpired(player, nowTs, playerData) -> number
- Inventory:SetMaxCapacity/SetMaxEquipped(player, amount, playerData) -> (boolean ok, ErrCode?)
- Inventory:SetItemProperties(player, itemId, props, playerData) -> (boolean ok, ErrCode?)
- Inventory:GetItem(player, itemId, playerData) -> Item?
- Inventory:GetBag/PeekBag(playerData) -> Bag
- Inventory:GetEquippedIds/Inventory:GetEquippedItems/Inventory:IsEquipped(...)
- Inventory:GetConsumedActivationIds/GetConsumedMeta/GetItemsByDef -> outputs for inspector/debug
- Inventory:EmitBagSnapshot(player, playerData)
- Inventory:Transfer(sourcePlayer, itemId, sourceData, destPlayer, destData) -> (boolean ok, ErrCode?)

Notes
- All changes emit signals for observers: Changed, ItemAdded, ItemRemoved, EquippedChanged, Consumed, BagSnapshot.
- Defintions are server-controlled and stable over time; Equipment maxStack is coerced to 1 by the system.
- Capacity checks are all-or-nothing for new records (non-partial stacking only affects existing stacks).

Example
```lua
-- Load definitions and create a new inventory
local defs = {
  sword = { defId = "sword", itemType = "Equipment" },
  potion = { defId = "potion", itemType = "Consumable", maxStack = 20, defaultProps = { quality = "standard" } },
}
local inv = InventoryModule.new("Default", 50, 5, defs)
local ok, err = inv:Add(player, "sword", 2, playerData)
```

Next steps
- Run the unit tests (Tests/Specs/InventorySpec.lua) in your Roblox test environment or via your project's test runner.
- If you want a separate transfer API for cross-game inventories, we can extend the interface further with cross-player synchronization hooks.
