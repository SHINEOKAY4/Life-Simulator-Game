--!strict
-- ServerScriptService/Server/Utilities/WorldPlacer.lua

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotState = require(ServerScriptService.Server.Classes.PlotState)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)
local DoorWallFill = require(ReplicatedStorage.Shared.Utilities.DoorWallFill)

export type Facing = PlacementHelpers.Facing

local WorldPlacer = {}

local GetYawFromFacing = PlacementHelpers.GetYawFromFacing
local GetLiftFromPivotToBottom = PlacementHelpers.GetLiftFromPivotToBottom
local GetFlatAlignedCFrame = PlacementHelpers.GetFlatAlignedCFrame
local GetRotationOnly = PlacementHelpers.GetRotation
local GetPivotRotation = PlacementHelpers.GetPivotRotation
local GetLiftAlongDirection = PlacementHelpers.GetLiftAlongDirection

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
	options: SpawnOptions?
)
	local spec = ItemFinder.FindItemById(itemId)
	if not spec then
		return
	end

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
		base = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing)
		applyWallModelScaling(model, facing, grid.CellSize)
	elseif placementType == "Floor" then
		local center = grid:FootprintCenterCFrame(cellX, cellZ, footprintWidth, footprintDepth, facing)
		base = center * CFrame.Angles(0, GetYawFromFacing(facing), 0)
	elseif placementType == "CellObject" then
		local center = grid:FootprintCenterCFrame(cellX, cellZ, footprintWidth, footprintDepth, facing)
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
		-- ADDED: roof placement
		-- Rule: a roof is placed above the surface by a catalog-defined roof height, then seated by pivot-bottom.
		local center = grid:FootprintCenterCFrame(cellX, cellZ, footprintWidth, footprintDepth, facing)
		local yaw = CFrame.Angles(0, GetYawFromFacing(facing), 0)
		local roofLift = 0
		if typeof(spec.HeightStuds) == "number" then
			roofLift = spec.HeightStuds
		elseif typeof(extraLift) == "number" and extraLift ~= 0 then
			roofLift = extraLift
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
		DoorWallFill.Apply(model, spec, options)
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanTouch = false
			part.CanQuery = true
		end
	end
	local fromKey = PlotState:PlacementKeyForType(cellX, cellZ, facing, placementType)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local container = plotModel and plotModel:FindFirstChild("Container") :: Model

	model.Name = fromKey
	model.Parent = container
end

function WorldPlacer.Despawn(player: Player, itemId: string, cellX: number, cellZ: number, facing: Facing)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return
	end
	local container = plotModel:FindFirstChild("Container")
	if not container then
		return
	end

	local desiredFacing = tostring(facing)
	for _, inst in container:GetChildren() do
		if
			inst:GetAttribute("ItemId") == itemId
			and inst:GetAttribute("CellX") == cellX
			and inst:GetAttribute("CellZ") == cellZ
			and inst:GetAttribute("Facing") == desiredFacing
		then
			inst:Destroy()
			break
		end
	end
end

return WorldPlacer
