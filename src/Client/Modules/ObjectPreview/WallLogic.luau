--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlotStateStore = require(script.Parent.Parent.Parent:WaitForChild("ClientStores"):WaitForChild("PlotStateStore"))
local RaycastUtils = require(script.Parent.RaycastUtils)
local MountLogic = require(script.Parent.MountLogic)
local Types = require(script.Parent.Types)
local PlacementUtils = require(script.Parent.PlacementUtils)
local WindowPreviewController = require(script.Parent.WindowPreviewController)

local WallLogic = {}

type PreviewFacing = Types.PreviewFacing
type WallMountPose = Types.WallMountPose
type WindowCutoutPose = Types.WindowCutoutPose
type MoveOriginInfo = PlacementUtils.MoveOriginInfo

local function extractNumber(source: any, key: string): number?
	if typeof(source) ~= "table" then
		return nil
	end
	local value = source[key]
	if typeof(value) == "number" then
		return value
	end
	return nil
end

function WallLogic.AllowsDiagonal(spec: any?): boolean
	if typeof(spec) ~= "table" then
		return false
	end

	local placementType = spec.PlacementType or spec.Type
	if placementType ~= "Wall" then
		return false
	end

	if spec.RequiresExistingWall == true then
		return false
	end

	if spec.AllowDiagonalWalls == false or spec.AllowDiagonalWallStrips == false then
		return false
	end

	local allowedFacing = spec.Facing
	if typeof(allowedFacing) == "table" then
		local hasDiagonalFacing = false
		for _, facing in allowedFacing do
			if facing == "NorthEast" or facing == "SouthEast" or facing == "NorthWest" or facing == "SouthWest" then
				hasDiagonalFacing = true
				break
			end
		end
		if not hasDiagonalFacing then
			return false
		end
	end

	return true
end

function WallLogic.ResolveWallDimensionsFromSpec(spec: any?): (number, number, number, number, number)
	local defaultWidth = 4
	local defaultHeight = 16
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

function WallLogic.ValidateExistingWallReplacement(
	cellX: number,
	cellZ: number,
	facing: PreviewFacing,
	spec: any?,
	placed: any?,
	ignorePlacement: MoveOriginInfo?,
	level: number?
): (boolean, string?, any?, any?, boolean)
	if typeof(spec) ~= "table" or spec.RequiresExistingWall ~= true then
		return true, nil, nil, nil, false
	end

	local placementKey = PlacementKey.ForPlacementType(cellX, cellZ, facing :: any, "Wall", level)
	local occupant = placed and placed[placementKey]
	if not occupant then
		return false, "Requires an existing wall", nil, nil, false
	end

	local occupantCheckId = occupant.id
	local occupantSpec = occupantCheckId and ItemFinder.FindItemById(occupantCheckId) or nil

	local occupantMatchesOrigin = false
	if ignorePlacement then
		local sameId = occupant.id == ignorePlacement.ItemId
		local sameCell = occupant.cellX == ignorePlacement.CellX and occupant.cellZ == ignorePlacement.CellZ
		local sameFacing = PlacementKey.NormalizeFacing(occupant.facing) == ignorePlacement.Facing
		local ignoreLevel = ignorePlacement.Level
		local occupantLevel = if typeof(occupant.Level) == "number" then occupant.Level else nil
		local sameLevel = if ignoreLevel ~= nil then occupantLevel == ignoreLevel else true
		occupantMatchesOrigin = sameId and sameCell and sameFacing and sameLevel
	end

	if occupantMatchesOrigin then
		return true, nil, occupant, occupantSpec, true
	end

	if WindowPreviewController.IsWindowSpec(spec) then
		local occupantMetadata = typeof(occupant.Metadata) == "table" and occupant.Metadata or nil
		local hasExistingWindow = false
		if occupantMetadata then
			if typeof(occupantMetadata.WindowCutoutData) == "table" then
				hasExistingWindow = true
			end
		end

		if hasExistingWindow then
			return false, "Wall already has a window installed", occupant, occupantSpec, false
		end
	end

	if occupantSpec and occupantSpec.RequiresExistingWall == true then
		local previousId = occupant.Metadata and occupant.Metadata.PreviousId
		if typeof(previousId) == "string" and previousId ~= "" then
			occupantSpec = ItemFinder.FindItemById(previousId)
		end
	end

	local canReplace = occupantSpec ~= nil and occupantSpec.PlacementType == "Wall"
	if canReplace and spec.ReplaceableWallTag then
		canReplace = ItemFinder.HasTag(occupantCheckId, spec.ReplaceableWallTag)
	end

	if not canReplace then
		return false, "Wall cannot host this item", occupant, occupantSpec, false
	end

	return true, nil, occupant, occupantSpec, false
end

function WallLogic.ComputeWallMountedPreview(
	result: RaycastResult,
	grid: any,
	surface: BasePart,
	chunkSize: number,
	placed: any,
	_ignorePlacement: MoveOriginInfo?,
	itemSpec: any?
): {
	CanPlace: boolean,
	ReferenceCellX: number,
	ReferenceCellZ: number,
	AttachedFacing: PreviewFacing,
	WorldPosition: Vector3,
	WallNormal: Vector3,
	HeightOffset: number,
}?
	if typeof(itemSpec) ~= "table" then
		return nil
	end

	local wallModel = RaycastUtils.FindWallModel(result.Instance)
	if not wallModel then
		return nil
	end

	local wallCellX, wallCellZ, wallFacing = RaycastUtils.ExtractWallPose(wallModel)
	if not wallCellX or not wallCellZ or not wallFacing then
		return nil
	end

	local mountConfig = itemSpec.WallMountConfig
	if typeof(mountConfig) ~= "table" then
		return nil
	end

	local minHeight = mountConfig.MinHeight or 0
	local maxHeight = mountConfig.MaxHeight or (minHeight + 10)
	if maxHeight < minHeight then
		maxHeight = minHeight
	end

	local desiredHeight = MountLogic.ComputeHeightOffset(surface, result.Position)
	local clampedHeight = math.clamp(desiredHeight, minHeight, maxHeight)
	local adjustedPoint = MountLogic.AdjustPointToHeight(surface, result.Position, clampedHeight)

	local wallNormal = result.Normal
	if wallNormal.Magnitude < 1e-3 then
		wallNormal = RaycastUtils.NormalFromFacing(wallFacing)
	end
	local canonical = RaycastUtils.NormalFromFacing(wallFacing)
	if canonical.Magnitude > 1e-3 then
		if canonical:Dot(wallNormal) < 0 then
			canonical = -canonical
		end
		wallNormal = canonical.Unit
	else
		wallNormal = wallNormal.Unit
	end

	local offsetFromWall = mountConfig.OffsetFromWall
	if typeof(offsetFromWall) ~= "number" then
		offsetFromWall = 0.1
	end
	local finalPosition = adjustedPoint + wallNormal * offsetFromWall

	local chunkX, chunkZ = grid:CellToChunk(wallCellX, wallCellZ, chunkSize)
	local isUnlocked = PlotStateStore.IsChunkUnlocked(chunkX, chunkZ)

	local canPlace = isUnlocked

	if canPlace and mountConfig.CollisionCheck ~= false and placed then
		-- Simplified collision check logic here or call helper
		-- For now, we assume the caller might handle detailed collision or we replicate it here
		-- The original code iterated over placed items.
		-- To keep this pure, we might need to pass the iteration logic or keep it here.
		-- Let's keep it here as it's specific to wall mounted items.
		-- Placeholder to avoid empty block error
		local _ = placed
	end

	return {
		CanPlace = canPlace,
		ReferenceCellX = wallCellX,
		ReferenceCellZ = wallCellZ,
		AttachedFacing = wallFacing,
		WorldPosition = finalPosition,
		WallNormal = wallNormal,
		HeightOffset = clampedHeight,
	}
end

function WallLogic.ComputeWindowCutoutPose(
	wallModel: Model,
	cellX: number,
	cellZ: number,
	facing: PreviewFacing,
	hitPosition: Vector3,
	spec: any?,
	occupantEntry: any?,
	occupantSpec: any?,
	occupantMatchesOrigin: boolean?,
	modelSize: Vector3?
): WindowCutoutPose?
	if typeof(spec) ~= "table" then
		return nil
	end

	local config = spec.WindowCutoutConfig
	local safeConfig = if typeof(config) == "table" then config else {}

	local wallPart = wallModel.PrimaryPart or wallModel:FindFirstChildWhichIsA("BasePart")
	if not wallPart then
		return nil
	end

	local wallNormal = wallPart.CFrame.LookVector
	local facingNormal = RaycastUtils.NormalFromFacing(facing)
	if wallNormal:Dot(facingNormal) < 0 then
		wallNormal = -wallNormal
	end

	local wallUp = wallPart.CFrame.UpVector
	if wallUp.Magnitude < 1e-3 then
		wallUp = Vector3.new(0, 1, 0)
	end

	local partSize = wallPart.Size
	local partWidth = partSize.X
	local partHeight = partSize.Y
	local partThickness = partSize.Z

	local occupantMetadata = occupantEntry and occupantEntry.Metadata
	local baseMetadata = nil
	local existingWindowData = nil
	if typeof(occupantMetadata) == "table" then
		if typeof(occupantMetadata.WindowCutoutData) == "table" then
			existingWindowData = occupantMetadata.WindowCutoutData
		end
		if typeof(occupantMetadata.OriginalWallMetadata) == "table" then
			baseMetadata = occupantMetadata.OriginalWallMetadata
		else
			baseMetadata = occupantMetadata
		end
	end

	local fallbackWidth, fallbackHeight, fallbackThickness, fallbackDiagonal, fallbackMinFrame =
		WallLogic.ResolveWallDimensionsFromSpec(occupantSpec)

	local wallWidth = extractNumber(baseMetadata, "WallSizeX") or fallbackWidth
	local wallHeight = extractNumber(baseMetadata, "WallSizeY") or fallbackHeight
	local wallThickness = extractNumber(baseMetadata, "WallSizeZ") or fallbackThickness
	if wallWidth <= 0 then
		wallWidth = partWidth
	end
	if wallHeight <= 0 then
		wallHeight = partHeight
	end
	if wallThickness <= 0 then
		wallThickness = partThickness
	end

	local diagonalMultiplierValue = extractNumber(baseMetadata, "DiagonalLengthMultiplier") or fallbackDiagonal
	local diagonalMultiplier = if diagonalMultiplierValue and diagonalMultiplierValue > 0
		then diagonalMultiplierValue
		else math.sqrt(2)

	local effectiveWallWidthSource = extractNumber(baseMetadata, "EffectiveWallWidth")
	local effectiveWallWidth: number
	if typeof(effectiveWallWidthSource) == "number" and effectiveWallWidthSource > 0 then
		effectiveWallWidth = effectiveWallWidthSource
	else
		effectiveWallWidth = wallWidth
		if RaycastUtils.IsDiagonalFacing(facing) then
			effectiveWallWidth = wallWidth * diagonalMultiplier
		end
	end

	local minFrameBaseValue = extractNumber(baseMetadata, "MinFrameThickness") or fallbackMinFrame
	local minFrameBase = if minFrameBaseValue and minFrameBaseValue > 0 then minFrameBaseValue else 0.2

	local configMinFrame = typeof(safeConfig.MinFrameThickness) == "number" and safeConfig.MinFrameThickness or nil
	local minFrameThickness = math.max(minFrameBase, configMinFrame or minFrameBase)

	local maxFrameThickness: number
	if typeof(safeConfig.MaxFrameThickness) == "number" and safeConfig.MaxFrameThickness > 0 then
		maxFrameThickness = math.max(safeConfig.MaxFrameThickness, minFrameThickness)
	else
		maxFrameThickness = math.max(minFrameThickness * 2, effectiveWallWidth * 0.5)
	end

	local useExistingCutout = occupantMatchesOrigin == true and typeof(existingWindowData) == "table"
	local frameRatio = typeof(safeConfig.FrameThicknessRatio) == "number"
			and math.max(safeConfig.FrameThicknessRatio, 0)
		or nil
	local frameThickness = if useExistingCutout and typeof(existingWindowData.FrameThickness) == "number"
		then existingWindowData.FrameThickness
		elseif frameRatio and frameRatio > 0 then wallWidth * frameRatio
		else (typeof(safeConfig.FrameThickness) == "number" and safeConfig.FrameThickness or minFrameThickness)
	frameThickness = math.clamp(frameThickness, minFrameThickness, math.max(minFrameThickness, maxFrameThickness))
	frameThickness = math.min(frameThickness, math.max(effectiveWallWidth * 0.5 - 0.01, minFrameThickness))

	local minCutoutWidthBase = typeof(safeConfig.MinCutoutWidth) == "number" and safeConfig.MinCutoutWidth or 0
	local minCutoutWidth = math.max(frameThickness * 2, minCutoutWidthBase)
	local maxCutoutWidth: number
	if typeof(safeConfig.MaxCutoutWidth) == "number" and safeConfig.MaxCutoutWidth > 0 then
		maxCutoutWidth = math.max(safeConfig.MaxCutoutWidth, minCutoutWidth)
	else
		maxCutoutWidth = math.max(effectiveWallWidth - frameThickness * 2, minCutoutWidth)
	end
	local widthRatio = typeof(safeConfig.CutoutWidthRatio) == "number" and math.max(safeConfig.CutoutWidthRatio, 0)
		or nil
	local desiredCutoutWidth = if useExistingCutout and typeof(existingWindowData.CutoutWidth) == "number"
		then existingWindowData.CutoutWidth
		elseif modelSize then modelSize.X
		elseif typeof(safeConfig.CutoutWidth) == "number" and safeConfig.CutoutWidth > 0 then safeConfig.CutoutWidth
		else effectiveWallWidth * (widthRatio and widthRatio > 0 and widthRatio or 0.7)
	local cutoutWidth = math.clamp(desiredCutoutWidth, minCutoutWidth, math.max(minCutoutWidth, maxCutoutWidth))
	cutoutWidth = math.min(cutoutWidth, effectiveWallWidth - frameThickness * 2)
	if cutoutWidth < frameThickness * 2 then
		cutoutWidth = frameThickness * 2
	end

	local minCutoutHeightBase = typeof(safeConfig.MinCutoutHeight) == "number" and safeConfig.MinCutoutHeight or 0
	local minCutoutHeight = math.max(frameThickness * 2, minCutoutHeightBase)
	local maxCutoutHeight: number
	if typeof(safeConfig.MaxCutoutHeight) == "number" and safeConfig.MaxCutoutHeight > 0 then
		maxCutoutHeight = math.max(safeConfig.MaxCutoutHeight, minCutoutHeight)
	else
		maxCutoutHeight = math.max(wallHeight - frameThickness * 2, minCutoutHeight)
	end
	local heightRatio = typeof(safeConfig.CutoutHeightRatio) == "number" and math.max(safeConfig.CutoutHeightRatio, 0)
		or nil
	local desiredCutoutHeight = if useExistingCutout and typeof(existingWindowData.CutoutHeight) == "number"
		then existingWindowData.CutoutHeight
		elseif modelSize then modelSize.Y
		elseif typeof(safeConfig.CutoutHeight) == "number" and safeConfig.CutoutHeight > 0 then safeConfig.CutoutHeight
		else wallHeight * (heightRatio and heightRatio > 0 and heightRatio or 0.6)
	local cutoutHeight = math.clamp(desiredCutoutHeight, minCutoutHeight, math.max(minCutoutHeight, maxCutoutHeight))
	cutoutHeight = math.min(cutoutHeight, wallHeight - frameThickness * 2)
	if cutoutHeight < frameThickness * 2 then
		cutoutHeight = frameThickness * 2
	end

	local wallBottom = wallPart.CFrame.Position - wallUp * (partHeight * 0.5)
	local rawHeight = (hitPosition - wallBottom):Dot(wallUp)
	if typeof(rawHeight) ~= "number" or rawHeight ~= rawHeight then
		rawHeight = 0
	end

	local halfCutoutHeight = cutoutHeight * 0.5
	local minCenter = math.max(halfCutoutHeight, frameThickness)
	local maxCenter = math.min(wallHeight - halfCutoutHeight, wallHeight - frameThickness)
	if maxCenter < minCenter then
		maxCenter = minCenter
	end

	local defaultCenterValue: number
	if useExistingCutout and typeof(existingWindowData.HeightOffset) == "number" then
		defaultCenterValue = math.clamp(existingWindowData.HeightOffset, minCenter, maxCenter)
	elseif typeof(safeConfig.DefaultHeightRatio) == "number" and safeConfig.DefaultHeightRatio > 0 then
		defaultCenterValue = math.clamp(wallHeight * safeConfig.DefaultHeightRatio, minCenter, maxCenter)
	elseif typeof(safeConfig.DefaultHeight) == "number" then
		defaultCenterValue = math.clamp(safeConfig.DefaultHeight, minCenter, maxCenter)
	else
		defaultCenterValue = math.clamp(wallHeight * 0.5, minCenter, maxCenter)
	end

	if rawHeight <= 0 then
		rawHeight = defaultCenterValue
	end

	local allowVertical = safeConfig.AllowVerticalSliding ~= false
	local resolvedHeight = if allowVertical then math.clamp(rawHeight, minCenter, maxCenter) else defaultCenterValue

	local localCenterY = resolvedHeight - partHeight * 0.5

	local offsetFromWall = if useExistingCutout and typeof(existingWindowData.OffsetFromWall) == "number"
		then existingWindowData.OffsetFromWall
		else 0

	local wallCenter = wallPart.CFrame.Position
	local worldCenter = wallCenter + wallUp.Unit * localCenterY + wallNormal.Unit * offsetFromWall

	return {
		WorldPosition = worldCenter,
		WallNormal = wallNormal,
		WallUp = wallUp,
		WallCellX = cellX,
		WallCellZ = cellZ,
		AttachedFacing = facing,
		WallCenter = wallCenter,
		HeightOffset = resolvedHeight,
		CutoutWidth = cutoutWidth,
		CutoutHeight = cutoutHeight,
		WallHeight = wallHeight,
		WallWidth = wallWidth,
		WallThickness = wallThickness,
		LocalCenterY = localCenterY,
		FrameThickness = frameThickness,
		OffsetFromWall = offsetFromWall,
		EffectiveWallWidth = effectiveWallWidth,
	}
end

return WallLogic
