--!strict
-- StarterPlayerScripts/Client/ClientStores/TenantStore.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local TenantPackets = require(ReplicatedStorage.Network.TenantPackets)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local TenantStore = {}
local PlayersTenants = {}

TenantStore.TenantsUpdated = GoodSignal.new()
TenantStore.TenantAdded = GoodSignal.new()
TenantStore.TenantRemoved = GoodSignal.new()

function TenantStore.Init()
	TenantPackets.ActiveTenantsSync.OnClientEvent:Connect(function(payload)
		local userId = payload.UserId
		local current = PlayersTenants[userId]
		if not current then
			current = {}
			PlayersTenants[userId] = current
		end

		local seen: { [string]: boolean } = {}
		local tenantsPayload = payload.Tenants
		if type(tenantsPayload) ~= "table" then
			return
		end

		for _, tenant in ipairs(tenantsPayload) do
			if typeof(tenant) == "table" and type(tenant.TenantId) == "string" then
				local tenantId = tenant.TenantId
				seen[tenantId] = true
				local existing = current[tenantId]
				current[tenantId] = tenant
				if existing then
					TenantStore.TenantsUpdated:Fire(userId, tenant)
				else
					TenantStore.TenantAdded:Fire(userId, tenant)
				end
			end
		end

		local toRemove = {}
		for tenantId in pairs(current) do
			if not seen[tenantId] then
				table.insert(toRemove, tenantId)
			end
		end
		for _, tenantId in ipairs(toRemove) do
			current[tenantId] = nil
			TenantStore.TenantRemoved:Fire(userId, tenantId)
		end
	end)

	TenantPackets.TenantDelta.OnClientEvent:Connect(function(payload)
		local userId = payload.UserId
		local tenants = PlayersTenants[userId]
		if not tenants then
			tenants = {}
			PlayersTenants[userId] = tenants
		end

		local deltas = payload.TenantData or {}
		if #deltas > 0 then
			for _, tenant in ipairs(deltas) do
				if typeof(tenant) == "table" and type(tenant.TenantId) == "string" then
					local tenantId = tenant.TenantId
					local existing = tenants[tenantId]
					tenants[tenantId] = tenant
					if existing then
						TenantStore.TenantsUpdated:Fire(userId, tenant)
					else
						TenantStore.TenantAdded:Fire(userId, tenant)
					end
				end
			end
		else
			local tenantId = payload.TenantId
			if type(tenantId) == "string" then
				local previous = tenants[tenantId]
				if previous then
					tenants[tenantId] = nil
					TenantStore.TenantRemoved:Fire(userId, tenantId)
				end
			end
		end
	end)
end

local function deepClone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local copy = table.clone(value)
	for key, item in value do
		copy[key] = deepClone(item)
	end
	return copy
end

local function resolveUserId(userId: number?): number?
	if typeof(userId) == "number" then
		return userId
	end
	local localPlayer = Players.LocalPlayer
	if not localPlayer then
		return nil
	end
	return localPlayer.UserId
end

function TenantStore.GetTenant(userId: number?, tenantId: string): any?
	if type(tenantId) ~= "string" or tenantId == "" then
		return nil
	end
	local resolvedUserId = resolveUserId(userId)
	if not resolvedUserId then
		return nil
	end
	local tenants = PlayersTenants[resolvedUserId]
	if not tenants then
		return nil
	end
	local data = tenants[tenantId]
	if data == nil then
		return nil
	end
	return deepClone(data)
end

function TenantStore.GetTenants(userId: number?): { [string]: any }?
	local resolvedUserId = resolveUserId(userId)
	if not resolvedUserId then
		return nil
	end
	local tenants = PlayersTenants[resolvedUserId]
	if not tenants then
		return nil
	end
	local snapshot = {}
	for id, data in tenants do
		snapshot[id] = deepClone(data)
	end
	return snapshot
end

return TenantStore
