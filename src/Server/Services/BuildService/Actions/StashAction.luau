--!strict
-- Picks up a placed item from the player's plot and adds it to their stash.
-- This is essentially DestroyAction + stash bookkeeping.

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local StashPackets = require(ReplicatedStorage.Network.StashPackets)

local DestroyAction = require(ServerScriptService.Server.Services.BuildService.Actions.DestroyAction)

-- Reads the stash items table from player data, creating it if absent.
local function getStashItems(player: Player): { [string]: number }?
	local stashState = PlayerSession.GetDataAwait(player, "StashState")
	if typeof(stashState) ~= "table" then
		return nil
	end
	if typeof(stashState.Items) ~= "table" then
		stashState.Items = {}
	end
	return stashState.Items :: { [string]: number }
end

-- Pushes the current stash contents to the client.
local function pushStashUpdate(player: Player)
	local items = getStashItems(player)
	if items then
		StashPackets.StashUpdated:FireClient(player, items)
	end
end

-- Returns the stash items table to the server caller, with a push side-effect.
-- Exported for use by the PlaceFromStash handler in BuildService.
local function getStashItemsPublic(player: Player): { [string]: number }?
	return getStashItems(player)
end

-- Adds `count` of `itemId` to the player's stash and pushes an update.
local function addToStash(player: Player, itemId: string, count: number)
	local items = getStashItems(player)
	if not items then
		return
	end
	local current = items[itemId]
	items[itemId] = (if typeof(current) == "number" then current else 0) + count
	pushStashUpdate(player)
end

-- Removes one of `itemId` from the stash. Returns true if successful.
local function deductFromStash(player: Player, itemId: string): boolean
	local items = getStashItems(player)
	if not items then
		return false
	end
	local count = items[itemId]
	if typeof(count) ~= "number" or count < 1 then
		return false
	end
	if count <= 1 then
		items[itemId] = nil
	else
		items[itemId] = count - 1
	end
	pushStashUpdate(player)
	return true
end

type Payload = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: string,
	Level: number?,
	SubSlotId: string?,
}

-- Picks up an item from the plot and stashes it.
local function StashAction(player: Player, payload: Payload): (boolean, string)
	local itemId = payload.ItemId
	if typeof(itemId) ~= "string" or itemId == "" then
		return false, "Invalid item ID"
	end

	-- Delegate removal to the existing destroy logic.
	local success, message = DestroyAction(player, {
		ItemId = itemId,
		CellX = payload.CellX,
		CellZ = payload.CellZ,
		Facing = payload.Facing,
		Level = payload.Level,
		SubSlotId = payload.SubSlotId,
	})

	if not success then
		return false, message
	end

	-- Item was successfully removed from the plot – add it to the stash.
	addToStash(player, itemId, 1)
	return true, "Stashed"
end

-- Public API used by BuildService.Init to handle GetStash and PlaceFromStash stash deduction.
StashAction.AddToStash = addToStash
StashAction.DeductFromStash = deductFromStash
StashAction.PushStashUpdate = pushStashUpdate
StashAction.GetStashItems = getStashItemsPublic

return StashAction
