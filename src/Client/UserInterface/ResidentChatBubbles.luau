--!strict
-- StarterPlayerScripts/Client/UserInterface/ResidentChatBubbles.luau
-- Renders lightweight chat text above residents using a custom billboard instead of ChatService bubbles.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BillboardText = require(script.Parent.BillboardText)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

export type BubbleEntry = {
	Handle: BillboardText.BillboardTextHandle,
	Adornee: BasePart,
	Token: number,
	Connections: { RBXScriptConnection },
}

local ResidentChatBubbles = {}
local bubbles: { [BasePart]: BubbleEntry } = {}
local initialized = false

local function resolveAdornee(instance: Instance): BasePart?
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Attachment") then
		local parent = instance.Parent
		if parent and parent:IsA("BasePart") then
			return parent
		end
	end
	if instance:IsA("Model") then
		local head = instance:FindFirstChild("Head")
		if head and head:IsA("BasePart") then
			return head
		end
		local root = instance.PrimaryPart
		if root and root:IsA("BasePart") then
			return root
		end
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				return descendant
			end
		end
	end
	return nil
end

local function destroyBubble(basePart: BasePart)
	local existing = bubbles[basePart]
	if not existing then
		return
	end
	bubbles[basePart] = nil
	for _, connection in ipairs(existing.Connections) do
		connection:Disconnect()
	end
	existing.Connections = {}
	existing.Handle:destroy()
end

local function getOrCreateBubble(instance: Instance): BubbleEntry?
	local adornee = resolveAdornee(instance)
	if not adornee then
		return nil
	end
	local existing = bubbles[adornee]
	if existing then
		if existing.Handle.instance.Parent == nil then
			existing.Handle.instance.Parent = PlayerGui
		end
		existing.Handle.instance.Adornee = adornee
		return existing
	end

	local handle = BillboardText.new({
		adornee = adornee,
		parent = PlayerGui,
		text = "",
		textColor = Color3.new(0, 0, 0), -- Black text
		backgroundColor = Color3.new(1, 1, 1), -- White background
		backgroundTransparency = 0, -- Opaque
		size = UDim2.fromOffset(40, 40), -- Fixed size for circular bubble
		studsOffsetWorldSpace = Vector3.new(0, 3.5, 0),
		alwaysOnTop = false,
		maxDistance = 70,
		textSize = 24, -- Larger emoji
		font = Enum.Font.GothamBold,
		clipsDescendants = false,
	})
	local billboard = handle.instance
	billboard.Enabled = false

	-- Make it circular
	local uiCorner = Instance.new("UICorner")
	uiCorner.CornerRadius = UDim.new(1, 0)
	uiCorner.Parent = handle.label

	-- Add a small tail (triangle) to make it look like a speech bubble
	local tail = Instance.new("ImageLabel")
	tail.Name = "Tail"
	tail.BackgroundTransparency = 1
	tail.Image = "rbxassetid://1264515756" -- Triangle image or similar
	tail.ImageColor3 = Color3.new(1, 1, 1)
	tail.Size = UDim2.fromOffset(10, 10)
	tail.Position = UDim2.new(0.5, -5, 1, -2)
	tail.Rotation = 180
	tail.Parent = handle.label

	local entry: BubbleEntry = {
		Handle = handle,
		Adornee = adornee,
		Token = 0,
		Connections = {},
	}

	local function bind(connection: RBXScriptConnection)
		table.insert(entry.Connections, connection)
	end

	bind(adornee.Destroying:Connect(function()
		destroyBubble(adornee)
	end))

	bind(adornee.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			destroyBubble(adornee)
		end
	end))

	bubbles[adornee] = entry
	return entry
end

local function onChatMessage(payload)
	local speaker = payload.Speaker
	local text = payload.Text
	local durationValue = payload.Duration

	if typeof(speaker) ~= "Instance" then
		return
	end
	if typeof(text) ~= "string" or text == "" then
		return
	end

	local bubble = getOrCreateBubble(speaker)
	if not bubble then
		return
	end

	local duration = if typeof(durationValue) == "number" then durationValue else 3

	-- If duration is 0, clear the bubble
	if duration == 0 then
		if bubble.Handle.instance.Enabled then
			bubble.Handle.instance.Enabled = false
		end
		return
	end

	bubble.Token += 1
	local token = bubble.Token

	local billboard = bubble.Handle.instance
	billboard.Enabled = true
	billboard.Adornee = bubble.Adornee
	bubble.Handle:setText(text)

	-- If duration is negative, it's persistent
	if duration < 0 then
		return
	end

	task.delay(duration, function()
		if bubbles[bubble.Adornee] ~= bubble then
			return
		end
		if bubble.Token ~= token then
			return
		end
		billboard.Enabled = false
	end)
end

function ResidentChatBubbles.Init()
	if initialized then
		return
	end
	initialized = true
	ResidentsPackets.ResidentChatMessage.OnClientEvent:Connect(onChatMessage)
end

return ResidentChatBubbles
