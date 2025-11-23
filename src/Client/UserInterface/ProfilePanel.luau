--!strict
-- StarterPlayerScripts/Client/UserInterface/ProfilePanel.luau
-- White-themed profile dashboard that surfaces plot insights and active tenants.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local ResidentsStore = require(script.Parent.Parent.ClientStores.ResidentsStore)
local TenantStore = require(script.Parent.Parent.ClientStores.TenantStore)
local PlacementPackets = require(ReplicatedStorage.Network.PlacementPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

local Player = Players.LocalPlayer

local ProfilePanel = {}
local visibilityChangedSignal = GoodSignal.new()
ProfilePanel.VisibilityChanged = visibilityChangedSignal

local rgb = Color3.fromRGB

local Theme = {
	Surface = rgb(255, 255, 255),
	SurfaceElevated = rgb(242, 246, 255),
	SoftSurface = rgb(248, 250, 255),
	Accent = rgb(88, 120, 255),
	AccentBright = rgb(100, 180, 255),
	AccentMuted = rgb(210, 220, 255),
	TextPrimary = rgb(40, 45, 60),
	TextSecondary = rgb(120, 130, 150),
	TextMuted = rgb(160, 170, 190),
	Positive = rgb(80, 210, 160),
	Warning = rgb(255, 140, 140),
	StarFilled = rgb(255, 190, 60),
	StarEmpty = rgb(220, 225, 240),
	Shadow = rgb(20, 30, 60),
	Divider = rgb(230, 235, 245),
	PanelStroke = rgb(200, 210, 235),
}

local function trimText(text: string): string
	return (string.gsub(text, "^%s*(.-)%s*$", "%1"))
end

local function collapseSpaces(text: string): string
	return (string.gsub(text, "%s+", " "))
end

local function pluralize(count: number, singular: string, plural: string?): string
	local resolvedPlural = plural or (singular .. "s")
	return string.format("%d %s", count, if count == 1 then singular else resolvedPlural)
end

local CURRENCY_OPTIONS = {
	currencySymbol = "$",
	decimalPlaces = 0,
	useAbbreviation = true,
	useCommas = true,
}

local NumberAbbrevOptions = {
	useAbbreviation = true,
	decimalPlaces = 1,
}

type RatingCardRefs = {
	valueLabel: TextLabel,
	noteLabel: TextLabel,
	starLabels: { TextLabel },
	accent: Color3,
}

type StatCardRefs = {
	valueLabel: TextLabel,
	hintLabel: TextLabel,
}

type TenantSnapshot = {
	TenantId: string,
	Name: string?,
	TierId: string?,
	Rent: number?,
	RentInterval: number?,
	Boost: number?,
	Traits: { string }?,
	RoomKey: string?,
}

type TenantCardData = {
	TenantId: string,
	Name: string,
	TierId: string,
	Rent: number,
	RentInterval: number,
	BoostPercent: number,
	Traits: { string },
	RoomKey: string?,
	IncomePerHour: number,
}

type PlotMetrics = {
	unlockedChunks: number,
	totalChunks: number,
	unlockedPercent: number,
	totalPlacements: number,
	avgCost: number,
	propertyValue: number,
	residentCount: number,
	tenantCount: number,
	totalIncomePerHour: number,
	tagCounts: { [string]: number },
}

type RatingCategoryResult = {
	id: string,
	label: string,
	score: number,
	note: string,
	accent: Color3,
}

type PlotInsights = {
	plotName: string,
	propertyValueText: string,
	overallScore: number,
	overallStars: number,
	stats: { [string]: { value: string, hint: string } },
	categories: { RatingCategoryResult },
	tenants: { TenantCardData },
}

local state = {
	profileFrame = nil :: Frame?,
	panelFrame = nil :: Frame?,
	headerNameLabel = nil :: TextLabel?,
	statsGrid = nil :: Frame?,
	starLabels = {} :: { TextLabel },
	starContainer = nil :: Frame?,
	renameButton = nil :: TextButton?,
	closeButton = nil :: TextButton?,
	renameOverlay = nil :: Frame?,
	renameTextBox = nil :: TextBox?,
	renameErrorLabel = nil :: TextLabel?,
	renameConfirmButton = nil :: TextButton?,
	renameBusy = false,
	ratingList = nil :: ScrollingFrame?,
	tenantsView = nil :: ScrollingFrame?,
	emptyTenantsLabel = nil :: TextLabel?,
	ratingsView = nil :: Frame?,
	tabs = {} :: { [string]: TextButton },
	ratingCards = {} :: { [string]: RatingCardRefs },
	statCards = {} :: { [string]: StatCardRefs },
	isOpen = false,
	activeTab = "Ratings",
	propertyValue = 0,
	plotModel = nil :: Model?,
	residentsFolder = nil :: Folder?,
	lastInsights = nil :: PlotInsights?,
	isDirty = true,
	panelScale = nil :: UIScale?,
	panelTween = nil :: Tween?,
	panelTweenConnection = nil :: RBXScriptConnection?,
}

local PANEL_SHOW_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
local PANEL_HIDE_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
local PANEL_MIN_SCALE = 0.86
local PANEL_SCALE_NAME = "ProfilePanelScale"

local plotConnections: { RBXScriptConnection } = {}
local residentsConnections: { RBXScriptConnection } = {}
local externalConnections: { RBXScriptConnection } = {}

type CategoryDefinition = {
	id: string,
	label: string,
	accent: Color3,
	compute: (PlotMetrics) -> (number, string),
}

local CategoryDefinitions: { CategoryDefinition }

local function disconnectConnections(connections: { RBXScriptConnection })
	for index = #connections, 1, -1 do
		local connection = connections[index]
		if connection.Connected then
			connection:Disconnect()
		end
		connections[index] = nil
	end
end

local function countDictionary(dictionary: { [any]: any }?): number
	if typeof(dictionary) ~= "table" then
		return 0
	end
	local total = 0
	for _ in dictionary do
		total += 1
	end
	return total
end

local function ensurePanelScale(): UIScale?
	local panel = state.panelFrame
	if not panel then
		return nil
	end
	local scale = state.panelScale
	if scale and scale.Parent == panel then
		return scale
	end
	local existing = panel:FindFirstChild(PANEL_SCALE_NAME)
	if existing and existing:IsA("UIScale") then
		state.panelScale = existing
		return existing
	end
	scale = Instance.new("UIScale")
	scale.Name = PANEL_SCALE_NAME
	scale.Scale = PANEL_MIN_SCALE
	scale.Parent = panel
	state.panelScale = scale
	return scale
end

local function tweenPanelVisibility(isVisible: boolean)
	local panel = state.panelFrame
	local profileFrame = state.profileFrame
	local scale = ensurePanelScale()
	if not panel or not profileFrame or not scale then
		return
	end
	if state.panelTween then
		state.panelTween:Cancel()
		state.panelTween = nil
	end
	if state.panelTweenConnection then
		state.panelTweenConnection:Disconnect()
		state.panelTweenConnection = nil
	end

	local tweenInfo = if isVisible then PANEL_SHOW_TWEEN else PANEL_HIDE_TWEEN
	local target = if isVisible then 1 else PANEL_MIN_SCALE
	if isVisible then
		panel.Visible = true
		profileFrame.Visible = true
		if scale.Scale <= PANEL_MIN_SCALE then
			scale.Scale = PANEL_MIN_SCALE
		end
	end

	local tween = TweenService:Create(scale, tweenInfo, { Scale = target })
	state.panelTween = tween
	state.panelTweenConnection = tween.Completed:Connect(function()
		if state.panelTween == tween then
			state.panelTween = nil
		end
		state.panelTweenConnection = nil
		if not isVisible then
			panel.Visible = false
			if not state.isOpen then
				profileFrame.Visible = false
			end
		end
	end)
	tween:Play()
end

local function formatCurrencyShort(amount: number): string
	return Formatter.formatCurrency(amount, CURRENCY_OPTIONS)
end

local function formatCompactNumber(value: number): string
	return Formatter.formatNumber(value, NumberAbbrevOptions)
end

local function resolvePlotName(): string
	local plotIndex = Player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) == "number" then
		local plotModel = PlotFinder.FindPlot(plotIndex)
		if plotModel then
			local customName = plotModel:GetAttribute("PlotName")
			if typeof(customName) == "string" and customName ~= "" then
				return customName
			end
			return string.format("Plot %d", plotIndex)
		end
	end
	return string.format("%s'" .. "s Plot", Player.DisplayName)
end

local function collectTenantList(): { TenantCardData }
	local snapshot = TenantStore.GetTenants(Player.UserId)
	local tenants: { TenantCardData } = {}
	if snapshot then
		for tenantId, tenant in snapshot do
			if typeof(tenantId) == "string" and typeof(tenant) == "table" then
				local rent = 0
				if typeof(tenant.Rent) == "number" then
					rent = tenant.Rent
				end

				local rentInterval = 0
				if typeof(tenant.RentInterval) == "number" then
					rentInterval = tenant.RentInterval
				end

				local boost = 0
				if typeof(tenant.Boost) == "number" then
					boost = tenant.Boost
				end

				local traits = {}
				if typeof(tenant.Traits) == "table" then
					traits = tenant.Traits
				end
				local incomePerHour = 0
				if rentInterval > 0 then
					incomePerHour = rent * (3600 / rentInterval)
				end
				tenants[#tenants + 1] = {
					TenantId = tenantId,
					Name = tenant.Name or "Tenant",
					TierId = tenant.TierId or "",
					Rent = rent,
					RentInterval = rentInterval,
					BoostPercent = math.round(boost * 100),
					Traits = traits,
					RoomKey = tenant.RoomKey,
					IncomePerHour = incomePerHour,
				}
			end
		end
	end
	table.sort(tenants, function(left, right)
		if left.Rent == right.Rent then
			return left.Name < right.Name
		end
		return left.Rent > right.Rent
	end)
	return tenants
end

local function analyzePlot(): PlotMetrics
	local snapshot = PlotStateStore.GetStateSnapshot()
	local unlockedChunks = 0
	local totalChunks = 0
	local tagCounts: { [string]: number } = {}
	local totalCost = 0
	local placementCount = 0

	if snapshot and typeof(snapshot.ChunkUnlocked) == "table" then
		for _, isUnlocked in snapshot.ChunkUnlocked do
			totalChunks += 1
			if isUnlocked then
				unlockedChunks += 1
			end
		end
	end

	if snapshot and typeof(snapshot.PlacedItems) == "table" then
		for _, placed in snapshot.PlacedItems do
			placementCount += 1
			local itemId = placed and placed.id
			if typeof(itemId) == "string" then
				local spec = ItemFinder.FindItemById(itemId)
				if spec then
					if typeof(spec.Tags) == "table" then
						for _, tag in spec.Tags do
							if typeof(tag) == "string" and tag ~= "" then
								local key = string.lower(tag)
								tagCounts[key] = (tagCounts[key] or 0) + 1
							end
						end
					end
					local cost = spec.Cost
					if typeof(cost) == "number" and cost > 0 then
						totalCost += cost
					end
				end
			end
		end
	end

	local tenantList = collectTenantList()

	local unlockedPercent = 1
	if totalChunks > 0 then
		unlockedPercent = unlockedChunks / totalChunks
	end

	local avgCost = 0
	if placementCount > 0 then
		avgCost = totalCost / placementCount
	end

	local metrics: PlotMetrics = {
		unlockedChunks = unlockedChunks,
		totalChunks = totalChunks,
		unlockedPercent = unlockedPercent,
		totalPlacements = placementCount,
		avgCost = avgCost,
		propertyValue = state.propertyValue,
		residentCount = countDictionary(ResidentsStore.GetResidents(Player.UserId)),
		tenantCount = #tenantList,
		totalIncomePerHour = 0,
		tagCounts = tagCounts,
	}

	for _, tenant in tenantList do
		metrics.totalIncomePerHour += tenant.IncomePerHour
	end

	return metrics
end

local function pickNote(score: number, excellent: string, good: string, needsLove: string): string
	if score >= 85 then
		return excellent
	elseif score >= 55 then
		return good
	end
	return needsLove
end

local function sumTags(metrics: PlotMetrics, tags: { string }): number
	local total = 0
	for _, tag in tags do
		total += metrics.tagCounts[tag] or 0
	end
	return total
end

local PLOT_NAME_MIN_LENGTH = 3
local PLOT_NAME_MAX_LENGTH = 24

local function utf8Length(text: string): number
	local success, length = pcall(function()
		return utf8.len(text)
	end)
	if success and typeof(length) == "number" then
		return length
	end
	return #text
end

local function validateProposedName(text: string): (boolean, string)
	local trimmed = collapseSpaces(trimText(text))
	local length = utf8Length(trimmed)
	if length < PLOT_NAME_MIN_LENGTH then
		return false, string.format("Name must be at least %d characters.", PLOT_NAME_MIN_LENGTH)
	end
	if length > PLOT_NAME_MAX_LENGTH then
		return false, string.format("Name can't exceed %d characters.", PLOT_NAME_MAX_LENGTH)
	end
	return true, trimmed
end

local function updateStarRow(starLabels: { TextLabel }, stars: number, color: Color3)
	local filled = math.floor(stars)
	local partial = stars - filled
	for index, label in ipairs(starLabels) do
		if index <= filled then
			label.TextTransparency = 0
			label.TextColor3 = color
		elseif index == filled + 1 and partial > 0 then
			label.TextTransparency = 0.35
			label.TextColor3 = color:Lerp(Theme.StarEmpty, 0.35)
		else
			label.TextTransparency = 0.55
			label.TextColor3 = Theme.StarEmpty
		end
	end
end

local function updateStarStrip(stars: number)
	updateStarRow(state.starLabels, stars, Theme.StarFilled)
end

CategoryDefinitions = {
	{
		id = "Cleanliness",
		label = "Cleanliness",
		accent = Color3.fromRGB(178, 226, 200),
		compute = function(metrics: PlotMetrics)
			local hygieneTags = { "bath", "sink", "laundry", "trash", "utility", "clean", "storage" }
			local fixtures = sumTags(metrics, hygieneTags)
			local target = math.max(2, metrics.residentCount + metrics.totalPlacements * 0.08)
			local ratio = if target > 0 then math.clamp(fixtures / target, 0, 1.2) else 1
			local scarcityPenalty = math.clamp(1 - (metrics.totalPlacements / 1200), 0, 0.2)
			local score = math.clamp(math.floor((ratio - scarcityPenalty) * 100), 10, 100)
			local note = pickNote(
				score,
				"Everything feels freshly wiped down.",
				"Add a sink or laundry nook to keep up.",
				"Tidy up with bins or cleaning stations."
			)
			return score, note
		end,
	},
	{
		id = "Atmosphere",
		label = "Atmosphere",
		accent = Color3.fromRGB(177, 208, 193),
		compute = function(metrics: PlotMetrics)
			local lushTags = { "nature", "plant", "garden", "pointofinterest", "water", "decor" }
			local lushCount = sumTags(metrics, lushTags)
			local target = math.max(4, metrics.residentCount * 0.8 + metrics.unlockedChunks * 0.35)
			local ratio = if target > 0 then math.clamp(lushCount / target, 0, 1.35) else 1
			local score = math.clamp(math.floor(ratio * 100), 15, 100)
			local note = pickNote(
				score,
				"Airy, lived-in energy.",
				"Anchor rooms with focal decor.",
				"Layer greenery to soften the edges."
			)
			return score, note
		end,
	},
	{
		id = "Lighting",
		label = "Lighting",
		accent = Color3.fromRGB(243, 210, 158),
		compute = function(metrics: PlotMetrics)
			local lightingTags = { "light", "lighting", "ceiling", "lamp" }
			local lightSources = sumTags(metrics, lightingTags)
			local baseline = math.max(3, metrics.totalPlacements * 0.18)
			local modifier = math.clamp(metrics.unlockedPercent, 0.35, 1)
			local ratio = if baseline > 0 then lightSources / baseline else 1
			local score = math.clamp(math.floor(ratio * 100 * modifier + 0.5), 10, 100)
			local note = pickNote(
				score,
				"Layered glow feels premium.",
				"Task lights cover core rooms.",
				"Add sconces or table lamps for warmth."
			)
			return score, note
		end,
	},
	{
		id = "Style",
		label = "Style & Decor",
		accent = Color3.fromRGB(214, 190, 255),
		compute = function(metrics: PlotMetrics)
			local stylishTags = { "decor", "modern", "luxury", "rug", "art", "premium" }
			local hits = sumTags(metrics, stylishTags)
			local costFactor = math.clamp(metrics.avgCost / 650, 0, 1)
			local breadth = math.clamp(hits / math.max(1, metrics.totalPlacements), 0, 0.85)
			local score = math.floor((0.55 * breadth + 0.45 * costFactor) * 100)
			local note = pickNote(
				score,
				"Looks editorial ready.",
				"Blend new textures or art.",
				"Add statements to define each room."
			)
			return math.clamp(score, 5, 100), note
		end,
	},
	{
		id = "Comfort",
		label = "Comfort",
		accent = Color3.fromRGB(178, 217, 255),
		compute = function(metrics: PlotMetrics)
			local comfortTags = { "comfort", "seating", "bed", "sofa", "bath", "table", "chair" }
			local comfortPieces = sumTags(metrics, comfortTags)
			local target = math.max(3, metrics.residentCount * 1.3 + metrics.tenantCount * 0.5)
			local ratio = if target > 0 then comfortPieces / target else 1
			local score = math.clamp(math.floor(ratio * 100), 10, 100)
			local note = pickNote(
				score,
				"Residents can spread out.",
				"A few more seats would help.",
				"Add lounges or utility rooms for relief."
			)
			return score, note
		end,
	},
}

local function buildInsights(): PlotInsights
	local metrics = analyzePlot()
	local categories: { RatingCategoryResult } = {}
	local totalScore = 0
	for _, def in CategoryDefinitions do
		local score, note = def.compute(metrics)
		totalScore += score
		categories[#categories + 1] = {
			id = def.id,
			label = def.label,
			score = score,
			note = note,
			accent = def.accent,
		}
	end

	local overallScore = math.clamp(math.floor(totalScore / #CategoryDefinitions + 0.5), 10, 100)
	local propertyValueText = formatCurrencyShort(metrics.propertyValue)

	local stats = {
		Value = {
			value = propertyValueText,
			hint = "Current appraisal",
		},
		Land = {
			value = string.format("%.0f%%", metrics.unlockedPercent * 100),
			hint = string.format("%d of %d chunks", metrics.unlockedChunks, math.max(metrics.totalChunks, 1)),
		},
		Household = {
			value = pluralize(metrics.tenantCount, "tenant"),
			hint = "Currently leased tenants",
		},
		Income = {
			value = string.format("%s/hr", formatCompactNumber(metrics.totalIncomePerHour)),
			hint = "Passive rent inflow",
		},
	}

	local tenantCards = collectTenantList()

	local overallStars = math.clamp(overallScore / 20, 0, 5)

	local insights: PlotInsights = {
		plotName = resolvePlotName(),
		overallScore = overallScore,
		overallStars = overallStars,
		propertyValueText = propertyValueText,
		stats = stats,
		categories = categories,
		tenants = tenantCards,
	}

	return insights
end

local function applyInsights(insights: PlotInsights)
	state.lastInsights = insights
	state.isDirty = false

	if state.headerNameLabel then
		state.headerNameLabel.Text = insights.plotName
	end
	updateStarStrip(insights.overallStars)

	for statId, card in state.statCards do
		local payload = insights.stats[statId]
		if payload then
			card.valueLabel.Text = payload.value
			card.hintLabel.Text = payload.hint
		else
			card.valueLabel.Text = "--"
			card.hintLabel.Text = ""
		end
	end

	for _, category in insights.categories do
		local card = state.ratingCards[category.id]
		if card then
			local starValue = math.clamp(category.score / 20, 0, 5)
			card.valueLabel.Text = string.format("%.1f / 5", starValue)
			card.noteLabel.Text = category.note
			updateStarRow(card.starLabels, starValue, card.accent)
		end
	end

	if state.tenantsView and state.emptyTenantsLabel then
		for _, child in ipairs(state.tenantsView:GetChildren()) do
			if child:IsA("Frame") and child.Name == "TenantCard" then
				child:Destroy()
			end
		end

		if #insights.tenants == 0 then
			state.emptyTenantsLabel.Visible = true
		else
			state.emptyTenantsLabel.Visible = false
			for _, tenant in ipairs(insights.tenants) do
				local card = Instance.new("Frame")
				card.Name = "TenantCard"
				card.BackgroundColor3 = Theme.SurfaceElevated
				card.Size = UDim2.new(1, -6, 0, 104)
				card.BorderSizePixel = 0
				card.ClipsDescendants = true
				card.Parent = state.tenantsView
				card.ZIndex = 6

				local corner = Instance.new("UICorner")
				corner.CornerRadius = UDim.new(0, 20)
				corner.Parent = card

				local stroke = Instance.new("UIStroke")
				stroke.Color = Theme.PanelStroke
				stroke.Transparency = 0.4
				stroke.Parent = card

				local gradient = Instance.new("UIGradient")
				gradient.Color = ColorSequence.new({
					ColorSequenceKeypoint.new(0, Theme.Surface),
					ColorSequenceKeypoint.new(1, Theme.SurfaceElevated),
				})
				gradient.Rotation = 90
				gradient.Parent = card

				local nameLabel = Instance.new("TextLabel")
				nameLabel.BackgroundTransparency = 1
				nameLabel.Size = UDim2.new(0.6, 0, 0, 28)
				nameLabel.Position = UDim2.fromOffset(18, 12)
				nameLabel.Font = Enum.Font.GothamBold
				nameLabel.TextSize = 20
				nameLabel.TextXAlignment = Enum.TextXAlignment.Left
				nameLabel.TextColor3 = Theme.TextPrimary
				nameLabel.Text = tenant.Name
				nameLabel.Parent = card

				local tierLabel = Instance.new("TextLabel")
				tierLabel.BackgroundTransparency = 1
				tierLabel.Size = UDim2.new(0.4, -18, 0, 20)
				tierLabel.Position = UDim2.new(0.6, 0, 0, 16)
				tierLabel.Font = Enum.Font.Gotham
				tierLabel.TextSize = 14
				tierLabel.TextXAlignment = Enum.TextXAlignment.Right
				tierLabel.TextColor3 = Theme.TextSecondary
				tierLabel.Text = tenant.TierId ~= "" and tenant.TierId or "Standard"
				tierLabel.Parent = card

				local rentLabel = Instance.new("TextLabel")
				rentLabel.BackgroundTransparency = 1
				rentLabel.Size = UDim2.new(0.58, -16, 0, 24)
				rentLabel.Position = UDim2.fromOffset(18, 46)
				rentLabel.Font = Enum.Font.Gotham
				rentLabel.TextSize = 16
				rentLabel.TextXAlignment = Enum.TextXAlignment.Left
				rentLabel.TextColor3 = Theme.TextSecondary
				rentLabel.Text = string.format(
					"%s every %s",
					formatCurrencyShort(tenant.Rent),
					Formatter.formatDuration(tenant.RentInterval, {
						units = { "hour", "minute" },
						shortUnits = true,
						maxUnits = 1,
					})
				)
				rentLabel.Parent = card

				local incomeLabel = Instance.new("TextLabel")
				incomeLabel.BackgroundTransparency = 1
				incomeLabel.Size = UDim2.new(0.4, -20, 0, 24)
				incomeLabel.Position = UDim2.new(0.6, 0, 0, 46)
				incomeLabel.Font = Enum.Font.GothamMedium
				incomeLabel.TextSize = 16
				incomeLabel.TextXAlignment = Enum.TextXAlignment.Right
				incomeLabel.TextColor3 = Theme.TextPrimary
				incomeLabel.Text = string.format("%s/hr", formatCompactNumber(tenant.IncomePerHour))
				incomeLabel.Parent = card

				local boostPill = Instance.new("TextLabel")
				boostPill.BackgroundColor3 = Theme.Accent
				boostPill.BackgroundTransparency = 0.15
				boostPill.Size = UDim2.fromOffset(118, 26)
				boostPill.Position = UDim2.new(1, -134, 0, 74)
				boostPill.Font = Enum.Font.GothamMedium
				boostPill.TextSize = 14
				boostPill.TextColor3 = Color3.new(1, 1, 1)
				boostPill.Text = string.format("+%d%% boost", tenant.BoostPercent)
				boostPill.Parent = card

				local boostCorner = Instance.new("UICorner")
				boostCorner.CornerRadius = UDim.new(0, 12)
				boostCorner.Parent = boostPill

				local traitsLabel = Instance.new("TextLabel")
				traitsLabel.BackgroundTransparency = 1
				traitsLabel.Size = UDim2.new(1, -36, 0, 20)
				traitsLabel.Position = UDim2.fromOffset(18, 78)
				traitsLabel.Font = Enum.Font.Gotham
				traitsLabel.TextSize = 14
				traitsLabel.TextXAlignment = Enum.TextXAlignment.Left
				traitsLabel.TextColor3 = Theme.TextSecondary
				if #tenant.Traits > 0 then
					traitsLabel.Text = table.concat(tenant.Traits, " · ", 1, math.min(3, #tenant.Traits))
				else
					traitsLabel.Text = "No noted traits"
				end
				traitsLabel.Parent = card
			end
		end
	end
end

local function refreshInsights()
	if not state.isOpen then
		state.isDirty = true
		return
	end
	local insights = buildInsights()
	applyInsights(insights)
	local badgeColor
	if insights.overallScore >= 85 then
		badgeColor = Theme.Positive
	elseif insights.overallScore >= 55 then
		badgeColor = Theme.Accent
	else
		badgeColor = Theme.Warning
	end
	local starContainer = state.starContainer
	if starContainer then
		TweenService:Create(
			starContainer,
			TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundColor3 = badgeColor:Lerp(Theme.Surface, 0.55) }
		):Play()
	end
end

local function markDirty()
	state.isDirty = true
	if state.isOpen then
		refreshInsights()
	end
end

local function setRenameStatus(message: string?)
	if state.renameErrorLabel then
		state.renameErrorLabel.Text = message or ""
		state.renameErrorLabel.Visible = message ~= nil and message ~= ""
	end
end

local function toggleRenameOverlay(show: boolean)
	local overlay = state.renameOverlay
	if not overlay then
		return
	end
	overlay.Visible = show
	if show and state.renameTextBox then
		state.renameTextBox.Text = state.headerNameLabel and state.headerNameLabel.Text or ""
		state.renameTextBox.CursorPosition = #state.renameTextBox.Text + 1
		state.renameTextBox:CaptureFocus()
	else
		if state.renameTextBox then
			state.renameTextBox:ReleaseFocus()
		end
		setRenameStatus(nil)
	end
end

local function setRenameBusy(isBusy: boolean)
	state.renameBusy = isBusy
	local button = state.renameConfirmButton
	if button then
		button.Text = if isBusy then "Saving..." else "Save"
		button.AutoButtonColor = not isBusy
		button.Active = not isBusy
		button.Selectable = not isBusy
	end
end

local function submitRename()
	if state.renameBusy or not state.renameTextBox then
		return
	end
	local proposed = state.renameTextBox.Text
	local isValid, result = validateProposedName(proposed)
	if not isValid then
		setRenameStatus(result)
		return
	end
	local normalized = result
	setRenameStatus(nil)
	setRenameBusy(true)
	state.renameTextBox.Text = normalized
	task.spawn(function()
		local success, responseMessage, resolvedName = PlacementPackets.RenamePlotRequest:Fire(normalized)
		setRenameBusy(false)
		if not success then
			setRenameStatus(responseMessage or "Unable to rename plot right now.")
			return
		end
		toggleRenameOverlay(false)
		if resolvedName and state.headerNameLabel then
			state.headerNameLabel.Text = resolvedName
		end
		markDirty()
	end)
end

local function setResidentsFolder(folder: Folder?)
	if state.residentsFolder == folder then
		if folder then
			local attr = folder:GetAttribute("PropertyValue")
			if typeof(attr) == "number" then
				state.propertyValue = math.max(0, math.floor((attr :: number) + 0.5))
			else
				state.propertyValue = 0
			end
			markDirty()
		end
		return
	end
	disconnectConnections(residentsConnections)
	state.residentsFolder = folder
	if not folder then
		state.propertyValue = 0
		markDirty()
		return
	end

	residentsConnections[#residentsConnections + 1] = folder
		:GetAttributeChangedSignal("PropertyValue")
		:Connect(function()
			local value = folder:GetAttribute("PropertyValue")
			if typeof(value) == "number" then
				state.propertyValue = math.max(0, math.floor(value + 0.5))
			else
				state.propertyValue = 0
			end
			markDirty()
		end)

	residentsConnections[#residentsConnections + 1] = folder.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			setResidentsFolder(nil)
		end
	end)

	local initial = folder:GetAttribute("PropertyValue")
	if typeof(initial) == "number" then
		state.propertyValue = math.max(0, math.floor(initial + 0.5))
	else
		state.propertyValue = 0
	end
	markDirty()
end

local function bindPlotModel()
	disconnectConnections(plotConnections)
	state.plotModel = nil

	local plotIndex = Player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		setResidentsFolder(nil)
		return
	end

	local model = PlotFinder.FindPlot(plotIndex)
	if not model then
		setResidentsFolder(nil)
		return
	end
	state.plotModel = model

	plotConnections[#plotConnections + 1] = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			bindPlotModel()
		end
	end)

	plotConnections[#plotConnections + 1] = model.ChildAdded:Connect(function(child)
		if child:IsA("Folder") and child.Name == "Residents" then
			setResidentsFolder(child)
		end
	end)

	plotConnections[#plotConnections + 1] = model.ChildRemoved:Connect(function(child)
		if child == state.residentsFolder then
			setResidentsFolder(nil)
		end
	end)

	local residents = model:FindFirstChild("Residents")
	if residents and residents:IsA("Folder") then
		setResidentsFolder(residents)
	else
		setResidentsFolder(nil)
	end
end

local function switchTab(tabId: string)
	state.activeTab = tabId
	for id, button in state.tabs do
		local isActive = id == tabId
		local stroke = button:FindFirstChild("UIStroke") :: UIStroke?

		if isActive then
			button.TextColor3 = Color3.new(1, 1, 1)
			button.BackgroundTransparency = 0
			button.BackgroundColor3 = Theme.Accent
			if stroke then
				stroke.Transparency = 1
			end
		else
			button.TextColor3 = Theme.TextSecondary
			button.BackgroundTransparency = 0
			button.BackgroundColor3 = Theme.SurfaceElevated
			if stroke then
				stroke.Transparency = 0.6
			end
		end
	end
	if state.ratingsView then
		state.ratingsView.Visible = tabId == "Ratings"
	end
	if state.tenantsView then
		state.tenantsView.Visible = tabId == "Tenants"
	end
end

local function createStatCard(parent: Instance, id: string, labelText: string)
	local card = Instance.new("Frame")
	card.Name = id .. "Stat"
	card.BackgroundColor3 = Theme.SurfaceElevated
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.Size = UDim2.fromOffset(0, 72)
	card.Parent = parent
	card.ZIndex = 5

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 24)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Theme.PanelStroke
	stroke.Transparency = 0.5
	stroke.Thickness = 1.5
	stroke.Parent = card

	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -24, 0, 18)
	label.Position = UDim2.fromOffset(14, 10)
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = Theme.TextSecondary
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = labelText
	label.Parent = card

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.new(1, -24, 0, 26)
	valueLabel.Position = UDim2.fromOffset(14, 28)
	valueLabel.Font = Enum.Font.GothamBlack
	valueLabel.TextSize = 22
	valueLabel.TextColor3 = Theme.TextPrimary
	valueLabel.TextXAlignment = Enum.TextXAlignment.Left
	valueLabel.Text = "--"
	valueLabel.Parent = card

	local hintLabel = Instance.new("TextLabel")
	hintLabel.BackgroundTransparency = 1
	hintLabel.Size = UDim2.new(1, -24, 0, 16)
	hintLabel.Position = UDim2.fromOffset(14, 52)
	hintLabel.Font = Enum.Font.Gotham
	hintLabel.TextSize = 12
	hintLabel.TextColor3 = Theme.TextMuted
	hintLabel.TextXAlignment = Enum.TextXAlignment.Left
	hintLabel.Text = ""
	hintLabel.Parent = card

	state.statCards[id] = {
		valueLabel = valueLabel,
		hintLabel = hintLabel,
	}
end

local function createRatingCard(parent: Instance, definition: CategoryDefinition)
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.Size = UDim2.new(1, -4, 0, 110)
	holder.Parent = parent

	local card = Instance.new("Frame")
	card.Name = definition.id .. "Card"
	card.Size = UDim2.fromScale(1, 1)
	card.BackgroundColor3 = Theme.Surface
	card.BackgroundTransparency = 0
	card.BorderSizePixel = 0
	card.Parent = holder
	card.ZIndex = 5

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 28)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 1.5
	stroke.Color = definition.accent:Lerp(Theme.Surface, 0.3)
	stroke.Transparency = 0.2
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(0.65, 0, 0, 24)
	title.Position = UDim2.fromOffset(20, 16)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 18
	title.TextColor3 = Theme.TextPrimary
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = definition.label
	title.Parent = card

	local valueLabel = Instance.new("TextLabel")
	valueLabel.BackgroundTransparency = 1
	valueLabel.Size = UDim2.fromOffset(96, 32)
	valueLabel.Position = UDim2.new(1, -116, 0, 12)
	valueLabel.Font = Enum.Font.GothamBlack
	valueLabel.TextSize = 24
	valueLabel.TextColor3 = definition.accent
	valueLabel.TextXAlignment = Enum.TextXAlignment.Right
	valueLabel.Text = "--"
	valueLabel.Parent = card

	local starsFrame = Instance.new("Frame")
	starsFrame.Name = "Stars"
	starsFrame.BackgroundTransparency = 1
	starsFrame.Size = UDim2.new(1, -40, 0, 26)
	starsFrame.Position = UDim2.fromOffset(20, 50)
	starsFrame.Parent = card

	local starLayout = Instance.new("UIListLayout")
	starLayout.FillDirection = Enum.FillDirection.Horizontal
	starLayout.Padding = UDim.new(0, 6)
	starLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	starLayout.SortOrder = Enum.SortOrder.LayoutOrder
	starLayout.Parent = starsFrame

	local starLabels: { TextLabel } = {}
	for i = 1, 5 do
		local starLabel = Instance.new("TextLabel")
		starLabel.BackgroundTransparency = 1
		starLabel.Size = UDim2.fromOffset(22, 24)
		starLabel.Font = Enum.Font.GothamBold
		starLabel.Text = "★"
		starLabel.TextSize = 20
		starLabel.TextColor3 = Theme.StarEmpty
		starLabel.TextTransparency = 0.55
		starLabel.Parent = starsFrame
		starLabels[i] = starLabel
	end

	local noteLabel = Instance.new("TextLabel")
	noteLabel.BackgroundTransparency = 1
	noteLabel.Size = UDim2.new(1, -40, 0, 24)
	noteLabel.Position = UDim2.fromOffset(20, 80)
	noteLabel.Font = Enum.Font.GothamMedium
	noteLabel.TextSize = 14
	noteLabel.TextColor3 = Theme.TextSecondary
	noteLabel.TextXAlignment = Enum.TextXAlignment.Left
	noteLabel.TextWrapped = true
	noteLabel.Text = "Gathering data..."
	noteLabel.Parent = card

	state.ratingCards[definition.id] = {
		valueLabel = valueLabel,
		noteLabel = noteLabel,
		starLabels = starLabels,
		accent = definition.accent,
	}
end

local function buildUI(profileFrame: Frame)
	profileFrame.Visible = false
	profileFrame.BackgroundTransparency = 0
	profileFrame.BackgroundColor3 = Theme.Shadow
	profileFrame.ClipsDescendants = true

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromScale(0.88, 0.88)
	panel.BackgroundColor3 = Theme.Surface
	panel.BackgroundTransparency = 0
	panel.BorderSizePixel = 0
	panel.Parent = profileFrame
	panel.ZIndex = 2
	panel.ClipsDescendants = true

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 32)
	corner.Parent = panel

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 2.5
	stroke.Color = Theme.PanelStroke
	stroke.Transparency = 0
	stroke.Parent = panel

	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Theme.Surface),
		ColorSequenceKeypoint.new(1, Theme.SoftSurface),
	})
	gradient.Rotation = 90
	gradient.Parent = panel

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 28)
	padding.PaddingBottom = UDim.new(0, 28)
	padding.PaddingLeft = UDim.new(0, 28)
	padding.PaddingRight = UDim.new(0, 28)
	padding.Parent = panel

	local headerHeight = 120
	local tabsHeight = 40

	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, headerHeight)
	header.BackgroundTransparency = 1
	header.Parent = panel

	local nameLabel = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency = 1
	nameLabel.Size = UDim2.new(1, -200, 0, 38)
	nameLabel.AnchorPoint = Vector2.new(0.5, 0)
	nameLabel.Position = UDim2.fromScale(0.5, 0)
	nameLabel.Font = Enum.Font.GothamBlack
	nameLabel.TextSize = 28
	nameLabel.TextColor3 = Theme.TextPrimary
	nameLabel.TextXAlignment = Enum.TextXAlignment.Center
	nameLabel.Text = "Plot Profile"
	nameLabel.Parent = header
	state.headerNameLabel = nameLabel

	local renameButton = Instance.new("TextButton")
	renameButton.Name = "RenameButton"
	renameButton.AnchorPoint = Vector2.new(1, 0)
	renameButton.Position = UDim2.new(1, -60, 0, 10)
	renameButton.Size = UDim2.fromOffset(36, 36)
	renameButton.AutoButtonColor = true
	renameButton.BackgroundColor3 = Theme.SurfaceElevated
	renameButton.BorderSizePixel = 0
	renameButton.Text = "✎"
	renameButton.Font = Enum.Font.GothamBold
	renameButton.TextSize = 16
	renameButton.TextColor3 = Theme.Accent
	renameButton.Parent = header
	state.renameButton = renameButton

	local renameCorner = Instance.new("UICorner")
	renameCorner.CornerRadius = UDim.new(1, 0)
	renameCorner.Parent = renameButton

	local renameStroke = Instance.new("UIStroke")
	renameStroke.Color = Theme.PanelStroke
	renameStroke.Transparency = 0
	renameStroke.Thickness = 1.5
	renameStroke.Parent = renameButton

	renameButton.Activated:Connect(function()
		toggleRenameOverlay(true)
	end)

	local closeButton = Instance.new("TextButton")
	closeButton.Name = "CloseButton"
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 8)
	closeButton.Size = UDim2.fromOffset(40, 40)
	closeButton.AutoButtonColor = true
	closeButton.BackgroundColor3 = Theme.SurfaceElevated
	closeButton.BorderSizePixel = 0
	closeButton.Text = "✕"
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 16
	closeButton.TextColor3 = Theme.TextPrimary
	closeButton.Parent = header
	state.closeButton = closeButton

	local closeCorner = Instance.new("UICorner")
	closeCorner.CornerRadius = UDim.new(1, 0)
	closeCorner.Parent = closeButton

	local closeStroke = Instance.new("UIStroke")
	closeStroke.Color = Theme.PanelStroke
	closeStroke.Transparency = 0.2
	closeStroke.Thickness = 1.5
	closeStroke.Parent = closeButton

	closeButton.Activated:Connect(function()
		ProfilePanel.Hide()
	end)

	local ratingBadge = Instance.new("Frame")
	ratingBadge.Name = "RatingBadge"
	ratingBadge.AnchorPoint = Vector2.new(0.5, 0)
	ratingBadge.Position = UDim2.new(0.5, 0, 0, 48)
	ratingBadge.Size = UDim2.fromOffset(260, 82)
	ratingBadge.BackgroundTransparency = 1
	ratingBadge.Parent = header
	ratingBadge.ZIndex = 5
	state.starContainer = ratingBadge

	local ratingCorner = Instance.new("UICorner")
	ratingCorner.CornerRadius = UDim.new(0, 18)
	ratingCorner.Parent = ratingBadge

	local ratingBadgePadding = Instance.new("UIPadding")
	ratingBadgePadding.PaddingTop = UDim.new(0, 12)
	ratingBadgePadding.PaddingBottom = UDim.new(0, 12)
	ratingBadgePadding.PaddingLeft = UDim.new(0, 16)
	ratingBadgePadding.PaddingRight = UDim.new(0, 16)
	ratingBadgePadding.Parent = ratingBadge

	local starsFrame = Instance.new("Frame")
	starsFrame.Name = "Stars"
	starsFrame.BackgroundTransparency = 1
	starsFrame.Size = UDim2.new(1, 0, 0, 30)
	starsFrame.Position = UDim2.fromOffset(0, 0)
	starsFrame.Parent = ratingBadge

	local starLayout = Instance.new("UIListLayout")
	starLayout.FillDirection = Enum.FillDirection.Horizontal
	starLayout.Padding = UDim.new(0, 4)
	starLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	starLayout.SortOrder = Enum.SortOrder.LayoutOrder
	starLayout.Parent = starsFrame

	for i = 1, 5 do
		local starLabel = Instance.new("TextLabel")
		starLabel.BackgroundTransparency = 1
		starLabel.Size = UDim2.fromOffset(22, 24)
		starLabel.Font = Enum.Font.GothamBold
		starLabel.Text = "★"
		starLabel.TextSize = 20
		starLabel.TextColor3 = Theme.StarEmpty
		starLabel.TextTransparency = 0.5
		starLabel.Parent = starsFrame
		state.starLabels[i] = starLabel
	end

	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.Size = UDim2.new(1, 0, 0, tabsHeight)
	tabs.Position = UDim2.fromOffset(0, headerHeight + 12)
	tabs.BackgroundTransparency = 1
	tabs.Parent = panel

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 12)
	tabLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Parent = tabs

	local function createTab(id: string, label: string)
		local button = Instance.new("TextButton")
		button.Name = id .. "Tab"
		button.Size = UDim2.new(0, 140, 1, 0)
		button.AutoButtonColor = false
		button.BackgroundColor3 = Theme.SurfaceElevated
		button.BackgroundTransparency = 0
		button.Text = label
		button.Font = Enum.Font.GothamBold
		button.TextSize = 14
		button.TextColor3 = Theme.TextSecondary
		button.Parent = tabs

		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(1, 0) -- Pill shape
		buttonCorner.Parent = button

		local buttonStroke = Instance.new("UIStroke")
		buttonStroke.Color = Theme.PanelStroke
		buttonStroke.Transparency = 0.6
		buttonStroke.Thickness = 1.5
		buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		buttonStroke.Parent = button

		button.Activated:Connect(function()
			switchTab(id)
		end)

		state.tabs[id] = button
	end

	createTab("Ratings", "Plot Ratings")
	createTab("Tenants", "Active Tenants")

	local bodyTop = headerHeight + tabsHeight + 24
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Position = UDim2.fromOffset(0, bodyTop)
	body.Size = UDim2.new(1, 0, 1, -bodyTop)
	body.BackgroundTransparency = 1
	body.Parent = panel

	local ratingsView = Instance.new("Frame")
	ratingsView.Name = "RatingsView"
	ratingsView.Size = UDim2.fromScale(1, 1)
	ratingsView.BackgroundTransparency = 1
	ratingsView.Parent = body

	local statsGrid = Instance.new("Frame")
	statsGrid.Name = "StatsGrid"
	statsGrid.BackgroundTransparency = 1
	statsGrid.Size = UDim2.new(1, 0, 0, 150)
	statsGrid.Parent = ratingsView

	local statsLayout = Instance.new("UIGridLayout")
	statsLayout.CellSize = UDim2.new(0.5, -12, 0, 70)
	statsLayout.CellPadding = UDim2.fromOffset(12, 10)
	statsLayout.FillDirectionMaxCells = 2
	statsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Parent = statsGrid

	createStatCard(statsGrid, "Value", "Property Value")
	createStatCard(statsGrid, "Land", "Unlocked Land")
	createStatCard(statsGrid, "Household", "Household")
	createStatCard(statsGrid, "Income", "Passive Income")

	local ratingList = Instance.new("ScrollingFrame")
	ratingList.Name = "RatingList"
	ratingList.Size = UDim2.new(1, -4, 1, -170)
	ratingList.Position = UDim2.fromOffset(0, 170)
	ratingList.ScrollBarThickness = 4
	ratingList.CanvasSize = UDim2.new()
	ratingList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ratingList.BackgroundTransparency = 1
	ratingList.BorderSizePixel = 0
	ratingList.Parent = ratingsView

	local ratingPadding = Instance.new("UIPadding")
	ratingPadding.PaddingTop = UDim.new(0, 8)
	ratingPadding.PaddingBottom = UDim.new(0, 12)
	ratingPadding.Parent = ratingList

	local ratingLayout = Instance.new("UIListLayout")
	ratingLayout.FillDirection = Enum.FillDirection.Vertical
	ratingLayout.SortOrder = Enum.SortOrder.LayoutOrder
	ratingLayout.Padding = UDim.new(0, 12)
	ratingLayout.Parent = ratingList

	for _, definition in CategoryDefinitions do
		createRatingCard(ratingList, definition)
	end

	local tenantsView = Instance.new("ScrollingFrame")
	tenantsView.Name = "TenantsView"
	tenantsView.Position = UDim2.new(0, 0, 0, 0)
	tenantsView.Size = UDim2.new(1, -4, 1, 0)
	tenantsView.BackgroundTransparency = 1
	tenantsView.Visible = false
	tenantsView.BorderSizePixel = 0
	tenantsView.ScrollBarThickness = 4
	tenantsView.AutomaticCanvasSize = Enum.AutomaticSize.Y
	tenantsView.CanvasSize = UDim2.new()
	tenantsView.Parent = body

	local tenantsPadding = Instance.new("UIPadding")
	tenantsPadding.PaddingTop = UDim.new(0, 4)
	tenantsPadding.PaddingBottom = UDim.new(0, 12)
	tenantsPadding.Parent = tenantsView

	local tenantsLayout = Instance.new("UIListLayout")
	tenantsLayout.FillDirection = Enum.FillDirection.Vertical
	tenantsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tenantsLayout.Padding = UDim.new(0, 12)
	tenantsLayout.Parent = tenantsView

	local emptyLabel = Instance.new("TextLabel")
	emptyLabel.BackgroundTransparency = 1
	emptyLabel.Size = UDim2.new(1, 0, 0, 60)
	emptyLabel.Font = Enum.Font.Gotham
	emptyLabel.TextSize = 16
	emptyLabel.TextColor3 = Theme.TextSecondary
	emptyLabel.Text = "No tenants are living here yet."
	emptyLabel.Visible = true
	emptyLabel.Parent = tenantsView

	local renameOverlay = Instance.new("Frame")
	renameOverlay.Name = "RenameOverlay"
	renameOverlay.BackgroundColor3 = Theme.Shadow
	renameOverlay.BackgroundTransparency = 0.55
	renameOverlay.Visible = false
	renameOverlay.Active = true
	renameOverlay.Size = UDim2.fromScale(1, 1)
	renameOverlay.ZIndex = 40
	renameOverlay.Parent = panel

	local scrimButton = Instance.new("TextButton")
	scrimButton.BackgroundTransparency = 1
	scrimButton.BorderSizePixel = 0
	scrimButton.Text = ""
	scrimButton.AutoButtonColor = false
	scrimButton.Size = UDim2.fromScale(1, 1)
	scrimButton.ZIndex = 41
	scrimButton.Parent = renameOverlay
	scrimButton.Activated:Connect(function()
		toggleRenameOverlay(false)
	end)

	local dialog = Instance.new("Frame")
	dialog.Name = "Dialog"
	dialog.AnchorPoint = Vector2.new(0.5, 0.3)
	dialog.Position = UDim2.fromScale(0.5, 0.3)
	dialog.Size = UDim2.new(1, -96, 0, 190)
	dialog.BackgroundColor3 = Theme.Surface
	dialog.ZIndex = 42
	dialog.Parent = renameOverlay

	local dialogCorner = Instance.new("UICorner")
	dialogCorner.CornerRadius = UDim.new(0, 18)
	dialogCorner.Parent = dialog

	local dialogStroke = Instance.new("UIStroke")
	dialogStroke.Color = Theme.PanelStroke
	dialogStroke.Transparency = 0.35
	dialogStroke.Thickness = 1.25
	dialogStroke.Parent = dialog

	local dialogPadding = Instance.new("UIPadding")
	dialogPadding.PaddingTop = UDim.new(0, 20)
	dialogPadding.PaddingBottom = UDim.new(0, 20)
	dialogPadding.PaddingLeft = UDim.new(0, 24)
	dialogPadding.PaddingRight = UDim.new(0, 24)
	dialogPadding.Parent = dialog

	local dialogTitle = Instance.new("TextLabel")
	dialogTitle.BackgroundTransparency = 1
	dialogTitle.Size = UDim2.new(1, 0, 0, 28)
	dialogTitle.Font = Enum.Font.GothamBold
	dialogTitle.TextSize = 22
	dialogTitle.TextColor3 = Theme.TextPrimary
	dialogTitle.TextXAlignment = Enum.TextXAlignment.Left
	dialogTitle.Text = "Rename plot"
	dialogTitle.Parent = dialog

	local dialogHint = Instance.new("TextLabel")
	dialogHint.BackgroundTransparency = 1
	dialogHint.Size = UDim2.new(1, 0, 0, 20)
	dialogHint.Position = UDim2.fromOffset(0, 32)
	dialogHint.Font = Enum.Font.Gotham
	dialogHint.TextSize = 14
	dialogHint.TextColor3 = Theme.TextSecondary
	dialogHint.TextXAlignment = Enum.TextXAlignment.Left
	dialogHint.Text = "Between 3 and 24 characters."
	dialogHint.Parent = dialog

	local inputBox = Instance.new("TextBox")
	inputBox.BackgroundColor3 = Theme.SurfaceElevated
	inputBox.BorderSizePixel = 0
	inputBox.ClearTextOnFocus = false
	inputBox.Size = UDim2.new(1, 0, 0, 40)
	inputBox.Position = UDim2.fromOffset(0, 62)
	inputBox.Font = Enum.Font.Gotham
	inputBox.TextSize = 18
	inputBox.TextColor3 = Theme.TextPrimary
	inputBox.PlaceholderColor3 = Theme.TextMuted
	inputBox.PlaceholderText = "Enter a new name"
	inputBox.TextXAlignment = Enum.TextXAlignment.Left
	inputBox.Parent = dialog

	local inputCorner = Instance.new("UICorner")
	inputCorner.CornerRadius = UDim.new(0, 12)
	inputCorner.Parent = inputBox

	local inputStroke = Instance.new("UIStroke")
	inputStroke.Color = Theme.PanelStroke
	inputStroke.Transparency = 0.3
	inputStroke.Parent = inputBox

	local errorLabel = Instance.new("TextLabel")
	errorLabel.BackgroundTransparency = 1
	errorLabel.Size = UDim2.new(1, 0, 0, 20)
	errorLabel.Position = UDim2.fromOffset(0, 106)
	errorLabel.Font = Enum.Font.Gotham
	errorLabel.TextSize = 14
	errorLabel.TextColor3 = Theme.Warning
	errorLabel.TextXAlignment = Enum.TextXAlignment.Left
	errorLabel.Visible = false
	errorLabel.Parent = dialog

	local buttonRow = Instance.new("Frame")
	buttonRow.BackgroundTransparency = 1
	buttonRow.Size = UDim2.new(1, 0, 0, 40)
	buttonRow.Position = UDim2.fromOffset(0, 130)
	buttonRow.Parent = dialog

	local buttonLayout = Instance.new("UIListLayout")
	buttonLayout.FillDirection = Enum.FillDirection.Horizontal
	buttonLayout.Padding = UDim.new(0, 10)
	buttonLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	buttonLayout.Parent = buttonRow

	local cancelButton = Instance.new("TextButton")
	cancelButton.BackgroundColor3 = Theme.Surface
	cancelButton.AutoButtonColor = true
	cancelButton.Size = UDim2.fromOffset(92, 36)
	cancelButton.Font = Enum.Font.Gotham
	cancelButton.TextSize = 15
	cancelButton.Text = "Cancel"
	cancelButton.TextColor3 = Theme.TextPrimary
	cancelButton.Parent = buttonRow

	local cancelCorner = Instance.new("UICorner")
	cancelCorner.CornerRadius = UDim.new(0, 12)
	cancelCorner.Parent = cancelButton

	cancelButton.Activated:Connect(function()
		toggleRenameOverlay(false)
	end)

	local saveButton = Instance.new("TextButton")
	saveButton.BackgroundColor3 = Theme.Accent
	saveButton.AutoButtonColor = true
	saveButton.Size = UDim2.fromOffset(110, 36)
	saveButton.Font = Enum.Font.GothamMedium
	saveButton.TextSize = 15
	saveButton.TextColor3 = Color3.new(1, 1, 1)
	saveButton.Text = "Save"
	saveButton.Parent = buttonRow

	local saveCorner = Instance.new("UICorner")
	saveCorner.CornerRadius = UDim.new(0, 12)
	saveCorner.Parent = saveButton

	saveButton.Activated:Connect(submitRename)

	state.renameOverlay = renameOverlay
	state.renameTextBox = inputBox
	state.renameErrorLabel = errorLabel
	state.renameConfirmButton = saveButton

	state.panelFrame = panel
	state.statsGrid = statsGrid
	state.ratingList = ratingList
	state.ratingsView = ratingsView
	state.tenantsView = tenantsView
	state.emptyTenantsLabel = emptyLabel

	switchTab("Ratings")
end

function ProfilePanel.Show()
	if not state.profileFrame or not state.panelFrame then
		return
	end
	local wasOpen = state.isOpen
	state.profileFrame.Visible = true
	state.isOpen = true
	if not wasOpen then
		visibilityChangedSignal:Fire(true)
	end
	if state.isDirty or not state.lastInsights then
		refreshInsights()
	else
		applyInsights(state.lastInsights)
	end
	tweenPanelVisibility(true)
end

function ProfilePanel.Hide()
	if not state.profileFrame then
		return
	end
	local wasOpen = state.isOpen
	state.isOpen = false
	if wasOpen then
		visibilityChangedSignal:Fire(false)
	end
	toggleRenameOverlay(false)
	if state.panelFrame then
		tweenPanelVisibility(false)
	else
		state.profileFrame.Visible = false
	end
end

function ProfilePanel.Toggle()
	if not state.profileFrame then
		return
	end
	if state.isOpen then
		ProfilePanel.Hide()
	else
		ProfilePanel.Show()
	end
end

function ProfilePanel.Init(profileFrame: Frame)
	if state.profileFrame then
		return
	end
	state.profileFrame = profileFrame
	buildUI(profileFrame)

	profileFrame:GetPropertyChangedSignal("Visible"):Connect(function()
		if not profileFrame.Visible and state.isOpen then
			state.isOpen = false
			toggleRenameOverlay(false)
			visibilityChangedSignal:Fire(false)
		end
	end)

	bindPlotModel()

	externalConnections[#externalConnections + 1] = Player:GetAttributeChangedSignal("OwnedPlotIndex")
		:Connect(function()
			bindPlotModel()
		end)

	externalConnections[#externalConnections + 1] = ResidentsStore.ResidentsUpdated:Connect(function(userId: number)
		if userId == Player.UserId then
			markDirty()
		end
	end)

	externalConnections[#externalConnections + 1] = ResidentsStore.ResidentAdded:Connect(function(userId: number)
		if userId == Player.UserId then
			markDirty()
		end
	end)

	externalConnections[#externalConnections + 1] = ResidentsStore.ResidentRemoved:Connect(function(userId: number)
		if userId == Player.UserId then
			markDirty()
		end
	end)

	externalConnections[#externalConnections + 1] = TenantStore.TenantsUpdated:Connect(function(userId: number)
		if userId == Player.UserId then
			markDirty()
		end
	end)

	externalConnections[#externalConnections + 1] = TenantStore.TenantAdded:Connect(function(userId: number)
		if userId == Player.UserId then
			markDirty()
		end
	end)

	externalConnections[#externalConnections + 1] = TenantStore.TenantRemoved:Connect(function(userId: number)
		if userId == Player.UserId then
			markDirty()
		end
	end)

	externalConnections[#externalConnections + 1] = PlotStateStore.OnRoomSnapshotChanged(function()
		markDirty()
	end)

	externalConnections[#externalConnections + 1] = PlotStateStore.OnPlacementMetadataChanged(function()
		markDirty()
	end)
end

return ProfilePanel
