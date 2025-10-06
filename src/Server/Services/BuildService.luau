--!strict
-- ServerScriptService/Server/Services/BuildService.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local PlotStateModule = require(ServerScriptService.Server.Classes.PlotState)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local RateLimiter = require(ReplicatedStorage.Shared.Utilities.RateLimiter)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
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

	Packets.DestroyRequest.OnServerInvoke = function( -- ADDED
		player: Player,
		payload: { ItemId: string, CellX: number, CellZ: number, Facing: string }
	): (boolean, string)
		return BuildService.Destroy(player, payload)
	end
	-- MoveRequest packet handler can be added here
	Packets.MoveRequest.OnServerInvoke = function(
		player: Player,
		payload: {
			ItemId: string,
			FromCellX: number,
			FromCellZ: number,
			FromFacing: string,
			ToCellX: number,
			ToCellZ: number,
			ToFacing: string,
		}
	): (boolean, string)
		if not PlaceBucket:Allow(player, 1) then
			local waitSeconds = PlaceBucket:SecondsUntilNextToken(player)
			return false, ("Too fast. Try again in %.2fs"):format(waitSeconds)
		end
		return BuildService.Move(player, payload)
	end

	Packets.RotateRequest.OnServerInvoke = function(
		player: Player,
		payload: { ItemId: string, FromKey: string, ToFacing: string }
	): (boolean, string)
		if not PlaceBucket:Allow(player, 1) then
			local waitSeconds = PlaceBucket:SecondsUntilNextToken(player)
			return false, ("Too fast. Try again in %.2fs"):format(waitSeconds)
		end
		return BuildService.Rotate(player, payload)
	end
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
		local widthCells = itemData.WidthCells or itemData.Width or 1
		local depthCells = itemData.DepthCells or itemData.Depth or 1

		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.CellX, payload.CellZ, widthCells, depthCells, facing) then
				return false, "Floor required under all cells"
			end
		end

		local success = state:Place(payload.ItemId, payload.CellX, payload.CellZ, widthCells, depthCells, facing)

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

function BuildService.Destroy(
	player: Player,
	payload: { ItemId: string, CellX: number, CellZ: number, Facing: string }
): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local spec = ItemFinder.FindItemById(payload.ItemId)
	if not spec then
		return false, "Invalid item ID"
	end
	local placementType = spec.PlacementType or spec.Type or "CellObject"

	local payloadFacing: Facing? = coerceFacing(payload.Facing)
	local keyFacing: Facing = payloadFacing or "North"
	local key = state:PlacementKeyForType(payload.CellX, payload.CellZ, keyFacing, placementType)
	local saved = state.Save.PlacedObjects[key]
	if not saved or saved.id ~= payload.ItemId then
		return false, "Item not found at location"
	end

	local w = spec.WidthCells or 1
	local d = spec.DepthCells or 1
	local savedFacing: Facing = PlacementKey.NormalizeFacing(saved.facing)
	local f: Facing = savedFacing

	-- switch by type
	if placementType == "Floor" then
		state:RemoveFloor(payload.CellX, payload.CellZ)
	elseif placementType == "Wall" then
		state:RemoveWall(payload.CellX, payload.CellZ, f)
	elseif placementType == "Roof" then
		state:RemoveRoof(payload.CellX, payload.CellZ, w, d, f)
	else -- CellObject
		state:RemoveCellObject(payload.CellX, payload.CellZ, w, d, f)
	end

	-- world + client delta
	WorldPlacer.Despawn(player, payload.ItemId, payload.CellX, payload.CellZ, f)
	Packets.PlacementDelta:FireClient(player, {
		Action = "Removed",
		Item = { ItemId = payload.ItemId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = f },
	})

	return true, "Removed"
end

function BuildService.Move(
	player: Player,
	payload: {
		ItemId: string,
		FromCellX: number,
		FromCellZ: number,
		FromFacing: string,
		ToCellX: number,
		ToCellZ: number,
		ToFacing: string,
	}
): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local spec = ItemFinder.FindItemById(payload.ItemId)
	if not spec then
		return false, "Invalid item ID"
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	local fromF: Facing = coerceFacing(payload.FromFacing) or "North"
	local toF: Facing = coerceFacing(payload.ToFacing) or fromF

	local allowedFacing = spec.Facing :: { Facing }?
	if placementType ~= "Floor" and allowedFacing and #allowedFacing > 0 then
		if not table.find(allowedFacing, toF) then
			return false, "Invalid facing for this item"
		end
	end

	local width = spec.WidthCells or spec.Width or 1
	local depth = spec.DepthCells or spec.Depth or 1

	local moveSucceeded: boolean
	local moveError: string?
	local removedFacing: Facing = fromF
	local placedFacing: Facing = toF

	if placementType == "CellObject" then
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.ToCellX, payload.ToCellZ, width, depth, toF) then
				return false, "Floor required under all cells"
			end
		end

		moveSucceeded, moveError = state:MoveCellObject(
			payload.ItemId,
			payload.FromCellX,
			payload.FromCellZ,
			fromF,
			payload.ToCellX,
			payload.ToCellZ,
			toF
		)
	elseif placementType == "Floor" then
		removedFacing = "North"
		placedFacing = "North"
		moveSucceeded, moveError =
			state:MoveFloor(payload.ItemId, payload.FromCellX, payload.FromCellZ, payload.ToCellX, payload.ToCellZ)
	elseif placementType == "Wall" then
		moveSucceeded, moveError = state:MoveWall(
			payload.ItemId,
			payload.FromCellX,
			payload.FromCellZ,
			fromF,
			payload.ToCellX,
			payload.ToCellZ,
			toF
		)
	elseif placementType == "Roof" then
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.ToCellX, payload.ToCellZ, width, depth, toF) then
				return false, "Floor required under roof"
			end
		end

		moveSucceeded, moveError = state:MoveRoof(
			payload.ItemId,
			payload.FromCellX,
			payload.FromCellZ,
			fromF,
			payload.ToCellX,
			payload.ToCellZ,
			toF
		)
	else
		return false, ("Cannot move items of type '%s'"):format(tostring(placementType))
	end

	if not moveSucceeded then
		return false, moveError or "Move failed"
	end

	WorldPlacer.Despawn(player, payload.ItemId, payload.FromCellX, payload.FromCellZ, removedFacing)
	WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.ToCellX, payload.ToCellZ, placedFacing)

	Packets.PlacementDelta:FireClient(player, {
		Action = "Removed",
		Item = {
			ItemId = payload.ItemId,
			CellX = payload.FromCellX,
			CellZ = payload.FromCellZ,
			Facing = removedFacing,
		},
	})
	Packets.PlacementDelta:FireClient(player, {
		Action = "Placed",
		Item = {
			ItemId = payload.ItemId,
			CellX = payload.ToCellX,
			CellZ = payload.ToCellZ,
			Facing = placedFacing,
		},
	})

	return true, "Moved"
end

function BuildService.Rotate(
	player: Player,
	payload: { ItemId: string, FromKey: string, ToFacing: string }
): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	if type(payload.FromKey) ~= "string" or payload.FromKey == "" then
		return false, "Invalid placement key"
	end

	local toFacingValue: Facing? = coerceFacing(payload.ToFacing)
	if not toFacingValue then
		return false, "Invalid facing"
	end
	local targetFacing: Facing = PlacementKey.NormalizeFacing(toFacingValue)

	local spec = ItemFinder.FindItemById(payload.ItemId)
	if not spec then
		return false, "Invalid item ID"
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	if placementType == "Floor" then
		return false, "Floors cannot be rotated"
	end

	local saved = state.Save.PlacedObjects[payload.FromKey]
	if not saved or saved.id ~= payload.ItemId then
		return false, "Item not found at key"
	end

	local parseOk, parsedCellX, parsedCellZ, parsedFacing, keyPlacementType =
		pcall(PlacementKey.ParseWithType, payload.FromKey)
	if not parseOk then
		local parseErr = parsedCellX
		return false, ("Invalid placement key: %s"):format(tostring(parseErr))
	end

	local cellX = parsedCellX :: number
	local cellZ = parsedCellZ :: number
	local currentFacing: Facing = PlacementKey.NormalizeFacing(parsedFacing :: Facing)

	if keyPlacementType and keyPlacementType ~= placementType then
		return false, "Placement type mismatch"
	end

	if currentFacing == targetFacing then
		return true, "Already facing that direction"
	end

	local allowedFacing = spec.Facing :: { Facing }?
	if allowedFacing and #allowedFacing > 0 and not table.find(allowedFacing, targetFacing) then
		return false, "Invalid facing for this item"
	end

	local rotated: boolean
	local rotateErr: string?
	if placementType == "CellObject" then
		local width = spec.WidthCells or spec.Width or 1
		local depth = spec.DepthCells or spec.Depth or 1
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(cellX, cellZ, width, depth, targetFacing) then
				return false, "Floor required under all cells"
			end
		end
		rotated, rotateErr = state:RotateCellObject(payload.ItemId, payload.FromKey, targetFacing)
	elseif placementType == "Wall" then
		rotated, rotateErr = state:RotateWall(payload.ItemId, payload.FromKey, targetFacing)
	elseif placementType == "Roof" then
		local width = spec.WidthCells or spec.Width or 1
		local depth = spec.DepthCells or spec.Depth or 1
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(cellX, cellZ, width, depth, targetFacing) then
				return false, "Floor required under roof"
			end
		end
		rotated, rotateErr = state:RotateRoof(payload.ItemId, payload.FromKey, targetFacing)
	else
		return false, ("Cannot rotate items of type '%s'"):format(tostring(placementType))
	end

	if not rotated then
		return false, rotateErr or "Rotation failed"
	end

	WorldPlacer.Despawn(player, payload.ItemId, cellX, cellZ, currentFacing)
	WorldPlacer.Spawn(player, state.Grid, payload.ItemId, cellX, cellZ, targetFacing)

	Packets.PlacementDelta:FireClient(player, {
		Action = "Removed",
		Item = {
			ItemId = payload.ItemId,
			CellX = cellX,
			CellZ = cellZ,
			Facing = currentFacing,
		},
	})
	Packets.PlacementDelta:FireClient(player, {
		Action = "Placed",
		Item = {
			ItemId = payload.ItemId,
			CellX = cellX,
			CellZ = cellZ,
			Facing = targetFacing,
		},
	})

	return true, "Rotated"
end

return BuildService
