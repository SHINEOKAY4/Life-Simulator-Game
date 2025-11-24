--!strict
-- ReplicatedStorage/Network/TenantPackets.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packet = require(ReplicatedStorage.Packages.Packet)

local TenantPackets = {}

local function tenantRecordShape()
	return {
		TenantId = Packet.String,
		Name = Packet.String,
		TierId = Packet.String,
		Traits = { Packet.String },
		Rent = Packet.NumberU32,
		RentInterval = Packet.NumberU32,
		Boost = Packet.NumberF32,
		RoomKey = Packet.String,
	}
end

local function roomRosterShape()
	return {
		RoomKey = Packet.String,
		Label = Packet.String,
		Level = Packet.NumberS16,
		Capacity = Packet.NumberU16,
		Occupied = Packet.NumberU16,
		MinCellX = Packet.NumberS16,
		MinCellZ = Packet.NumberS16,
		SizeX = Packet.NumberU16,
		SizeZ = Packet.NumberU16,
	}
end

TenantPackets.ProspectSpawn = Packet("TenantProspectSpawn", {
	ProspectId = Packet.String,
	Slot = Packet.NumberU8,
	Name = Packet.String,
	TierId = Packet.String,
	RentPerInterval = Packet.NumberU32,
	RentIntervalSeconds = Packet.NumberU32,
	Deposit = Packet.NumberU32,
	RentBoostPercent = Packet.NumberF32,
	LeaseSeconds = Packet.NumberU32,
	Traits = { Packet.String },
})

TenantPackets.ProspectRemoved = Packet("TenantProspectRemoved", {
	ProspectId = Packet.String,
	Slot = Packet.NumberU8,
	Reason = Packet.String,
})

TenantPackets.ProspectPrompt = Packet("TenantProspectPrompt", {
	ProspectId = Packet.String,
	Slot = Packet.NumberU8,
	Name = Packet.String,
	TierId = Packet.String,
	RentPerInterval = Packet.NumberU32,
	RentIntervalSeconds = Packet.NumberU32,
	Deposit = Packet.NumberU32,
	RentBoostPercent = Packet.NumberF32,
	LeaseSeconds = Packet.NumberU32,
	Traits = { Packet.String },
})

TenantPackets.ProspectDecision = Packet("TenantProspectDecision", Packet.String, Packet.String, Packet.String):Response(
	Packet.Boolean8,
	Packet.StringLong
)

TenantPackets.EvictTenantRequest =
	Packet("TenantEvictRequest", Packet.String):Response(Packet.Boolean8, Packet.StringLong)

TenantPackets.GetTenantDetails = Packet("GetTenantDetails", Packet.String):Response({
	TenantId = Packet.String,
	Name = Packet.String,
	TierId = Packet.String,
	Rent = Packet.NumberU32,
	RentInterval = Packet.NumberU32,
	Boost = Packet.NumberF32,
	Traits = { Packet.String },
	Rating = Packet.NumberF32,
	RoomKey = Packet.String,
})

TenantPackets.ActiveTenantsSync = Packet("ActiveTenantsSync", {
	UserId = Packet.NumberF64,
	Tenants = {
		tenantRecordShape(),
	},
})

TenantPackets.RequestActiveTenants = Packet("RequestActiveTenants", {}):Response({
	UserId = Packet.NumberF64,
	Tenants = {
		tenantRecordShape(),
	},
})

TenantPackets.TenantDelta = Packet("TenantDelta", {
	UserId = Packet.NumberF64,
	TenantId = Packet.String, -- For deletions
	TenantData = { -- Optional, if present it's an update/add
		tenantRecordShape(),
	},
})

TenantPackets.RequestTenantRooms = Packet("TenantRoomRosterRequest", {}):Response({
	UserId = Packet.NumberF64,
	TotalCapacity = Packet.NumberU16,
	Available = Packet.NumberU16,
	Rooms = {
		roomRosterShape(),
	},
})

TenantPackets.RequestRoomDiagnostics = Packet("TenantRoomDiagnosticsRequest", {}):Response({
	UserId = Packet.NumberF64,
	Rooms = {
		{
			RoomKey = Packet.String,
			Level = Packet.NumberS16,
			MinCellX = Packet.NumberS16,
			MinCellZ = Packet.NumberS16,
			SizeX = Packet.NumberU16,
			SizeZ = Packet.NumberU16,
			CellCount = Packet.NumberU16,
			CellIndices = { Packet.NumberU32 },
			Ready = Packet.Boolean8,
			Reason = Packet.String,
			HasBed = Packet.Boolean8,
			IsEnclosed = Packet.Boolean8,
			Capacity = Packet.NumberU16,
			Occupied = Packet.NumberU16,
		},
	},
})

return TenantPackets
