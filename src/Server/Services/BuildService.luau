--!strict
-- ServerScriptService/Server/Services/BuildService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local PlotStateModule = require(ServerScriptService.Server.Classes.PlotState)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local RateLimiter = require(ReplicatedStorage.Shared.Utilities.RateLimiter)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)

type Facing = PlotStateModule.Facing
type PlotRuntimeState = PlotStateModule.PlotState

local BuildService = {}

local Limiter = RateLimiter.new()
local PlaceBucket = Limiter:Bucket("place", { ratePerSecond = 4, burst = 6 })

local function coerceFacing(value: string?): Facing?
	if value == "North" or value == "East" or value == "South" or value == "West" then
		return value :: Facing
	end

	return nil
end

function BuildService.Init()
	print("BuildService initialized.")
	Packets.PlaceRequest.OnServerInvoke = function(
		player: Player,
		payload: { ItemId: string, CellX: number, CellZ: number, Facing: string }
	): (boolean, string)
		if not PlaceBucket:Allow(player, 1) then
			local waitSeconds = PlaceBucket:SecondsUntilNextToken(player)
			return false, ("Too fast. Try again in %.2fs"):format(waitSeconds)
		end
		return BuildService.Build(player, payload)
	end

	-- Packets for Destroy and Rotate can be added here
end

function BuildService.Build(
	player: Player,
	payload: { ItemId: string, CellX: number, CellZ: number, Facing: string }
): (boolean, string)
	local runtimeState = PlotService.GetState(player)
	if not runtimeState then
		return false, "No plot runtime state"
	end

	local state: PlotRuntimeState = runtimeState

	local facingValue: Facing? = coerceFacing(payload.Facing)
	if not facingValue then
		return false, "Invalid facing"
	end

	local facing: Facing = facingValue

	local itemData = ItemFinder.FindItemById(payload.ItemId)
	if not itemData then
		return false, "Invalid item ID"
	end

	--#TODO: Add max placement limits per item type

	--#TODO: Add cost deduction logic on each placement

	local placementType = itemData.PlacementType or itemData.Type or "CellObject"

	local allowedFacing = itemData.Facing :: { Facing }?
	if placementType ~= "Floor" and allowedFacing and #allowedFacing > 0 then -- Changed
		if not table.find(allowedFacing, facing) then
			return false, "Invalid facing for this item"
		end
	end

	if itemData.PlacementType == "Floor" then
		local widthCells = itemData.WidthCells or itemData.Width or 1
		local depthCells = itemData.DepthCells or itemData.Depth or 1
		local floorFacing: Facing = "North"
		local success =
			state:PlaceFloor(payload.ItemId, payload.CellX, payload.CellZ, widthCells, depthCells, floorFacing)
		if not success then
			return false, "Failed to place floor"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, floorFacing)

		Packets.PlacementDelta:FireClient(player, {
			Action = "Placed", -- Added
			Item = { ItemId = payload.ItemId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = floorFacing }, -- Added
		})

		return true, "Floor placed"
	elseif itemData.PlacementType == "CellObject" then
		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if
				not state:HasFloorUnderFootprint(
					payload.CellX,
					payload.CellZ,
					itemData.WidthCells,
					itemData.DepthCells,
					facing
				)
			then
				return false, "Floor required under all cells"
			end
		end

		local success = state:PlaceRoof(
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			itemData.WidthCells,
			itemData.DepthCells,
			facing
		)

		if not success then
			return false, "Failed to place cell object"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Packets.PlacementDelta:FireClient(player, {
			Action = "Placed", -- Added
			Item = { ItemId = payload.ItemId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = facing },
		})
		return true, "Cell object placed"
	elseif itemData.PlacementType == "Wall" then
		local requiresFloorOnBothSides = itemData.RequiresFloorOnBothSides or false
		local success =
			state:PlaceWall(payload.ItemId, payload.CellX, payload.CellZ, 1, 1, facing, requiresFloorOnBothSides)
		if not success then
			return false, "Failed to place wall"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Packets.PlacementDelta:FireClient(player, {
			Action = "Placed", -- Added
			Item = { ItemId = payload.ItemId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = facing },
		})

		return true, "Wall placed"
	elseif itemData.PlacementType == "Roof" then
		-- ✅ Allow roof placement only if floor exists below
		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if
				not state:HasFloorUnderFootprint(
					payload.CellX,
					payload.CellZ,
					itemData.WidthCells,
					itemData.DepthCells,
					facing
				)
			then
				return false, "Floor required under roof"
			end
		end

		local success = state:PlaceRoof(
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			itemData.WidthCells,
			itemData.DepthCells,
			facing
		)
		if not success then
			return false, "Failed to place roof"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Packets.PlacementDelta:FireClient(player, {
			Action = "Placed",
			Item = { ItemId = payload.ItemId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = facing },
		})

		return true, "Roof placed"
	else
		return false, "Unknown placement type"
	end
end

function BuildService.Destroy() end

function BuildService.Rotate() end

return BuildService
