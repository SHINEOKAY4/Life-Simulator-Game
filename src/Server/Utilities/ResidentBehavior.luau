--!strict
-- ServerScriptService/Server/Utilities/ResidentBehavior.lua

local PathfindingService = game:GetService("PathfindingService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)
local GridClass = require(ReplicatedStorage.Shared.Utilities.Grid)
local ResidentState = require(ServerScriptService.Server.Classes.ResidentState)

local ResidentsFolder = ReplicatedStorage.Assets.Residents

local ResidentPlacer = {}

type Facing = PlacementHelpers.Facing

local VALID_FACINGS: { [string]: true } = {
	North = true,
	East = true,
	South = true,
	West = true,
}

local PlotGridCache = setmetatable({} :: { [Model]: any }, { __mode = "k" })

local function normalizeFacing(facingValue: any): Facing
	if typeof(facingValue) == "string" and VALID_FACINGS[facingValue] then
		return (facingValue :: any) :: Facing
	end
	return "North" :: Facing
end

local function getPlotGrid(plotModel: Model?): any?
	if not plotModel then
		return nil
	end

	local cached = PlotGridCache[plotModel]
	if cached then
		return cached
	end

	local surface = plotModel:FindFirstChild("Surface") :: BasePart?
	local cellSize = plotModel:GetAttribute("CellSize") :: number?
	if not surface or typeof(cellSize) ~= "number" then
		return nil
	end

	local success, gridOrError = pcall(GridClass.new, surface, cellSize)
	if not success then
		warn(
			('[ResidentBehavior] Failed to create grid for plot "%s": %s'):format(plotModel.Name, tostring(gridOrError))
		)
		return nil
	end

	local grid = gridOrError
	PlotGridCache[plotModel] = grid
	return grid
end

local function getSpecDimensions(spec: any?): (number, number)
	if not spec then
		return 1, 1
	end

	local width = tonumber(spec.WidthCells or spec.Width) or 1
	local depth = tonumber(spec.DepthCells or spec.Depth) or 1
	return width, depth
end

local function computeApproachPosition(plotModel: Model, stationModel: Model, rootY: number): Vector3?
	local grid = getPlotGrid(plotModel)
	if not grid then
		return nil
	end

	local cellX = stationModel:GetAttribute("CellX") :: number?
	local cellZ = stationModel:GetAttribute("CellZ") :: number?
	if typeof(cellX) ~= "number" or typeof(cellZ) ~= "number" then
		return nil
	end

	local itemId = stationModel:GetAttribute("ItemId")
	local spec = if typeof(itemId) == "string" then ItemFinder.FindItemById(itemId) else nil
	local widthCells, depthCells = getSpecDimensions(spec)

	local facing: Facing = normalizeFacing(stationModel:GetAttribute("Facing"))
	local okCenter, centerCFrameOrMessage =
		pcall(grid.FootprintCenterCFrame, grid, cellX, cellZ, widthCells, depthCells, facing)
	if not okCenter then
		warn(
			("[ResidentBehavior] Failed to resolve footprint center for %s: %s"):format(
				stationModel.Name,
				tostring(centerCFrameOrMessage)
			)
		)
		return nil
	end

	local centerCFrame = centerCFrameOrMessage :: CFrame
	local approachBase = centerCFrame * CFrame.Angles(0, PlacementHelpers.GetYawFromFacing(facing), 0)

	local rotatedDepthCells = if facing == "East" or facing == "West" then widthCells else depthCells
	local halfDepth = (rotatedDepthCells * grid.CellSize) * 0.5
	local approachPadding = math.max(grid.CellSize * 0.5, 1.5)
	local offsetDistance = halfDepth + approachPadding

	local frontPosition = approachBase.Position + approachBase.LookVector * offsetDistance
	return Vector3.new(frontPosition.X, rootY, frontPosition.Z)
end

function ResidentPlacer.SpawnResident(player: Player, residentData: ResidentState.ResidentData)
	-- Here you would typically create an NPC instance in the game world
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local spawnLocation = plotModel and plotModel:FindFirstChild("Spawn") :: BasePart
	local residentsFolder = plotModel and plotModel:FindFirstChild("Residents") :: Folder

	local residentModel = if residentData.Gender == "Male"
		then ResidentsFolder.Male:Clone()
		else ResidentsFolder.Female:Clone()
	residentModel.Name = residentData.Name
	residentModel.Parent = residentsFolder
	residentModel:PivotTo(spawnLocation.CFrame)
end

function ResidentPlacer.DespawnResident(player: Player, residentName: string)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local residentsFolder = plotModel and plotModel:FindFirstChild("Residents") :: Folder
	print(residentsFolder, residentsFolder:FindFirstChild(residentName))
	local residentModel = residentsFolder and residentsFolder:FindFirstChild(residentName) :: Model?
	if residentModel then
		residentModel:Destroy()
	else
		warn("Resident model not found for despawning: " .. residentName)
	end
end

--#TODO If the path is blocked or failed check if the player has the same station and attempt to go to that station instead then repeat until all options are exhausted
function ResidentPlacer.MoveToStation(player: Player, resident: string, targetStation: string)
	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local containerFolder = plotModel and plotModel:FindFirstChild("Container") :: Folder
	local residentsFolder = plotModel and plotModel:FindFirstChild("Residents") :: Folder
	local residentModel = residentsFolder and residentsFolder:FindFirstChild(resident) :: Model?
	if not residentModel then
		warn("Resident model not found for moving: " .. resident)
		return
	end

	local humanoid = residentModel:FindFirstChildOfClass("Humanoid") :: Humanoid?
	local rootPart = residentModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local targetStationModel = containerFolder and containerFolder:FindFirstChild(targetStation) :: Model?
	if not targetStationModel or not ItemFinder.IsStationModel(targetStationModel.Name) then
		warn("Target station not found or invalid: " .. targetStation)
		return
	end
	if not rootPart then
		warn("HumanoidRootPart not found in resident model: " .. resident)
		return
	end
	if not humanoid then
		warn("Humanoid not found in resident model: " .. resident)
		return
	end

	local target = targetStationModel.PrimaryPart
	if not target then
		warn("Target station has no PrimaryPart: " .. targetStation)
		return
	end

	local desiredPosition = computeApproachPosition(plotModel, targetStationModel, rootPart.Position.Y)
	local goalPosition = desiredPosition or target.Position

	local function follow(goal: Vector3): boolean
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
		})

		path:ComputeAsync(rootPart.Position, goal)

		if path.Status ~= Enum.PathStatus.Success then
			return false
		end

		for _, waypoint in ipairs(path:GetWaypoints()) do
			humanoid:MoveTo(waypoint.Position)
			local reached = humanoid.MoveToFinished:Wait()
			if not reached then
				return false
			end
		end

		return true
	end

	if not follow(goalPosition) then
		if desiredPosition then
			warn(
				("[ResidentBehavior] Path failed for %s when approaching %s offset; retrying direct target"):format(
					residentModel.Name,
					targetStation
				)
			)
		end
		if not follow(target.Position) then
			warn("[ResidentBehavior] Path failed for " .. residentModel.Name)
		end
	end
end

return ResidentPlacer
