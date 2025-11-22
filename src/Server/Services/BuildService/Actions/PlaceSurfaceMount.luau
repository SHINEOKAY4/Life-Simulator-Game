--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)
local PlotStateModule = require(ServerScriptService.Server.Classes.PlotState)

local SMALL_NUDGE = 1e-3

type Payload = {
	ItemId: string,
	ParentKey: string,
	LocalPosX: number,
	LocalPosY: number,
	LocalPosZ: number,
	LocalRotationY: number?,
	Metadata: { [string]: any }?,
}

type PlotRuntimeState = PlotStateModule.PlotState

local function toVector3(x: number?, y: number?, z: number?): Vector3?
	if typeof(x) ~= "number" or typeof(y) ~= "number" or typeof(z) ~= "number" then
		return nil
	end

	if x ~= x or y ~= y or z ~= z then
		return nil
	end

	return Vector3.new(x, y, z)
end

local function ensureParentExists(state: PlotRuntimeState, parentKey: string): boolean
	local parentEntry = state.Save.PlacedObjects[parentKey]
	if parentEntry then
		return true
	end

	return false
end

local function PlaceSurfaceMount(player: Player, payload: Payload): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	if typeof(payload.ItemId) ~= "string" or payload.ItemId == "" then
		return false, "Invalid item id"
	end

	if typeof(payload.ParentKey) ~= "string" or payload.ParentKey == "" then
		return false, "Missing parent"
	end

	local parentKey = payload.ParentKey
	if not ensureParentExists(state, parentKey) then
		return false, "Parent not found"
	end

	local itemSpec = ItemFinder.FindItemById(payload.ItemId)
	if not itemSpec then
		return false, "Invalid item id"
	end

	local unlocked, lockReason = Helpers.ensurePlacementUnlocked(player, itemSpec, payload.ItemId)
	if not unlocked then
		return false, lockReason or "Level up to unlock this attachment"
	end

	local placementType = itemSpec.PlacementType or itemSpec.Type
	if placementType ~= "SurfaceMounted" then
		return false, "Item is not surface-mounted"
	end

	local localPosition = toVector3(payload.LocalPosX, payload.LocalPosY, payload.LocalPosZ)
	if not localPosition then
		return false, "Invalid mount position"
	end

	if math.abs(localPosition.X) > 1e6 or math.abs(localPosition.Y) > 1e6 or math.abs(localPosition.Z) > 1e6 then
		return false, "Mount position out of range"
	end

	local rotationY = payload.LocalRotationY
	if rotationY ~= nil then
		if typeof(rotationY) ~= "number" or rotationY ~= rotationY then
			return false, "Invalid rotation"
		end
	end

	local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, itemSpec, 1)
	if not canAfford then
		return false, failureReason or "Not enough cash"
	end

	local adjustedPosition = localPosition
	if adjustedPosition.Magnitude < SMALL_NUDGE then
		adjustedPosition = Vector3.new(SMALL_NUDGE, adjustedPosition.Y, SMALL_NUDGE)
	end

	local mountKey, err =
		state:PlaceSurfaceMount(payload.ItemId, parentKey, adjustedPosition, rotationY, payload.Metadata)
	if not mountKey then
		return false, err or "Failed to mount object"
	end

	local savedEntry = state.SurfaceMountedObjects[mountKey]
	if not savedEntry then
		return false, "Mount state missing"
	end

	WorldPlacer.SpawnSurfaceMount(player, parentKey, mountKey, payload.ItemId, savedEntry)
	Helpers.sendSurfaceMountDelta(player, "Placed", mountKey, savedEntry)
	Helpers.deductPlacementCost(player, currencyState, totalCost)
	Helpers.rewardPlacementProgress(player, itemSpec, 1)

	return true, "Surface mount placed"
end

return PlaceSurfaceMount
