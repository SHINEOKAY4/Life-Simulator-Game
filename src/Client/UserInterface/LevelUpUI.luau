--!strict
-- StarterPlayerScripts/Client/UserInterface/LevelUpUI.luau
-- Celebratory level-up overlay with unlocked-item roll and confetti.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local ProgressionPackets = require(ReplicatedStorage.Network.ProgressionPackets)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local VisualFX = require(ReplicatedStorage.Shared.Utilities.VisualFX)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local LevelUpGui = PlayerGui:WaitForChild("LevelUpGui") :: ScreenGui
local MainFrame = LevelUpGui:WaitForChild("Main") :: Frame
local Background = MainFrame:WaitForChild("Background") :: GuiObject
local UnlockedItemFrame = MainFrame:WaitForChild("UnlockedItemFrame") :: Frame
local ItemsScrollingFrame = UnlockedItemFrame:WaitForChild("ScrollingFrame") :: ScrollingFrame
local GraphicFrame = MainFrame:WaitForChild("Graphic") :: Frame
local CounterFrame = GraphicFrame:WaitForChild("Counter") :: Frame
local LevelLabel = GraphicFrame:WaitForChild("LevelLabel") :: TextLabel
local HeaderFrame = MainFrame:WaitForChild("Header") :: Frame
local TitleFrame = HeaderFrame:WaitForChild("Title") :: Frame
local TextFrame = TitleFrame:WaitForChild("Text") :: Frame
local TitleLabel = TextFrame:WaitForChild("TitleLabel") :: TextLabel
local TitleLabelStroke = TextFrame:WaitForChild("TitleLabelStroke") :: TextLabel
local ContinueButton = MainFrame:WaitForChild("ContinueButton") :: GuiButton
local ActiveQueryFolder = PlayerGui:WaitForChild("ActiveQuery")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local TemplatesFolder = AssetsFolder:WaitForChild("InterfacesTemplates")
local ItemUnlockedTemplate = TemplatesFolder:WaitForChild("ItemUnlockedButton") :: GuiButton

local function clearUIScales(target: Instance)
	for _, child in ipairs(target:GetChildren()) do
		if child:IsA("UIScale") then
			child:Destroy()
		end
	end
end

local hideToken = 0
local THUMBNAIL_TEMPLATE = "rbxthumb://type=Asset&id=%d&w=420&h=420"
local PLACEHOLDER_THUMBNAIL = "rbxasset://textures/ui/GuiImagePlaceholder.png"
local OVERLAY_SUPPRESSION_TARGETS = table.freeze({
	"PlotBuilderEnabled",
	"PlotExpansionEnabled",
	"ObjectPreviewEnabled",
	"ObjectSelectorEnabled",
	"ResidentRosterEnabled",
	"HUDBottomRightEnabled",
	"RadialBillboardButtonEnabled",
	"PlotGridOverlayEnabled",
	"ResidentUIEnabled",
})

local overlayRestoreMap: { [string]: boolean } = {}

local LevelUpOverlayValue = (function()
	local existing = ActiveQueryFolder:FindFirstChild("LevelUpOverlayActive")
	if existing and existing:IsA("BoolValue") then
		return existing
	end
	local value = Instance.new("BoolValue")
	value.Name = "LevelUpOverlayActive"
	value.Value = false
	value.Parent = ActiveQueryFolder
	return value
end)()

local function applyOverlaySuppression()
	for _, name in ipairs(OVERLAY_SUPPRESSION_TARGETS) do
		local boolValue = ActiveQueryFolder:FindFirstChild(name)
		if boolValue and boolValue:IsA("BoolValue") then
			if overlayRestoreMap[name] == nil then
				overlayRestoreMap[name] = boolValue.Value
			end
			boolValue.Value = false
		end
	end
	LevelUpOverlayValue.Value = true
end

local function releaseOverlaySuppression()
	for name, previous in overlayRestoreMap do
		local boolValue = ActiveQueryFolder:FindFirstChild(name)
		if boolValue and boolValue:IsA("BoolValue") then
			boolValue.Value = previous
		end
		overlayRestoreMap[name] = nil
	end
	LevelUpOverlayValue.Value = false
end

local ConfettiLayer = (function()
	local existing = LevelUpGui:FindFirstChild("ConfettiLayer")
	if existing and existing:IsA("Frame") then
		existing.BackgroundTransparency = 1
		existing.ClipsDescendants = false
		existing.Size = UDim2.fromScale(1, 1)
		existing.Position = UDim2.fromScale(0, 0)
		existing.ZIndex = 999
		return existing
	end
	local effectFrame = Instance.new("Frame")
	effectFrame.Name = "ConfettiLayer"
	effectFrame.BackgroundTransparency = 1
	effectFrame.ClipsDescendants = false
	effectFrame.Active = false
	effectFrame.Size = UDim2.fromScale(1, 1)
	effectFrame.Position = UDim2.fromScale(0, 0)
	effectFrame.ZIndex = 999
	effectFrame.Parent = LevelUpGui
	return effectFrame
end)()

local LevelUpSound: Sound = (function()
	local existing = SoundService:FindFirstChild("LevelUpCelebration")
	if existing and existing:IsA("Sound") then
		return existing
	end
	local sound = Instance.new("Sound")
	sound.Name = "LevelUpCelebration"
	sound.SoundId = "rbxassetid://103126237078653" -- Placeholder: Victory/Success Sound
	sound.Volume = 0.8
	sound.Parent = SoundService
	return sound
end)()

local ConfettiColors = table.freeze({
	Color3.fromRGB(255, 116, 149),
	Color3.fromRGB(255, 203, 99),
	Color3.fromRGB(132, 248, 171),
	Color3.fromRGB(120, 183, 255),
	Color3.fromRGB(191, 153, 255),
})

local ENTRY_SLIDE_IN_SECONDS = 0.25
local CONFETTI_TWEEN = TweenInfo.new(1.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
local HEADER_FADE = TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function formatCurrency(amount: number): string
	local integer = math.floor(amount + 0.5)
	local str = tostring(integer)
	local result = ""
	local count = 0
	for index = #str, 1, -1 do
		count += 1
		result = string.sub(str, index, index) .. result
		if count % 3 == 0 and index > 1 then
			result = "," .. result
		end
	end
	return "$" .. result
end

local function normalizeUnlockedIds(payloadIds: any): { string }
	local normalized: { string } = {}
	if typeof(payloadIds) ~= "table" then
		return normalized
	end
	for _, value in ipairs(payloadIds) do
		if typeof(value) == "string" and value ~= "" then
			normalized[#normalized + 1] = value
		end
	end
	return normalized
end

local function playSound()
	LevelUpSound.TimePosition = 0
	LevelUpSound:Play()
end

local function clearItemList()
	for _, child in ipairs(ItemsScrollingFrame:GetChildren()) do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function setTextOnDescendant(root: Instance, names: { string }, text: string)
	for _, name in ipairs(names) do
		local descendant = root:FindFirstChild(name, true)
		if descendant then
			if descendant:IsA("TextLabel") then
				(descendant :: TextLabel).Text = text
				return
			end
			if descendant:IsA("TextButton") then
				(descendant :: TextButton).Text = text
				return
			end
		end
	end
end

local function coerceThumbnailSource(value: any): string?
	if typeof(value) == "number" then
		local rounded = math.floor(value + 0.5)
		if rounded > 0 then
			return string.format(THUMBNAIL_TEMPLATE, rounded)
		end
		return nil
	end
	if typeof(value) == "string" and value ~= "" then
		if
			string.find(value, "rbxthumb://", 1, true)
			or string.find(value, "rbxassetid://", 1, true)
			or string.find(value, "rbxasset://", 1, true)
		then
			return value
		end
		local numericValue = tonumber(value)
		if numericValue and numericValue > 0 then
			return string.format(THUMBNAIL_TEMPLATE, math.floor(numericValue + 0.5))
		end
		local digits = string.match(value, "(%d+)")
		if digits then
			local parsed = tonumber(digits)
			if parsed and parsed > 0 then
				return string.format(THUMBNAIL_TEMPLATE, parsed)
			end
		end
	end
	return nil
end

local function resolveItemImage(spec: { [string]: any }?): string
	if not spec then
		return PLACEHOLDER_THUMBNAIL
	end
	local candidates = {
		spec.AssetId,
		spec.IconId,
		spec.IconImageId,
		spec.ImageId,
	}
	for _, candidate in ipairs(candidates) do
		local resolved = coerceThumbnailSource(candidate)
		if resolved then
			return resolved
		end
	end
	return PLACEHOLDER_THUMBNAIL
end

local function makeUnlockEntry(itemId: string, layoutOrder: number)
	local spec = ItemFinder.FindItemById(itemId)
	local button = ItemUnlockedTemplate:Clone()
	button.Name = string.format("Unlocked_%s", itemId)
	button.LayoutOrder = layoutOrder
	button.Visible = true
	if button:IsA("GuiButton") then
		button.AutoButtonColor = false
		button.Active = false
		button.Selectable = false
	end

	local itemName = if spec and typeof(spec.Name) == "string" and spec.Name ~= "" then spec.Name else itemId
	local description = if spec
			and typeof(spec.Description) == "string"
			and spec.Description ~= ""
		then spec.Description
		else "Now available in your catalog."

	setTextOnDescendant(button, { "ItemName", "Title", "Label", "MainText" }, itemName)
	setTextOnDescendant(button, { "ItemDescription", "Description", "Body", "BodyText", "Details" }, description)

	if spec and typeof(spec.Cost) == "number" and spec.Cost > 0 then
		setTextOnDescendant(button, { "Cost", "Price", "PriceLabel" }, formatCurrency(spec.Cost))
	end

	local assetId = resolveItemImage(spec)
	if button:IsA("ImageButton") or button:IsA("ImageLabel") then
		(button :: ImageButton).Image = assetId
	end

	button.Parent = ItemsScrollingFrame
	VisualFX.SlideIn(button, "Right", ENTRY_SLIDE_IN_SECONDS)
end

local function spawnConfettiWave(count: number)
	ConfettiLayer.Visible = true
	for index = 1, count do
		task.delay((index - 1) * 0.03, function()
			if not ConfettiLayer.Parent then
				return
			end
			local shard = Instance.new("Frame")
			shard.Name = "ConfettiShard"
			shard.BorderSizePixel = 0
			shard.BackgroundColor3 = ConfettiColors[(index - 1) % #ConfettiColors + 1]
			shard.BackgroundTransparency = 0
			shard.Size = UDim2.fromOffset(math.random(6, 14), math.random(12, 24))
			shard.AnchorPoint = Vector2.new(0.5, 0.5)
			shard.Position = UDim2.fromScale(math.random(), -0.05)
			shard.Rotation = math.random(-45, 45)
			shard.ZIndex = ConfettiLayer.ZIndex + 1
			shard.Parent = ConfettiLayer

			local targetX = math.clamp(shard.Position.X.Scale + (math.random() - 0.5) * 0.25, 0, 1)
			local rotationDelta = math.random(180, 540)
			local tween = TweenService:Create(shard, CONFETTI_TWEEN, {
				Position = UDim2.fromScale(targetX, 1.1),
				Rotation = shard.Rotation + rotationDelta,
				BackgroundTransparency = 1,
			})
			tween.Completed:Connect(function()
				shard:Destroy()
				if #ConfettiLayer:GetChildren() == 0 then
					ConfettiLayer.Visible = false
				end
			end)
			tween:Play()
		end)
	end
end

local function playConfetti()
	spawnConfettiWave(28)
	task.delay(0.18, function()
		spawnConfettiWave(22)
	end)
end

local function setHeaderText(text: string)
	TitleLabel.Text = text
	TitleLabelStroke.Text = text
end

local function setHeaderTransparency(alpha: number)
	TitleLabel.TextTransparency = alpha
	TitleLabelStroke.TextTransparency = alpha
end

local function animateHeader()
	setHeaderTransparency(1)
	local labelTween = TweenService:Create(TitleLabel, HEADER_FADE, {
		TextTransparency = 0,
	})
	local strokeTween = TweenService:Create(TitleLabelStroke, HEADER_FADE, {
		TextTransparency = 0,
	})
	labelTween:Play()
	strokeTween:Play()
end

local function showLevelUp(level: number, itemIds: { string })
	hideToken += 1
	clearUIScales(MainFrame)
	applyOverlaySuppression()
	MainFrame.Visible = true
	setHeaderText(string.format("Level %d Complete", level))
	LevelLabel.Text = tostring(level)
	ItemsScrollingFrame.CanvasPosition = Vector2.new(0, 0)
	UnlockedItemFrame.Visible = #itemIds > 0

	clearItemList()
	for index, itemId in ipairs(itemIds) do
		makeUnlockEntry(itemId, index)
	end

	VisualFX.BounceIn(MainFrame, 0.35)
	VisualFX.Pulse(CounterFrame, 1.12, 0.5)
	if Background:IsA("Frame") then
		VisualFX.ColorSweep(Background, Color3.fromRGB(21, 20, 30), Background.BackgroundColor3, 0.6)
	end
	animateHeader()
	playConfetti()
	playSound()
end

local function hideLevelUp()
	hideToken += 1
	local currentToken = hideToken
	if not MainFrame.Visible then
		releaseOverlaySuppression()
		return
	end
	VisualFX.Collapse(MainFrame, 0.18)
	task.delay(0.2, function()
		if hideToken ~= currentToken then
			return
		end
		MainFrame.Visible = false
		clearUIScales(MainFrame)
		releaseOverlaySuppression()
	end)
end

local lastKnownLevel = if typeof(LocalPlayer:GetAttribute("PlayerLevel")) == "number"
	then LocalPlayer:GetAttribute("PlayerLevel") :: number
	else 1

local function onProgressionUpdate(payload: any)
	local targetLevel = if typeof(payload) == "table" and typeof(payload.Level) == "number"
		then payload.Level
		else lastKnownLevel
	local unlockedIds = normalizeUnlockedIds(payload and payload.UnlockedItemIds)
	local leveledUp = targetLevel > lastKnownLevel
	lastKnownLevel = targetLevel

	if not leveledUp and #unlockedIds == 0 then
		return
	end

	showLevelUp(targetLevel, unlockedIds)
end

local LevelUpUI = {}
local isInitialized = false

function LevelUpUI.Hide()
	hideLevelUp()
end

function LevelUpUI.Init()
	if isInitialized then
		return
	end
	isInitialized = true
	MainFrame.Visible = false
	ConfettiLayer.Visible = false
	ContinueButton.Activated:Connect(hideLevelUp)
	ProgressionPackets.ProgressionUpdate.OnClientEvent:Connect(onProgressionUpdate)
end

return LevelUpUI
