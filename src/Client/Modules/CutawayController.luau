--!strict
-- Handles Sims-style cutaway visibility when upgrade/utility modes are active

local Players = game:GetService("Players")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local PlotBuilderUI = require(script.Parent.Parent.UserInterface.PlotBuilderUI)
local UtilityVisuals = require(script.Parent.UtilityVisuals)
type PlacementRoomCoverageRecord = PlotStateStore.PlacementRoomCoverageRecord

-- Constants
local CUTAWAY_FORCE_SOURCE = "UpgradeCutaway"
local WALL_INTERIOR_TRANSPARENCY = 0.35
local WALL_EXTERIOR_TRANSPARENCY = 0.55
local OBJECT_TRANSPARENCY = 0.25
local CEILING_TRANSPARENCY = 0.48
local DEFAULT_TRANSPARENCY = 0.4
local STAIRS_TRANSPARENCY = 0.3
local SURFACE_MOUNTED_MIN_TRANSPARENCY = 0.3

-- Initialization
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ActiveQueryFolder = PlayerGui:WaitForChild("ActiveQuery")

-- State tracking
local isEnabled = false
local initialized = false
local appliedParts: { [BasePart]: number } = {}
local queryOverrides: { [BasePart]: boolean } = {}

-- Helper function to create or retrieve BoolValue
local function getOrCreateBoolValue(parent: Instance, name: string, defaultValue: boolean): BoolValue
	local value = parent:FindFirstChild(name)
	if value and value:IsA("BoolValue") then
		return value
	end
	local created = Instance.new("BoolValue")
	created.Name = name
	created.Value = defaultValue
	created.Parent = parent
	return created
end

local ceilingPlacementActive = getOrCreateBoolValue(ActiveQueryFolder, "CeilingPlacementActive", false)
local CutawayVisibleValue = getOrCreateBoolValue(ActiveQueryFolder, "CutawayVisible", false)

local CutawayController = {}

local function setCutawayVisible(value: boolean)
	if CutawayVisibleValue.Value ~= value then
		CutawayVisibleValue.Value = value
	end
end

-- Utility: Iterate through all BaseParts in an instance
local function forEachBasePart(instance: Instance, handler: (BasePart) -> ())
	if instance:IsA("BasePart") then
		handler(instance)
		return
	end
	for _, descendant in ipairs(instance:GetDescendants()) do
		if descendant:IsA("BasePart") then
			handler(descendant)
		end
	end
end

-- Safely restore a part's property with error handling
local function safeRestoreProperty(restoreFunc: () -> ())
	pcall(restoreFunc)
end

-- Transparency Management
local function trackTouchedPart(part: BasePart, targetTransparency: number, touched: { [BasePart]: boolean })
	touched[part] = true

	-- Store original transparency if not already stored
	if appliedParts[part] == nil then
		appliedParts[part] = part.LocalTransparencyModifier
	end

	local clampedTransparency = math.clamp(targetTransparency, 0, 1)
	local desiredTransparency = math.max(part.Transparency, clampedTransparency)

	if part.LocalTransparencyModifier ~= desiredTransparency then
		part.LocalTransparencyModifier = desiredTransparency
	end
end

local function clearOverrides()
	for part, originalTransparency in pairs(appliedParts) do
		if originalTransparency ~= nil then
			safeRestoreProperty(function()
				part.LocalTransparencyModifier = originalTransparency
			end)
		end
		appliedParts[part] = nil
	end
end

local function cleanupUntouched(touched: { [BasePart]: boolean })
	for part, originalTransparency in pairs(appliedParts) do
		if not touched[part] or part.Parent == nil then
			safeRestoreProperty(function()
				part.LocalTransparencyModifier = originalTransparency
			end)
			appliedParts[part] = nil
		end
	end
end

local function applyTransparencyToInstance(
	instance: Instance,
	targetTransparency: number,
	touched: { [BasePart]: boolean }
)
	if targetTransparency <= 0 then
		return
	end

	forEachBasePart(instance, function(part)
		trackTouchedPart(part, targetTransparency, touched)
	end)
end

-- Query State Management
local function setPartQueryState(part: BasePart, shouldDisable: boolean, touched: { [BasePart]: boolean })
	touched[part] = true

	if shouldDisable then
		-- Store original state and disable
		if queryOverrides[part] == nil then
			queryOverrides[part] = part.CanQuery
		end
		if part.CanQuery then
			part.CanCollide = false
			part.CanQuery = false
		end
	else
		-- Restore original state
		local originalCanQuery = queryOverrides[part]
		if originalCanQuery ~= nil then
			queryOverrides[part] = nil
			if part.CanQuery ~= originalCanQuery then
				part.CanQuery = originalCanQuery
				part.CanCollide = originalCanQuery
			end
		end
	end
end

local function applyQueryToInstance(instance: Instance, disable: boolean, touched: { [BasePart]: boolean })
	forEachBasePart(instance, function(part)
		setPartQueryState(part, disable, touched)
	end)
end

local function cleanupQueryOverrides(touched: { [BasePart]: boolean }?)
	for part, originalCanQuery in pairs(queryOverrides) do
		local shouldCleanup = not touched or part.Parent == nil or not touched[part]
		if shouldCleanup then
			safeRestoreProperty(function()
				part.CanQuery = originalCanQuery
			end)
			queryOverrides[part] = nil
		end
	end
end

-- Placement Property Resolvers
local function resolvePlacementType(entry: any, instance: Instance?): string
	-- Try entry properties first
	if entry then
		local placementType = entry.PlacementType or entry.placementType
		if typeof(placementType) == "string" and placementType ~= "" then
			return placementType
		end
	end

	-- Fall back to instance attribute
	if instance then
		local attr = instance:GetAttribute("PlacementType")
		if typeof(attr) == "string" and attr ~= "" then
			return attr
		end
	end

	return "CellObject"
end

local function resolvePlacementLevel(entry: any, instance: Instance?): number
	-- Try entry properties first
	if entry then
		local levelValue = entry.Level or entry.level
		if typeof(levelValue) == "number" then
			return levelValue
		end
	end

	-- Fall back to instance attribute
	if instance then
		local attr = instance:GetAttribute("Level")
		if typeof(attr) == "number" then
			return attr
		end
	end

	return PlotStateStore.GetDefaultLevel()
end

local function shouldHideDifferentLevel(placementType: string, placementLevel: number, activeLevel: number): boolean
	-- Hide everything above the active level for clean cutaway view
	-- Special handling for floor-level objects

	-- Roofs: Hide at or above active level
	if placementType == "Roof" then
		return placementLevel >= activeLevel
	end

	-- Floors: Hide above active level
	if placementType == "Floor" then
		return placementLevel > activeLevel
	end

	-- Walls: Hide above active level to prevent view obstruction
	if placementType == "Wall" then
		return placementLevel > activeLevel
	end

	-- All other objects (CellObject, WallMounted, SurfaceMounted, Ceiling, Stairs): Hide above active level
	if placementLevel > activeLevel then
		return true
	end

	return false
end

-- Transparency Calculation
local function resolveTargetTransparency(
	placementType: string,
	placementLevel: number,
	activeLevel: number,
	coverage: PlacementRoomCoverageRecord?
): number?
	-- Hide objects on different levels
	if shouldHideDifferentLevel(placementType, placementLevel, activeLevel) then
		return 1
	end

	-- Only apply transparency to active level
	if placementLevel ~= activeLevel then
		return nil
	end

	-- Type-specific transparency rules
	if placementType == "Floor" then
		return nil -- Keep floors opaque for player readability
	elseif placementType == "Wall" then
		local hasOutdoor = coverage and coverage.HasOutdoorCells == true
		local hasRooms = coverage and coverage.RoomIds and next(coverage.RoomIds) ~= nil

		if hasOutdoor then
			return WALL_EXTERIOR_TRANSPARENCY
		elseif hasRooms then
			return WALL_INTERIOR_TRANSPARENCY
		else
			return DEFAULT_TRANSPARENCY
		end
	elseif placementType == "CellObject" or placementType == "WallMounted" then
		return OBJECT_TRANSPARENCY
	elseif placementType == "SurfaceMounted" then
		return math.max(OBJECT_TRANSPARENCY, SURFACE_MOUNTED_MIN_TRANSPARENCY)
	elseif placementType == "Ceiling" then
		return CEILING_TRANSPARENCY
	elseif placementType == "Roof" then
		return 1
	elseif placementType == "Stairs" then
		return STAIRS_TRANSPARENCY
	end

	return DEFAULT_TRANSPARENCY
end

local function applyPlacementAdjustments()
	if not PlotStateStore.IsReady() then
		cleanupQueryOverrides(nil)
		clearOverrides()
		return
	end

	local container = PlotStateStore.GetPlotContainer()
	if not container then
		cleanupQueryOverrides(nil)
		clearOverrides()
		return
	end

	local activeLevel = PlotStateStore.GetActiveLevel()
	local queryTouched: { [BasePart]: boolean } = {}
	local transparencyTouched: { [BasePart]: boolean }? = if isEnabled then {} else nil

	PlotStateStore.IteratePlacements(function(key: string, entry: any)
		local instance = container:FindFirstChild(key)
		if not instance then
			return nil
		end

		local placementType = resolvePlacementType(entry, instance)
		local placementLevel = resolvePlacementLevel(entry, instance)
		local disableQuery = placementLevel > activeLevel
		applyQueryToInstance(instance, disableQuery, queryTouched)

		if not transparencyTouched then
			return nil
		end

		local coverage = PlotStateStore.GetPlacementRoomCoverage(key)
		local targetTransparency = resolveTargetTransparency(placementType, placementLevel, activeLevel, coverage)
		if targetTransparency then
			applyTransparencyToInstance(instance, targetTransparency, transparencyTouched)
		end

		return nil
	end)

	cleanupQueryOverrides(queryTouched)
	if transparencyTouched then
		cleanupUntouched(transparencyTouched)
	end
end

local function enable()
	if isEnabled then
		return
	end
	isEnabled = true
	setCutawayVisible(true)
	UtilityVisuals.SetForceShow(true, CUTAWAY_FORCE_SOURCE)
	applyPlacementAdjustments()
end

local function disable()
	if not isEnabled then
		return
	end
	isEnabled = false
	UtilityVisuals.SetForceShow(false, CUTAWAY_FORCE_SOURCE)
	setCutawayVisible(false)
	clearOverrides()
	applyPlacementAdjustments()
end

local function hookSignals()
	PlotBuilderUI.OnUpgradeViewChanged(function(active)
		if active then
			enable()
		else
			disable()
		end
	end)

	PlotStateStore.OnActiveLevelChanged(function()
		applyPlacementAdjustments()
	end)

	PlotStateStore.OnRoomSnapshotChanged(function()
		applyPlacementAdjustments()
	end)

	PlotStateStore.OnPlacementMetadataChanged(function()
		applyPlacementAdjustments()
	end)

	ceilingPlacementActive.Changed:Connect(function()
		-- When ceiling placement mode changes, refresh cutaway to show/hide roofs and upper floors
		applyPlacementAdjustments()
	end)
end

function CutawayController.Init()
	if initialized then
		return
	end
	initialized = true
	setCutawayVisible(false)
	hookSignals()
	if PlotBuilderUI.IsUpgradeViewActive() then
		enable()
	end
	applyPlacementAdjustments()
end

return CutawayController
