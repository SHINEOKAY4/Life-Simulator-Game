--!strict
-- ReplicatedStorage/Network/EmotePackets.luau
-- Defines network packets for the emote system.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local EmotePackets = {}

-- Client -> Server: request the list of emote definitions available to the player.
-- Response: success flag, array of emote info tables ({ id, name, description }).
EmotePackets.GetEmotes = Packet("EmoteGetEmotes"):Response(Packet.Boolean8, Packet.Any)

-- Client -> Server: perform a specific emote by id.
-- Payload: emoteId (String).
-- Response: success flag, error string (or empty string on success).
EmotePackets.PerformEmote = Packet("EmotePerform", Packet.String):Response(Packet.Boolean8, Packet.String)

-- Server -> All Clients: broadcast when any player performs an emote.
-- Payload: { PlayerId, EmoteId }.
EmotePackets.EmotePerformed = Packet("EmotePerformed", {
	PlayerId = Packet.NumberF64,
	EmoteId = Packet.String,
})

return EmotePackets
