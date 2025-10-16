--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotStateModule = require(ServerScriptService.Server.Classes.PlotState)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

type Facing = PlotStateModule.Facing
type PlotRuntimeState = PlotStateModule.PlotState
type SavedPlacedObject = PlotStateModule.SavedPlacedObject

type Metadata = { [string]: any }

local Helpers = {}

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
	metadata: Metadata?
)
	local width, depth = Helpers.resolveFootprintDimensions(itemId, metadata)
	Packets.PlacementDelta:FireClient(player, {
		Action = action,
		Item = {
			ItemId = itemId,
			CellX = cellX,
			CellZ = cellZ,
			Facing = facing,
			WidthCells = width,
			DepthCells = depth,
		},
	})
end

function Helpers.coerceFacing(value: string?): Facing?
	if value == "North" or value == "East" or value == "South" or value == "West" then
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

return Helpers
