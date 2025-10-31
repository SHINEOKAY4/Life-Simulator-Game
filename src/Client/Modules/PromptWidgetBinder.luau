--!strict
-- StarterPlayerScripts/Client/Modules/PromptWidgetBinder.luau
-- Provides a shared proximity prompt ring presentation used by multiple interaction controllers.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local PromptWidgetBinder = {}

local promptWidgets: { [ProximityPrompt]: BillboardGui } = {}
local promptSuppressed: { [ProximityPrompt]: boolean } = {}
local trackedPrompts: { [ProximityPrompt]: boolean } = {}
local promptEventsBound = false

local function applyCircleStyling(frame: Frame)
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	stroke.Thickness = 2
	stroke.Color = Color3.fromRGB(255, 255, 255)
	stroke.Transparency = 0.15
	stroke.Parent = frame
end

local function ensureWidget(prompt: ProximityPrompt): BillboardGui?
	local adornee = prompt.Parent
	if not adornee or not adornee:IsA("BasePart") then
		return nil
	end

	local existing = promptWidgets[prompt]
	if existing then
		existing.Adornee = adornee
		existing.MaxDistance = math.max(prompt.MaxActivationDistance + 20, 25)
		return existing
	end

	local gui = Instance.new("BillboardGui")
	gui.Name = "PromptRing"
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.MaxDistance = math.max(prompt.MaxActivationDistance + 20, 25)
	gui.Size = UDim2.fromOffset(100, 100)
	gui.StudsOffsetWorldSpace = Vector3.new(0, 3.25, 0)
	gui.Enabled = false
	gui.Adornee = adornee
	gui.Parent = PlayerGui

	local root = Instance.new("Frame")
	root.Name = "Root"
	root.BackgroundTransparency = 1
	root.Size = UDim2.fromScale(1, 1)
	root.Parent = gui

	local keyRing = Instance.new("Frame")
	keyRing.Name = "KeyRing"
	keyRing.AnchorPoint = Vector2.new(0.5, 0)
	keyRing.Position = UDim2.fromScale(0.5, 0)
	keyRing.Size = UDim2.fromOffset(40, 40)
	keyRing.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	keyRing.BackgroundTransparency = 0.1
	keyRing.Parent = root
	applyCircleStyling(keyRing)

	local keyText = Instance.new("TextLabel")
	keyText.Name = "KeyText"
	keyText.AnchorPoint = Vector2.new(0.5, 0.5)
	keyText.Position = UDim2.fromScale(0.5, 0.5)
	keyText.BackgroundTransparency = 1
	keyText.Font = Enum.Font.GothamBold
	keyText.TextSize = 18
	keyText.TextColor3 = Color3.fromRGB(28, 32, 44)
	keyText.Text = ""
	keyText.Parent = keyRing

	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.AnchorPoint = Vector2.new(0.5, 0)
	actionLabel.Position = UDim2.new(0.5, 0, 0, 48)
	actionLabel.Size = UDim2.fromOffset(0, 0)
	actionLabel.AutomaticSize = Enum.AutomaticSize.XY
	actionLabel.BackgroundTransparency = 1
	actionLabel.Font = Enum.Font.GothamBold
	actionLabel.TextSize = 16
	actionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionLabel.Text = prompt.ActionText ~= "" and prompt.ActionText or "Interact"
	actionLabel.TextXAlignment = Enum.TextXAlignment.Center
	actionLabel.TextYAlignment = Enum.TextYAlignment.Top
	actionLabel.Parent = root

	promptWidgets[prompt] = gui
	return gui
end

local function updateWidget(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType?)
	local widget = ensureWidget(prompt)
	if not widget then
		return
	end

	local root = widget:FindFirstChild("Root")
	if not root or not root:IsA("Frame") then
		return
	end

	local keyRing = root:FindFirstChild("KeyRing")
	local keyText = keyRing and keyRing:FindFirstChild("KeyText")
	local actionLabel = root:FindFirstChild("ActionLabel")

	if keyRing and keyRing:IsA("Frame") and keyText and keyText:IsA("TextLabel") then
		local displayText = ""
		if inputType == Enum.ProximityPromptInputType.Touch then
			displayText = "Tap"
		elseif inputType == Enum.ProximityPromptInputType.Gamepad then
			displayText = prompt.GamepadKeyCode.Name
		else
			displayText = prompt.KeyboardKeyCode.Name
		end
		keyText.Text = displayText
	end

	if actionLabel and actionLabel:IsA("TextLabel") then
		actionLabel.Text = prompt.ActionText ~= "" and prompt.ActionText or "Interact"
	end

	local adornee = prompt.Parent
	if adornee and adornee:IsA("BasePart") then
		widget.Adornee = adornee
	end
end

local function setWidgetVisible(prompt: ProximityPrompt, isVisible: boolean)
	local widget = promptWidgets[prompt]
	if not widget then
		return
	end
	if promptSuppressed[prompt] then
		widget.Enabled = false
		return
	end
	widget.Enabled = isVisible
end

local function ensurePromptSignals()
	if promptEventsBound then
		return
	end
	promptEventsBound = true

	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			if not trackedPrompts[prompt] then
				return
			end
			ensureWidget(prompt)
			updateWidget(prompt, inputType)
			setWidgetVisible(prompt, true)
		end
	)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		setWidgetVisible(prompt, false)
	end)

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		setWidgetVisible(prompt, false)
	end)
end

function PromptWidgetBinder.Attach(prompt: ProximityPrompt)
	if trackedPrompts[prompt] then
		return
	end
	trackedPrompts[prompt] = true
	ensurePromptSignals()
	ensureWidget(prompt)
	updateWidget(prompt, nil)
end

function PromptWidgetBinder.Detach(prompt: ProximityPrompt)
	trackedPrompts[prompt] = nil
	promptSuppressed[prompt] = nil
	local widget = promptWidgets[prompt]
	if widget then
		widget:Destroy()
		promptWidgets[prompt] = nil
	end
end

function PromptWidgetBinder.Refresh(prompt: ProximityPrompt)
	if not trackedPrompts[prompt] then
		return
	end
	updateWidget(prompt, nil)
end

function PromptWidgetBinder.SetSuppressed(prompt: ProximityPrompt, isSuppressed: boolean)
	if isSuppressed then
		promptSuppressed[prompt] = true
	else
		promptSuppressed[prompt] = nil
	end
	setWidgetVisible(prompt, false)
end

return PromptWidgetBinder
