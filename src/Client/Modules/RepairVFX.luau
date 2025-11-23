--!strict
-- Client/Modules/RepairVFX.luau
-- Encapsulates visual/audio feedback for broken and repaired objects.

local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local RepairVFX = {}

local function firstBasePart(instance: Instance?): BasePart?
	if not instance then
		return nil
	end
	if instance:IsA("BasePart") then
		return instance
	end
	if instance:IsA("Model") then
		return instance.PrimaryPart or instance:FindFirstChildWhichIsA("BasePart")
	end
	return instance:FindFirstChildWhichIsA("BasePart")
end

local function createBillboard(parent: Instance?, severity: number, worldPosition: Vector3?): (Instance?, () -> ())
	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(64, 64)
	billboard.StudsOffset = Vector3.new(0, 3.5 + severity * 1.25, 0)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0

	local icon = Instance.new("ImageLabel")
	icon.BackgroundTransparency = 1
	icon.Size = UDim2.fromScale(1, 1)
	icon.Image = "rbxassetid://11814391157" -- wrench icon
	icon.ImageColor3 = Color3.fromRGB(255, 198, 92)
	icon.ImageTransparency = 0.15
	icon.Parent = billboard

	local adornee = firstBasePart(parent)
	if adornee then
		billboard.Adornee = adornee
		billboard.Parent = adornee
		return billboard, function()
			billboard:Destroy()
		end
	end

	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = worldPosition or Vector3.new()
	anchor.Parent = Workspace
	billboard.Adornee = anchor
	billboard.Parent = anchor

	return billboard, function()
		billboard:Destroy()
		anchor:Destroy()
	end
end

local function createParticles(basePart: BasePart, severity: number): () -> ()
	local attachment = Instance.new("Attachment")
	attachment.Name = "RepairVFXAttachment"
	attachment.Parent = basePart

	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxassetid://259950196"
	sparks.Rate = 12 + math.floor(severity * 8)
	sparks.Speed = NumberRange.new(2, 4)
	sparks.Lifetime = NumberRange.new(0.4, 0.7)
	sparks.SpreadAngle = Vector2.new(35, 35)
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 182, 89), Color3.fromRGB(255, 255, 255))
	sparks.LightEmission = 0.6
	sparks.Parent = attachment

	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxassetid://241876103"
	smoke.Rate = 6 + math.floor(severity * 6)
	smoke.Speed = NumberRange.new(0.5, 1.4)
	smoke.Lifetime = NumberRange.new(1.2, 1.8)
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 120, 120), Color3.fromRGB(70, 70, 70))
	smoke.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	smoke.Parent = attachment

	local hum = Instance.new("Sound")
	hum.SoundId = "rbxassetid://9118823106"
	hum.Looped = true
	hum.Volume = 0.35 + severity * 0.25
	hum.PlaybackSpeed = 0.9 + severity * 0.2
	hum.Parent = attachment
	hum:Play()

	return function()
		hum:Stop()
		hum:Destroy()
		sparks.Enabled = false
		smoke.Enabled = false
		sparks:Destroy()
		smoke:Destroy()
		attachment:Destroy()
	end
end

function RepairVFX.Attach(
	target: Instance?,
	opts: { Severity: number, WorldPosition: Vector3?, VisualSeed: number? }
): () -> ()
	local severity = math.clamp(opts.Severity or 0.5, 0.1, 1)
	local cleanups: { () -> () } = {}

	if target then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(255, 136, 51)
		highlight.FillTransparency = 0.65
		highlight.OutlineColor = Color3.fromRGB(255, 235, 161)
		highlight.OutlineTransparency = 0.15
		highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		highlight.Adornee = target
		highlight.Parent = target
		table.insert(cleanups, function()
			highlight:Destroy()
		end)
	end

	local basePart = firstBasePart(target)
	if basePart then
		table.insert(cleanups, createParticles(basePart, severity))
	end

	local _, cleanupBillboard = createBillboard(target, severity, opts.WorldPosition)
	table.insert(cleanups, cleanupBillboard)

	return function()
		for _, cleanup in ipairs(cleanups) do
			cleanup()
		end
	end
end

local function resolvePosition(target: Instance?, worldPosition: Vector3?): Vector3?
	local basePart = firstBasePart(target)
	if basePart then
		return basePart.Position
	end
	return worldPosition
end

function RepairVFX.PlayRepairComplete(target: Instance?, worldPosition: Vector3?)
	local position = resolvePosition(target, worldPosition)
	if not position then
		return
	end

	local burst = Instance.new("Part")
	burst.Anchored = true
	burst.CanCollide = false
	burst.CanQuery = false
	burst.Transparency = 1
	burst.Size = Vector3.new(0.2, 0.2, 0.2)
	burst.Position = position + Vector3.new(0, 1.25, 0)
	burst.Parent = Workspace

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://129437899"
	emitter.Speed = NumberRange.new(4, 7)
	emitter.Lifetime = NumberRange.new(0.4, 0.6)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(255, 214, 170))
	emitter.Parent = burst
	emitter:Emit(35)

	local ding = Instance.new("Sound")
	ding.SoundId = "rbxassetid://9113430683"
	ding.Volume = 0.7
	ding.Parent = burst
	ding:Play()

	Debris:AddItem(burst, 2)
end

return RepairVFX
