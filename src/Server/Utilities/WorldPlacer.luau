--!strict
-- ServerScriptService/Server/Utilities/WorldPlacer.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotState = require(ServerScriptService.Server.Classes.PlotState)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)
local DoorWallFill = require(ReplicatedStorage.Shared.Utilities.DoorWallFill)
local WindowWallFill = require(ReplicatedStorage.Shared.Utilities.WindowWallFill)
local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)
local SurfacePalette = require(ReplicatedStorage.Shared.Configurations.Build.SurfacePalette)

export type Facing = PlacementHelpers.Facing

local WorldPlacer = {}

local GetYawFromFacing = PlacementHelpers.GetYawFromFacing
local GetLiftFromPivotToBottom = PlacementHelpers.GetLiftFromPivotToBottom
local GetFlatAlignedCFrame = PlacementHelpers.GetFlatAlignedCFrame
local GetRotationOnly = PlacementHelpers.GetRotation
local GetPivotRotation = PlacementHelpers.GetPivotRotation
local GetLiftAlongDirection = PlacementHelpers.GetLiftAlongDirection

type PlotContainer = Model | Folder
local SURFACE_PLACEMENT_TARGETS: { [string]: boolean } = {
	Floor = true,
	Wall = true,
}

local function getPlotContainer(player: Player): PlotContainer?
	local plotIndexValue = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndexValue) ~= "number" then
		return nil
	end

	local plotModel = PlotFinder.FindPlot(plotIndexValue)
	if not plotModel then
		return nil
	end

	local container = plotModel:FindFirstChild("Container")
	if not container then
		return nil
	end
	if not container:IsA("Model") and not container:IsA("Folder") then
		return nil
	end

	return container
end

local function sampleWallSize(wallId: string?): Vector3
	if typeof(wallId) ~= "string" or wallId == "" then
		return Vector3.new(4, 12, 0.5)
	end

	local spec = ItemFinder.FindItemById(wallId)
	if spec then
		local dims = spec.WallDimensions
		if typeof(dims) == "table" then
			local width = typeof(dims.NominalWidth) == "number" and dims.NominalWidth or 4
			local height = typeof(dims.NominalHeight) == "number" and dims.NominalHeight or 12
			local thickness = typeof(dims.NominalThickness) == "number" and dims.NominalThickness or 0.5
			return Vector3.new(width, height, thickness)
		end
	end

	local wallModel = ItemFinder.CloneModel(wallId)
	if not wallModel then
		return Vector3.new(4, 12, 0.5)
	end

	local _, size = wallModel:GetBoundingBox()
	wallModel:Destroy()
	return size
end

local function isDiagonalFacing(facing: Facing): boolean
	return facing == "NorthEast" or facing == "NorthWest" or facing == "SouthEast" or facing == "SouthWest"
end

local function extractNumber(source: { [string]: any }?, key: string): number?
	if typeof(source) ~= "table" then
		return nil
	end

	local value = source[key]
	if typeof(value) == "number" then
		return value
	end

	return nil
end

export type SpawnOptions = {
	metadata: { [string]: any }?,
	previousWallId: string?,
	sizeCells: { [string]: number }?,
}

local function coerceVector3(value: any, fallback: Vector3): Vector3
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) ~= "table" then
		return fallback
	end
	local xValue = value.X or value.x
	local yValue = value.Y or value.y
	local zValue = value.Z or value.z
	if typeof(xValue) ~= "number" or typeof(yValue) ~= "number" or typeof(zValue) ~= "number" then
		return fallback
	end
	return Vector3.new(xValue, yValue, zValue)
end

local function resolveWallMountMetadata(metadata: { [string]: any }?): { [string]: any }?
	if typeof(metadata) ~= "table" then
		return nil
	end

	local wallData = metadata.WallMountData
	if typeof(wallData) ~= "table" then
		return nil
	end

	local resolved = {
		ReferenceCellX = wallData.ReferenceCellX,
		ReferenceCellZ = wallData.ReferenceCellZ,
		AttachedFacing = wallData.AttachedFacing,
		HeightOffset = wallData.HeightOffset,
		OffsetFromWall = wallData.OffsetFromWall,
		WorldPosition = coerceVector3(wallData.WorldPosition, Vector3.new()),
		WallNormal = coerceVector3(wallData.WallNormal, Vector3.new(0, 0, -1)),
	}

	return resolved
end

local function readSurfaceId(metadata: { [string]: any }?): string?
	if typeof(metadata) ~= "table" then
		return nil
	end

	local surfaceId = metadata.SurfaceId
	if typeof(surfaceId) == "string" and surfaceId ~= "" then
		return surfaceId
	end

	local original = metadata.OriginalWallMetadata
	if typeof(original) == "table" then
		local originalSurfaceId = original.SurfaceId
		if typeof(originalSurfaceId) == "string" and originalSurfaceId ~= "" then
			return originalSurfaceId
		end
	end

	return nil
end

local function applySurfacePaletteToModel(
	model: Model,
	placementType: string,
	spec: { [string]: any }?,
	metadata: { [string]: any }?
)
	local resolvedSurfaceId = readSurfaceId(metadata)
	if not resolvedSurfaceId and typeof(spec) == "table" then
		local defaultSurfaceId = spec.DefaultSurfaceId
		if typeof(defaultSurfaceId) == "string" and defaultSurfaceId ~= "" then
			resolvedSurfaceId = defaultSurfaceId
		end
	end

	if typeof(resolvedSurfaceId) ~= "string" or resolvedSurfaceId == "" then
		model:SetAttribute("SurfaceId", nil)
		model:SetAttribute("SurfaceKind", nil)
		model:SetAttribute("SurfaceColor", nil)
		model:SetAttribute("SurfaceMaterial", nil)
		model:SetAttribute("SurfaceRoughness", nil)
		model:SetAttribute("SurfaceMetalness", nil)
		return
	end

	model:SetAttribute("SurfaceId", resolvedSurfaceId)
	local definition = SurfacePalette.GetSurface(resolvedSurfaceId)
	if not definition then
		return
	end

	model:SetAttribute("SurfaceKind", definition.Kind)
	model:SetAttribute("SurfaceColor", definition.Color)
	model:SetAttribute("SurfaceMaterial", definition.Material.Name)
	if typeof(definition.Roughness) == "number" then
		model:SetAttribute("SurfaceRoughness", definition.Roughness)
	else
		model:SetAttribute("SurfaceRoughness", nil)
	end
	if typeof(definition.Metalness) == "number" then
		model:SetAttribute("SurfaceMetalness", definition.Metalness)
	else
		model:SetAttribute("SurfaceMetalness", nil)
	end

	if not SURFACE_PLACEMENT_TARGETS[placementType] then
		return
	end
	if placementType == "Wall" and typeof(spec) == "table" and spec.RequiresExistingWall == true then
		return
	end

	local function paintPart(part: BasePart)
		if part:GetAttribute("SurfacePaletteLocked") == true then
			return
		end
		if part.Transparency >= 1 then
			return
		end
		part.Material = definition.Material
		part.Color = definition.Color
	end

	local primaryPart = model.PrimaryPart
	if primaryPart then
		paintPart(primaryPart)
	end
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			paintPart(descendant)
		end
	end
end

local function applyWallModelScaling(model: Model, facing: Facing, cellSize: number)
	local rootPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not rootPart then
		return
	end

	local axisAttr = rootPart:GetAttribute("WallLengthAxis")
	local baseHeightAttr = rootPart:GetAttribute("WallBaseHeight")
	local baseLengthAttr = rootPart:GetAttribute("WallBaseLength")
	local baseThicknessAttr = rootPart:GetAttribute("WallBaseThickness")

	if not axisAttr or not baseHeightAttr or not baseLengthAttr or not baseThicknessAttr then
		local size = rootPart.Size
		local axis = "X"
		if math.abs(size.Z - cellSize) < math.abs(size.X - cellSize) then
			axis = "Z"
		end
		local baseLength = if axis == "X" then size.X else size.Z
		local baseThickness = if axis == "X" then size.Z else size.X
		rootPart:SetAttribute("WallLengthAxis", axis)
		rootPart:SetAttribute("WallBaseHeight", size.Y)
		rootPart:SetAttribute("WallBaseLength", baseLength)
		rootPart:SetAttribute("WallBaseThickness", baseThickness)
		axisAttr = axis
		baseHeightAttr = size.Y
		baseLengthAttr = baseLength
		baseThicknessAttr = baseThickness
	end

	local axis = axisAttr :: string
	local baseHeight = baseHeightAttr :: number
	local baseLength = baseLengthAttr :: number
	local baseThickness = baseThicknessAttr :: number

	local lengthMultiplier = 1
	if facing == "NorthEast" or facing == "SouthEast" or facing == "NorthWest" or facing == "SouthWest" then
		lengthMultiplier = math.sqrt(2)
	end

	local targetLength = baseLength * lengthMultiplier
	if axis == "X" then
		rootPart.Size = Vector3.new(targetLength, baseHeight, baseThickness)
	else
		rootPart.Size = Vector3.new(baseThickness, baseHeight, targetLength)
	end
end

-- Spawn a physical model for a saved/placed item.
function WorldPlacer.Spawn(
	player: Player,
	grid: any,
	itemId: string,
	cellX: number,
	cellZ: number,
	facing: Facing,
	optionsOrLevel: any?,
	maybeOptions: SpawnOptions?
)
	local levelValue: number? = nil
	local options: SpawnOptions? = nil
	if typeof(optionsOrLevel) == "number" then
		levelValue = optionsOrLevel :: number
		options = maybeOptions
	elseif typeof(optionsOrLevel) == "table" or optionsOrLevel == nil then
		options = optionsOrLevel :: SpawnOptions?
	else
		options = nil
	end
	local spec = ItemFinder.FindItemById(itemId)
	if not spec then
		return
	end

	local resolvedLevel = PlotState.ResolveLevel(levelValue)
	local floorHeight = BuildConstants.FloorHeightStuds or 12
	local levelHeight = resolvedLevel * floorHeight

	local placementType = spec.PlacementType or "CellObject"
	local catalogWidth = spec.WidthCells or spec.Width or 1
	local catalogDepth = spec.DepthCells or spec.Depth or 1
	local footprintWidth = catalogWidth
	local footprintDepth = catalogDepth
	local extraLift = 0
	if typeof(spec.SurfaceOffsetStuds) == "number" then
		extraLift = spec.SurfaceOffsetStuds
	end

	local metadata = options and options.metadata or nil
	local sizeOverride = options and (options :: any).sizeCells or nil
	local widthOverride = nil
	local depthOverride = nil
	if sizeOverride then
		widthOverride = sizeOverride.WidthCells or sizeOverride.widthCells or sizeOverride.Width or sizeOverride.width
		depthOverride = sizeOverride.DepthCells or sizeOverride.depthCells or sizeOverride.Depth or sizeOverride.depth
	end
	if metadata then
		widthOverride = widthOverride or metadata.WidthCells or metadata.widthCells or metadata.Width or metadata.width
		depthOverride = depthOverride or metadata.DepthCells or metadata.depthCells or metadata.Depth or metadata.depth
	end

	if typeof(widthOverride) == "number" and widthOverride > 0 then
		footprintWidth = widthOverride
	end
	if typeof(depthOverride) == "number" and depthOverride > 0 then
		footprintDepth = depthOverride
	end

	local model = ItemFinder.CloneModel(itemId)
	if not model then
		return
	end

	local facingString = tostring(facing)
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("CellX", cellX)
	model:SetAttribute("CellZ", cellZ)
	model:SetAttribute("Facing", facingString)
	model:SetAttribute("WidthCells", footprintWidth)
	model:SetAttribute("DepthCells", footprintDepth)
	model:SetAttribute("PlacementType", placementType)
	model:SetAttribute("Level", resolvedLevel)

	if options then
		if options.previousWallId then
			model:SetAttribute("PreviousWallId", options.previousWallId)
		elseif options.metadata then
			local metaPrev = options.metadata.PreviousId
			if typeof(metaPrev) == "string" and metaPrev ~= "" then
				model:SetAttribute("PreviousWallId", metaPrev)
			end
		end
	end

	applySurfacePaletteToModel(model, placementType, spec, metadata)

	if placementType == "Floor" then
		local floorPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if floorPart then
			local baseSize = floorPart.Size
			local widthScale = footprintWidth / math.max(catalogWidth, 1)
			local depthScale = footprintDepth / math.max(catalogDepth, 1)
			floorPart.Size = Vector3.new(baseSize.X * widthScale, baseSize.Y, baseSize.Z * depthScale)
		end
	elseif placementType == "Roof" then
		local roofPart = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
		if roofPart then
			local baseSize = roofPart.Size
			local widthScale = footprintWidth / math.max(catalogWidth, 1)
			local depthScale = footprintDepth / math.max(catalogDepth, 1)
			roofPart.Size = Vector3.new(baseSize.X * widthScale, baseSize.Y, baseSize.Z * depthScale)
		end
	end

	local base: CFrame
	local target: CFrame?
	if placementType == "Wall" then
		base = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing, levelHeight)
		applyWallModelScaling(model, facing, grid.CellSize)

		local windowData = metadata and metadata.WindowCutoutData
		if spec.WallVariant == "Window" then
			local wallWidth = extractNumber(windowData, "WallSizeX") or extractNumber(metadata, "WallSizeX")
			local wallHeight = extractNumber(windowData, "WallSizeY") or extractNumber(metadata, "WallSizeY")
			local wallThickness = extractNumber(windowData, "WallSizeZ") or extractNumber(metadata, "WallSizeZ")

			if typeof(wallWidth) ~= "number" or typeof(wallHeight) ~= "number" or typeof(wallThickness) ~= "number" then
				local referenceId = if options and options.previousWallId
					then options.previousWallId
					else metadata and metadata.PreviousId
				local sampled = sampleWallSize(referenceId or itemId)
				wallWidth = typeof(wallWidth) == "number" and wallWidth or sampled.X
				wallHeight = typeof(wallHeight) == "number" and wallHeight or sampled.Y
				wallThickness = typeof(wallThickness) == "number" and wallThickness or sampled.Z
			end

			local resolvedWallWidth = math.max(wallWidth or 4, 0.5)
			local resolvedWallHeight = math.max(wallHeight or 12, 0.5)
			local resolvedWallThickness = math.max(wallThickness or 0.05, 0.05)

			local diagonalMultiplier = extractNumber(metadata, "DiagonalLengthMultiplier") or math.sqrt(2)
			local effectiveWidthValue = extractNumber(windowData, "EffectiveWallWidth")
			local resolvedEffectiveWidth: number
			if typeof(effectiveWidthValue) == "number" then
				resolvedEffectiveWidth = effectiveWidthValue
			else
				local metadataEffectiveWidth = extractNumber(metadata, "EffectiveWallWidth")
				if typeof(metadataEffectiveWidth) == "number" then
					resolvedEffectiveWidth = metadataEffectiveWidth
				elseif isDiagonalFacing(facing) then
					resolvedEffectiveWidth = resolvedWallWidth * diagonalMultiplier
				else
					resolvedEffectiveWidth = resolvedWallWidth
				end
			end
			if resolvedEffectiveWidth < resolvedWallWidth then
				resolvedEffectiveWidth = resolvedWallWidth
			end

			local windowConfig = spec.WindowCutoutConfig

			local heightOffsetValue = extractNumber(windowData, "HeightOffset")
			local resolvedHeightOffset: number
			if typeof(heightOffsetValue) == "number" then
				resolvedHeightOffset = heightOffsetValue
			else
				local defaultHeightRatio = extractNumber(windowConfig, "DefaultHeightRatio")
				if typeof(defaultHeightRatio) == "number" then
					resolvedHeightOffset = resolvedWallHeight * defaultHeightRatio
				else
					local defaultHeightValue = extractNumber(windowConfig, "DefaultHeight")
					if typeof(defaultHeightValue) == "number" then
						resolvedHeightOffset = defaultHeightValue
					else
						resolvedHeightOffset = resolvedWallHeight * 0.5
					end
				end
			end

			local offsetFromWallValue = extractNumber(windowData, "OffsetFromWall")
			local resolvedOffsetFromWall: number
			if typeof(offsetFromWallValue) == "number" then
				resolvedOffsetFromWall = offsetFromWallValue
			else
				resolvedOffsetFromWall = extractNumber(windowConfig, "OffsetFromWall") or 0
			end

			local frameThicknessValue = extractNumber(windowData, "FrameThickness")
			local resolvedFrameThickness: number
			if typeof(frameThicknessValue) == "number" then
				resolvedFrameThickness = math.max(frameThicknessValue, 0.05)
			else
				local frameThicknessRatio = extractNumber(windowConfig, "FrameThicknessRatio")
				if typeof(frameThicknessRatio) == "number" and frameThicknessRatio > 0 then
					resolvedFrameThickness = resolvedEffectiveWidth * frameThicknessRatio
				else
					local frameThicknessAbsolute = extractNumber(windowConfig, "FrameThickness")
					if typeof(frameThicknessAbsolute) == "number" then
						resolvedFrameThickness = frameThicknessAbsolute
					else
						resolvedFrameThickness = 0.2
					end
				end
			end
			local minFrameThickness = extractNumber(windowConfig, "MinFrameThickness") or 0.05
			local maxFrameThickness = extractNumber(windowConfig, "MaxFrameThickness")
				or math.max(resolvedEffectiveWidth * 0.5 - 0.01, 0.05)
			resolvedFrameThickness = math.clamp(resolvedFrameThickness, minFrameThickness, maxFrameThickness)

			local cutoutWidthValue = extractNumber(windowData, "CutoutWidth")
			local resolvedCutoutWidth: number
			if typeof(cutoutWidthValue) == "number" then
				resolvedCutoutWidth = cutoutWidthValue
			else
				local cutoutWidthRatio = extractNumber(windowConfig, "CutoutWidthRatio")
				if typeof(cutoutWidthRatio) == "number" and cutoutWidthRatio > 0 then
					resolvedCutoutWidth = resolvedEffectiveWidth * cutoutWidthRatio
				else
					local defaultCutoutWidth = extractNumber(windowConfig, "CutoutWidth")
					if typeof(defaultCutoutWidth) == "number" then
						resolvedCutoutWidth = defaultCutoutWidth
					else
						resolvedCutoutWidth = resolvedEffectiveWidth * 0.7
					end
				end
			end

			local cutoutHeightValue = extractNumber(windowData, "CutoutHeight")
			local resolvedCutoutHeight: number
			if typeof(cutoutHeightValue) == "number" then
				resolvedCutoutHeight = cutoutHeightValue
			else
				local cutoutHeightRatio = extractNumber(windowConfig, "CutoutHeightRatio")
				if typeof(cutoutHeightRatio) == "number" and cutoutHeightRatio > 0 then
					resolvedCutoutHeight = resolvedWallHeight * cutoutHeightRatio
				else
					local defaultCutoutHeight = extractNumber(windowConfig, "CutoutHeight")
					if typeof(defaultCutoutHeight) == "number" then
						resolvedCutoutHeight = defaultCutoutHeight
					else
						resolvedCutoutHeight = resolvedWallHeight * 0.6
					end
				end
			end

			local minCutoutWidth = math.max(
				extractNumber(windowConfig, "MinCutoutWidth") or resolvedFrameThickness * 2,
				resolvedFrameThickness * 2
			)
			local maxCutoutWidth = math.max(
				extractNumber(windowConfig, "MaxCutoutWidth") or (resolvedEffectiveWidth - resolvedFrameThickness * 0.5),
				resolvedFrameThickness * 2
			)
			resolvedCutoutWidth = math.clamp(resolvedCutoutWidth, minCutoutWidth, maxCutoutWidth)

			local minCutoutHeight = math.max(
				extractNumber(windowConfig, "MinCutoutHeight") or resolvedFrameThickness * 2,
				resolvedFrameThickness * 2
			)
			local maxCutoutHeight = math.max(
				extractNumber(windowConfig, "MaxCutoutHeight") or (resolvedWallHeight - resolvedFrameThickness * 0.5),
				resolvedFrameThickness * 2
			)
			resolvedCutoutHeight = math.clamp(resolvedCutoutHeight, minCutoutHeight, maxCutoutHeight)

			local edgeCF = base
			local wallNormal = edgeCF.LookVector
			local wallUp = edgeCF.UpVector
			local wallBottom = edgeCF.Position
			local worldCenter = wallBottom + wallUp * resolvedHeightOffset + wallNormal * resolvedOffsetFromWall
			local forward = (-wallNormal).Unit
			local pivotRotation = GetPivotRotation(model)
			local bboxCF = select(1, model:GetBoundingBox())
			local pivotCF = model:GetPivot()
			local localCenterOffset = Vector3.new()
			if typeof(bboxCF) == "CFrame" and typeof(pivotCF) == "CFrame" then
				localCenterOffset = pivotCF:PointToObjectSpace(bboxCF.Position)
			end
			local desiredOrientation = CFrame.lookAt(worldCenter, worldCenter + forward, wallUp) * pivotRotation
			target = desiredOrientation * CFrame.new(-localCenterOffset)

			model:SetAttribute("WindowHeightOffset", resolvedHeightOffset)
			model:SetAttribute("WindowWallSizeX", resolvedEffectiveWidth)
			model:SetAttribute("WindowWallSizeY", resolvedWallHeight)
			model:SetAttribute("WindowWallSizeZ", resolvedWallThickness)
			model:SetAttribute("WindowWallThickness", resolvedWallThickness)
			model:SetAttribute("WindowCutoutWidth", resolvedCutoutWidth)
			model:SetAttribute("WindowCutoutHeight", resolvedCutoutHeight)
			model:SetAttribute("WindowFrameThickness", resolvedFrameThickness)
		end
	elseif placementType == "Floor" then
		local center = grid:FootprintCenterCFrame(cellX, cellZ, footprintWidth, footprintDepth, facing)
		center = center * CFrame.new(0, levelHeight, 0)
		base = center * CFrame.Angles(0, GetYawFromFacing(facing), 0)
	elseif placementType == "CellObject" then
		local center = grid:FootprintCenterCFrame(cellX, cellZ, footprintWidth, footprintDepth, facing)
		center = center * CFrame.new(0, levelHeight, 0)
		local yaw = CFrame.Angles(0, GetYawFromFacing(facing), 0)
		local plotSurface: BasePart? = grid and grid.Plot
		local aligned = GetFlatAlignedCFrame(plotSurface, center.Position)
		local baseRotation = GetRotationOnly(aligned)
		local pivotRotation = GetPivotRotation(model)
		local orientation = baseRotation * yaw * pivotRotation
		local surfaceUp = plotSurface and plotSurface.CFrame.UpVector or Vector3.yAxis
		local lift = GetLiftAlongDirection(model, surfaceUp) + extraLift
		target = CFrame.new(center.Position + surfaceUp * lift) * orientation
	elseif placementType == "Roof" then
		-- Roof placement sits above its floor level by a configurable lift
		local center = grid:FootprintCenterCFrame(cellX, cellZ, footprintWidth, footprintDepth, facing)
		center = center * CFrame.new(0, levelHeight, 0)
		local yaw = CFrame.Angles(0, GetYawFromFacing(facing), 0)
		local roofLift = if typeof(spec.HeightStuds) == "number"
			then spec.HeightStuds
			else BuildConstants.RoofLiftStuds or 12
		if typeof(extraLift) == "number" and extraLift ~= 0 then
			roofLift += extraLift
		end
		base = (center * yaw) * CFrame.new(0, roofLift, 0)
	elseif placementType == "WallMounted" then
		local resolved = resolveWallMountMetadata(metadata)
		if not resolved then
			return
		end
		local wallNormal = resolved.WallNormal
		if wallNormal.Magnitude < 1e-3 then
			wallNormal = Vector3.new(0, 0, -1)
		end
		local upVector = grid and grid.Plot and grid.Plot.CFrame.UpVector or Vector3.yAxis
		local pivotRotation = GetPivotRotation(model)
		local forward = (-wallNormal).Unit
		local lookCFrame = CFrame.lookAt(resolved.WorldPosition, resolved.WorldPosition + forward, upVector)
		target = lookCFrame * pivotRotation
		model:SetAttribute("WallMountReferenceCellX", resolved.ReferenceCellX)
		model:SetAttribute("WallMountReferenceCellZ", resolved.ReferenceCellZ)
		model:SetAttribute("WallMountHeightOffset", resolved.HeightOffset)
		model:SetAttribute("WallMountOffsetFromWall", resolved.OffsetFromWall or 0)
		model:SetAttribute("WallMountWorldPosition", resolved.WorldPosition)
		model:SetAttribute("WallMountWallNormal", wallNormal.Unit)
	end

	if target then
		model:PivotTo(target)
	elseif placementType == "Floor" or placementType == "Roof" then
		model:PivotTo(base)
	else
		model:PivotTo(base * CFrame.new(0, GetLiftFromPivotToBottom(model), 0))
	end

	if placementType == "Wall" and spec.RequiresExistingWall == true then
		if spec.WallVariant == "Window" then
			WindowWallFill.Apply(model, spec, options)
		else
			DoorWallFill.Apply(model, spec, options)
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanTouch = false
			part.CanQuery = true
		end
	end
	local fromKey = PlotState:PlacementKeyForType(cellX, cellZ, facing, placementType, resolvedLevel)
	local container = getPlotContainer(player)

	model.Name = fromKey
	model.Parent = container
end

function WorldPlacer.Despawn(
	player: Player,
	itemId: string,
	cellX: number,
	cellZ: number,
	facing: Facing,
	level: number?
)
	local container = getPlotContainer(player)
	if not container then
		return
	end

	local desiredFacing = tostring(facing)
	local desiredLevel = if level ~= nil then PlotState.ResolveLevel(level) else nil
	for _, inst in container:GetChildren() do
		if
			inst:GetAttribute("ItemId") == itemId
			and inst:GetAttribute("CellX") == cellX
			and inst:GetAttribute("CellZ") == cellZ
			and inst:GetAttribute("Facing") == desiredFacing
		then
			if desiredLevel ~= nil then
				local instLevelAttr = inst:GetAttribute("Level")
				local instLevel = if typeof(instLevelAttr) == "number" then instLevelAttr else 0
				if instLevel ~= desiredLevel then
					continue
				end
			end
			inst:Destroy()
			break
		end
	end
end

local function sanitizeRotationY(value: any): number
	if typeof(value) ~= "number" then
		return 0
	end
	if value ~= value then
		return 0
	end
	return value
end

function WorldPlacer.SpawnSurfaceMount(
	player: Player,
	parentKey: string,
	mountKey: string,
	itemId: string,
	mountData: { [string]: any }?
)
	local container = getPlotContainer(player)
	if not container then
		return
	end

	local parentModel = container:FindFirstChild(parentKey)
	if not parentModel or not parentModel:IsA("Model") then
		return
	end

	local model = ItemFinder.CloneModel(itemId)
	if not model then
		return
	end

	local localPosition = coerceVector3(mountData and mountData.LocalPosition, Vector3.new())
	local rotationY = sanitizeRotationY(mountData and mountData.LocalRotationY)
	local pivotRotation = GetPivotRotation(model)
	local parentPivot = parentModel:GetPivot()
	local localOffset = CFrame.new(localPosition) * CFrame.Angles(0, rotationY, 0)
	local target = parentPivot * localOffset * pivotRotation

	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("PlacementType", "SurfaceMounted")
	model:SetAttribute("ParentPlacementKey", parentKey)
	model:SetAttribute("MountKey", mountKey)
	model:SetAttribute("LocalPosX", localPosition.X)
	model:SetAttribute("LocalPosY", localPosition.Y)
	model:SetAttribute("LocalPosZ", localPosition.Z)
	model:SetAttribute("LocalRotationY", rotationY)
	if mountData then
		local mountIndexValue = mountData.mountIndex
		if typeof(mountIndexValue) == "number" then
			model:SetAttribute("MountIndex", mountIndexValue)
		end
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanTouch = false
			part.CanQuery = true
		end
	end

	model:PivotTo(target)
	model.Name = mountKey
	model.Parent = container
end

function WorldPlacer.DespawnSurfaceMount(player: Player, mountKey: string)
	local container = getPlotContainer(player)
	if not container then
		return
	end

	local target = container:FindFirstChild(mountKey)
	if not target then
		target = container:FindFirstChild(mountKey, true)
	end

	if target and target:IsA("Model") then
		target:Destroy()
	end
end

function WorldPlacer.GetPlacementModel(player: Player, placementKey: string): Model?
	local container = getPlotContainer(player)
	if not container then
		return nil
	end

	local instance = container:FindFirstChild(placementKey)
	if instance and instance:IsA("Model") then
		return instance
	end

	return nil
end

return WorldPlacer
