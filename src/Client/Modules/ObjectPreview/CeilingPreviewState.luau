--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlotStateStore = require(script.Parent.Parent.Parent:WaitForChild("ClientStores"):WaitForChild("PlotStateStore"))
local Types = require(script.Parent.Types)

type PlacementFacing = "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest"

local CeilingPreviewState = {}

local dropMin = 0
local dropMax = 0
local defaultDrop = 0
local rotationStep = math.rad(15)
local currentRotation = 0
local currentDrop = 0
local TAU = math.pi * 2

local function resolveCeilingMountConfig(spec: any?): (number, number, number, number)
	local minDrop = 0
	local maxDrop = minDrop + 6
	local defaultDropValue = minDrop
	local rotationStepDegrees = 15
	if typeof(spec) == "table" then
		local config = spec.CeilingMountConfig
		if typeof(config) == "table" then
			if typeof(config.MinDropStuds) == "number" then
				minDrop = math.max(config.MinDropStuds, 0)
			end
			if typeof(config.MaxDropStuds) == "number" then
				maxDrop = math.max(config.MaxDropStuds, minDrop + 0.1)
			end
			if typeof(config.DefaultDropStuds) == "number" then
				defaultDropValue = config.DefaultDropStuds
			end
			if typeof(config.RotationStepDegrees) == "number" and config.RotationStepDegrees > 0 then
				rotationStepDegrees = config.RotationStepDegrees
			end
		end
	end
	if maxDrop < minDrop + 0.1 then
		maxDrop = minDrop + 0.1
	end
	defaultDropValue = math.clamp(defaultDropValue, minDrop, maxDrop)
	local rotationStepRadians = math.rad(rotationStepDegrees)
	if rotationStepRadians <= 0 then
		rotationStepRadians = math.rad(15)
	end
	return minDrop, maxDrop, defaultDropValue, rotationStepRadians
end

function CeilingPreviewState.Initialize(spec: any?)
	dropMin, dropMax, defaultDrop, rotationStep = resolveCeilingMountConfig(spec)
	currentDrop = defaultDrop
	currentRotation = 0
end

function CeilingPreviewState.Reset()
	dropMin = 0
	dropMax = 0
	defaultDrop = 0
	rotationStep = math.rad(15)
	currentDrop = 0
	currentRotation = 0
end

local function clampDrop(value: number): number
	return math.clamp(value, dropMin, dropMax)
end

function CeilingPreviewState.Rotate(step: number)
	local delta = rotationStep
	if delta <= 0 then
		delta = math.rad(15)
	end
	currentRotation = (currentRotation + delta * step) % TAU
end

function CeilingPreviewState.GetRotation(): number
	return currentRotation
end

function CeilingPreviewState.SetDrop(value: number)
	currentDrop = clampDrop(value)
end

function CeilingPreviewState.GetDrop(): number
	return currentDrop
end

local function resolveNormal(surface: BasePart, hitResult: RaycastResult?): Vector3
	local fallbackNormal = -surface.CFrame.UpVector.Unit
	if fallbackNormal.Magnitude < 1e-3 then
		fallbackNormal = Vector3.new(0, -1, 0)
	else
		fallbackNormal = fallbackNormal.Unit
	end

	if not hitResult then
		return fallbackNormal
	end

	local candidate = hitResult.Normal
	if candidate.Magnitude < 1e-3 then
		return fallbackNormal
	end

	local unitCandidate = candidate.Unit
	local alignment = unitCandidate:Dot(fallbackNormal)
	if alignment >= 0.1 then
		return unitCandidate
	end

	if (-unitCandidate):Dot(fallbackNormal) >= 0.1 then
		return (-unitCandidate).Unit
	end

	return fallbackNormal
end

function CeilingPreviewState.ComputePose(
	grid: any,
	surface: BasePart,
	hitResult: RaycastResult?,
	cellX: number,
	cellZ: number,
	facing: Types.PreviewFacing,
	level: number,
	snapshot: any
): Types.CeilingMountPose?
	if not grid or not surface then
		return nil
	end

	local resolvedCellX = math.floor(cellX + 0.5)
	local resolvedCellZ = math.floor(cellZ + 0.5)
	if not grid:IsCellInBounds(resolvedCellX, resolvedCellZ) then
		return nil
	end
	if not PlotStateStore.IsCellUnlocked(resolvedCellX, resolvedCellZ) then
		return nil
	end

	local snapshotData = snapshot or PlotStateStore.GetStateSnapshot()
	local placedItems = snapshotData and snapshotData.PlacedItems or nil
	local normalizedFacing: PlacementFacing = PlacementKey.NormalizeFacing(facing :: any)
	local placementKey = PlacementKey.ForPlacementType(resolvedCellX, resolvedCellZ, normalizedFacing, "Ceiling", level)
	local occupied = placedItems and placedItems[placementKey] ~= nil
	local hasSupport = PlotStateStore.HasCeilingSupport(level, resolvedCellX, resolvedCellZ)
	local canPlace = hasSupport and not occupied

	local floorHeight = PlotStateStore.GetFloorHeightStuds()
	local anchorLevel = level + 1
	local baseCFrame = grid:FootprintCenterCFrame(resolvedCellX, resolvedCellZ, 1, 1, "North")
	local anchorCFrame = baseCFrame * CFrame.new(0, anchorLevel * floorHeight, 0)

	local supportHeight = anchorCFrame.Position.Y
	local snapTolerance = math.max(floorHeight * 0.5, 0.5)
	if hitResult then
		local candidateHeight = hitResult.Position.Y
		if math.abs(candidateHeight - supportHeight) <= snapTolerance then
			supportHeight = candidateHeight
		end
	end

	local dropStuds = clampDrop(currentDrop)
	local resolvedNormal = resolveNormal(surface, hitResult)
	local supportPosition = Vector3.new(anchorCFrame.Position.X, supportHeight, anchorCFrame.Position.Z)
	local worldPosition = supportPosition + resolvedNormal * dropStuds

	return {
		CellX = resolvedCellX,
		CellZ = resolvedCellZ,
		Level = level,
		Facing = normalizedFacing :: Types.PreviewFacing,
		DropStuds = dropStuds,
		RotationY = currentRotation,
		WorldPosition = worldPosition,
		CeilingNormal = resolvedNormal,
		CanPlace = canPlace,
	}
end

return CeilingPreviewState
