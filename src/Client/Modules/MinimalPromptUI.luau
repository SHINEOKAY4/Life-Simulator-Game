--!strict
-- StarterPlayerScripts/Client/Modules/MinimalPromptUI.luau
-- Provides a clean, minimal square proximity prompt UI that doesn't use PromptWidgetBinder.
-- Designed for mailbox and tenant interactions to avoid screen clutter.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ProximityPromptService = game:GetService("ProximityPromptService")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local MinimalPromptUI = {}

local activePrompts: { [ProximityPrompt]: BillboardGui } = {}
local promptConnections: { [ProximityPrompt]: { RBXScriptConnection } } = {}
local lastInputType: Enum.ProximityPromptInputType = Enum.ProximityPromptInputType.Keyboard
local serviceConnectionsInitialized = false

local DEFAULT_OFFSET = Vector3.new(0, 0, 0)

local function getInputDisplay(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType): string
	if inputType == Enum.ProximityPromptInputType.Touch then
		return "TAP"
	elseif inputType == Enum.ProximityPromptInputType.Gamepad then
		local keyCode = prompt.GamepadKeyCode
		if keyCode == Enum.KeyCode.ButtonX then
			return "X"
		elseif keyCode == Enum.KeyCode.ButtonY then
			return "Y"
		elseif keyCode == Enum.KeyCode.ButtonA then
			return "A"
		elseif keyCode == Enum.KeyCode.ButtonB then
			return "B"
		end
		return keyCode.Name
	else
		return prompt.KeyboardKeyCode.Name
	end
end

local function getPromptOffset(prompt: ProximityPrompt): Vector3
	local offsetAttr = prompt:GetAttribute("MinimalPromptOffset")
	if typeof(offsetAttr) == "Vector3" then
		return offsetAttr
	end
	return DEFAULT_OFFSET
end

local function createMinimalPromptUI(prompt: ProximityPrompt): BillboardGui
	local adornee: Instance
	if prompt.Parent and (prompt.Parent:IsA("BasePart") or prompt.Parent:IsA("Attachment")) then
		adornee = prompt.Parent
	else
		-- Fallback to the prompt's parent if it exists
		adornee = prompt.Parent or prompt
	end

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "MinimalPromptUI"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Size = UDim2.fromOffset(90, 36)
	billboard.StudsOffsetWorldSpace = getPromptOffset(prompt)
	billboard.MaxDistance = math.max(prompt.MaxActivationDistance + 15, 30)
	billboard.Adornee = adornee
	billboard.Enabled = false
	billboard.Parent = PlayerGui

	-- Main container (transparent background)
	local container = Instance.new("Frame")
	container.Name = "Container"
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Parent = billboard

	-- Key indicator (compact square)
	local keyBox = Instance.new("Frame")
	keyBox.Name = "KeyBox"
	keyBox.AnchorPoint = Vector2.new(0, 0.5)
	keyBox.Position = UDim2.new(0, 4, 0.5, 0)
	keyBox.Size = UDim2.fromOffset(24, 24)
	keyBox.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	keyBox.BackgroundTransparency = 0.08
	keyBox.BorderSizePixel = 0
	keyBox.Parent = container

	local keyBoxCorner = Instance.new("UICorner")
	keyBoxCorner.CornerRadius = UDim.new(0, 5)
	keyBoxCorner.Parent = keyBox

	local keyBoxStroke = Instance.new("UIStroke")
	keyBoxStroke.Color = Color3.fromRGB(255, 255, 255)
	keyBoxStroke.Transparency = 0.5
	keyBoxStroke.Thickness = 1.5
	keyBoxStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	keyBoxStroke.Parent = keyBox

	local keyLabel = Instance.new("TextLabel")
	keyLabel.Name = "KeyLabel"
	keyLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	keyLabel.Position = UDim2.fromScale(0.5, 0.5)
	keyLabel.Size = UDim2.fromScale(1, 1)
	keyLabel.BackgroundTransparency = 1
	keyLabel.Font = Enum.Font.GothamBold
	keyLabel.TextColor3 = Color3.fromRGB(28, 32, 44)
	keyLabel.TextSize = 12
	keyLabel.Text = "E"
	keyLabel.Parent = keyBox

	-- Action text (compact, right of key)
	local actionLabel = Instance.new("TextLabel")
	actionLabel.Name = "ActionLabel"
	actionLabel.Position = UDim2.fromOffset(32, 0)
	actionLabel.Size = UDim2.new(1, -36, 1, 0)
	actionLabel.BackgroundTransparency = 1
	actionLabel.Font = Enum.Font.GothamMedium
	actionLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	actionLabel.TextSize = 12
	actionLabel.Text = prompt.ActionText
	actionLabel.TextXAlignment = Enum.TextXAlignment.Left
	actionLabel.TextYAlignment = Enum.TextYAlignment.Center
	actionLabel.TextTruncate = Enum.TextTruncate.AtEnd
	actionLabel.Parent = container

	return billboard
end

local function updatePromptUI(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
	local billboard = activePrompts[prompt]
	if not billboard then
		return
	end

	local container = billboard:FindFirstChild("Container")
	if not container or not container:IsA("Frame") then
		return
	end

	local keyBox = container:FindFirstChild("KeyBox")
	local keyLabel = keyBox and keyBox:FindFirstChild("KeyLabel")
	local actionLabel = container:FindFirstChild("ActionLabel")

	if keyLabel and keyLabel:IsA("TextLabel") then
		keyLabel.Text = getInputDisplay(prompt, inputType)
	end

	if actionLabel and actionLabel:IsA("TextLabel") then
		actionLabel.Text = prompt.ActionText
	end

	-- Update offset if changed
	billboard.StudsOffsetWorldSpace = getPromptOffset(prompt)
end

local function showPromptUI(prompt: ProximityPrompt, visible: boolean)
	local billboard = activePrompts[prompt]
	if billboard then
		billboard.Enabled = visible
	end
end

local function cleanupPrompt(prompt: ProximityPrompt)
	local billboard = activePrompts[prompt]
	if billboard then
		billboard:Destroy()
		activePrompts[prompt] = nil
	end

	local connections = promptConnections[prompt]
	if connections then
		for _, connection in ipairs(connections) do
			connection:Disconnect()
		end
		promptConnections[prompt] = nil
	end
end

local function initializeServiceConnections()
	if serviceConnectionsInitialized then
		return
	end
	serviceConnectionsInitialized = true

	ProximityPromptService.PromptShown:Connect(
		function(prompt: ProximityPrompt, inputType: Enum.ProximityPromptInputType)
			if not activePrompts[prompt] then
				return
			end
			lastInputType = inputType
			updatePromptUI(prompt, inputType)
			showPromptUI(prompt, true)
		end
	)

	ProximityPromptService.PromptHidden:Connect(function(prompt: ProximityPrompt)
		showPromptUI(prompt, false)
	end)

	-- Removed PromptTriggered hiding to allow toggle-style prompts to remain visible
	-- ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
	-- 	showPromptUI(prompt, false)
	-- end)

	-- Update input type when user switches input methods
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Gamepad1 then
			lastInputType = Enum.ProximityPromptInputType.Gamepad
		elseif
			input.UserInputType == Enum.UserInputType.Keyboard
			or input.UserInputType == Enum.UserInputType.MouseButton1
		then
			lastInputType = Enum.ProximityPromptInputType.Keyboard
		elseif input.UserInputType == Enum.UserInputType.Touch then
			lastInputType = Enum.ProximityPromptInputType.Touch
		end
	end)
end

function MinimalPromptUI.Attach(prompt: ProximityPrompt)
	if activePrompts[prompt] then
		MinimalPromptUI.Refresh(prompt)
		return
	end

	initializeServiceConnections()

	local billboard = createMinimalPromptUI(prompt)
	activePrompts[prompt] = billboard

	local connections = {}
	promptConnections[prompt] = connections

	connections[#connections + 1] = prompt.Destroying:Connect(function()
		MinimalPromptUI.Detach(prompt)
	end)

	connections[#connections + 1] = prompt.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			MinimalPromptUI.Detach(prompt)
		end
	end)

	-- Listen for property changes
	connections[#connections + 1] = prompt:GetPropertyChangedSignal("ActionText"):Connect(function()
		updatePromptUI(prompt, lastInputType)
	end)

	connections[#connections + 1] = prompt:GetPropertyChangedSignal("MaxActivationDistance"):Connect(function()
		if billboard then
			billboard.MaxDistance = math.max(prompt.MaxActivationDistance + 15, 30)
		end
	end)

	updatePromptUI(prompt, lastInputType)
end

function MinimalPromptUI.Detach(prompt: ProximityPrompt)
	cleanupPrompt(prompt)
end

function MinimalPromptUI.Refresh(prompt: ProximityPrompt)
	if not activePrompts[prompt] then
		return
	end
	updatePromptUI(prompt, lastInputType)
end

return MinimalPromptUI
