--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CurrencyService = require(ServerScriptService.Server.Services.CurrencyService)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local ProgressionService = require(ServerScriptService.Server.Services.ProgressionService)
local AchievementService = require(ServerScriptService.Server.Services.AchievementService)
local PlotStateModule = require(ServerScriptService.Server.Classes.PlotState)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementBehavior = require(ReplicatedStorage.Shared.Utilities.PlacementBehavior)
local SurfacePalette = require(ReplicatedStorage.Shared.Configurations.Build.SurfacePalette)

type Facing = PlotStateModule.Facing
type PlotRuntimeState = PlotStateModule.PlotState
type SavedPlacedObject = PlotStateModule.SavedPlacedObject

type CurrencyState = { [string]: number }

local PRIMARY_CURRENCY_NAME = "Cash"

type Metadata = { [string]: any }

local Helpers = {}

local function sanitizeSurfaceId(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end
	if value == "" then
		return nil
	end
	return value
end

local function cloneMetadata(value: any): any
	if typeof(value) ~= "table" then
		return value
	end

	local result = {}
	for key, entry in pairs(value) do
		result[key] = cloneMetadata(entry)
	end

	return result
end

local function serializeVector3(value: any): { X: number, Y: number, Z: number }
	if typeof(value) == "Vector3" then
		return {
			X = value.X,
			Y = value.Y,
			Z = value.Z,
		}
	end

	if typeof(value) == "table" then
		local xValue = value.X or value.x
		local yValue = value.Y or value.y
		local zValue = value.Z or value.z
		if typeof(xValue) == "number" and typeof(yValue) == "number" and typeof(zValue) == "number" then
			return {
				X = xValue,
				Y = yValue,
				Z = zValue,
			}
		end
	end

	return {
		X = 0,
		Y = 0,
		Z = 0,
	}
end

function Helpers.resolveFootprintDimensions(itemId: string, metadata: Metadata?): (number, number)
	local spec = ItemFinder.FindItemById(itemId)
	local widthOverride = metadata and (metadata.WidthCells or metadata.widthCells or metadata.Width or metadata.width)
	local depthOverride = metadata and (metadata.DepthCells or metadata.depthCells or metadata.Depth or metadata.depth)
	local width = if typeof(widthOverride) == "number" and widthOverride > 0 then widthOverride else nil
	local depth = if typeof(depthOverride) == "number" and depthOverride > 0 then depthOverride else nil
	if not width then
		width = spec and (spec.WidthCells or spec.Width) or 1
	end
	if not depth then
		depth = spec and (spec.DepthCells or spec.Depth) or 1
	end
	return width or 1, depth or 1
end

function Helpers.sendPlacementDelta(
	player: Player,
	action: string,
	itemId: string,
	cellX: number,
	cellZ: number,
	facing: Facing,
	metadata: Metadata?,
	level: number?,
	placementKey: string?
)
	local width, depth = Helpers.resolveFootprintDimensions(itemId, metadata)
	local metadataPayload = if metadata ~= nil then cloneMetadata(metadata) else nil
	local subSlotId = ""
	if metadataPayload then
		local slotCandidate = metadataPayload.SubSlotId or metadataPayload.subSlotId
		if typeof(slotCandidate) == "string" and slotCandidate ~= "" then
			subSlotId = slotCandidate
		end
	end
	Packets.PlacementDelta:FireClient(player, {
		Action = action,
		Item = {
			ItemId = itemId,
			CellX = cellX,
			CellZ = cellZ,
			Facing = facing,
			WidthCells = width,
			DepthCells = depth,
			Metadata = metadataPayload,
			Level = level,
			PlacementKey = placementKey,
			SubSlotId = subSlotId,
		},
	})
end

function Helpers.resolveSurfaceId(itemSpec: { [string]: any }?, requestedSurfaceId: string?): string?
	return SurfacePalette.ResolveForPlacement(itemSpec, sanitizeSurfaceId(requestedSurfaceId))
end

function Helpers.getPlacementKeyLabel(itemSpec: { [string]: any }?): string
	return PlacementBehavior.getPlacementKeyLabel(itemSpec)
end

function Helpers.getPlacementKeyLabelForSubSlot(itemSpec: { [string]: any }?, subSlotId: string?): string
	return PlacementBehavior.getPlacementKeyLabelForSubSlot(itemSpec, subSlotId)
end

function Helpers.allowsStacking(itemSpec: { [string]: any }?): boolean
	return PlacementBehavior.allowsStacking(itemSpec)
end

function Helpers.sendSurfaceMountDelta(
	player: Player,
	action: string,
	mountKey: string,
	mountEntry: PlotStateModule.SavedSurfaceMount
)
	local metadataPayload = if mountEntry.Metadata ~= nil then cloneMetadata(mountEntry.Metadata) else nil
	Packets.SurfaceMountDelta:FireClient(player, {
		Action = action,
		Mount = {
			Key = mountKey,
			ParentKey = mountEntry.parentKey,
			ItemId = mountEntry.id,
			LocalPosition = serializeVector3(mountEntry.LocalPosition),
			LocalRotationY = mountEntry.LocalRotationY,
			Metadata = metadataPayload,
		},
	})
end

function Helpers.coerceFacing(value: string?): Facing?
	if value == nil then
		return nil
	end

	if
		value == "North"
		or value == "East"
		or value == "South"
		or value == "West"
		or value == "NorthEast"
		or value == "NorthWest"
		or value == "SouthEast"
		or value == "SouthWest"
	then
		return value :: Facing
	end

	return nil
end

function Helpers.resolvePlacedItem(
	state: PlotRuntimeState,
	identifier: string
): (string?, any?, Facing?, SavedPlacedObject?)
	if type(identifier) ~= "string" or identifier == "" then
		return nil, nil, nil, nil
	end

	local spec = ItemFinder.FindItemById(identifier)
	if spec then
		return identifier, spec, nil, nil
	end

	local placedMap = (state.Save and state.Save.PlacedObjects) or nil
	if placedMap then
		local saved = placedMap[identifier]
		if saved then
			local savedSpec = ItemFinder.FindItemById(saved.id)
			if savedSpec then
				return saved.id, savedSpec, PlacementKey.NormalizeFacing(saved.facing), saved
			end
		end
	end

	local parseOk, parsedCellX, parsedCellZ, parsedFacingValue, parsedPlacementType =
		pcall(PlacementKey.ParseWithType, identifier)
	if parseOk and placedMap then
		local parsedFacing: Facing = Helpers.coerceFacing(parsedFacingValue :: string?) or "North"
		local canonKey = state:PlacementKeyForType(parsedCellX, parsedCellZ, parsedFacing, parsedPlacementType)
		local saved = placedMap[canonKey]
		if saved then
			local savedSpec = ItemFinder.FindItemById(saved.id)
			if savedSpec then
				return saved.id, savedSpec, PlacementKey.NormalizeFacing(saved.facing), saved
			end
		end
	end

	return nil, nil, nil, nil
end

local function computeQuantityMultiplier(quantity: number?): number
	if typeof(quantity) ~= "number" then
		return 1
	end
	if quantity <= 0 then
		return 0
	end
	local floored = math.floor(quantity)
	if floored < 1 then
		return 1
	end
	return floored
end

function Helpers.computePlacementCost(itemSpec: { [string]: any }?, quantity: number?): number
	if typeof(itemSpec) ~= "table" then
		return 0
	end
	local unitCost = itemSpec.Cost
	if typeof(unitCost) ~= "number" or unitCost <= 0 then
		return 0
	end
	local multiplier = computeQuantityMultiplier(quantity)
	if multiplier <= 0 then
		return 0
	end
	return unitCost * multiplier
end

function Helpers.ensurePlacementFunds(
	player: Player,
	itemSpec: { [string]: any }?,
	quantity: number?
): (boolean, string?, number, CurrencyState?)
	local totalCost = Helpers.computePlacementCost(itemSpec, quantity)
	if totalCost <= 0 then
		return true, nil, 0, nil
	end

	local currencyState = PlayerSession.GetDataAwait(player, "CurrencyState")
	if typeof(currencyState) ~= "table" then
		warn(("[BuildService] Currency state unavailable for %s"):format(player.Name))
		return false, "Unable to process placement right now.", 0, nil
	end

	local balanceValue = currencyState[PRIMARY_CURRENCY_NAME]
	local balance = if typeof(balanceValue) == "number" then balanceValue else 0
	if balance < totalCost then
		local itemNameValue = itemSpec and itemSpec.Name
		local itemName = if typeof(itemNameValue) == "string" and itemNameValue ~= "" then itemNameValue else "item"
		return false, ("Not enough cash for %s (need %d)."):format(itemName, totalCost), totalCost, currencyState
	end

	return true, nil, totalCost, currencyState
end

function Helpers.deductPlacementCost(player: Player, currencyState: CurrencyState?, totalCost: number)
	if totalCost <= 0 then
		return
	end
	if currencyState == nil then
		return
	end
	CurrencyService.Remove(player, PRIMARY_CURRENCY_NAME, totalCost, currencyState)
end

function Helpers.ensurePlacementUnlocked(
	player: Player,
	itemSpec: { [string]: any }?,
	itemId: string?
): (boolean, string?)
	return ProgressionService.CanPlaceItem(player, itemSpec, itemId)
end

function Helpers.rewardPlacementProgress(player: Player, itemSpec: { [string]: any }?, quantity: number?)
	ProgressionService.RecordBuildPlacement(player, itemSpec, quantity)
	AchievementService.RecordBuildPlaced(player, quantity)
end

return Helpers
