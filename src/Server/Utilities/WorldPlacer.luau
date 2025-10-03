--!strict
-- ServerScriptService/Server/Utilities/WorldPlacer.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)

export type Facing = PlacementHelpers.Facing

local WorldPlacer = {}

local GetYawFromFacing = PlacementHelpers.GetYawFromFacing
local GetLiftFromPivotToBottom = PlacementHelpers.GetLiftFromPivotToBottom

-- Spawn a physical model for a saved/placed item. -- Added
function WorldPlacer.Spawn(player: Player, grid: any, itemId: string, cellX: number, cellZ: number, facing: Facing)
	local spec = ItemFinder.FindItemById(itemId)
	if not spec then
		return
	end

	local placementType = spec.PlacementType or "CellObject"
	local footprintWidth = spec.WidthCells or spec.Width or 1
	local footprintDepth = spec.DepthCells or spec.Depth or 1

	local model = ItemFinder.CloneModel(itemId)
	if not model then
		return
	end
	model:SetAttribute("ItemId", itemId)
	model:SetAttribute("CellX", cellX)
	model:SetAttribute("CellZ", cellZ)
	model:SetAttribute("Facing", tostring(facing))

	local base: CFrame
	if placementType == "Wall" then
		base = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing)
	elseif placementType == "Floor" or placementType == "CellObject" then
		local center = grid:FootprintCenterCFrame(cellX, cellZ, footprintWidth, footprintDepth, facing)
		base = center * CFrame.Angles(0, GetYawFromFacing(facing), 0)
	elseif placementType == "Roof" then
		-- ADDED: roof placement
		-- Rule: a roof is placed above the surface by a catalog-defined roof height, then seated by pivot-bottom.
		local center = grid:FootprintCenterCFrame(cellX, cellZ, footprintWidth, footprintDepth, facing)
		local yaw = CFrame.Angles(0, GetYawFromFacing(facing), 0)
		local roofY = spec.HeightStuds -- studs above the plot surface plane
		base = (center * yaw) * CFrame.new(0, roofY, 0)
	end

	if placementType == "Floor" or placementType == "Roof" then
		model:PivotTo(base)
	else
		model:PivotTo(base * CFrame.new(0, GetLiftFromPivotToBottom(model), 0))
	end

	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanTouch = false
			part.CanQuery = true
		end
	end

	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local container = plotModel and plotModel:FindFirstChild("Container") :: Model
	model.Parent = container
end

function WorldPlacer.Despawn(player: Player, itemId: string, cellX: number, cellZ: number, facing: Facing)
	local desiredFacing = tostring(facing)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return
	end
	local container = plotModel:FindFirstChild("Container")
	if not container then
		return
	end

	for _, inst in container:GetChildren() do
		local matchesItem = inst:GetAttribute("ItemId") == itemId
		local matchesCellX = inst:GetAttribute("CellX") == cellX
		local matchesCellZ = inst:GetAttribute("CellZ") == cellZ
		local matchesFacing = inst:GetAttribute("Facing") == desiredFacing

		if matchesItem and matchesCellX and matchesCellZ and matchesFacing then
			inst:Destroy()
			break
		end
	end
end

return WorldPlacer
