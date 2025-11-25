--!strict
-- Handles Sims-style cutaway visibility when upgrade/utility modes are active

local Players = game:GetService("Players")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local PlotBuilderUI = require(script.Parent.Parent.UserInterface.PlotBuilderUI)
local UtilityVisuals = require(script.Parent.UtilityVisuals)
type PlacementRoomCoverageRecord = PlotStateStore.PlacementRoomCoverageRecord

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ActiveQueryFolder = PlayerGui:WaitForChild("ActiveQuery")

local CutawayController = {}

local isEnabled = false
local initialized = false
local CUTAWAY_FORCE_SOURCE = "UpgradeCutaway"
local appliedParts: { [BasePart]: number } = {}
local queryOverrides: { [BasePart]: boolean } = {}

local WALL_INTERIOR_TRANSPARENCY = 0.35
local WALL_EXTERIOR_TRANSPARENCY = 0.55
local OBJECT_TRANSPARENCY = 0.25
local CEILING_TRANSPARENCY = 0.48
local DEFAULT_TRANSPARENCY = 0.4

local function resolveCutawayValue(): BoolValue
	local value = ActiveQueryFolder:FindFirstChild("CutawayVisible")
	if value and value:IsA("BoolValue") then
		return value
	end
	local created = Instance.new("BoolValue")
	created.Name = "CutawayVisible"
	created.Value = false
	created.Parent = ActiveQueryFolder
	return created
end

local CutawayVisibleValue = resolveCutawayValue()

local function setCutawayVisible(value: boolean)
	if CutawayVisibleValue.Value ~= value then
		CutawayVisibleValue.Value = value
	end
end

local function trackTouchedPart(part: BasePart, targetTransparency: number, touched: { [BasePart]: boolean })
	touched[part] = true
	local stored = appliedParts[part]
	if stored == nil then
		appliedParts[part] = part.LocalTransparencyModifier
	end
	local resolved = math.clamp(targetTransparency, 0, 1)
	local desired = math.max(part.Transparency, resolved)
	if part.LocalTransparencyModifier ~= desired then
		part.LocalTransparencyModifier = desired
	end
end

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

local function clearOverrides()
	for part, original in pairs(appliedParts) do
		if original ~= nil then
			local ok = pcall(function()
				part.LocalTransparencyModifier = original
			end)
			if not ok then
				-- Part may have been removed; ignore
			end
		end
		appliedParts[part] = nil
	end
end

local function cleanupUntouched(touched: { [BasePart]: boolean })
	for part, original in pairs(appliedParts) do
		if not touched[part] or part.Parent == nil then
			local ok = pcall(function()
				part.LocalTransparencyModifier = original
			end)
			if not ok then
				-- Silently ignore destroyed parts
			end
			appliedParts[part] = nil
		end
	end
end

local function applyToInstance(instance: Instance, targetTransparency: number, touched: { [BasePart]: boolean })
	if targetTransparency <= 0 then
		return
	end

	forEachBasePart(instance, function(part)
		trackTouchedPart(part, targetTransparency, touched)
	end)
end

local function setPartQueryState(part: BasePart, shouldDisable: boolean, touched: { [BasePart]: boolean })
	if shouldDisable then
		touched[part] = true
		local stored = queryOverrides[part]
		if stored == nil then
			queryOverrides[part] = part.CanQuery
		end
		if part.CanQuery then
			part.CanCollide = false
			part.CanQuery = false
		end
		return
	end

	local stored = queryOverrides[part]
	if stored == nil then
		return
	end
	touched[part] = true
	queryOverrides[part] = nil
	if part.CanQuery ~= stored then
		part.CanQuery = stored
		part.CanCollide = stored
	end
end

local function applyQueryToInstance(instance: Instance, disable: boolean, touched: { [BasePart]: boolean })
	forEachBasePart(instance, function(part)
		setPartQueryState(part, disable, touched)
	end)
end

local function cleanupQueryOverrides(touched: { [BasePart]: boolean }?)
	if not touched then
		for part, original in pairs(queryOverrides) do
			local ok = pcall(function()
				part.CanQuery = original
			end)
			if not ok then
				-- Ignore parts that were removed while disabled
			end
			queryOverrides[part] = nil
		end
		return
	end

	for part, original in pairs(queryOverrides) do
		if part.Parent == nil or not touched[part] then
			local ok = pcall(function()
				part.CanQuery = original
			end)
			if not ok then
				-- Ignore parts that were removed while disabled
			end
			queryOverrides[part] = nil
		end
	end
end

local function resolvePlacementType(entry: any, instance: Instance?): string
	local placementType = entry and (entry.PlacementType or entry.placementType)
	if typeof(placementType) == "string" and placementType ~= "" then
		return placementType :: string
	end
	if instance then
		local attr = instance:GetAttribute("PlacementType")
		if typeof(attr) == "string" and attr ~= "" then
			return attr
		end
	end
	return "CellObject"
end

local function resolvePlacementLevel(entry: any, instance: Instance?): number
	local levelValue = entry and (entry.Level or entry.level)
	if typeof(levelValue) == "number" then
		return levelValue
	end
	if instance then
		local attr = instance:GetAttribute("Level")
		if typeof(attr) == "number" then
			return attr
		end
	end
	return PlotStateStore.GetDefaultLevel()
end

local function shouldHideDifferentLevel(placementType: string, placementLevel: number, activeLevel: number): boolean
	if placementType == "Roof" then
		return placementLevel >= activeLevel
	end
	if placementType == "Floor" then
		return placementLevel > activeLevel
	end
	return false
end

local function resolveTargetTransparency(
	placementType: string,
	placementLevel: number,
	activeLevel: number,
	coverage: PlacementRoomCoverageRecord?
): number?
	if shouldHideDifferentLevel(placementType, placementLevel, activeLevel) then
		return 1
	end

	if placementLevel ~= activeLevel then
		return nil
	end

	if placementType == "Floor" then
		return nil -- keep current floor opaque for player readability
	elseif placementType == "Wall" then
		local hasOutdoor = coverage ~= nil and coverage.HasOutdoorCells == true
		local hasRooms = coverage ~= nil and coverage.RoomIds ~= nil and next(coverage.RoomIds) ~= nil
		if hasOutdoor then
			return WALL_EXTERIOR_TRANSPARENCY
		end
		if hasRooms then
			return WALL_INTERIOR_TRANSPARENCY
		end
		return DEFAULT_TRANSPARENCY
	elseif placementType == "CellObject" or placementType == "WallMounted" then
		return OBJECT_TRANSPARENCY
	elseif placementType == "SurfaceMounted" then
		return math.max(OBJECT_TRANSPARENCY, 0.3)
	elseif placementType == "Ceiling" then
		return CEILING_TRANSPARENCY
	elseif placementType == "Roof" then
		return 1
	elseif placementType == "Stairs" then
		return 0.3
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
			return
		end

		local placementType = resolvePlacementType(entry, instance)
		local placementLevel = resolvePlacementLevel(entry, instance)
		local disableQuery = placementLevel > activeLevel
		applyQueryToInstance(instance, disableQuery, queryTouched)

		if not transparencyTouched then
			return
		end

		local coverage = PlotStateStore.GetPlacementRoomCoverage(key)
		local target = resolveTargetTransparency(placementType, placementLevel, activeLevel, coverage)
		if target then
			applyToInstance(instance, target, transparencyTouched)
		end
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
