--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local StashPackets = require(ReplicatedStorage.Network.StashPackets)
local RateLimiter = require(ReplicatedStorage.Shared.Utilities.RateLimiter)

local ActionsFolder = script.Actions

local ActionModules = {
	Build = ActionsFolder.Build,
	DestroyAction = ActionsFolder.DestroyAction,
	StashAction = ActionsFolder.StashAction,
	Move = ActionsFolder.Move,
	PlaceFloorArea = ActionsFolder.PlaceFloorArea,
	PlaceRoofArea = ActionsFolder.PlaceRoofArea,
	PlaceWallStrip = ActionsFolder.PlaceWallStrip,
	PlaceSurfaceMount = ActionsFolder.PlaceSurfaceMount,
	DestroySurfaceMount = ActionsFolder.DestroySurfaceMount,
	Rotate = ActionsFolder.Rotate,
	PaintSurface = ActionsFolder.PaintSurface,
	ConnectUtility = ActionsFolder.ConnectUtility,
	DisconnectUtility = ActionsFolder.DisconnectUtility,
}

local ActionCache: { [string]: any } = {}

local function resolveAction(actionName: string)
	local cached = ActionCache[actionName]
	if cached ~= nil then
		return cached
	end
	local actionModule = ActionModules[actionName]
	if not actionModule then
		error(("Unknown build action '%s'"):format(actionName))
	end
	local resolved = require(actionModule)
	ActionCache[actionName] = resolved
	return resolved
end

local function dispatchAction(actionName: string)
	local resolved: any = nil
	return function(player: Player, payload: any): (boolean, string)
		if resolved == nil then
			resolved = resolveAction(actionName)
		end
		return resolved(player, payload)
	end
end

local function dispatchActionMethod(actionName: string, methodName: string)
	local resolved: any = nil
	return function(player: Player, payload: any): (boolean, string)
		if resolved == nil then
			resolved = resolveAction(actionName)
		end
		local method = resolved[methodName]
		return method(player, payload)
	end
end

local BuildService = {}

local Limiter = RateLimiter.new()
local PlaceBucket = Limiter:Bucket("place", { ratePerSecond = 4, burst = 6 })

local function withRateLimit(handler: (Player, any) -> (boolean, string))
	return function(player: Player, payload: any): (boolean, string)
		if not PlaceBucket:Allow(player, 1) then
			local waitSeconds = PlaceBucket:SecondsUntilNextToken(player)
			return false, ("Too fast. Try again in %.2fs"):format(waitSeconds)
		end

		return handler(player, payload)
	end
end

BuildService.PlaceFloorArea = dispatchAction("PlaceFloorArea")
BuildService.PlaceRoofArea = dispatchAction("PlaceRoofArea")
BuildService.PlaceWallStrip = dispatchAction("PlaceWallStrip")
BuildService.Build = dispatchAction("Build")
BuildService.Destroy = dispatchAction("DestroyAction")
BuildService.Move = dispatchAction("Move")
BuildService.Rotate = dispatchAction("Rotate")
BuildService.PlaceSurfaceMount = dispatchAction("PlaceSurfaceMount")
BuildService.DestroySurfaceMount = dispatchAction("DestroySurfaceMount")
BuildService.PaintSurface = dispatchActionMethod("PaintSurface", "PaintSurface")
BuildService.PaintSurfaceBatch = dispatchActionMethod("PaintSurface", "PaintSurfaceBatch")
BuildService.ConnectUtility = dispatchAction("ConnectUtility")
BuildService.DisconnectUtility = dispatchAction("DisconnectUtility")

function BuildService.Init()
	Packets.PlaceRequest.OnServerInvoke = withRateLimit(BuildService.Build)
	Packets.PlaceFloorAreaRequest.OnServerInvoke = withRateLimit(BuildService.PlaceFloorArea)
	Packets.PlaceRoofAreaRequest.OnServerInvoke = withRateLimit(BuildService.PlaceRoofArea)
	Packets.PlaceWallStripRequest.OnServerInvoke = withRateLimit(BuildService.PlaceWallStrip)
	Packets.PlaceSurfaceMountRequest.OnServerInvoke = withRateLimit(BuildService.PlaceSurfaceMount)
	Packets.DestroySurfaceMountRequest.OnServerInvoke = withRateLimit(BuildService.DestroySurfaceMount)
	Packets.PaintSurfaceRequest.OnServerInvoke = withRateLimit(BuildService.PaintSurface)
	Packets.PaintSurfaceBatchRequest.OnServerInvoke = withRateLimit(BuildService.PaintSurfaceBatch)
	Packets.DestroyRequest.OnServerInvoke = withRateLimit(BuildService.Destroy)
	Packets.MoveRequest.OnServerInvoke = withRateLimit(BuildService.Move)
	Packets.RotateRequest.OnServerInvoke = withRateLimit(BuildService.Rotate)
	Packets.ConnectUtilityRequest.OnServerInvoke = withRateLimit(BuildService.ConnectUtility)
	Packets.DisconnectUtilityRequest.OnServerInvoke = withRateLimit(BuildService.DisconnectUtility)

	-- Stash packet handlers
	StashPackets.StashItem.OnServerInvoke = withRateLimit(dispatchAction("StashAction"))

	StashPackets.GetStash.OnServerInvoke = function(player: Player): (boolean, string, any)
		local stashAction = resolveAction("StashAction")
		local items = stashAction.GetStashItems(player)
		if not items then
			return false, "Unable to load stash", nil
		end
		return true, "ok", items
	end

	StashPackets.PlaceFromStash.OnServerInvoke = withRateLimit(function(player: Player, payload: any): (boolean, string)
		local itemId = if typeof(payload) == "table" and typeof(payload.ItemId) == "string" then payload.ItemId else nil
		if not itemId or itemId == "" then
			return false, "Invalid item ID"
		end
		local stashAction = resolveAction("StashAction")
		if not stashAction.DeductFromStash(player, itemId) then
			return false, "Item not in stash"
		end
		local buildPayload = table.clone(payload)
		buildPayload.SkipCost = true
		local success, message = BuildService.Build(player, buildPayload)
		if not success then
			-- Restore the deducted count on failure.
			stashAction.AddToStash(player, itemId, 1)
		end
		return success, message
	end)
end

return BuildService
