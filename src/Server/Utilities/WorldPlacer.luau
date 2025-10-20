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
	end

	local base: CFrame
	local target: CFrame?
	if placementType == "Wall" then
		base = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing)
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
		if inst:GetAttribute("ItemId") == itemId 
			and inst:GetAttribute("CellX") == cellX 
			and inst:GetAttribute("CellZ") == cellZ 
			and inst:GetAttribute("Facing") == desiredFacing then
			inst:Destroy()
			break
		end
	end
end

return WorldPlacer
