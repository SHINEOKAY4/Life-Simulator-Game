--!strict
-- StarterPlayerScripts/UserInterface/ProfileUI.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local ResidentsFolderFinder = require(ReplicatedStorage.Shared.Utilities.ResidentsFolderFinder)
local VisualFX = require(ReplicatedStorage.Shared.Utilities.VisualFX)
local ComfortRating = require(ReplicatedStorage.Shared.Utilities.ComfortRating)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local TenantStore = require(script.Parent.Parent.ClientStores.TenantStore)
local PlacementPackets = require(ReplicatedStorage.Network.PlacementPackets)
local ReviewsUI = require(script.Parent.ReviewsUI)
local TenantProfileUI = require(script.Parent.TenantProfileUI)
local TemperatureController = require(script.Parent.Parent.Modules.TemperatureController)
local ResidentsStore = require(script.Parent.Parent.ClientStores.ResidentsStore)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ActiveQueryFolder = (PlayerGui:FindFirstChild("ActiveQuery") or PlayerGui:WaitForChild("ActiveQuery")) :: Folder

local HudBottomRightFlag = ActiveQueryFolder:FindFirstChild("HUDBottomRightEnabled") :: BoolValue?

local ProfileGui = PlayerGui:WaitForChild("ProfileGui") :: ScreenGui
local MainFrame = ProfileGui:WaitForChild("Main") :: Frame
local WindowFrame = MainFrame:WaitForChild("Window") :: Frame
local BodyFrame = WindowFrame:WaitForChild("Body") :: Frame
local RightPanel = BodyFrame:WaitForChild("RightPanel") :: Frame
local StatsFrame = RightPanel:WaitForChild("StatsFrame") :: Frame
local HouseholdStatLabel = (StatsFrame:WaitForChild("HouseholdStat") :: Frame):WaitForChild("NumberLabel") :: TextLabel
local IncomeStatLabel = (StatsFrame:WaitForChild("IncomeStat") :: Frame):WaitForChild("NumberLabel") :: TextLabel
local LandStatLabel = (StatsFrame:WaitForChild("LandStat") :: Frame):WaitForChild("NumberLabel") :: TextLabel
local ValueStatLabel = (StatsFrame:WaitForChild("ValueStat") :: Frame):WaitForChild("NumberLabel") :: TextLabel

local RenameButton = RightPanel:WaitForChild("RenameButton") :: TextButton
local TextBox = RightPanel:WaitForChild("TextBox") :: TextBox

local RatingsFrame = BodyFrame:WaitForChild("RatingsFrame") :: Frame
local RatingsScrollingFrame = RatingsFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local AtmosphereFrame = RatingsScrollingFrame:WaitForChild("AtmosphereCard") :: Frame
local CleanlinessFrame = RatingsScrollingFrame:WaitForChild("CleanlinessCard") :: Frame
local ComfortFrame = RatingsScrollingFrame:WaitForChild("ComfortCard") :: Frame
local StyleFrame = RatingsScrollingFrame:WaitForChild("StyleCard") :: Frame
local LightingFrame = RatingsScrollingFrame:WaitForChild("LightingCard") :: Frame

local AtmosphereRatingLabel = AtmosphereFrame:WaitForChild("RatingLabel") :: TextLabel
local CleanlinessRatingLabel = CleanlinessFrame:WaitForChild("RatingLabel") :: TextLabel
local ComfortRatingLabel = ComfortFrame:WaitForChild("RatingLabel") :: TextLabel
local StyleRatingLabel = StyleFrame:WaitForChild("RatingLabel") :: TextLabel
local LightingRatingLabel = LightingFrame:WaitForChild("RatingLabel") :: TextLabel

local AtmosphereStarsFrame = AtmosphereFrame:WaitForChild("Stars") :: Frame
local CleanlinessStarsFrame = CleanlinessFrame:WaitForChild("Stars") :: Frame
local ComfortStarsFrame = ComfortFrame:WaitForChild("Stars") :: Frame
local StyleStarsFrame = StyleFrame:WaitForChild("Stars") :: Frame
local LightingStarsFrame = LightingFrame:WaitForChild("Stars") :: Frame

local CloseButton = (BodyFrame:WaitForChild("ImageLabel") :: Frame):WaitForChild("CloseButton") :: ImageButton

local PROPERTY_VALUE_ATTRIBUTE_NAME = "PropertyValue"
local INCOME_RATE_ATTRIBUTE_NAME = "TenantIncomePerSecond"

local STAR_FILLED_COLOR = Color3.fromRGB(255, 209, 92)
local STAR_HALF_COLOR = Color3.fromRGB(255, 233, 163)
local STAR_EMPTY_COLOR = Color3.fromRGB(120, 120, 120)

local VALUE_DISPLAY_OPTIONS = {
	currencySymbol = "$",
	decimalPlaces = 1,
	useAbbreviation = true,
	useCommas = true,
}

local INCOME_DISPLAY_OPTIONS = {
	currencySymbol = "$",
	decimalPlaces = 1,
	useAbbreviation = true,
	useCommas = true,
}

type RatingRule = {
	tags: { string }?,
	stationTypes: { [string]: boolean }?,
	tagLookup: { [string]: boolean }?,
	stationLookup: { [string]: boolean }?,
	scale: number,
}

local ratingRules: { [string]: RatingRule } = {
	Atmosphere = {
		tags = { "Nature", "Plant", "PointOfInterest", "Fire", "Garden" },
		scale = 6,
	},
	Cleanliness = {
		tags = { "Bath", "Hygiene", "Utility", "Toilet", "Water" },
		stationTypes = { HygieneStation = true },
		scale = 4,
	},
	Comfort = {
		tags = { "Comfort", "Seating", "Bed" },
		stationTypes = { RestStation = true, ComfortStation = true },
		scale = 5,
	},
	Style = {
		tags = { "Modern", "Luxury", "Elegant", "Decor", "Rug" },
		scale = 6,
	},
	Lighting = {
		tags = { "Lighting", "Light", "Ceiling" },
		scale = 4,
	},
}

for _, rule in ratingRules do
	if rule.tags then
		local lookup = {}
		for _, tag in ipairs(rule.tags) do
			lookup[tag] = true
		end
		rule.tagLookup = lookup
	end
	rule.stationLookup = rule.stationTypes
	rule.scale = math.max(rule.scale, 1)
end

local ratingWidgets = {
	Atmosphere = { label = AtmosphereRatingLabel, stars = AtmosphereStarsFrame },
	Cleanliness = { label = CleanlinessRatingLabel, stars = CleanlinessStarsFrame },
	Comfort = { label = ComfortRatingLabel, stars = ComfortStarsFrame },
	Style = { label = StyleRatingLabel, stars = StyleStarsFrame },
	Lighting = { label = LightingRatingLabel, stars = LightingStarsFrame },
}

local POPUP_OPTIONS = {
	hiddenScale = 0.92,
}

local starCache: { [Frame]: { TextLabel } } = {}
local isInitialized = false
local isVisible = false
local residentsFolder: Folder?
local propertyValueConn: RBXScriptConnection?
local residentsFolderAncestryConn: RBXScriptConnection?
local plotSnapshotConn: RBXScriptConnection?
local unlockDeltaConn: any
local hudBottomRightSuppressed = false
local hudBottomRightRestoreValue: boolean? = nil

local function suppressHudBottomRight()
	if hudBottomRightSuppressed or not HudBottomRightFlag then
		return
	end
	hudBottomRightSuppressed = true
	hudBottomRightRestoreValue = HudBottomRightFlag.Value
	HudBottomRightFlag.Value = false
end

local function restoreHudBottomRight()
	if not hudBottomRightSuppressed or not HudBottomRightFlag then
		return
	end
	hudBottomRightSuppressed = false
	local fallback = if hudBottomRightRestoreValue ~= nil then hudBottomRightRestoreValue else true
	HudBottomRightFlag.Value = fallback
	hudBottomRightRestoreValue = nil
end

local function getOrderedStars(starsFrame: Frame): { TextLabel }
	local cached = starCache[starsFrame]
	if cached then
		return cached
	end
	local labels = {}
	for _, child in ipairs(starsFrame:GetChildren()) do
		if child:IsA("TextLabel") then
			labels[#labels + 1] = child
		end
	end
	table.sort(labels, function(left, right)
		return left.LayoutOrder < right.LayoutOrder
	end)
	starCache[starsFrame] = labels
	return labels
end

local function applyStars(starsFrame: Frame, ratingValue: number)
	local ordered = getOrderedStars(starsFrame)
	for index, label in ipairs(ordered) do
		local starProgress = ratingValue - (index - 1)
		if starProgress >= 1 then
			label.TextColor3 = STAR_FILLED_COLOR
			label.TextTransparency = 0
		elseif starProgress >= 0.5 then
			label.TextColor3 = STAR_HALF_COLOR
			label.TextTransparency = 0
		else
			label.TextColor3 = STAR_EMPTY_COLOR
			label.TextTransparency = 0.35
		end
	end
end

local function applyRating(ratingName: string, ratingValue: number)
	local widget = ratingWidgets[ratingName]
	if not widget then
		return
	end
	local clamped = math.clamp(ratingValue, 0, 5)
	local labelText = if clamped <= 0 then "0/5" else string.format("%.1f/5", clamped)
	widget.label.Text = labelText
	applyStars(widget.stars, clamped)
end

local function convertCountToRating(count: number, scale: number): number
	if scale <= 0 then
		scale = 1
	end
	local normalized = math.clamp(count / scale, 0, 1)
	local rating = normalized * 5
	return math.floor(rating * 10 + 0.5) / 10
end

-- Calculate average temperature across all rooms
local function getAverageRoomTemperature(): number?
	local snapshot = PlotStateStore.GetStateSnapshot()
	if not snapshot then
		return nil
	end

	local totalTemp = 0
	local roomCount = 0
	local maxLevel = snapshot.MaxLevel or 0

	for level = 0, maxLevel do
		local rooms = PlotStateStore.GetRoomsForLevel(level)
		if rooms then
			for _, room in ipairs(rooms) do
				if room.CellCount > 0 then
					local temp = TemperatureController.GetTemperature(level, room.Id)
					if typeof(temp) == "number" then
						totalTemp += temp
						roomCount += 1
					end
				end
			end
		end
	end

	if roomCount == 0 then
		return nil
	end

	return totalTemp / roomCount
end

local function recomputeRatings()
	local snapshot = PlotStateStore.GetStateSnapshot()
	local placedItems = snapshot.PlacedItems
	if not placedItems then
		for ratingName in pairs(ratingRules) do
			applyRating(ratingName, 0)
		end
		return
	end

	local counts: { [string]: number } = {}
	for ratingName in pairs(ratingRules) do
		counts[ratingName] = 0
	end

	-- Standard tag-based counting for most categories
	for _, record in pairs(placedItems) do
		local itemId = record.id
		if typeof(itemId) == "string" and itemId ~= "" then
			local spec = ItemFinder.FindItemById(itemId)
			if spec then
				local tags = spec.Tags
				local stationType = spec.StationType
				for ratingName, rule in pairs(ratingRules) do
					-- Skip Comfort category - we'll handle it separately
					if ratingName == "Comfort" then
						continue
					end

					local matched = false
					if rule.stationLookup and typeof(stationType) == "string" and rule.stationLookup[stationType] then
						matched = true
					elseif tags and rule.tagLookup then
						for _, tag in ipairs(tags) do
							if rule.tagLookup[tag] then
								matched = true
								break
							end
						end
					end
					if matched then
						counts[ratingName] = (counts[ratingName] or 0) + 1
					end
				end
			end
		end
	end

	-- Apply standard ratings (except Comfort)
	for ratingName, rule in pairs(ratingRules) do
		if ratingName ~= "Comfort" then
			local rawCount = counts[ratingName] or 0
			local ratingValue = convertCountToRating(rawCount, rule.scale)
			applyRating(ratingName, ratingValue)
		end
	end

	-- Calculate comprehensive Comfort rating
	local avgTemp = getAverageRoomTemperature()
	local residents = ResidentsStore.GetResidents(Player.UserId)
	local tenants = TenantStore.GetTenants(Player.UserId)

	local residentCount = 0
	if residents then
		for _ in pairs(residents) do
			residentCount += 1
		end
	end

	local tenantCount = 0
	if tenants then
		for _ in pairs(tenants) do
			tenantCount += 1
		end
	end

	local comfortComponents = ComfortRating.Calculate(placedItems, avgTemp, residentCount, tenantCount)
	local comfortStars = ComfortRating.ScoreToStars(comfortComponents.TotalScore)
	applyRating("Comfort", comfortStars)
end

local function updateLandStat()
	local snapshot = PlotStateStore.GetStateSnapshot()
	local chunkInfo = snapshot.ChunkInfo
	local chunkUnlocked = snapshot.ChunkUnlocked
	if typeof(chunkInfo) ~= "table" or not chunkUnlocked then
		LandStatLabel.Text = "0%"
		return
	end
	local columns = tonumber(chunkInfo.ChunkColumns)
	local rows = tonumber(chunkInfo.ChunkRows)
	if not columns or not rows or columns <= 0 or rows <= 0 then
		LandStatLabel.Text = "0%"
		return
	end
	local totalChunks = columns * rows
	local unlocked = 0
	for _, isUnlocked in chunkUnlocked do
		if isUnlocked == true then
			unlocked = unlocked + 1
		end
	end
	local percent = math.clamp(unlocked / totalChunks, 0, 1)
	LandStatLabel.Text = string.format("%d%%", math.floor(percent * 100 + 0.5))
end

local function updateHouseholdStat()
	local tenants = TenantStore.GetTenants(Player.UserId)
	local count = 0
	if tenants then
		for _ in tenants do
			count = count + 1
		end
	end
	HouseholdStatLabel.Text = tostring(count)
end

local function updateIncomeStat()
	local ratePerSecond = Player:GetAttribute(INCOME_RATE_ATTRIBUTE_NAME)
	local numeric = if typeof(ratePerSecond) == "number" then math.max(ratePerSecond, 0) else 0
	local perHour = numeric * 3600
	local formatted = Formatter.formatCurrency(perHour, INCOME_DISPLAY_OPTIONS)
	IncomeStatLabel.Text = string.format("%s/hr", formatted)
end

local function updatePropertyValueFromAttribute(value: any)
	local numeric = if typeof(value) == "number" then math.max(value, 0) else 0
	ValueStatLabel.Text = Formatter.formatCurrency(numeric, VALUE_DISPLAY_OPTIONS)
end

local function disconnectFolderSignals()
	if propertyValueConn then
		propertyValueConn:Disconnect()
		propertyValueConn = nil
	end
	if residentsFolderAncestryConn then
		residentsFolderAncestryConn:Disconnect()
		residentsFolderAncestryConn = nil
	end
end

local function attachResidentsFolder(folder: Folder?)
	if folder == residentsFolder then
		return
	end
	disconnectFolderSignals()
	residentsFolder = folder
	if folder then
		propertyValueConn = folder:GetAttributeChangedSignal(PROPERTY_VALUE_ATTRIBUTE_NAME):Connect(function()
			updatePropertyValueFromAttribute(folder:GetAttribute(PROPERTY_VALUE_ATTRIBUTE_NAME))
		end)
		residentsFolderAncestryConn = folder.AncestryChanged:Connect(function(_, parent)
			if not parent then
				attachResidentsFolder(nil)
				task.defer(function()
					attachResidentsFolder(ResidentsFolderFinder.FindFolder(Player))
				end)
			end
		end)
		updatePropertyValueFromAttribute(folder:GetAttribute(PROPERTY_VALUE_ATTRIBUTE_NAME))
	else
		updatePropertyValueFromAttribute(nil)
	end
end

local function refreshResidentsFolder()
	attachResidentsFolder(ResidentsFolderFinder.FindFolder(Player))
end

local function ensurePlotConnections()
	if not plotSnapshotConn then
		plotSnapshotConn = PlotStateStore.OnRoomSnapshotChanged(function()
			recomputeRatings()
			updateLandStat()
		end)
	end
	if not unlockDeltaConn then
		unlockDeltaConn = PlacementPackets.PlotStateUnlockDelta.OnClientEvent:Connect(function()
			task.defer(updateLandStat)
		end) :: any
	end
end

local ProfileUI = {}

local function hideConflictingInterfaces()
	ReviewsUI.SetVisible(false)
	-- Hide BillUI
	local billGui = PlayerGui:FindFirstChild("BillGUI")
	if billGui and billGui:IsA("ScreenGui") then
		local mainFrame = billGui:FindFirstChild("Main")
		if mainFrame and mainFrame.Visible then
			local ok, module = pcall(require, script.Parent.BillUI)
			if ok and module and typeof(module.Hide) == "function" then
				module.Hide()
			end
		end
	end
	if TenantProfileUI and typeof(TenantProfileUI.Hide) == "function" then
		TenantProfileUI.Hide()
	end
end

local function setVisible(visible: boolean)
	if isVisible == visible then
		if visible then
			hideConflictingInterfaces()
		end
		return
	end
	isVisible = visible
	if visible then
		suppressHudBottomRight()
		hideConflictingInterfaces()
		MainFrame.Visible = true
		VisualFX.SetPopupVisible(WindowFrame, true, POPUP_OPTIONS)
		return
	end
	restoreHudBottomRight()
	VisualFX.SetPopupVisible(WindowFrame, false, {
		hiddenScale = POPUP_OPTIONS.hiddenScale,
		onHidden = function()
			if not isVisible then
				MainFrame.Visible = false
			end
		end,
	})
end

function ProfileUI.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	MainFrame.Visible = false
	WindowFrame.Visible = false
	TextBox.TextEditable = false

	CloseButton.Activated:Connect(function()
		ProfileUI.Hide()
	end)

	RenameButton.Activated:Connect(function()
		TextBox.TextEditable = true
		TextBox:CaptureFocus()
	end)

	TextBox.FocusLost:Connect(function()
		TextBox.TextEditable = false
	end)

	Player:GetAttributeChangedSignal(INCOME_RATE_ATTRIBUTE_NAME):Connect(updateIncomeStat)
	Player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		task.defer(refreshResidentsFolder)
	end)

	TenantStore.TenantAdded:Connect(updateHouseholdStat)
	TenantStore.TenantRemoved:Connect(updateHouseholdStat)
	TenantStore.TenantsUpdated:Connect(updateHouseholdStat)

	ensurePlotConnections()
	refreshResidentsFolder()
	updateHouseholdStat()
	updateIncomeStat()
	updateLandStat()
	recomputeRatings()

	setVisible(false)
end

function ProfileUI.Show()
	if not isInitialized then
		ProfileUI.Init()
	end
	setVisible(true)
end

function ProfileUI.Hide()
	if not isInitialized then
		return
	end
	setVisible(false)
end

function ProfileUI.Toggle()
	if not isInitialized then
		ProfileUI.Init()
	end
	setVisible(not isVisible)
end

return ProfileUI
