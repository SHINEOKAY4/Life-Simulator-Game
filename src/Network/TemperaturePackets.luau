--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

return {
	-- Sends a list of room temperatures for the player's plot
	-- Args: { { X: number, Z: number, Level: number, Temp: number } }
	-- We use a representative cell (X, Z) to identify the room.
	Update = Packet("TemperatureUpdate", {
		{
			X = Packet.NumberU8,
			Z = Packet.NumberU8,
			Level = Packet.NumberU8,
			Temp = Packet.NumberF32,
		},
	}),

	-- Sets the target temperature for a room via a thermostat
	-- Args: { X: number, Z: number, Level: number, TargetTemp: number }
	SetTargetTemp = Packet("SetTargetTemp", {
		X = Packet.NumberU8,
		Z = Packet.NumberU8,
		Level = Packet.NumberU8,
		TargetTemp = Packet.NumberF32,
	}),

	GetRoomDetails = Packet("GetRoomDetails", {
		X = Packet.NumberU8,
		Z = Packet.NumberU8,
		Level = Packet.NumberU8,
	}):Response({
		MinTemp = Packet.NumberF32,
		MaxTemp = Packet.NumberF32,
		CurrentTemp = Packet.NumberF32,
	}),
}
