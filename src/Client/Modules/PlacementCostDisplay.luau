--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local Player = Players.LocalPlayer or Players.PlayerAdded:Wait()
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotBuilderGui = PlayerGui:WaitForChild("PlotBuilderGui")

local PlacementCostDisplay = {}

local CASH_OPTIONS = {
	currencySymbol = "$",
	decimalPlaces = 0,
	useCommas = true,
}

local UNIT_LABELS = {
	Floor = { singular = "tile", plural = "tiles" },
	Roof = { singular = "tile", plural = "tiles" },
	Wall = { singular = "segment", plural = "segments" },
	WallMounted = { singular = "installation", plural = "installations" },
	SurfaceMounted = { singular = "placement", plural = "placements" },
	Ceiling = { singular = "fixture", plural = "fixtures" },
}

local TEXT_COLORS = {
	blocked = Color3.fromRGB(255, 118, 118),
	unauthorized = Color3.fromRGB(255, 205, 98),
	allowed = Color3.fromRGB(178, 255, 214),
}

local TEXT_STROKE_COLOR = Color3.new(0, 0, 0)
local TEXT_STROKE_TRANSPARENCY = 0.18
local MAX_DISPLAY_DISTANCE = 512

local billboard: BillboardGui? = nil
local textLabel: TextLabel? = nil
local adornPart: BasePart? = nil

local lastKind: string? = nil
local lastItemId: string? = nil
local lastTotalCost: number? = nil
local lastUnitCount: number? = nil
local lastCanPlace: boolean? = nil
local lastCanAfford: boolean? = nil
local lastWorldPosition: Vector3? = nil
local lastVisible = false

local function ensureGui()
	if billboard then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "PlacementCostAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Parent = Workspace
	adornPart = anchor

	local billboardGui = Instance.new("BillboardGui")
	billboardGui.Name = "PlacementCostBillboard"
	billboardGui.AlwaysOnTop = true
	billboardGui.Enabled = false
	billboardGui.ResetOnSpawn = false
	billboardGui.LightInfluence = 0
	billboardGui.MaxDistance = MAX_DISPLAY_DISTANCE
	billboardGui.Size = UDim2.fromOffset(220, 62)
	billboardGui.Adornee = anchor
	billboardGui.Parent = PlotBuilderGui

	local label = Instance.new("TextLabel")
	label.Name = "CostText"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Font = Enum.Font.GothamMedium
	label.RichText = false
	label.TextScaled = false
	label.TextWrapped = true
	label.TextSize = 18
	label.TextColor3 = TEXT_COLORS.allowed
	label.TextStrokeColor3 = TEXT_STROKE_COLOR
	label.TextStrokeTransparency = TEXT_STROKE_TRANSPARENCY
	label.Text = ""
	label.ZIndex = 1
	label.Parent = billboardGui

	billboard = billboardGui
	textLabel = label
end

local function formatCurrency(value: number): string
	return Formatter.formatCurrency(value, CASH_OPTIONS)
end

local function formatUnits(kind: string, unitCount: number): string
	local labels = UNIT_LABELS[kind]
	if not labels then
		labels = { singular = "unit", plural = "units" }
	end
	local label = if unitCount == 1 then labels.singular else labels.plural
	return string.format("%d %s", unitCount, label)
end

local function resolveItemName(itemId: string?): string
	if typeof(itemId) ~= "string" or itemId == "" then
		return "Item"
	end
	local spec = ItemFinder.FindItemById(itemId)
	local displayName = spec and spec.Name
	if typeof(displayName) == "string" and displayName ~= "" then
		return displayName
	end
	return itemId
end

local function resolveUnitCost(itemId: string?): number?
	if typeof(itemId) ~= "string" or itemId == "" then
		return nil
	end
	local spec = ItemFinder.FindItemById(itemId)
	local costValue = spec and spec.Cost
	if typeof(costValue) ~= "number" then
		return nil
	end
	return costValue
end

local function updateVisualState(canPlace: boolean, canAfford: boolean)
	if not textLabel then
		return
	end

	local color = TEXT_COLORS.allowed
	if not canPlace then
		color = TEXT_COLORS.blocked
	elseif not canAfford then
		color = TEXT_COLORS.unauthorized
	end

	textLabel.TextColor3 = color
end

local function setVisible(visible: boolean)
	if lastVisible == visible then
		return
	end
	lastVisible = visible
	if billboard then
		billboard.Enabled = visible
	end
end

local function updateCostDisplay(
	kind: string,
	itemId: string?,
	unitCount: number,
	canPlace: boolean,
	worldPosition: Vector3?
)
	ensureGui()
	if not billboard or not textLabel or not adornPart then
		return
	end

	if unitCount <= 0 or not worldPosition then
		setVisible(false)
		return
	end

	local unitCost = resolveUnitCost(itemId)
	if not unitCost then
		setVisible(false)
		return
	end

	local totalCost = unitCost * unitCount
	local playerCash = Player:GetAttribute("Cash")
	local cashBalance = if typeof(playerCash) == "number" then playerCash else 0
	local canAfford = totalCost <= cashBalance

	adornPart.CFrame = CFrame.new(worldPosition)

	local samePosition = false
	if lastWorldPosition then
		samePosition = (lastWorldPosition - worldPosition).Magnitude < 0.01
	end

	if
		lastKind == kind
		and lastItemId == itemId
		and lastTotalCost == totalCost
		and lastUnitCount == unitCount
		and lastCanPlace == canPlace
		and lastCanAfford == canAfford
		and samePosition
	then
		setVisible(true)
		return
	end

	lastKind = kind
	lastItemId = itemId
	lastTotalCost = totalCost
	lastUnitCount = unitCount
	lastCanPlace = canPlace
	lastCanAfford = canAfford
	lastWorldPosition = worldPosition

	local costText = formatCurrency(totalCost)
	local details = string.format("%s • %s", formatUnits(kind, unitCount), resolveItemName(itemId))
	textLabel.Text = string.format("%s\n%s", costText, details)

	updateVisualState(canPlace, canAfford)
	setVisible(true)
end

function PlacementCostDisplay.UpdateFloor(
	itemId: string?,
	cellCount: number,
	canPlace: boolean,
	worldPosition: Vector3?
)
	if typeof(cellCount) ~= "number" then
		PlacementCostDisplay.Hide()
		return
	end
	updateCostDisplay("Floor", itemId, math.max(cellCount, 0), canPlace, worldPosition)
end

function PlacementCostDisplay.UpdateRoof(itemId: string?, cellCount: number, canPlace: boolean, worldPosition: Vector3?)
	if typeof(cellCount) ~= "number" then
		PlacementCostDisplay.Hide()
		return
	end
	updateCostDisplay("Roof", itemId, math.max(cellCount, 0), canPlace, worldPosition)
end

function PlacementCostDisplay.UpdateWall(
	itemId: string?,
	segmentCount: number,
	canPlace: boolean,
	worldPosition: Vector3?
)
	if typeof(segmentCount) ~= "number" then
		PlacementCostDisplay.Hide()
		return
	end
	updateCostDisplay("Wall", itemId, math.max(segmentCount, 0), canPlace, worldPosition)
end

function PlacementCostDisplay.UpdateWallMounted(
	itemId: string?,
	installationCount: number,
	canPlace: boolean,
	worldPosition: Vector3?
)
	if typeof(installationCount) ~= "number" then
		PlacementCostDisplay.Hide()
		return
	end
	updateCostDisplay("WallMounted", itemId, math.max(installationCount, 0), canPlace, worldPosition)
end

function PlacementCostDisplay.UpdateSurfaceMounted(
	itemId: string?,
	placementCount: number,
	canPlace: boolean,
	worldPosition: Vector3?
)
	if typeof(placementCount) ~= "number" then
		PlacementCostDisplay.Hide()
		return
	end
	updateCostDisplay("SurfaceMounted", itemId, math.max(placementCount, 0), canPlace, worldPosition)
end

function PlacementCostDisplay.UpdateCeiling(
	itemId: string?,
	fixtureCount: number,
	canPlace: boolean,
	worldPosition: Vector3?
)
	if typeof(fixtureCount) ~= "number" then
		PlacementCostDisplay.Hide()
		return
	end
	updateCostDisplay("Ceiling", itemId, math.max(fixtureCount, 0), canPlace, worldPosition)
end

function PlacementCostDisplay.Hide()
	lastKind = nil
	lastItemId = nil
	lastTotalCost = nil
	lastUnitCount = nil
	lastCanPlace = nil
	lastCanAfford = nil
	lastWorldPosition = nil
	setVisible(false)
end

return PlacementCostDisplay
