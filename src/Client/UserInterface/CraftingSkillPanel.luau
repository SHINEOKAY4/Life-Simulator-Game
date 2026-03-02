--!strict
-- CraftingSkillPanel.luau
-- Shows per-skill progression bars (level, current XP, XP to next level).
-- Opens/closes with C (same key as CraftingUI) and updates in real time via
-- SkillSummaryUpdated when a craft completes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local CraftingPackets = require(ReplicatedStorage.Network.CraftingPackets)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local CraftingSkillPanel = {}

type SkillRowRefs = {
	Fill: Frame,
	XpLabel: TextLabel,
	LevelLabel: TextLabel,
}

local RootGui: ScreenGui
local SkillRows: { [string]: SkillRowRefs } = {}

local SKILL_ORDER = { "Survival", "Carpentry", "Cooking", "Smithing" }

local SKILL_COLORS: { [string]: Color3 } = {
	Survival = Color3.fromRGB(82, 174, 111),
	Carpentry = Color3.fromRGB(165, 124, 68),
	Cooking = Color3.fromRGB(205, 92, 92),
	Smithing = Color3.fromRGB(112, 128, 155),
}

local function getSkillColor(skillId: string): Color3
	return SKILL_COLORS[skillId] or Color3.fromRGB(100, 140, 200)
end

local function renderSkills(skills: { any })
	for _, skillData in ipairs(skills) do
		local skillId = skillData.SkillId
		local row = SkillRows[skillId]
		if not row then
			continue
		end

		local level = skillData.Level or 1
		local xpInto = skillData.ExperienceIntoLevel or 0
		local xpForNext = skillData.ExperienceForNext or 1

		row.LevelLabel.Text = string.format("Lv.%d", level)

		local fillPct = if xpForNext > 0 then math.clamp(xpInto / xpForNext, 0, 1) else 1
		row.Fill.Size = UDim2.new(fillPct, 0, 1, 0)
		row.Fill.BackgroundColor3 = getSkillColor(skillId)

		if xpForNext <= 0 then
			row.XpLabel.Text = "MAX LEVEL"
		else
			row.XpLabel.Text = string.format("%d / %d XP", xpInto, xpForNext)
		end
	end
end

local function requestSkills()
	local ok, success, _, payload = pcall(function()
		return CraftingPackets.GetSkillSummary:Fire()
	end)
	if ok and success and typeof(payload) == "table" then
		renderSkills(payload)
	end
end

local function buildUi()
	RootGui = Instance.new("ScreenGui")
	RootGui.Name = "CraftingSkillPanel"
	RootGui.ResetOnSpawn = false
	RootGui.Enabled = false
	RootGui.DisplayOrder = 34
	RootGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	RootGui.Parent = PlayerGui

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -12)
	panel.Size = UDim2.fromOffset(820, 155)
	panel.BackgroundColor3 = Color3.fromRGB(25, 28, 35)
	panel.BorderSizePixel = 0
	panel.Parent = RootGui

	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 10)
	panelCorner.Parent = panel

	local panelStroke = Instance.new("UIStroke")
	panelStroke.Color = Color3.fromRGB(71, 91, 125)
	panelStroke.Thickness = 1
	panelStroke.Parent = panel

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(16, 10)
	header.Size = UDim2.fromOffset(200, 22)
	header.Font = Enum.Font.GothamBold
	header.Text = "Crafting Skills"
	header.TextSize = 16
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.fromRGB(195, 205, 224)
	header.Parent = panel

	local rowContainer = Instance.new("Frame")
	rowContainer.Name = "Rows"
	rowContainer.BackgroundTransparency = 1
	rowContainer.Position = UDim2.fromOffset(12, 36)
	rowContainer.Size = UDim2.new(1, -24, 1, -48)
	rowContainer.Parent = panel

	local rowLayout = Instance.new("UIListLayout")
	rowLayout.Padding = UDim.new(0, 4)
	rowLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rowLayout.FillDirection = Enum.FillDirection.Vertical
	rowLayout.Parent = rowContainer

	for index, skillId in ipairs(SKILL_ORDER) do
		local row = Instance.new("Frame")
		row.Name = skillId
		row.LayoutOrder = index
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 26)
		row.Parent = rowContainer

		local nameLabel = Instance.new("TextLabel")
		nameLabel.BackgroundTransparency = 1
		nameLabel.Position = UDim2.fromOffset(0, 0)
		nameLabel.Size = UDim2.fromOffset(110, 26)
		nameLabel.Font = Enum.Font.GothamMedium
		nameLabel.Text = skillId
		nameLabel.TextSize = 13
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
		nameLabel.Parent = row

		local levelLabel = Instance.new("TextLabel")
		levelLabel.BackgroundTransparency = 1
		levelLabel.Position = UDim2.fromOffset(112, 0)
		levelLabel.Size = UDim2.fromOffset(60, 26)
		levelLabel.Font = Enum.Font.GothamBold
		levelLabel.Text = "Lv.1"
		levelLabel.TextSize = 13
		levelLabel.TextXAlignment = Enum.TextXAlignment.Center
		levelLabel.TextColor3 = getSkillColor(skillId)
		levelLabel.Parent = row

		local barBg = Instance.new("Frame")
		barBg.Name = "BarBg"
		barBg.Position = UDim2.fromOffset(178, 7)
		barBg.Size = UDim2.fromOffset(440, 12)
		barBg.BackgroundColor3 = Color3.fromRGB(40, 44, 55)
		barBg.BorderSizePixel = 0
		barBg.Parent = row

		local barBgCorner = Instance.new("UICorner")
		barBgCorner.CornerRadius = UDim.new(1, 0)
		barBgCorner.Parent = barBg

		local barFill = Instance.new("Frame")
		barFill.Name = "Fill"
		barFill.Size = UDim2.new(0, 0, 1, 0)
		barFill.BackgroundColor3 = getSkillColor(skillId)
		barFill.BorderSizePixel = 0
		barFill.Parent = barBg

		local fillCorner = Instance.new("UICorner")
		fillCorner.CornerRadius = UDim.new(1, 0)
		fillCorner.Parent = barFill

		local xpLabel = Instance.new("TextLabel")
		xpLabel.BackgroundTransparency = 1
		xpLabel.Position = UDim2.fromOffset(626, 0)
		xpLabel.Size = UDim2.fromOffset(170, 26)
		xpLabel.Font = Enum.Font.Gotham
		xpLabel.Text = "0 / 45 XP"
		xpLabel.TextSize = 12
		xpLabel.TextXAlignment = Enum.TextXAlignment.Right
		xpLabel.TextColor3 = Color3.fromRGB(190, 200, 215)
		xpLabel.Parent = row

		SkillRows[skillId] = {
			Fill = barFill,
			XpLabel = xpLabel,
			LevelLabel = levelLabel,
		}
	end
end

function CraftingSkillPanel.SetVisible(visible: boolean)
	if not RootGui then
		CraftingSkillPanel.Init()
	end
	RootGui.Enabled = visible
	if visible then
		requestSkills()
	end
end

function CraftingSkillPanel.Init()
	if RootGui then
		return
	end
	buildUi()

	CraftingPackets.SkillSummaryUpdated.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.Skills) == "table" then
			renderSkills(payload.Skills)
		end
	end)

	UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
		if gameProcessed or UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		if input.KeyCode == Enum.KeyCode.C then
			CraftingSkillPanel.SetVisible(not RootGui.Enabled)
		elseif input.KeyCode == Enum.KeyCode.Escape and RootGui.Enabled then
			CraftingSkillPanel.SetVisible(false)
		end
	end)
end

return CraftingSkillPanel
