--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local DEBUG_ATTRIBUTE = "SurfacePaintDebug"

local PaintSurface = {}

export type PaintSurfacePayload = {
	PlacementKey: string?,
	SurfaceId: string?,
	PaintColor: { [string]: number }? | Color3?,
}

export type PaintSurfaceBatchPayload = {
	PlacementKeys: { string }?,
	SurfaceId: string?,
	PaintColor: { [string]: number }? | Color3?,
}

local SUPPORTED_TYPES = {
	Floor = true,
	Wall = true,
}

local function sanitizePlacementKey(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end
	if value == "" then
		return nil
	end
	return value
end

local function sanitizePlacementKeys(list: any): { string }?
	if typeof(list) ~= "table" then
		return nil
	end
	local sanitized: { string } = {}
	for _, value in ipairs(list) do
		local key = sanitizePlacementKey(value)
		if key then
			sanitized[#sanitized + 1] = key
		end
	end
	if #sanitized == 0 then
		return nil
	end
	return sanitized
end

local function sanitizeSurfaceId(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end
	if value == "" then
		return nil
	end
	return value
end

local function parsePaintColor(value: any): Color3?
	if typeof(value) == "Color3" then
		return Color3.new(math.clamp(value.R, 0, 1), math.clamp(value.G, 0, 1), math.clamp(value.B, 0, 1))
	end
	if typeof(value) ~= "table" then
		return nil
	end
	local r = tonumber(value.R or value.r)
	local g = tonumber(value.G or value.g)
	local b = tonumber(value.B or value.b)
	if typeof(r) ~= "number" or typeof(g) ~= "number" or typeof(b) ~= "number" then
		return nil
	end
	return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end

local function encodeColor(color: Color3?): { [string]: number }?
	if typeof(color) ~= "Color3" then
		return nil
	end
	return {
		R = color.R,
		G = color.G,
		B = color.B,
	}
end

local function getOrCreateMetadata(savedEntry: { [string]: any }): { [string]: any }
	local metadata = savedEntry.Metadata
	if typeof(metadata) ~= "table" then
		metadata = {}
		savedEntry.Metadata = metadata
	end
	return metadata
end

local function isDebugEnabled(): boolean
	if Workspace:GetAttribute(DEBUG_ATTRIBUTE) == true then
		return true
	end
	local ok, result = pcall(function()
		return RunService:IsStudio()
	end)
	return ok and result == true
end

local function formatDebugPayload(data: any): string
	if data == nil then
		return "{}"
	end
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
	if ok then
		return encoded
	end
	return tostring(data)
end

local function debugLog(message: string, data: any?)
	if not isDebugEnabled() then
		return
	end
	if data ~= nil then
		warn(("[SurfacePaint][Server] %s :: %s"):format(message, formatDebugPayload(data)))
	else
		warn("[SurfacePaint][Server] " .. message)
	end
end

local function getStateContext(player: Player)
	local state = PlotService.GetState(player)
	if not state then
		return nil, nil, "Plot not ready"
	end
	local placedObjects = state.Save and state.Save.PlacedObjects
	if not placedObjects then
		return nil, nil, "No placements recorded"
	end
	return state, placedObjects, nil
end

local function applyPaintToPlacement(
	player: Player,
	placedObjects: { [string]: any },
	placementKey: string,
	requestedSurfaceId: string?,
	paintColor: Color3?,
	playerName: string
): (boolean, string)
	local savedEntry = placedObjects[placementKey]
	if not savedEntry then
		return false, "Placement not found"
	end

	local spec = ItemFinder.FindItemById(savedEntry.id)
	if not spec then
		return false, "Catalog item missing"
	end

	local placementType = tostring(spec.PlacementType or spec.Type or "CellObject")
	if not SUPPORTED_TYPES[placementType] then
		return false, "Only floors and walls support painting"
	end

	local metadata = getOrCreateMetadata(savedEntry)
	local resolvedSurfaceId = Helpers.resolveSurfaceId(spec, requestedSurfaceId)
	if requestedSurfaceId and requestedSurfaceId ~= "" and not resolvedSurfaceId then
		return false, "Material is not allowed for this placement"
	end
	if resolvedSurfaceId then
		metadata.SurfaceId = resolvedSurfaceId
	end

	metadata.PaintColor = encodeColor(paintColor)
	WorldPlacer.ApplySurfaceUpdate(player, placementKey, spec, metadata)

	local facing = savedEntry.facing :: any
	Helpers.sendPlacementDelta(
		player,
		"Updated",
		savedEntry.id,
		savedEntry.cellX,
		savedEntry.cellZ,
		facing,
		metadata,
		savedEntry.yLevel
	)

	debugLog(("Surface updated for %s"):format(playerName), {
		placementKey = placementKey,
		resolvedSurfaceId = metadata.SurfaceId,
		paintColor = metadata.PaintColor,
	})
	return true, "Surface updated"
end

function PaintSurface.PaintSurface(player: Player, payload: PaintSurfacePayload): (boolean, string)
	local playerName = if typeof(player) == "Instance" then player.Name else "?"
	local placementKey = sanitizePlacementKey(payload and payload.PlacementKey)
	local requestedSurfaceId = sanitizeSurfaceId(payload and payload.SurfaceId)
	debugLog(("Received request from %s"):format(playerName), {
		placementKey = placementKey,
		requestedSurfaceId = requestedSurfaceId,
		paintColor = payload and payload.PaintColor or nil,
	})

	if not placementKey then
		return false, "Missing placement key"
	end

	local state, placedObjects, stateError = getStateContext(player)
	if not state then
		return false, stateError or "Plot not ready"
	end

	local paintColor = parsePaintColor(payload and payload.PaintColor)
	local success, message =
		applyPaintToPlacement(player, placedObjects, placementKey, requestedSurfaceId, paintColor, playerName)
	if not success then
		debugLog(("Rejected request for %s: %s"):format(playerName, message), {
			placementKey = placementKey,
		})
	end
	return success, message
end

function PaintSurface.PaintSurfaceBatch(player: Player, payload: PaintSurfaceBatchPayload): (boolean, string)
	local playerName = if typeof(player) == "Instance" then player.Name else "?"
	local placementKeys = sanitizePlacementKeys(payload and payload.PlacementKeys)
	local requestedSurfaceId = sanitizeSurfaceId(payload and payload.SurfaceId)
	debugLog(("Received batch request from %s"):format(playerName), {
		count = placementKeys and #placementKeys or 0,
		requestedSurfaceId = requestedSurfaceId,
	})

	if not placementKeys or #placementKeys == 0 then
		return false, "No placement keys provided"
	end

	local state, placedObjects, stateError = getStateContext(player)
	if not state then
		return false, stateError or "Plot not ready"
	end

	local paintColor = parsePaintColor(payload and payload.PaintColor)
	local successes = 0
	local failures = 0
	local lastError: string? = nil
	for _, key in ipairs(placementKeys) do
		local ok, message =
			applyPaintToPlacement(player, placedObjects, key, requestedSurfaceId, paintColor, playerName)
		if ok then
			successes += 1
		else
			failures += 1
			lastError = message
		end
	end

	if successes == 0 then
		return false, lastError or "No placements updated"
	end
	if failures > 0 then
		return true, ("Updated %d placement(s); %d failed"):format(successes, failures)
	end
	return true, ("Updated %d placement(s)"):format(successes)
end

return PaintSurface
