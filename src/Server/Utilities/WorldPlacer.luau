--!strict
-- ServerScriptService/Server/Utilities/WorldPlacer.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

export type Facing = "North" | "East" | "South" | "West"

local WorldPlacer = {}

local function yawFromFacing(f: Facing): number -- Added
	if f == "East" then
		return math.rad(90)
	end
	if f == "South" then
		return math.rad(180)
	end
	if f == "West" then
		return math.rad(270)
	end
	return 0
end

local function liftFromPivotToBottom(model: Model): number -- Added
	local bboxCFrame, bboxSize = model:GetBoundingBox()
	local pivotCFrame = model:GetPivot()
	local pivotLocal = bboxCFrame:PointToObjectSpace(pivotCFrame.Position)
	return (bboxSize.Y * 0.5) + pivotLocal.Y
end

-- Spawn a physical model for a saved/placed item. -- Added
function WorldPlacer.Spawn(player: Player, grid: any, itemId: string, cellX: number, cellZ: number, facing: Facing)
	local template = ItemFinder.ResolveItemModel(itemId)
	if not template then
		return
	end

	local spec = ItemFinder.FindItemById(itemId)
	if not spec then
		return
	end

	local placementType = spec.PlacementType or "CellObject"

	local model = template:Clone()
	model.Name = itemId

	local base: CFrame
	if placementType == "Wall" then
		base = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing)
	elseif placementType == "Floor" or placementType == "CellObject" then
		-- Floors are 1x1; apply facing yaw only for visual texture direction
		base = grid:CellToWorldCenterCFrame(cellX, cellZ) * CFrame.Angles(0, yawFromFacing(facing), 0)
	end

	if placementType == "Floor" then
		model:PivotTo(base)
	else
		model:PivotTo(base * CFrame.new(0, liftFromPivotToBottom(model), 0))
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

return WorldPlacer
