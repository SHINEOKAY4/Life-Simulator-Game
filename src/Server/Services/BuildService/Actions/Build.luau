--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotService = require(ServerScriptService.Server.Services.PlotService)
local WorldPlacer = require(ServerScriptService.Server.Utilities.WorldPlacer)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)
local Helpers = require(ServerScriptService.Server.Services.BuildService.Helpers)
local PlotStateModule = require(ServerScriptService.Server.Classes.PlotState)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlacementBehavior = require(ReplicatedStorage.Shared.Utilities.PlacementBehavior)
local SubSlotResolver = require(ReplicatedStorage.Shared.Utilities.SubSlotResolver)

type Facing = PlotStateModule.Facing

type Payload = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: string,
	Level: number?,
	SurfaceId: string?,
	WallMountEnabled: boolean?,
	WallMountCellX: number?,
	WallMountCellZ: number?,
	WallMountFacing: string?,
	WallMountHeightOffset: number?,
	WallMountPosX: number?,
	WallMountPosY: number?,
	WallMountPosZ: number?,
	WallMountNormalX: number?,
	WallMountNormalY: number?,
	WallMountNormalZ: number?,
	CeilingMountEnabled: boolean?,
	CeilingMountCellX: number?,
	CeilingMountCellZ: number?,
	CeilingMountLevel: number?,
	CeilingMountDropStuds: number?,
	CeilingMountRotationY: number?,
	CeilingMountPosX: number?,
	CeilingMountPosY: number?,
	CeilingMountPosZ: number?,
	CeilingMountNormalX: number?,
	CeilingMountNormalY: number?,
	CeilingMountNormalZ: number?,
	WindowEnabled: boolean?,
	WindowHeightOffset: number?,
}

-- Derives authoritative world pose metadata for wall-mounted items using the plot grid.
local function computeWallMountMetadata(
	grid: any,
	itemSpec: { [string]: any }?,
	cellX: number,
	cellZ: number,
	facing: Facing,
	heightOffset: number,
	orientationHint: Vector3?
): { [string]: any }
	local mountConfig = if itemSpec and typeof(itemSpec.WallMountConfig) == "table"
		then itemSpec.WallMountConfig
		else nil
	local offsetFromWall = 0.1
	if mountConfig and typeof(mountConfig.OffsetFromWall) == "number" then
		offsetFromWall = mountConfig.OffsetFromWall
	end
	if offsetFromWall < 0 then
		offsetFromWall = 0
	end
	local wallCFrame = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing, heightOffset)
	local canonicalNormal = wallCFrame.LookVector
	if canonicalNormal.Magnitude < 1e-3 then
		canonicalNormal = Vector3.new(0, 0, -1)
	else
		canonicalNormal = canonicalNormal.Unit
	end
	local resolvedNormal = canonicalNormal
	if orientationHint and orientationHint.Magnitude >= 1e-3 then
		local hintUnit = orientationHint.Unit
		local alignment = canonicalNormal:Dot(hintUnit)
		if alignment < -0.1 then
			resolvedNormal = -canonicalNormal
		elseif alignment > 0.1 then
			resolvedNormal = canonicalNormal
		end
	end

	local worldPosition = wallCFrame.Position + resolvedNormal * offsetFromWall

	return {
		WallMountData = {
			ReferenceCellX = cellX,
			ReferenceCellZ = cellZ,
			AttachedFacing = facing,
			HeightOffset = heightOffset,
			OffsetFromWall = offsetFromWall,
			WorldPosition = {
				X = worldPosition.X,
				Y = worldPosition.Y,
				Z = worldPosition.Z,
			},
			WallNormal = {
				X = resolvedNormal.X,
				Y = resolvedNormal.Y,
				Z = resolvedNormal.Z,
			},
		},
	}
end

local function computeCeilingMountMetadata(
	grid: any,
	cellX: number,
	cellZ: number,
	facing: Facing,
	level: number,
	dropStuds: number,
	rotationY: number,
	referencedWorldPosition: Vector3?,
	requestedNormal: Vector3?
): { [string]: any }
	local resolvedLevel = PlotStateModule.ResolveLevel(level)
	local floorHeight = BuildConstants.FloorHeightStuds or 12
	local anchorLevel = resolvedLevel + 1
	local baseCFrame = grid:FootprintCenterCFrame(cellX, cellZ, 1, 1, "North")
	local anchorCFrame = baseCFrame * CFrame.new(0, anchorLevel * floorHeight, 0)
	local anchorPosition = anchorCFrame.Position
	local plotUp = grid and grid.Plot and grid.Plot.CFrame.UpVector or Vector3.yAxis
	local fallbackNormal = -plotUp.Unit
	if fallbackNormal.Magnitude < 1e-3 then
		fallbackNormal = Vector3.new(0, -1, 0)
	else
		fallbackNormal = fallbackNormal.Unit
	end

	local resolvedNormal = fallbackNormal
	if requestedNormal and requestedNormal.Magnitude >= 1e-3 then
		local unitCandidate = requestedNormal.Unit
		local alignment = unitCandidate:Dot(fallbackNormal)
		if alignment >= 0.1 then
			resolvedNormal = unitCandidate
		elseif (-unitCandidate):Dot(fallbackNormal) >= 0.1 then
			resolvedNormal = (-unitCandidate).Unit
		end
	end

	local supportHeight = anchorPosition.Y
	if referencedWorldPosition then
		local supportEstimate = referencedWorldPosition - resolvedNormal * dropStuds
		local tolerance = math.max(floorHeight * 0.5, 0.5)
		if math.abs(supportEstimate.Y - anchorPosition.Y) <= tolerance then
			supportHeight = supportEstimate.Y
		end
	end
	local supportPosition = Vector3.new(anchorPosition.X, supportHeight, anchorPosition.Z)
	local worldPosition = supportPosition + resolvedNormal * dropStuds
	return {
		CeilingMountData = {
			ReferenceCellX = cellX,
			ReferenceCellZ = cellZ,
			Facing = facing,
			RoomLevel = resolvedLevel,
			AnchorLevel = anchorLevel,
			DropStuds = dropStuds,
			RotationY = rotationY,
			WorldPosition = {
				X = worldPosition.X,
				Y = worldPosition.Y,
				Z = worldPosition.Z,
			},
			CeilingNormal = {
				X = resolvedNormal.X,
				Y = resolvedNormal.Y,
				Z = resolvedNormal.Z,
			},
		},
	}
end

local function isDiagonalFacing(facing: Facing): boolean
	return facing == "NorthEast" or facing == "NorthWest" or facing == "SouthEast" or facing == "SouthWest"
end

local function resolveWallDimensionsFromSpec(spec: { [string]: any }?): (number, number, number, number, number)
	local defaultWidth = 4
	local defaultHeight = 12
	local defaultThickness = 0.5
	local defaultDiagonalMultiplier = math.sqrt(2)
	local defaultMinFrame = 0.2

	if typeof(spec) ~= "table" then
		return defaultWidth, defaultHeight, defaultThickness, defaultDiagonalMultiplier, defaultMinFrame
	end

	local dims = spec.WallDimensions
	if typeof(dims) ~= "table" then
		return defaultWidth, defaultHeight, defaultThickness, defaultDiagonalMultiplier, defaultMinFrame
	end

	local width = typeof(dims.NominalWidth) == "number" and dims.NominalWidth or defaultWidth
	local height = typeof(dims.NominalHeight) == "number" and dims.NominalHeight or defaultHeight
	local thickness = typeof(dims.NominalThickness) == "number" and dims.NominalThickness or defaultThickness
	local diagonalMultiplier = typeof(dims.DiagonalLengthMultiplier) == "number" and dims.DiagonalLengthMultiplier
		or defaultDiagonalMultiplier
	local minFrame = typeof(dims.MinFrameThickness) == "number" and dims.MinFrameThickness or defaultMinFrame

	return width, height, thickness, diagonalMultiplier, minFrame
end

local function collectFootprintCells(
	grid: any,
	cellX: number,
	cellZ: number,
	widthCells: number,
	depthCells: number,
	facing: Facing
): { number }?
	local ok, cells = pcall(grid.FootprintCells, grid, cellX, cellZ, widthCells, depthCells, facing)
	if not ok then
		return nil
	end
	return cells
end

local function buildCellSet(indices: { number }?): { [number]: boolean }
	local set: { [number]: boolean } = {}
	if not indices then
		return set
	end
	for _, index in ipairs(indices) do
		set[index] = true
	end
	return set
end

local function hasCellOverlap(candidate: { [number]: boolean }, other: { number }?): boolean
	if not other then
		return false
	end
	for _, index in ipairs(other) do
		if candidate[index] then
			return true
		end
	end
	return false
end

local function validateSubSlotAvailability(
	state: PlotStateModule.PlotState,
	itemSpec: { [string]: any }?,
	cellX: number,
	cellZ: number,
	facing: Facing,
	level: number,
	widthCells: number,
	depthCells: number,
	requestedSlotId: string?
): (boolean, string?)
	if not SubSlotResolver.UsesSubSlots(itemSpec) then
		return true, nil
	end
	local grid = state.Grid
	if not grid then
		return true, nil
	end
	local footprintCells = collectFootprintCells(grid, cellX, cellZ, widthCells, depthCells, facing)
	if not footprintCells then
		return true, nil
	end
	local footprintSet = buildCellSet(footprintCells)
	local normalizedSlotId = SubSlotResolver.NormalizeSlotId(itemSpec, requestedSlotId)
	for _, existing in pairs(state.Save.PlacedObjects) do
		if not existing then
			continue
		end
		local existingLevel = if typeof(existing.yLevel) == "number" then existing.yLevel else state.DefaultLevel
		if existingLevel ~= level then
			continue
		end
		local existingSpec = ItemFinder.FindItemById(existing.id)
		if not existingSpec then
			continue
		end
		local placementType = existingSpec.PlacementType or existingSpec.Type or "CellObject"
		if placementType ~= "CellObject" then
			continue
		end
		local existingCells = collectFootprintCells(
			grid,
			existing.cellX,
			existing.cellZ,
			existing.WidthCells or existingSpec.WidthCells or existingSpec.Width or 1,
			existing.DepthCells or existingSpec.DepthCells or existingSpec.Depth or 1,
			PlacementKey.NormalizeFacing(existing.facing :: Facing)
		)
		if not hasCellOverlap(footprintSet, existingCells) then
			continue
		end
		if not SubSlotResolver.UsesSubSlots(existingSpec) then
			if PlacementBehavior.allowsStacking(existingSpec) then
				continue
			end
			return false, "Cell already has an object placed"
		end
		if not SubSlotResolver.CanItemsShare(itemSpec, existingSpec) then
			return false, "Cell reserved for another decor type"
		end
		local occupiedSlot = SubSlotResolver.ResolveSavedSlotId(existing.Metadata, existingSpec)
		if occupiedSlot and normalizedSlotId and occupiedSlot == normalizedSlotId then
			return false, "Sub-slot already occupied"
		end
	end
	return true, nil
end

local function buildWallMetadata(spec: { [string]: any }?, facing: Facing): { [string]: any }
	local width, height, thickness, diagonalMultiplier, minFrame = resolveWallDimensionsFromSpec(spec)
	local effectiveWidth = width
	if isDiagonalFacing(facing) then
		effectiveWidth *= diagonalMultiplier
	end

	return {
		WallSizeX = width,
		WallSizeY = height,
		WallSizeZ = thickness,
		EffectiveWallWidth = effectiveWidth,
		DiagonalLengthMultiplier = diagonalMultiplier,
		MinFrameThickness = minFrame,
	}
end

local function snapshotWallMetadata(metadata: { [string]: any }?): { [string]: any }?
	if typeof(metadata) ~= "table" then
		return nil
	end

	local snapshot = table.clone(metadata)
	snapshot.PreviousId = nil
	snapshot.ReplaceableTag = nil
	snapshot.RequiresFloorOnBothSides = nil
	snapshot.WindowCutoutData = nil
	snapshot.OriginalWallMetadata = nil

	return snapshot
end

local function Build(player: Player, payload: Payload): (boolean, string)
	local state = PlotService.GetState(player)
	if not state then
		return false, "No plot runtime state"
	end

	local facingValue: Facing? = Helpers.coerceFacing(payload.Facing)
	if not facingValue then
		return false, "Invalid facing"
	end

	local facing: Facing = facingValue
	local level = state:NormalizeLevel(payload.Level)

	local itemData = ItemFinder.FindItemById(payload.ItemId)
	if not itemData then
		return false, "Invalid item ID"
	end

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
		local totalCells = widthCells * depthCells
		local floorSurfaceId = Helpers.resolveSurfaceId(itemData, payload.SurfaceId)

		local canAfford, failureReason, totalCost, currencyState =
			Helpers.ensurePlacementFunds(player, itemData, totalCells)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end
		local metadata = {
			WidthCells = widthCells,
			DepthCells = depthCells,
		}
		if floorSurfaceId then
			metadata.SurfaceId = floorSurfaceId
		end
		local footprintSize = {
			WidthCells = widthCells,
			DepthCells = depthCells,
		}
		local success = state:PlaceFloor(
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			widthCells,
			depthCells,
			floorFacing,
			level,
			metadata
		)
		if not success then
			return false, "Failed to place floor"
		end
		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, floorFacing, level, {
			metadata = metadata,
			sizeCells = footprintSize,
		})

		Helpers.sendPlacementDelta(
			player,
			"Placed",
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			floorFacing,
			metadata,
			level
		)

		Helpers.deductPlacementCost(player, currencyState, totalCost)

		return true, "Floor placed"
	elseif placementType == "WallMounted" then
		local wallEnabled = payload.WallMountEnabled == true
		if not wallEnabled then
			return false, "Wall mount target missing"
		end

		local wallCellXValue = payload.WallMountCellX
		local wallCellZValue = payload.WallMountCellZ
		if typeof(wallCellXValue) ~= "number" or typeof(wallCellZValue) ~= "number" then
			return false, "Invalid wall coordinates"
		end
		local wallCellX = math.floor(wallCellXValue + 0.5)
		local wallCellZ = math.floor(wallCellZValue + 0.5)

		local wallFacingValue = Helpers.coerceFacing(payload.WallMountFacing)
		if not wallFacingValue then
			return false, "Invalid wall facing"
		end
		local wallFacing: Facing = wallFacingValue :: any

		local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, itemData, 1)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end

		local mountConfig = itemData.WallMountConfig
		if typeof(mountConfig) ~= "table" then
			return false, "Wall mount configuration missing"
		end

		local grid = state.Grid
		if grid == nil then
			return false, "Plot grid unavailable"
		end

		local minHeight = typeof(mountConfig.MinHeight) == "number" and mountConfig.MinHeight or 0
		local maxHeightValue = typeof(mountConfig.MaxHeight) == "number" and mountConfig.MaxHeight or (minHeight + 10)
		if maxHeightValue < minHeight then
			maxHeightValue = minHeight
		end
		local requestedHeight = if typeof(payload.WallMountHeightOffset) == "number"
			then payload.WallMountHeightOffset
			else minHeight
		local heightOffset = math.clamp(requestedHeight, minHeight, maxHeightValue)

		local successCheck, placementFailure = state:CanPlaceWallMounted(wallCellX, wallCellZ, wallFacing, level)
		if not successCheck then
			return false, placementFailure or "Cannot attach to wall"
		end

		local orientationHintVector: Vector3? = nil
		local normalX = payload.WallMountNormalX
		local normalY = payload.WallMountNormalY
		local normalZ = payload.WallMountNormalZ
		if typeof(normalX) == "number" and typeof(normalY) == "number" and typeof(normalZ) == "number" then
			local candidate = Vector3.new(normalX, normalY, normalZ)
			if candidate.Magnitude >= 1e-3 then
				orientationHintVector = candidate
			end
		end

		local metadata = computeWallMountMetadata(
			grid,
			itemData,
			wallCellX,
			wallCellZ,
			wallFacing,
			heightOffset,
			orientationHintVector
		)
		local placed, placeError =
			state:PlaceWallMounted(payload.ItemId, wallCellX, wallCellZ, wallFacing, metadata, level)
		if not placed then
			return false, placeError or "Failed to attach to wall"
		end

		local stationType = if itemData.StationType then itemData.StationType else nil
		if stationType then
			local placementKey = state:PlacementKeyForType(wallCellX, wallCellZ, wallFacing, placementType, level)
			PlotService.AddStationForPlayer(player, stationType, placementKey, payload.ItemId)
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, wallCellX, wallCellZ, wallFacing, level, {
			metadata = metadata,
		})

		Helpers.sendPlacementDelta(player, "Placed", payload.ItemId, wallCellX, wallCellZ, wallFacing, metadata, level)
		Helpers.deductPlacementCost(player, currencyState, totalCost)
		return true, "Wall attachment placed"
	elseif placementType == "Ceiling" then
		local ceilingEnabled = payload.CeilingMountEnabled == true
		if not ceilingEnabled then
			return false, "Ceiling mount target missing"
		end

		local ceilingCellXValue = payload.CeilingMountCellX
		local ceilingCellZValue = payload.CeilingMountCellZ
		if typeof(ceilingCellXValue) ~= "number" or typeof(ceilingCellZValue) ~= "number" then
			return false, "Invalid ceiling coordinates"
		end
		local ceilingCellX = math.floor(ceilingCellXValue + 0.5)
		local ceilingCellZ = math.floor(ceilingCellZValue + 0.5)

		local ceilingLevelValue = payload.CeilingMountLevel
		local ceilingLevel = if typeof(ceilingLevelValue) == "number"
			then state:NormalizeLevel(ceilingLevelValue)
			else level

		local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, itemData, 1)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end

		local canPlaceCeiling, ceilingFailure =
			state:CanPlaceCeilingMounted(ceilingCellX, ceilingCellZ, facing, ceilingLevel)
		if not canPlaceCeiling then
			return false, ceilingFailure or "Cannot attach to ceiling"
		end

		local mountConfig = if typeof(itemData.CeilingMountConfig) == "table" then itemData.CeilingMountConfig else {}
		local minDrop = typeof(mountConfig.MinDropStuds) == "number" and math.max(mountConfig.MinDropStuds, 0) or 0
		local maxDrop = typeof(mountConfig.MaxDropStuds) == "number"
				and math.max(mountConfig.MaxDropStuds, minDrop + 0.1)
			or (minDrop + 6)
		local defaultDrop = typeof(mountConfig.DefaultDropStuds) == "number" and mountConfig.DefaultDropStuds or minDrop
		local requestedDrop = if typeof(payload.CeilingMountDropStuds) == "number"
			then payload.CeilingMountDropStuds
			else defaultDrop
		local dropStuds = math.clamp(requestedDrop, minDrop, maxDrop)

		local requestedRotation = if typeof(payload.CeilingMountRotationY) == "number"
			then payload.CeilingMountRotationY
			else 0
		local rotationY = requestedRotation

		local grid = state.Grid
		if not grid then
			return false, "Plot grid unavailable"
		end

		local requestedWorldPosition: Vector3? = nil
		local posX = payload.CeilingMountPosX
		local posY = payload.CeilingMountPosY
		local posZ = payload.CeilingMountPosZ
		if typeof(posX) == "number" and typeof(posY) == "number" and typeof(posZ) == "number" then
			requestedWorldPosition = Vector3.new(posX, posY, posZ)
		end
		local requestedNormal: Vector3? = nil
		local ceilNormalX = payload.CeilingMountNormalX
		local ceilNormalY = payload.CeilingMountNormalY
		local ceilNormalZ = payload.CeilingMountNormalZ
		if typeof(ceilNormalX) == "number" and typeof(ceilNormalY) == "number" and typeof(ceilNormalZ) == "number" then
			local candidateNormal = Vector3.new(ceilNormalX, ceilNormalY, ceilNormalZ)
			if candidateNormal.Magnitude >= 1e-3 then
				requestedNormal = candidateNormal
			end
		end

		local metadata = computeCeilingMountMetadata(
			grid,
			ceilingCellX,
			ceilingCellZ,
			facing,
			ceilingLevel,
			dropStuds,
			rotationY,
			requestedWorldPosition,
			requestedNormal
		)

		local placedCeiling, ceilingError =
			state:PlaceCeilingMounted(payload.ItemId, ceilingCellX, ceilingCellZ, facing, metadata, ceilingLevel)
		if not placedCeiling then
			return false, ceilingError or "Failed to attach to ceiling"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, ceilingCellX, ceilingCellZ, facing, ceilingLevel, {
			metadata = metadata,
		})

		Helpers.sendPlacementDelta(
			player,
			"Placed",
			payload.ItemId,
			ceilingCellX,
			ceilingCellZ,
			facing,
			metadata,
			ceilingLevel
		)
		Helpers.deductPlacementCost(player, currencyState, totalCost)
		return true, "Ceiling decor placed"
	elseif itemData.PlacementType == "CellObject" then
		local widthCells = itemData.WidthCells or itemData.Width or 1
		local depthCells = itemData.DepthCells or itemData.Depth or 1
		local placementKeyType = Helpers.getPlacementKeyLabel(itemData)
		local allowStacking = Helpers.allowsStacking(itemData)
		local subSlotMetadata: { [string]: any }? = nil
		local requestedSubSlotId = if typeof(payload.SubSlotId) == "string"
			then payload.SubSlotId
			elseif payload.SubSlotId ~= nil then tostring(payload.SubSlotId)
			else ""
		local normalizedSubSlotId = SubSlotResolver.NormalizeSlotId(itemData, requestedSubSlotId)
		if SubSlotResolver.UsesSubSlots(itemData) then
			local slotOk, slotReason = validateSubSlotAvailability(
				state,
				itemData,
				payload.CellX,
				payload.CellZ,
				facing,
				level,
				widthCells,
				depthCells,
				normalizedSubSlotId
			)
			if not slotOk then
				return false, slotReason or "Sub-slot unavailable"
			end
			subSlotMetadata = {
				SubSlotId = normalizedSubSlotId,
			}
			placementKeyType = Helpers.getPlacementKeyLabelForSubSlot(itemData, normalizedSubSlotId)
		end

		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if
				not state:HasFloorUnderFootprint(payload.CellX, payload.CellZ, widthCells, depthCells, facing, level)
			then
				return false, "Floor required under all cells"
			end
		end

		local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, itemData, 1)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end

		local success, placementKey =
			state:Place(payload.ItemId, payload.CellX, payload.CellZ, widthCells, depthCells, facing, level, {
				PlacementType = placementKeyType,
				IgnoreOccupancy = allowStacking,
				Metadata = subSlotMetadata,
			})

		if not success or not placementKey then
			return false, "Failed to place cell object"
		end

		local entry = state.Save.PlacedObjects[placementKey]
		if entry then
			if subSlotMetadata then
				entry.Metadata = subSlotMetadata
			else
				entry.Metadata = nil
			end
		end

		local stationType = if itemData.StationType then itemData.StationType else nil
		if stationType then
			PlotService.AddStationForPlayer(player, stationType, placementKey, payload.ItemId)
		end
		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing, level, {
			metadata = subSlotMetadata,
		})

		Helpers.sendPlacementDelta(
			player,
			"Placed",
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			facing,
			subSlotMetadata,
			level,
			placementKey
		)

		Helpers.deductPlacementCost(player, currencyState, totalCost)
		return true, "Cell object placed"
	elseif itemData.PlacementType == "Wall" then
		local requiresFloorOnBothSides = itemData.RequiresFloorOnBothSides or false
		local incomingSurfaceId = Helpers.resolveSurfaceId(itemData, payload.SurfaceId)
		local canAfford, failureReason, totalCost, currencyState = Helpers.ensurePlacementFunds(player, itemData, 1)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end
		if itemData.RequiresExistingWall then
			local isWindowVariant = itemData.WallVariant == "Window"
			if isWindowVariant and payload.WindowEnabled ~= true then
				return false, "Window target missing"
			end

			local windowConfig = if isWindowVariant then itemData.WindowCutoutConfig else nil
			if isWindowVariant and typeof(windowConfig) ~= "table" then
				return false, "Window configuration missing"
			end

			if isWindowVariant then
				local existingKey = state:PlacementKeyForType(payload.CellX, payload.CellZ, facing, "Wall", level)
				local existingEntry = state.Save.PlacedObjects[existingKey]
				if existingEntry then
					local metadata = existingEntry.Metadata
					if typeof(metadata) == "table" and typeof(metadata.WindowCutoutData) == "table" then
						return false, "Wall already has a window installed"
					end
				end
			end

			local replacedId, err = state:ReplaceWallSegment(
				payload.ItemId,
				payload.CellX,
				payload.CellZ,
				facing,
				requiresFloorOnBothSides,
				itemData.ReplaceableWallTag,
				level
			)
			if not replacedId then
				return false, err or "Failed to replace wall"
			end

			local key = state:PlacementKeyForType(payload.CellX, payload.CellZ, facing, "Wall", level)
			local savedWall = state.Save.PlacedObjects[key]
			if not savedWall then
				return false, "Wall replacement missing state"
			end

			local metadataValue = savedWall.Metadata
			local metadata: { [string]: any }
			if typeof(metadataValue) == "table" then
				metadata = metadataValue
			else
				metadata = {}
				savedWall.Metadata = metadata
			end

			local replacedSpec = ItemFinder.FindItemById(replacedId)
			local preservedSurfaceId = if typeof(metadata.SurfaceId) == "string" and metadata.SurfaceId ~= ""
				then metadata.SurfaceId
				else nil
			local replacementSpecSurface = Helpers.resolveSurfaceId(replacedSpec, payload.SurfaceId)
			local effectiveSurfaceId = preservedSurfaceId or replacementSpecSurface or incomingSurfaceId
			if effectiveSurfaceId then
				metadata.SurfaceId = effectiveSurfaceId
			end

			if isWindowVariant and windowConfig then
				if metadata.OriginalWallMetadata == nil then
					metadata.OriginalWallMetadata = snapshotWallMetadata(metadata)
				end

				local specWidth, specHeight, specThickness, specDiagonalMultiplier, specMinFrame =
					resolveWallDimensionsFromSpec(replacedSpec)

				local wallWidth = typeof(metadata.WallSizeX) == "number" and metadata.WallSizeX or specWidth
				local wallHeight = typeof(metadata.WallSizeY) == "number" and metadata.WallSizeY or specHeight
				local wallThickness = typeof(metadata.WallSizeZ) == "number" and metadata.WallSizeZ or specThickness
				local diagonalMultiplier = typeof(metadata.DiagonalLengthMultiplier) == "number"
						and metadata.DiagonalLengthMultiplier
					or specDiagonalMultiplier
				local minFrameBase = typeof(metadata.MinFrameThickness) == "number" and metadata.MinFrameThickness
					or specMinFrame

				local effectiveWallWidth = typeof(metadata.EffectiveWallWidth) == "number"
						and metadata.EffectiveWallWidth
					or wallWidth
				if isDiagonalFacing(facing) then
					effectiveWallWidth = wallWidth * diagonalMultiplier
				end

				local minFrameThickness = math.max(
					minFrameBase,
					typeof(windowConfig.MinFrameThickness) == "number" and windowConfig.MinFrameThickness
						or minFrameBase
				)
				local maxFrameThickness = typeof(windowConfig.MaxFrameThickness) == "number"
						and windowConfig.MaxFrameThickness
					or math.max(minFrameThickness * 2, effectiveWallWidth * 0.5)
				local frameRatio = typeof(windowConfig.FrameThicknessRatio) == "number"
						and math.max(windowConfig.FrameThicknessRatio, 0)
					or nil
				local frameThickness = if frameRatio and frameRatio > 0
					then wallWidth * frameRatio
					else (
						typeof(windowConfig.FrameThickness) == "number" and windowConfig.FrameThickness
						or minFrameThickness
					)
				frameThickness =
					math.clamp(frameThickness, minFrameThickness, math.max(minFrameThickness, maxFrameThickness))
				frameThickness = math.min(frameThickness, math.max(effectiveWallWidth * 0.5 - 0.01, minFrameThickness))

				local minCutoutWidth = math.max(
					frameThickness * 2,
					typeof(windowConfig.MinCutoutWidth) == "number" and windowConfig.MinCutoutWidth or 0
				)
				local maxCutoutWidth = typeof(windowConfig.MaxCutoutWidth) == "number"
						and math.max(windowConfig.MaxCutoutWidth, minCutoutWidth)
					or math.max(effectiveWallWidth - frameThickness * 2, minCutoutWidth)
				local widthRatio = typeof(windowConfig.CutoutWidthRatio) == "number"
						and math.max(windowConfig.CutoutWidthRatio, 0)
					or nil
				local desiredCutoutWidth = effectiveWallWidth * (widthRatio and widthRatio > 0 and widthRatio or 0.7)
				if typeof(windowConfig.CutoutWidth) == "number" and windowConfig.CutoutWidth > 0 then
					desiredCutoutWidth = windowConfig.CutoutWidth
				end
				local cutoutWidth =
					math.clamp(desiredCutoutWidth, minCutoutWidth, math.max(minCutoutWidth, maxCutoutWidth))
				cutoutWidth = math.min(cutoutWidth, effectiveWallWidth - frameThickness * 2)
				if cutoutWidth < frameThickness * 2 then
					cutoutWidth = frameThickness * 2
				end

				local minCutoutHeight = math.max(
					frameThickness * 2,
					typeof(windowConfig.MinCutoutHeight) == "number" and windowConfig.MinCutoutHeight or 0
				)
				local maxCutoutHeight = typeof(windowConfig.MaxCutoutHeight) == "number"
						and math.max(windowConfig.MaxCutoutHeight, minCutoutHeight)
					or math.max(wallHeight - frameThickness * 2, minCutoutHeight)
				local heightRatio = typeof(windowConfig.CutoutHeightRatio) == "number"
						and math.max(windowConfig.CutoutHeightRatio, 0)
					or nil
				local desiredCutoutHeight = wallHeight * (heightRatio and heightRatio > 0 and heightRatio or 0.6)
				if typeof(windowConfig.CutoutHeight) == "number" and windowConfig.CutoutHeight > 0 then
					desiredCutoutHeight = windowConfig.CutoutHeight
				end
				local cutoutHeight =
					math.clamp(desiredCutoutHeight, minCutoutHeight, math.max(minCutoutHeight, maxCutoutHeight))
				cutoutHeight = math.min(cutoutHeight, wallHeight - frameThickness * 2)
				if cutoutHeight < frameThickness * 2 then
					cutoutHeight = frameThickness * 2
				end

				local halfCutout = cutoutHeight * 0.5
				local minCenter = math.max(
					halfCutout,
					typeof(windowConfig.MinHeight) == "number" and windowConfig.MinHeight or halfCutout
				)
				local maxCenter = math.min(
					wallHeight - halfCutout,
					typeof(windowConfig.MaxHeight) == "number" and windowConfig.MaxHeight or wallHeight - halfCutout
				)
				if maxCenter < minCenter then
					maxCenter = minCenter
				end

				local defaultCenterValue = nil
				if typeof(windowConfig.DefaultHeightRatio) == "number" and windowConfig.DefaultHeightRatio > 0 then
					defaultCenterValue = wallHeight * windowConfig.DefaultHeightRatio
				elseif typeof(windowConfig.DefaultHeight) == "number" then
					defaultCenterValue = windowConfig.DefaultHeight
				else
					defaultCenterValue = wallHeight * 0.5
				end
				local defaultCenter = math.clamp(defaultCenterValue, minCenter, maxCenter)
				local allowVertical = windowConfig.AllowVerticalSliding ~= false
				local requestedCenter = if typeof(payload.WindowHeightOffset) == "number"
					then payload.WindowHeightOffset
					else defaultCenter
				local resolvedCenter = if allowVertical
					then math.clamp(requestedCenter, minCenter, maxCenter)
					else defaultCenter

				local offsetFromWall = typeof(windowConfig.OffsetFromWall) == "number" and windowConfig.OffsetFromWall
					or 0
				local grid = state.Grid
				local levelHeight = 0
				if grid then
					local floorHeight = state:GetFloorHeightStuds()
					if typeof(floorHeight) == "number" then
						levelHeight = level * floorHeight
					end
				end
				local edgeCF = grid
					and grid:CellToWorldEdgeCenterCFrame(payload.CellX, payload.CellZ, facing, levelHeight)

				local function serializeVector(vec: Vector3?): { [string]: number }?
					if typeof(vec) ~= "Vector3" then
						return nil
					end
					return {
						X = vec.X,
						Y = vec.Y,
						Z = vec.Z,
					}
				end

				metadata.WallSizeX = wallWidth
				metadata.WallSizeY = wallHeight
				metadata.WallSizeZ = wallThickness
				metadata.EffectiveWallWidth = effectiveWallWidth
				metadata.DiagonalLengthMultiplier = diagonalMultiplier
				metadata.MinFrameThickness = minFrameThickness

				metadata.WindowCutoutData = {
					HeightOffset = resolvedCenter,
					CutoutWidth = cutoutWidth,
					CutoutHeight = cutoutHeight,
					OffsetFromWall = offsetFromWall,
					AllowVerticalSliding = allowVertical,
					FrameThickness = frameThickness,
					WallSizeX = wallWidth,
					WallSizeY = wallHeight,
					WallSizeZ = wallThickness,
					EffectiveWallWidth = effectiveWallWidth,
					EdgePosition = edgeCF and serializeVector(edgeCF.Position) or nil,
					EdgeRight = edgeCF and serializeVector(edgeCF.RightVector) or nil,
					EdgeUp = edgeCF and serializeVector(edgeCF.UpVector) or nil,
					EdgeForward = edgeCF and serializeVector(edgeCF.LookVector) or nil,
				}
			else
				metadata.WindowCutoutData = nil
			end

			state.Save.PlacedObjects[key] = savedWall

			WorldPlacer.Despawn(player, replacedId, payload.CellX, payload.CellZ, facing, level)
			WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing, level, {
				previousWallId = replacedId,
				metadata = savedWall.Metadata,
			})

			Helpers.sendPlacementDelta(player, "Removed", replacedId, payload.CellX, payload.CellZ, facing, nil, level)
			Helpers.sendPlacementDelta(
				player,
				"Placed",
				payload.ItemId,
				payload.CellX,
				payload.CellZ,
				facing,
				savedWall.Metadata,
				level
			)

			Helpers.deductPlacementCost(player, currencyState, totalCost)

			if isWindowVariant then
				return true, "Window installed"
			end

			return true, "Door installed"
		end

		local wallMetadata = buildWallMetadata(itemData, facing)
		if incomingSurfaceId then
			wallMetadata.SurfaceId = incomingSurfaceId
		end
		local success = state:PlaceWall(
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			1,
			1,
			facing,
			requiresFloorOnBothSides,
			wallMetadata,
			level
		)
		if not success then
			return false, "Failed to place wall"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing, level, {
			metadata = wallMetadata,
		})

		Helpers.sendPlacementDelta(
			player,
			"Placed",
			payload.ItemId,
			payload.CellX,
			payload.CellZ,
			facing,
			wallMetadata,
			level
		)
		Helpers.deductPlacementCost(player, currencyState, totalCost)

		return true, "Wall placed"
	elseif itemData.PlacementType == "Roof" then
		local widthCells = itemData.WidthCells or itemData.Width or 1
		local depthCells = itemData.DepthCells or itemData.Depth or 1
		if itemData.Rules and itemData.Rules.RequiresFloorUnderAllCells then
			if
				not state:HasFloorUnderFootprint(payload.CellX, payload.CellZ, widthCells, depthCells, facing, level)
			then
				return false, "Floor required under roof"
			end
		end

		local totalCells = widthCells * depthCells
		local canAfford, failureReason, totalCost, currencyState =
			Helpers.ensurePlacementFunds(player, itemData, totalCells)
		if not canAfford then
			return false, failureReason or "Not enough cash"
		end

		local success =
			state:PlaceRoof(payload.ItemId, payload.CellX, payload.CellZ, widthCells, depthCells, facing, level)
		if not success then
			return false, "Failed to place roof"
		end

		WorldPlacer.Spawn(player, state.Grid, payload.ItemId, payload.CellX, payload.CellZ, facing, level)

		Helpers.sendPlacementDelta(player, "Placed", payload.ItemId, payload.CellX, payload.CellZ, facing, nil, level)
		Helpers.deductPlacementCost(player, currencyState, totalCost)

		return true, "Roof placed"
	else
		return false, "Unknown placement type"
	end
end

return Build
