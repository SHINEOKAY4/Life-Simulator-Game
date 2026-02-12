--!strict
-- Client/Modules/ExperienceVFX.luau
-- World-space sparkle burst and floating text whenever the player earns XP.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

local ExperienceVFX = {}

local TEXT_COLOR = Color3.fromRGB(122, 191, 255)
local TEXT_STROKE = Color3.fromRGB(18, 52, 92)
local PARTICLE_COLOR = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 219, 176)),
	ColorSequenceKeypoint.new(0.5, Color3.fromRGB(189, 141, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(120, 189, 255)),
})
local PARTICLE_LIGHT = ColorSequence.new(Color3.fromRGB(255, 255, 255))
local PULSE_SOUND_ID = "rbxassetid://9118823106"

local function resolveWorldPosition(): Vector3
	local character = LocalPlayer.Character
	if character then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") then
			return root.Position + Vector3.new(0, 4, 0)
		end
		local part = character:FindFirstChildWhichIsA("BasePart")
		if part then
			return part.Position + Vector3.new(0, 4, 0)
		end
	end

	local camera = Workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position + camera.CFrame.LookVector * 6
	end

	return Vector3.new()
end

local function createAnchor(position: Vector3): BasePart
	local anchor = Instance.new("Part")
	anchor.Name = "ExperienceVFXAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace
	return anchor
end

local function formatAmount(amount: number?): string
	if typeof(amount) ~= "number" or amount <= 0 then
		return "+XP"
	end
	local rounded = math.floor(amount + 0.5)
	if rounded >= 1000 then
		local abbrev = math.floor(rounded / 100) / 10 -- one decimal place without trailing zeros
		local formatted = if math.abs(abbrev - math.floor(abbrev)) < 1e-4
			then tostring(math.floor(abbrev))
			else string.format("%.1f", abbrev)
		return string.format("+%sK XP", formatted)
	end
	return string.format("+%d XP", rounded)
end

local function createTextBillboard(anchor: BasePart, amount: number?)
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "ExperienceBillboard"
	billboard.Size = UDim2.fromOffset(120, 48)
	billboard.AlwaysOnTop = false
	billboard.LightInfluence = 0
	billboard.MaxDistance = 200
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 0, 0)
	billboard.Adornee = anchor
	billboard.Parent = anchor

	local frame = Instance.new("Frame")
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Parent = billboard

	local amountLabel = Instance.new("TextLabel")
	amountLabel.BackgroundTransparency = 1
	amountLabel.Size = UDim2.fromScale(1, 1)
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.Text = formatAmount(amount)
	amountLabel.TextColor3 = TEXT_COLOR
	amountLabel.TextStrokeTransparency = 0.4
	amountLabel.TextStrokeColor3 = TEXT_STROKE
	amountLabel.TextTransparency = 0.05
	amountLabel.TextScaled = true
	amountLabel.Parent = frame

	return billboard, amountLabel
end

local function spawnBurstParticles(anchor: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Name = "ExperienceVFXAttachment"
	attachment.Parent = anchor

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxassetid://2899537281"
	sparks.LightEmission = 0.8
	sparks.Lifetime = NumberRange.new(0.35, 0.65)
	sparks.Speed = NumberRange.new(4, 7)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.Color = PARTICLE_COLOR
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 0),
	})
	sparks.Parent = attachment
	sparks:Emit(18)

	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxassetid://129437899"
	motes.Lifetime = NumberRange.new(0.7, 1.1)
	motes.Speed = NumberRange.new(1, 2.2)
	motes.Rate = 0
	motes.Color = PARTICLE_LIGHT
	motes.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	motes.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.6),
		NumberSequenceKeypoint.new(1, 0),
	})
	motes.Parent = attachment
	motes:Emit(10)

	local pulse = Instance.new("Sound")
	pulse.SoundId = PULSE_SOUND_ID
	pulse.Volume = 0.35
	pulse.PlaybackSpeed = 1.1
	pulse.Parent = attachment
	pulse:Play()

	Debris:AddItem(attachment, 2)
end

local function animateBillboard(billboard: BillboardGui, amountLabel: TextLabel)
	local floatTween = TweenService:Create(
		billboard,
		TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ StudsOffsetWorldSpace = Vector3.new(0, 1.4, 0) }
	)
	floatTween:Play()

	local fadeTween = TweenService:Create(
		amountLabel,
		TweenInfo.new(0.95, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }
	)
	fadeTween:Play()
end

function ExperienceVFX.PlayExperienceGain(amount: number?, reason: string?)
	-- Skip particle effects for chore completion (garbage pickup)
	if reason == "ChoreCompleted" then
		return
	end
	
	local position = resolveWorldPosition()
	local anchor = createAnchor(position)
	local billboard, amountLabel = createTextBillboard(anchor, amount)
	spawnBurstParticles(anchor)
	animateBillboard(billboard, amountLabel)

	local riseTween = TweenService:Create(
		anchor,
		TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ CFrame = anchor.CFrame + Vector3.new(0, 1, 0) }
	)
	riseTween:Play()

	Debris:AddItem(anchor, 2)
end

return ExperienceVFX
