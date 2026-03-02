--!strict
-- ReplicatedStorage/Network/StashPackets.luau
-- Packets for the player stash (pick up items from plot, view stash, place from stash).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local StashPackets = {}

-- Pick up a placed item from the plot and add it to the stash (does not charge currency).
-- Payload mirrors the shape of DestroyRequest.
StashPackets.StashItem = Packet("StashItem", {
	ItemId = Packet.String,
	CellX = Packet.NumberU8,
	CellZ = Packet.NumberU8,
	Facing = Packet.Static1,
	Level = Packet.NumberU8,
	SubSlotId = Packet.String,
}):Response(Packet.Boolean8, Packet.StringLong)

-- Fetch the client's current stash contents.
-- Response: success, message, items table { [itemId]: count }
StashPackets.GetStash = Packet("GetStash"):Response(Packet.Boolean8, Packet.StringLong, Packet.Any)

-- Place an item from the stash onto the plot (free – deducts from stash instead of charging cash).
-- Payload mirrors PlaceRequest so the same client-side preview flow works.
StashPackets.PlaceFromStash = Packet("PlaceFromStash", {
	ItemId = Packet.String,
	CellX = Packet.NumberU8,
	CellZ = Packet.NumberU8,
	Facing = Packet.Static1,
	Level = Packet.NumberU8,
	SurfaceId = Packet.String,
	SubSlotId = Packet.String,
	WallMountEnabled = Packet.Boolean8,
	WallMountCellX = Packet.NumberU16,
	WallMountCellZ = Packet.NumberU16,
	WallMountFacing = Packet.Static1,
	WallMountHeightOffset = Packet.NumberF32,
	WallMountPosX = Packet.NumberF32,
	WallMountPosY = Packet.NumberF32,
	WallMountPosZ = Packet.NumberF32,
	WallMountNormalX = Packet.NumberF32,
	WallMountNormalY = Packet.NumberF32,
	WallMountNormalZ = Packet.NumberF32,
	CeilingMountEnabled = Packet.Boolean8,
	CeilingMountCellX = Packet.NumberU16,
	CeilingMountCellZ = Packet.NumberU16,
	CeilingMountLevel = Packet.NumberU8,
	CeilingMountDropStuds = Packet.NumberF32,
	CeilingMountRotationY = Packet.NumberF32,
	CeilingMountPosX = Packet.NumberF32,
	CeilingMountPosY = Packet.NumberF32,
	CeilingMountPosZ = Packet.NumberF32,
	CeilingMountNormalX = Packet.NumberF32,
	CeilingMountNormalY = Packet.NumberF32,
	CeilingMountNormalZ = Packet.NumberF32,
	WindowEnabled = Packet.Boolean8,
	WindowHeightOffset = Packet.NumberF32,
}):Response(Packet.Boolean8, Packet.StringLong)

-- Server → client push: stash contents changed.
-- Payload: items table { [itemId]: count }
StashPackets.StashUpdated = Packet("StashUpdated", Packet.Any)

return StashPackets
