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
type SavedPlacedObject = PlotStateModule.SavedPlacedObject

local BuildService = {}

local Limiter = RateLimiter.new()
local PlaceBucket = Limiter:Bucket("place", { ratePerSecond = 4, burst = 6 })

local function moveDoorSegment(
	player: Player,
	state: PlotRuntimeState,
	resolvedId: string,
	spec: any,
	fromX: number,
	fromZ: number,
	fromF: Facing,
	toX: number,
	toZ: number,
	toF: Facing
): (boolean, string?)
	local requiresFloorOnBothSides = spec.RequiresFloorOnBothSides == true
	local replaceableTag = spec.ReplaceableWallTag

	local replacedId, replaceErr =
		state:ReplaceWallSegment(resolvedId, toX, toZ, toF, requiresFloorOnBothSides, replaceableTag)
	if not replacedId then
		return false, replaceErr or "Failed to attach door at destination"
	end

	local destKey = state:PlacementKeyForType(toX, toZ, toF, "Wall")
	local savedDoor = state.Save.PlacedObjects[destKey]

	local removeResult = state:RemoveWall(fromX, fromZ, fromF)
	if not removeResult then
		local revertDest = state:RemoveWall(toX, toZ, toF)
		if revertDest and revertDest.restoredId then
			local revertDoorId, revertErr =
				state:ReplaceWallSegment(resolvedId, fromX, fromZ, fromF, requiresFloorOnBothSides, replaceableTag)
			if not revertDoorId then
				warn(("[BuildService] Failed to restore door after move failure: %s"):format(tostring(revertErr)))
			end
		end
		return false, "Door not found at original location"
	end

	local removedId = removeResult.removedId
	local restoredId = removeResult.restoredId

	WorldPlacer.Despawn(player, removedId, fromX, fromZ, fromF)
	Packets.PlacementDelta:FireClient(player, {
		Action = "Removed",
		Item = {
			ItemId = removedId,
			CellX = fromX,
			CellZ = fromZ,
			Facing = fromF,
		},
	})

	if restoredId then
		WorldPlacer.Spawn(player, state.Grid, restoredId, fromX, fromZ, fromF)
		Packets.PlacementDelta:FireClient(player, {
			Action = "Placed",
			Item = {
				ItemId = restoredId,
				CellX = fromX,
				CellZ = fromZ,
				Facing = fromF,
			},
		})
	end

	WorldPlacer.Despawn(player, replacedId, toX, toZ, toF)
	Packets.PlacementDelta:FireClient(player, {
		Action = "Removed",
		Item = {
			ItemId = replacedId,
			CellX = toX,
			CellZ = toZ,
			Facing = toF,
		},
	})

	WorldPlacer.Spawn(player, state.Grid, resolvedId, toX, toZ, toF, {
		previousWallId = replacedId,
		metadata = savedDoor and savedDoor.Metadata,
	})
	Packets.PlacementDelta:FireClient(player, {
		Action = "Placed",
		Item = {
			ItemId = resolvedId,
			CellX = toX,
			CellZ = toZ,
			Facing = toF,
		},
	})

	return true, nil
end

local function coerceFacing(value: string?): Facing?
	if value == "North" or value == "East" or value == "South" or value == "West" then
		return value :: Facing
	end

	return nil
end

local function resolvePlacedItem(
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
		local parsedFacing: Facing = coerceFacing(parsedFacingValue :: string?) or "North"
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

	Packets.DestroyRequest.OnServerInvoke = function(
		player: Player,
		payload: { ItemId: string, CellX: number, CellZ: number, Facing: string }
	): (boolean, string)
		if not PlaceBucket:Allow(player, 1) then
			local waitSeconds = PlaceBucket:SecondsUntilNextToken(player)
			return false, ("Too fast. Try again in %.2fs"):format(waitSeconds)
		end
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
	if placementType ~= "Floor" and allowedFacing and #allowedFacing > 0 then
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

		local stationType = if itemData.StationType then itemData.StationType else nil
		if stationType then
			local placementKey = state:PlacementKeyForType(payload.CellX, payload.CellZ, facing, placementType)
			PlotService.AddStationForPlayer(player, stationType, placementKey, payload.ItemId)
		end
		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing)

		Packets.PlacementDelta:FireClient(player, {
			Action = "Placed", -- Added
			Item = { ItemId = payload.ItemId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = facing },
		})
		return true, "Cell object placed"
	elseif itemData.PlacementType == "Wall" then
		local requiresFloorOnBothSides = itemData.RequiresFloorOnBothSides or false
		if itemData.RequiresExistingWall then
			local replacedId, err = state:ReplaceWallSegment(
				payload.ItemId,
				payload.CellX,
				payload.CellZ,
				facing,
				requiresFloorOnBothSides,
				itemData.ReplaceableWallTag
			)
			if not replacedId then
				return false, err or "Failed to replace wall"
			end

			WorldPlacer.Despawn(player, replacedId, payload.CellX, payload.CellZ, facing)
			local key = state:PlacementKeyForType(payload.CellX, payload.CellZ, facing, "Wall")
			local savedDoor = state.Save.PlacedObjects[key]
			WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing, {
				previousWallId = replacedId,
				metadata = savedDoor and savedDoor.Metadata,
			})

			Packets.PlacementDelta:FireClient(player, {
				Action = "Removed",
				Item = { ItemId = replacedId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = facing },
			})
			Packets.PlacementDelta:FireClient(player, {
				Action = "Placed",
				Item = { ItemId = payload.ItemId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = facing },
			})

			return true, "Door installed"
		end

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

	local resolvedId, spec, savedFacingHint, savedFromIdentifier = resolvePlacedItem(state, payload.ItemId)
	if not spec or not resolvedId then
		return false, "Invalid item ID"
	end
	local placementType = spec.PlacementType or spec.Type or "CellObject"

	local payloadFacing: Facing? = coerceFacing(payload.Facing)
	local keyFacing: Facing
	if payloadFacing then
		keyFacing = payloadFacing
	elseif savedFacingHint then
		keyFacing = savedFacingHint :: Facing
	else
		keyFacing = "North"
	end
	local key = state:PlacementKeyForType(payload.CellX, payload.CellZ, keyFacing, placementType)
	local saved = state.Save.PlacedObjects[key]
	if not saved or saved.id ~= resolvedId then
		if
			savedFromIdentifier
			and savedFromIdentifier.cellX == payload.CellX
			and savedFromIdentifier.cellZ == payload.CellZ
		then
			local fallbackSaved = savedFromIdentifier
			saved = fallbackSaved
			keyFacing = PlacementKey.NormalizeFacing(fallbackSaved.facing)
			key = state:PlacementKeyForType(fallbackSaved.cellX, fallbackSaved.cellZ, keyFacing, placementType)
		end
	end
	if not saved or saved.id ~= resolvedId then
		return false, "Item not found at location"
	end

	local w = spec.WidthCells or 1
	local d = spec.DepthCells or 1
	local placementFacing: Facing = PlacementKey.NormalizeFacing(saved.facing)
	local f: Facing = placementFacing

	local removedId = resolvedId
	local restoredId: string? = nil

	-- switch by type
	if placementType == "Floor" then
		state:RemoveFloor(payload.CellX, payload.CellZ)
	elseif placementType == "Wall" then
		local result = state:RemoveWall(payload.CellX, payload.CellZ, f)
		if not result then
			return false, "Item not found at location"
		end
		removedId = result.removedId
		restoredId = result.restoredId
	elseif placementType == "Roof" then
		state:RemoveRoof(payload.CellX, payload.CellZ, w, d, f)
	else -- CellObject
		state:RemoveCellObject(payload.CellX, payload.CellZ, w, d, f)
		if spec.StationType then
			PlotService.RemoveStationForPlayer(player, spec.StationType, key)
		end
	end

	-- world + client delta
	WorldPlacer.Despawn(player, removedId, payload.CellX, payload.CellZ, f)
	Packets.PlacementDelta:FireClient(player, {
		Action = "Removed",
		Item = { ItemId = removedId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = f },
	})

	if restoredId then
		WorldPlacer.Spawn(player, state.Grid, restoredId, payload.CellX, payload.CellZ, f)
		Packets.PlacementDelta:FireClient(player, {
			Action = "Placed",
			Item = { ItemId = restoredId, CellX = payload.CellX, CellZ = payload.CellZ, Facing = f },
		})
	end

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

	local resolvedId, spec = resolvePlacedItem(state, payload.ItemId)
	if not spec or not resolvedId then
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
	local fromKey = state:PlacementKeyForType(payload.FromCellX, payload.FromCellZ, fromF, placementType)
	local toKey = state:PlacementKeyForType(payload.ToCellX, payload.ToCellZ, toF, placementType)

	if placementType == "CellObject" then
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(payload.ToCellX, payload.ToCellZ, width, depth, toF) then
				return false, "Floor required under all cells"
			end
		end

		moveSucceeded, moveError = state:MoveCellObject(
			resolvedId,
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
			state:MoveFloor(resolvedId, payload.FromCellX, payload.FromCellZ, payload.ToCellX, payload.ToCellZ)
	elseif placementType == "Wall" then
		if spec.RequiresExistingWall then
			if payload.FromCellX == payload.ToCellX and payload.FromCellZ == payload.ToCellZ and fromF == toF then
				return true, "Moved"
			end
			local doorSucceeded, doorError = moveDoorSegment(
				player,
				state,
				resolvedId,
				spec,
				payload.FromCellX,
				payload.FromCellZ,
				fromF,
				payload.ToCellX,
				payload.ToCellZ,
				toF
			)
			if not doorSucceeded then
				return false, doorError or "Door move failed"
			end
			return true, "Moved"
		end
		moveSucceeded, moveError = state:MoveWall(
			resolvedId,
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
			resolvedId,
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

	if spec.StationType and fromKey ~= toKey then
		PlotService.RemoveStationForPlayer(player, spec.StationType, fromKey)
		PlotService.AddStationForPlayer(player, spec.StationType, toKey, resolvedId)
	end

	WorldPlacer.Despawn(player, resolvedId, payload.FromCellX, payload.FromCellZ, removedFacing)
	WorldPlacer.Spawn(player, state.Grid, resolvedId, payload.ToCellX, payload.ToCellZ, placedFacing)

	Packets.PlacementDelta:FireClient(player, {
		Action = "Removed",
		Item = {
			ItemId = resolvedId,
			CellX = payload.FromCellX,
			CellZ = payload.FromCellZ,
			Facing = removedFacing,
		},
	})
	Packets.PlacementDelta:FireClient(player, {
		Action = "Placed",
		Item = {
			ItemId = resolvedId,
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

	local resolvedId, spec = resolvePlacedItem(state, payload.ItemId)
	if not spec or not resolvedId then
		return false, "Invalid item ID"
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	if placementType == "Wall" and spec.RequiresExistingWall then
		return false, "Doors cannot be rotated"
	end
	if placementType == "Floor" then
		return false, "Floors cannot be rotated"
	end

	local saved = state.Save.PlacedObjects[payload.FromKey]
	if not saved or saved.id ~= resolvedId then
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
		rotated, rotateErr = state:RotateCellObject(resolvedId, payload.FromKey, targetFacing)
	elseif placementType == "Wall" then
		rotated, rotateErr = state:RotateWall(resolvedId, payload.FromKey, targetFacing)
	elseif placementType == "Roof" then
		local width = spec.WidthCells or spec.Width or 1
		local depth = spec.DepthCells or spec.Depth or 1
		if spec.Rules and spec.Rules.RequiresFloorUnderAllCells then
			if not state:HasFloorUnderFootprint(cellX, cellZ, width, depth, targetFacing) then
				return false, "Floor required under roof"
			end
		end
		rotated, rotateErr = state:RotateRoof(resolvedId, payload.FromKey, targetFacing)
	else
		return false, ("Cannot rotate items of type '%s'"):format(tostring(placementType))
	end

	if not rotated then
		return false, rotateErr or "Rotation failed"
	end

	if spec.StationType then
		local fromKeyNormalized = state:PlacementKeyForType(cellX, cellZ, currentFacing, placementType)
		local toKey = state:PlacementKeyForType(cellX, cellZ, targetFacing, placementType)
		if fromKeyNormalized ~= toKey then
			PlotService.RemoveStationForPlayer(player, spec.StationType, fromKeyNormalized)
			PlotService.AddStationForPlayer(player, spec.StationType, toKey, resolvedId)
		end
	end

	WorldPlacer.Despawn(player, resolvedId, cellX, cellZ, currentFacing)
	WorldPlacer.Spawn(player, state.Grid, resolvedId, cellX, cellZ, targetFacing)

	Packets.PlacementDelta:FireClient(player, {
		Action = "Removed",
		Item = {
			ItemId = resolvedId,
			CellX = cellX,
			CellZ = cellZ,
			Facing = currentFacing,
		},
	})
	Packets.PlacementDelta:FireClient(player, {
		Action = "Placed",
		Item = {
			ItemId = resolvedId,
			CellX = cellX,
			CellZ = cellZ,
			Facing = targetFacing,
		},
	})

	return true, "Rotated"
end

return BuildService
