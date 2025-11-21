--!strict
--Inventory
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Signal = require(ReplicatedStorage.Packages.GoodSignal)

local Settings = {
	DEFAULT_CAPACITY = 50,
	DEFAULT_EQUIPPED = 5,
}
--==============================[ Types ]==============================
export type ItemType = "Equipment" | "Consumable"

export type ErrCode =
	"WrongType"
	| "NotFound"
	| "Locked"
	| "Equipped"
	| "Capacity"
	| "MaxEquipped"
	| "InvalidQty"
	| "InvalidProps"
	| "DefMissing"

export type Item = {
	id: string,
	defId: string,
	properties: { [string]: any }, -- Consumables include properties.quantity:number
	equipped: boolean,
	locked: boolean,
	createdAt: number,
	updatedAt: number,
}

export type ItemDef = {
	defId: string,
	itemType: ItemType, -- REQUIRED
	maxStack: number?, -- default 1 (Equipment coerced to 1; ensure = 1)
	canDelete: boolean?, -- default true
	tags: { [string]: boolean }?,
	metadata: { [string]: any }?,
	defaultProps: { [string]: any }?, -- applied ONLY on creating a new record/stack
}

export type ActivationId = string

export type ActiveConsumedMeta = {
	activationId: ActivationId,
	sourceItemId: string?,
	defId: string,
	startedAt: number,
	expiresAt: number?,
	context: { [string]: any }?,
}

export type Bag = {
	items: { [string]: Item },
	indexByDef: { [string]: { [string]: boolean } },
	count: number,

	equipped: { [string]: boolean },
	equippedCount: number,

	consumed: { [ActivationId]: boolean },
	consumedMeta: { [ActivationId]: ActiveConsumedMeta },
	consumedCount: number,

	maxCapacity: number,
	maxEquipped: number,
}

type Definitions = { [string]: ItemDef }
type InventoryRoot = { [string]: Bag } -- playerData.Inventory

-- Split instance type: fields vs methods (so __index composition type-checks)
type InventoryFields = {
	Changed: any,
	ItemAdded: any,
	ItemRemoved: any,
	EquippedChanged: any,
	Consumed: any,
	ConsumedChanged: any,
	BagSnapshot: any,

	Category: string,
	MaxCapacity: number,
	MaxEquipped: number,
	ItemDefinitions: Definitions,
}

type InventoryMethods = {
	Destroy: (self: Inventory) -> (),

	Add: (
		self: Inventory,
		player: Player,
		defId: string,
		qty: number?,
		playerData: { [string]: any }
	) -> (boolean, ErrCode?),
	Remove: (self: Inventory, player: Player, itemId: string, playerData: { [string]: any }) -> (boolean, ErrCode?),
	Lock: (self: Inventory, player: Player, itemId: string, playerData: { [string]: any }) -> (boolean, ErrCode?),
	Unlock: (self: Inventory, player: Player, itemId: string, playerData: { [string]: any }) -> (boolean, ErrCode?),

	Equip: (self: Inventory, player: Player, itemId: string, playerData: { [string]: any }) -> (boolean, ErrCode?),
	Unequip: (self: Inventory, player: Player, itemId: string, playerData: { [string]: any }) -> (boolean, ErrCode?),

	Consume: (
		self: Inventory,
		player: Player,
		itemId: string,
		qty: number?,
		playerData: { [string]: any }
	) -> (boolean, ErrCode?),
	ActivateConsumed: (
		self: Inventory,
		player: Player,
		itemId: string?,
		meta: ActiveConsumedMeta?,
		playerData: { [string]: any }
	) -> (ActivationId?, ErrCode?),
	DeactivateConsumed: (
		self: Inventory,
		player: Player,
		activationId: ActivationId,
		reason: string?,
		playerData: { [string]: any }
	) -> (boolean, ErrCode?),
	PruneExpired: (self: Inventory, player: Player, now: number?, playerData: { [string]: any }) -> number,

	SetMaxCapacity: (
		self: Inventory,
		player: Player,
		amount: number,
		playerData: { [string]: any }
	) -> (boolean, ErrCode?),
	SetMaxEquipped: (
		self: Inventory,
		player: Player,
		amount: number,
		playerData: { [string]: any }
	) -> (boolean, ErrCode?),

	SetItemProperties: (
		self: Inventory,
		player: Player,
		itemId: string,
		props: { [string]: any },
		playerData: { [string]: any }
	) -> (boolean, ErrCode?),
	GetItem: (self: Inventory, player: Player, itemId: string, playerData: { [string]: any }) -> Item?,

	GetBag: (self: Inventory, playerData: { [string]: any }) -> Bag,
	PeekBag: (self: Inventory, playerData: { [string]: any }) -> Bag?,
	GetEquippedIds: (self: Inventory, player: Player, playerData: { [string]: any }) -> { [string]: boolean },
	GetEquippedItems: (self: Inventory, player: Player, playerData: { [string]: any }) -> { Item },
	IsEquipped: (self: Inventory, player: Player, itemId: string, playerData: { [string]: any }) -> boolean,
	GetConsumedActivationIds: (
		self: Inventory,
		player: Player,
		playerData: { [string]: any }
	) -> { [ActivationId]: boolean },
	GetConsumedMeta: (
		self: Inventory,
		player: Player,
		playerData: { [string]: any }
	) -> { [ActivationId]: ActiveConsumedMeta },
	GetItemsByDef: (self: Inventory, player: Player, defId: string, playerData: { [string]: any }) -> { Item },
	EmitBagSnapshot: (self: Inventory, player: Player, playerData: { [string]: any }) -> (),
}

export type Inventory = InventoryFields & InventoryMethods
export type InventoryModule = InventoryMethods & {
	new: (category: string?, maxCapacity: number?, maxEquipped: number?, definitions: Definitions) -> Inventory,
}

--==========================[ Internals ]==========================
local function Now(): number
	return Workspace:GetServerTimeNow()
end

local function NewItemId(): string
	return HttpService:GenerateGUID(false)
end

local function NewActivationId(): ActivationId
	return "act_" .. HttpService:GenerateGUID(false)
end

local function copyShallow<T>(t: T): T
	local c: any = {}
	for k, v in pairs(t :: any) do
		if type(v) == "table" then
			c[k] = table.clone(v)
		else
			c[k] = v
		end
	end
	return c :: any
end

local function copyBoolMap(m: { [string]: boolean }): { [string]: boolean }
	return table.clone(m)
end

local function propsWithoutQty(props: { [string]: any }): { [string]: any }
	local out: { [string]: any } = {}
	for k, v in pairs(props) do
		if k ~= "quantity" then
			out[k] = v
		end
	end
	return out
end

local function shallowEqualProps(a: { [string]: any }, b: { [string]: any }): boolean
	for k, v in pairs(a) do
		if k ~= "quantity" then
			if b[k] ~= v then
				return false
			end
		end
	end
	for k, _ in pairs(b) do
		if k ~= "quantity" then
			if a[k] == nil then
				return false
			end
		end
	end
	return true
end

local function EnsureInventoryRoot(playerData: { [string]: any }): InventoryRoot
	if playerData.Inventory == nil then
		playerData.Inventory = {} :: InventoryRoot
	end
	return playerData.Inventory :: InventoryRoot
end

-- Create a *typed* new bag (avoid assigning `{}` to a Bag-typed variable)
local function NewBag(maxCap: number, maxEq: number): Bag
	return {
		items = {},
		indexByDef = {},
		count = 0,

		equipped = {},
		equippedCount = 0,

		consumed = {},
		consumedMeta = {},
		consumedCount = 0,

		maxCapacity = maxCap,
		maxEquipped = maxEq,
	}
end

-- Defensive shape repair (schema-agnostic; no versioning)
local function EnsureBagShape(bag: any, maxCap: number, maxEq: number): Bag
	bag.items = bag.items or {}
	bag.indexByDef = bag.indexByDef or {}
	bag.equipped = bag.equipped or {}
	bag.consumed = bag.consumed or {}
	bag.consumedMeta = bag.consumedMeta or {}
	bag.count = bag.count or 0
	bag.equippedCount = bag.equippedCount or 0
	bag.consumedCount = bag.consumedCount or 0
	bag.maxCapacity = bag.maxCapacity or maxCap
	bag.maxEquipped = bag.maxEquipped or maxEq
	return bag :: Bag
end

local function Recount(bag: Bag)
	local c = 0
	for _ in pairs(bag.items) do
		c += 1
	end
	bag.count = c
	local eq = 0
	for _ in pairs(bag.equipped) do
		eq += 1
	end
	bag.equippedCount = eq
	local ac = 0
	for _ in pairs(bag.consumed) do
		ac += 1
	end
	bag.consumedCount = ac
end

-- index rebuild for loaded profiles missing index
local function BuildIndex(bag: Bag)
	bag.indexByDef = {}
	for id, it in pairs(bag.items) do
		local set = bag.indexByDef[it.defId]
		if not set then
			set = {}
			bag.indexByDef[it.defId] = set
		end
		set[id] = true
	end
end

local function ApplyDefaultProps(def: ItemDef, base: { [string]: any }?): { [string]: any }
	local props: { [string]: any } = {}
	if def.defaultProps then
		for k, v in pairs(def.defaultProps :: any) do
			props[k] = v
		end
	end
	if base then
		for k, v in pairs(base) do
			props[k] = v
		end
	end
	return props
end

local function GetDef(defs: Definitions, defId: string): ItemDef?
	local def = defs[defId]
	if not def then
		return nil
	end
	local coerced: ItemDef = table.clone(def)
	if coerced.itemType == "Equipment" then
		coerced.maxStack = 1
	end
	if coerced.maxStack == nil or (type(coerced.maxStack) == "number" and coerced.maxStack < 1) then
		coerced.maxStack = 1
	end
	return coerced
end

--==============================[ Module ]==============================
local Inventory: InventoryModule & { __index: InventoryMethods } = {} :: any
Inventory.__index = Inventory -- __index expects InventoryMethods

--- Construct a new Inventory instance (bag/category).
--- Category is a logical namespace under playerData.Inventory.
--- Signals are created per-instance and fire AFTER mutations.
---@param category string? @Bag/category name; defaults to "Default"
---@param maxCapacity number? @Max item-record slots; defaults Settings.DEFAULT_CAPACITY
---@param maxEquipped number? @Max equipped equipment; defaults Settings.DEFAULT_EQUIPPED
---@param definitions table @Map defId -> ItemDef (server-owned, stable)
---@return Inventory
function Inventory.new(
	category: string?,
	maxCapacity: number?,
	maxEquipped: number?,
	definitions: Definitions
): Inventory
	local fields: InventoryFields = {
		Category = category or "Default",
		MaxCapacity = maxCapacity or Settings.DEFAULT_CAPACITY,
		MaxEquipped = maxEquipped or Settings.DEFAULT_EQUIPPED,
		ItemDefinitions = definitions,

		-- Signals
		Changed = Signal.new(),
		ItemAdded = Signal.new(),
		ItemRemoved = Signal.new(),
		EquippedChanged = Signal.new(),
		Consumed = Signal.new(),
		ConsumedChanged = Signal.new(),
		BagSnapshot = Signal.new(),
	}
	local self = setmetatable(fields, Inventory)
	return (self :: any) :: Inventory -- fields & methods via __index
end

--- Destroy hooks for tests/hot-reload. (No resources retained.)
function Inventory:Destroy()
	-- Placeholder for tests/hot-reload (no resources retained)
end

--==========================[ Bag Access ]==========================

--- Get/create the bag for this category and repair/recount/index as needed.
--- Shape-repair is defensive; index is rebuilt if items exist but index is empty.
---@param playerData table @Your PlayerSession root (mutated in-place)
---@return Bag
function Inventory:GetBag(playerData: { [string]: any }): Bag
	local root = EnsureInventoryRoot(playerData)

	local existing = root[self.Category]
	local bag: Bag
	if existing == nil then
		bag = NewBag(self.MaxCapacity, self.MaxEquipped)
		root[self.Category] = bag
	else
		bag = EnsureBagShape(existing, self.MaxCapacity, self.MaxEquipped)
	end

	if next(bag.indexByDef) == nil and next(bag.items) ~= nil then
		BuildIndex(bag)
	end
	Recount(bag)
	return bag
end

--- Peek the bag without creating it. Still ensures shape if present.
---@param playerData table
---@return Bag? @nil if the bag/category does not yet exist
function Inventory:PeekBag(playerData: { [string]: any }): Bag?
	local root = playerData.Inventory :: InventoryRoot?
	if not root then
		return nil
	end
	local bag = root[self.Category] :: Bag?
	if not bag then
		return nil
	end
	return EnsureBagShape(bag, self.MaxCapacity, self.MaxEquipped)
end

--==========================[ Public API ]==========================

--- Add items to the bag.
--- Equipment: creates N distinct records (stack coerced to 1).
--- Consumable: fills equivalent stacks (same defId & props sans 'quantity'), then spills as new stacks.
--- Capacity policy: ALL-OR-NOTHING by NEW records only.
--- Fires: ItemAdded (per new record), Changed("Add", {defId, qtyAdded, newRecords})
---@param player Player
---@param defId string
---@param qty number? @>=1 (defaults 1)
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:Add(player: Player, defId: string, qty: number?, playerData: { [string]: any }): (boolean, ErrCode?)
	local def = GetDef(self.ItemDefinitions, defId)
	if not def then
		return false, "DefMissing"
	end
	local n = math.floor(qty or 1)
	if n < 1 then
		return false, "InvalidQty"
	end
	local bag = self:GetBag(playerData)
	local now = Now()

	if def.itemType == "Equipment" then
		local requiredNew = n
		if bag.count + requiredNew > bag.maxCapacity then
			return false, "Capacity"
		end
		for _ = 1, n do
			local id = NewItemId()
			local item: Item = {
				id = id,
				defId = defId,
				properties = ApplyDefaultProps(def, nil),
				equipped = false,
				locked = false,
				createdAt = now,
				updatedAt = now,
			}
			bag.items[id] = item
			if not bag.indexByDef[defId] then
				bag.indexByDef[defId] = {}
			end
			bag.indexByDef[defId][id] = true
			bag.count += 1
			self.ItemAdded:Fire(player, self.Category, copyShallow(item))
		end
		self.Changed:Fire(player, self.Category, "Add", { defId = defId, qtyAdded = n, newRecords = n })
		return true
	end

	-- Consumable path
	local maxStack = def.maxStack :: number
	local neededNew = 0
	local remaining = n
	-- Gather equivalent stacks: same props (excluding quantity). Our target props = defaultProps of def.
	local targetProps = ApplyDefaultProps(def, nil)
	local equivalences: { string } = {}
	for id in pairs(bag.indexByDef[defId] or {}) do
		local it = bag.items[id]
		if it and shallowEqualProps(propsWithoutQty(it.properties), targetProps) then
			table.insert(equivalences, id)
		end
	end
	-- Plan fills
	local plan: { any } = {}
	for _, id in ipairs(equivalences) do
		if remaining == 0 then
			break
		end
		local it = bag.items[id]
		local cur = it.properties.quantity or 0
		local add = math.min(maxStack - cur, remaining)
		if add > 0 then
			table.insert(plan, { op = "fill", id = id, add = add })
			remaining -= add
		end
	end
	-- Plan new stacks
	while remaining > 0 do
		local take = math.min(maxStack, remaining)
		table.insert(plan, { op = "new", qty = take })
		remaining -= take
		neededNew += 1
	end
	-- Capacity gate
	if bag.count + neededNew > bag.maxCapacity then
		return false, "Capacity"
	end
	-- Apply plan
	local newRecords = 0
	for _, step in ipairs(plan) do
		if step.op == "fill" then
			local it = bag.items[step.id]
			it.properties.quantity = (it.properties.quantity or 0) + step.add
			it.updatedAt = now
		else
			local id = NewItemId()
			local props = ApplyDefaultProps(def, { quantity = step.qty })
			local item: Item = {
				id = id,
				defId = defId,
				properties = props,
				equipped = false,
				locked = false,
				createdAt = now,
				updatedAt = now,
			}
			bag.items[id] = item
			if not bag.indexByDef[defId] then
				bag.indexByDef[defId] = {}
			end
			bag.indexByDef[defId][id] = true
			bag.count += 1
			newRecords += 1
			self.ItemAdded:Fire(player, self.Category, copyShallow(item))
		end
	end
	self.Changed:Fire(player, self.Category, "Add", { defId = defId, qtyAdded = n, newRecords = newRecords })
	return true
end

--- Remove a record (no quantity semantics).
--- Denies removal if item is Equipped or Locked.
--- Self-heals orphan equip flags (item missing but equipped) ? clears equip and returns true.
--- Fires: ItemRemoved (on deletion), Changed("Remove", {itemId, recordDeleted=true})
---@param player Player
---@param itemId string
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:Remove(player: Player, itemId: string, playerData: { [string]: any }): (boolean, ErrCode?)
	local bag = self:PeekBag(playerData)
	if not bag then
		return false, "NotFound"
	end
	local item = bag.items[itemId]
	if not item then
		-- self-heal: if flagged equipped but item missing, clear equip
		if bag.equipped[itemId] then
			bag.equipped[itemId] = nil
			bag.equippedCount -= 1
			if bag.equippedCount < 0 then
				bag.equippedCount = 0
			end
			self.EquippedChanged:Fire(player, self.Category, itemId, false)
			self.Changed:Fire(player, self.Category, "Unequip", { itemId = itemId })
			return true
		end
		return false, "NotFound"
	end
	if item.equipped then
		return false, "Equipped"
	end
	if item.locked then
		return false, "Locked"
	end
	-- mutate
	bag.items[itemId] = nil
	local set = bag.indexByDef[item.defId]
	if set then
		set[itemId] = nil
		if next(set) == nil then
			bag.indexByDef[item.defId] = nil
		end
	end
	bag.count -= 1
	if bag.count < 0 then
		bag.count = 0
	end
	self.ItemRemoved:Fire(player, self.Category, copyShallow(item))
	self.Changed:Fire(player, self.Category, "Remove", { itemId = itemId, recordDeleted = true })
	return true
end

--- Lock an item to prevent explicit Remove (does NOT block Consume or Equip/Unequip).
--- Fires: Changed("Lock", {itemId})
---@param player Player
---@param itemId string
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:Lock(player: Player, itemId: string, playerData: { [string]: any }): (boolean, ErrCode?)
	local bag = self:PeekBag(playerData)
	if not bag then
		return false, "NotFound"
	end
	local item = bag.items[itemId]
	if not item then
		return false, "NotFound"
	end
	item.locked = true
	item.updatedAt = Now()
	self.Changed:Fire(player, self.Category, "Lock", { itemId = itemId })
	return true
end

--- Unlock a previously locked item.
--- Fires: Changed("Unlock", {itemId})
---@param player Player
---@param itemId string
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:Unlock(player: Player, itemId: string, playerData: { [string]: any }): (boolean, ErrCode?)
	local bag = self:PeekBag(playerData)
	if not bag then
		return false, "NotFound"
	end
	local item = bag.items[itemId]
	if not item then
		return false, "NotFound"
	end
	item.locked = false
	item.updatedAt = Now()
	self.Changed:Fire(player, self.Category, "Unlock", { itemId = itemId })
	return true
end

--- Equip an equipment record (idempotent).
--- Enforces MaxEquipped; WrongType if item def is not Equipment.
--- Fires: EquippedChanged(itemId, true), Changed("Equip", {itemId})
---@param player Player
---@param itemId string
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:Equip(player: Player, itemId: string, playerData: { [string]: any }): (boolean, ErrCode?)
	local bag = self:PeekBag(playerData)
	if not bag then
		return false, "NotFound"
	end
	local item = bag.items[itemId]
	if not item then
		return false, "NotFound"
	end
	local def = GetDef(self.ItemDefinitions, item.defId)
	if not def then
		return false, "DefMissing"
	end
	if def.itemType ~= "Equipment" then
		return false, "WrongType"
	end
	if bag.equipped[itemId] then
		return true
	end -- idempotent
	if bag.equippedCount >= bag.maxEquipped then
		return false, "MaxEquipped"
	end
	bag.equipped[itemId] = true
	bag.equippedCount += 1
	item.equipped = true
	item.updatedAt = Now()
	self.EquippedChanged:Fire(player, self.Category, itemId, true)
	self.Changed:Fire(player, self.Category, "Equip", { itemId = itemId })
	return true
end

--- Unequip an equipment record (idempotent).
--- If the item is missing but flagged equipped, self-heals and returns true.
--- Fires: EquippedChanged(itemId, false), Changed("Unequip", {itemId})
---@param player Player
---@param itemId string
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:Unequip(player: Player, itemId: string, playerData: { [string]: any }): (boolean, ErrCode?)
	local bag = self:PeekBag(playerData)
	if not bag then
		return false, "NotFound"
	end
	local item = bag.items[itemId]
	if not item then
		-- self-heal: item missing but flagged equipped
		if bag.equipped[itemId] then
			bag.equipped[itemId] = nil
			bag.equippedCount -= 1
			if bag.equippedCount < 0 then
				bag.equippedCount = 0
			end
			self.EquippedChanged:Fire(player, self.Category, itemId, false)
			self.Changed:Fire(player, self.Category, "Unequip", { itemId = itemId })
			return true
		end
		return false, "NotFound"
	end
	if not bag.equipped[itemId] then
		return true
	end -- idempotent
	bag.equipped[itemId] = nil
	bag.equippedCount -= 1
	if bag.equippedCount < 0 then
		bag.equippedCount = 0
	end
	item.equipped = false
	item.updatedAt = Now()
	self.EquippedChanged:Fire(player, self.Category, itemId, false)
	self.Changed:Fire(player, self.Category, "Unequip", { itemId = itemId })
	return true
end

--- Consume quantity from a Consumable record (qty>=1). Strict overspend errors.
--- When quantity hits 0, the record is deleted (lock does NOT prevent this).
--- Fires: Consumed(itemId, {qty}), Changed("Consume", {itemId, qty})
---@param player Player
---@param itemId string
---@param qty number? @>=1 (defaults 1)
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:Consume(
	player: Player,
	itemId: string,
	qty: number?,
	playerData: { [string]: any }
): (boolean, ErrCode?)
	local bag = self:PeekBag(playerData)
	if not bag then
		return false, "NotFound"
	end
	local item = bag.items[itemId]
	if not item then
		return false, "NotFound"
	end
	local def = GetDef(self.ItemDefinitions, item.defId)
	if not def then
		return false, "DefMissing"
	end
	if def.itemType ~= "Consumable" then
		return false, "WrongType"
	end
	local n = math.floor(qty or 1)
	if n < 1 then
		return false, "InvalidQty"
	end
	local cur = item.properties.quantity or 0

	-- strict overspend ? error
	if n > cur then
		return false, "InvalidQty"
	end

	if n == cur then
		-- delete record
		bag.items[itemId] = nil
		local set = bag.indexByDef[item.defId]
		if set then
			set[itemId] = nil
			if next(set) == nil then
				bag.indexByDef[item.defId] = nil
			end
		end
		bag.count -= 1
		if bag.count < 0 then
			bag.count = 0
		end
	else
		item.properties.quantity = cur - n
		item.updatedAt = Now()
	end
	self.Consumed:Fire(player, self.Category, itemId, { qty = n })
	self.Changed:Fire(player, self.Category, "Consume", { itemId = itemId, qty = n })
	return true
end

--- Activate a consumable effect independent of item lifetime.
--- Populates activationId/startedAt if omitted. defId required (derived from itemId if provided).
--- Fires: ConsumedChanged(actId, true, meta), Changed("ActivateConsumed", {activationId, defId, expiresAt})
---@param player Player
---@param itemId string? @Optional source item for deriving defId
---@param meta ActiveConsumedMeta? @Optional; missing fields are filled
---@param playerData table
---@return string? activationId, ErrCode? err
function Inventory:ActivateConsumed(
	player: Player,
	itemId: string?,
	meta: ActiveConsumedMeta?,
	playerData: { [string]: any }
): (ActivationId?, ErrCode?)
	local bag = self:GetBag(playerData)
	local m: ActiveConsumedMeta = meta or ({} :: any)
	if not m.activationId then
		m.activationId = NewActivationId()
	end
	if not m.startedAt then
		m.startedAt = Now()
	end
	if not m.defId then
		if itemId then
			local it = bag.items[itemId]
			if not it then
				return nil, "NotFound"
			end
			m.defId = it.defId
		else
			return nil, "DefMissing"
		end
	end
	bag.consumed[m.activationId] = true
	bag.consumedMeta[m.activationId] = copyShallow(m)
	bag.consumedCount += 1
	self.ConsumedChanged:Fire(player, self.Category, m.activationId, true, copyShallow(m))
	self.Changed:Fire(
		player,
		self.Category,
		"ActivateConsumed",
		{ activationId = m.activationId, defId = m.defId, expiresAt = m.expiresAt }
	)
	return m.activationId
end

--- Deactivate a previously activated consumable effect.
--- Fires: ConsumedChanged(actId, false, meta?), Changed("DeactivateConsumed", {activationId, reason})
---@param player Player
---@param activationId string
---@param reason string? @Optional audit/debug info
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:DeactivateConsumed(
	player: Player,
	activationId: ActivationId,
	reason: string?,
	playerData: { [string]: any }
): (boolean, ErrCode?)
	local bag = self:PeekBag(playerData)
	if not bag then
		return false, "NotFound"
	end
	if not bag.consumed[activationId] then
		return false, "NotFound"
	end
	bag.consumed[activationId] = nil
	local meta = bag.consumedMeta[activationId]
	bag.consumedMeta[activationId] = nil
	bag.consumedCount -= 1
	if bag.consumedCount < 0 then
		bag.consumedCount = 0
	end
	self.ConsumedChanged:Fire(player, self.Category, activationId, false, meta and copyShallow(meta) or nil)
	self.Changed:Fire(player, self.Category, "DeactivateConsumed", { activationId = activationId, reason = reason })
	return true
end

--- Deactivate all activations expiring at or before 'now'.
--- Does NOT run timers; caller supplies 'now' or uses server time.
--- Fires: ConsumedChanged(...) for each removed; Changed("PruneExpired", {count}) if any
---@param player Player
---@param nowTs number? @Seconds timestamp (Workspace:GetServerTimeNow() if nil)
---@param playerData table
---@return number countRemoved
function Inventory:PruneExpired(player: Player, nowTs: number?, playerData: { [string]: any }): number
	local bag = self:PeekBag(playerData)
	if not bag then
		return 0
	end
	local now = nowTs or Now()
	local removed = 0
	for actId, meta in pairs(bag.consumedMeta) do
		if meta.expiresAt and meta.expiresAt <= now then
			bag.consumed[actId] = nil
			bag.consumedMeta[actId] = nil
			removed += 1
			self.ConsumedChanged:Fire(player, self.Category, actId, false, copyShallow(meta))
		end
	end
	-- recount consumedCount
	local c = 0
	for _ in pairs(bag.consumed) do
		c += 1
	end
	bag.consumedCount = c
	if removed > 0 then
		self.Changed:Fire(player, self.Category, "PruneExpired", { count = removed })
	end
	return removed
end

-- Limits

--- Set the max record capacity for this bag.
--- Fires: Changed("SetMaxCapacity", {amount})
---@param player Player
---@param amount number @<0 coerced to 0
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:SetMaxCapacity(player: Player, amount: number, playerData: { [string]: any }): (boolean, ErrCode?)
	if amount < 0 then
		amount = 0
	end
	local bag = self:GetBag(playerData)
	bag.maxCapacity = amount
	self.Changed:Fire(player, self.Category, "SetMaxCapacity", { amount = amount })
	return true
end

--- Set the max simultaneously equipped items.
--- Fires: Changed("SetMaxEquipped", {amount})
---@param player Player
---@param amount number @<0 coerced to 0
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:SetMaxEquipped(player: Player, amount: number, playerData: { [string]: any }): (boolean, ErrCode?)
	if amount < 0 then
		amount = 0
	end
	local bag = self:GetBag(playerData)
	bag.maxEquipped = amount
	self.Changed:Fire(player, self.Category, "SetMaxEquipped", { amount = amount })
	return true
end

-- Properties

--- Shallow-merge arbitrary custom properties into an item (copies remain elsewhere).
--- Reserved fields are rejected; stack field 'quantity' is blocked.
--- Fires: Changed("SetItemProperties", {itemId, keys})
---@param player Player
---@param itemId string
---@param props table @User props; cannot contain reserved keys or 'quantity'
---@param playerData table
---@return boolean ok, ErrCode? err
function Inventory:SetItemProperties(
	player: Player,
	itemId: string,
	props: { [string]: any },
	playerData: { [string]: any }
): (boolean, ErrCode?)
	local bag = self:PeekBag(playerData)
	if not bag then
		return false, "NotFound"
	end
	local item = bag.items[itemId]
	if not item then
		return false, "NotFound"
	end
	-- guard reserved fields + stack field
	if
		props.id ~= nil
		or props.defId ~= nil
		or props.equipped ~= nil
		or props.locked ~= nil
		or props.createdAt ~= nil
		or props.updatedAt ~= nil
		or props.quantity ~= nil -- block stack edits
	then
		return false, "InvalidProps"
	end
	for k, v in pairs(props) do
		item.properties[k] = v
	end
	item.updatedAt = Now()
	local keys = {}
	for k, _ in pairs(props) do
		table.insert(keys, k)
	end
	self.Changed:Fire(player, self.Category, "SetItemProperties", { itemId = itemId, keys = keys })
	return true
end

-- Queries (copies)

--- Get a COPY of an item record.
---@param player Player
---@param itemId string
---@param playerData table
---@return Item? @nil if missing
function Inventory:GetItem(_player: Player, itemId: string, playerData: { [string]: any }): Item?
	local bag = self:PeekBag(playerData)
	if not bag then
		return nil
	end
	local it = bag.items[itemId]
	if not it then
		return nil
	end
	return copyShallow(it)
end

--- Get a COPY of equipped id set.
---@param player Player
---@param playerData table
---@return table<string, boolean>
function Inventory:GetEquippedIds(_player: Player, playerData: { [string]: any }): { [string]: boolean }
	local bag = self:PeekBag(playerData)
	if not bag then
		return {}
	end
	return copyBoolMap(bag.equipped)
end

--- Get COPIES of equipped items.
---@param player Player
---@param playerData table
---@return Item[]
function Inventory:GetEquippedItems(_player: Player, playerData: { [string]: any }): { Item }
	local bag = self:PeekBag(playerData)
	if not bag then
		return {}
	end
	local out: { Item } = {}
	for id in pairs(bag.equipped) do
		local it = bag.items[id]
		if it then
			table.insert(out, copyShallow(it))
		end
	end
	return out
end

--- Check if an itemId is currently equipped.
---@param player Player
---@param itemId string
---@param playerData table
---@return boolean
function Inventory:IsEquipped(_player: Player, itemId: string, playerData: { [string]: any }): boolean
	local bag = self:PeekBag(playerData)
	if not bag then
		return false
	end
	return bag.equipped[itemId] == true
end

--- Get a COPY of active-consumed activation id set.
---@param player Player
---@param playerData table
---@return table<string, boolean>
function Inventory:GetConsumedActivationIds(_player: Player, playerData: { [string]: any }): { [ActivationId]: boolean }
	local bag = self:PeekBag(playerData)
	if not bag then
		return {}
	end
	return table.clone(bag.consumed)
end

--- Get COPIES of active-consumed metadata by activation id.
---@param player Player
---@param playerData table
---@return table<string, ActiveConsumedMeta>
function Inventory:GetConsumedMeta(
	_player: Player,
	playerData: { [string]: any }
): { [ActivationId]: ActiveConsumedMeta }
	local bag = self:PeekBag(playerData)
	if not bag then
		return {}
	end
	local out: { [ActivationId]: ActiveConsumedMeta } = {}
	for id, m in pairs(bag.consumedMeta) do
		out[id] = copyShallow(m)
	end
	return out
end

--- Get COPIES of items by definition id.
--- Uses GetBag() to guarantee index rebuild if needed.
---@param player Player
---@param defId string
---@param playerData table
---@return Item[]
function Inventory:GetItemsByDef(_widthplayer: Player, defId: string, playerData: { [string]: any }): { Item }
	-- Use GetBag so were guaranteed shape repair + index rebuild.
	local bag = self:GetBag(playerData)
	local out: { Item } = {}
	for id in pairs(bag.indexByDef[defId] or {}) do
		local it = bag.items[id]
		if it then
			table.insert(out, copyShallow(it))
		end
	end
	return out
end

--- Emit a full COPY snapshot of the bag (for initial sync/resync).
--- Fires: BagSnapshot(player, category, snapshotTable)
---@param player Player
---@param playerData table
function Inventory:EmitBagSnapshot(player: Player, playerData: { [string]: any })
	local bag = self:GetBag(playerData)
	local itemsCopy: { [string]: Item } = {}
	for id, it in pairs(bag.items) do
		itemsCopy[id] = copyShallow(it)
	end
	local consumedCopy = table.clone(bag.consumed)
	local consumedMetaCopy: { [ActivationId]: ActiveConsumedMeta } = {}
	for id, m in pairs(bag.consumedMeta) do
		consumedMetaCopy[id] = copyShallow(m)
	end
	self.BagSnapshot:Fire(player, self.Category, {
		items = itemsCopy,
		equipped = copyBoolMap(bag.equipped),
		consumed = consumedCopy,
		consumedMeta = consumedMetaCopy,
		count = bag.count,
		equippedCount = bag.equippedCount,
		consumedCount = bag.consumedCount,
		maxCapacity = bag.maxCapacity,
		maxEquipped = bag.maxEquipped,
	})
end

return (Inventory :: any) :: InventoryModule
