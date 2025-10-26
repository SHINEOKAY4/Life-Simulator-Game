--!strict
-- StarterPlayerScripts/Client/UserInterface/MailboxCashEffect.luau
-- Plays a mailbox-to-HUD cash burst and contextual sounds when payroll is collected.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local PayrollPackets = require(ReplicatedStorage.Network.PayrollPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local MainHUDGui = PlayerGui:WaitForChild("MainHUD") :: ScreenGui
local TopRight = MainHUDGui:WaitForChild("TopRight") :: Frame
local Extras = TopRight:FindFirstChild("Extras") :: Frame
local CashImageFrame = Extras:WaitForChild("CashImageFrame") :: Frame

local function resolveTargetImage(frame: Frame): ImageLabel
	local existing = frame:FindFirstChildWhichIsA("ImageLabel")
	if existing then
		return existing
	end
	return frame:WaitForChild("ImageLabel") :: ImageLabel
end

local TargetImage = resolveTargetImage(CashImageFrame)

local EFFECT_Z_INDEX = 200
local MAX_BURST = 12
local MIN_BURST = 4
local BURST_INTERVAL = 0.04

local CollectSound: Sound = (function()
	local existing = SoundService:FindFirstChild("MailboxCollectSound")
	if existing and existing:IsA("Sound") then
		return existing
	end
	local sound = Instance.new("Sound")
	sound.Name = "MailboxCollectSound"
	sound.SoundId = "rbxassetid://99023919906775"
	sound.Volume = 0.85
	sound.PlayOnRemove = false
	sound.Parent = SoundService
	return sound
end)()

local EmptyClickSound: Sound = (function()
	local existing = SoundService:FindFirstChild("MailboxClickEmptySound")
	if existing and existing:IsA("Sound") then
		return existing
	end
	local sound = Instance.new("Sound")
	sound.Name = "MailboxClickEmptySound"
	sound.SoundId = "rbxassetid://9116439227"
	sound.Volume = 0.6
	sound.PlayOnRemove = false
	sound.Parent = SoundService
	return sound
end)()

local EffectContainer: Frame = (function()
	local existing = MainHUDGui:FindFirstChild("MailboxCashEffects")
	if existing and existing:IsA("Frame") then
		existing.ZIndex = EFFECT_Z_INDEX
		existing.Visible = true
		return existing
	end
	local frame = Instance.new("Frame")
	frame.Name = "MailboxCashEffects"
	frame.BackgroundTransparency = 1
	frame.Size = UDim2.fromScale(1, 1)
	frame.Position = UDim2.fromScale(0, 0)
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = false
	frame.ZIndex = EFFECT_Z_INDEX
	frame.Parent = MainHUDGui
	return frame
end)()

local cachedMailboxPart: BasePart? = nil

local function playSound(sound: Sound)
	sound.TimePosition = 0
	sound:Play()
end

local function resolveMailboxPart(): BasePart?
	local plotIndex = LocalPlayer:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	local mailbox = plotModel:FindFirstChild("Mailbox")
	if not mailbox then
		return nil
	end
	if mailbox:IsA("BasePart") then
		return mailbox
	end
	local basePart = mailbox:FindFirstChildWhichIsA("BasePart", true)
	return basePart
end

local function refreshMailboxReference()
	cachedMailboxPart = resolveMailboxPart()
end

local function getMailboxPosition(): Vector3?
	local part = cachedMailboxPart
	if part and part:IsDescendantOf(Workspace) then
		return part.Position
	end
	refreshMailboxReference()
	part = cachedMailboxPart
	if part and part:IsDescendantOf(Workspace) then
		return part.Position
	end
	return nil
end

local function worldToScreen(position: Vector3): Vector2?
	local camera = Workspace.CurrentCamera
	if not camera then
		return nil
	end
	local viewportPoint, onScreen = camera:WorldToViewportPoint(position)
	if not onScreen then
		viewportPoint = Vector3.new(camera.ViewportSize.X * 0.5, camera.ViewportSize.Y * 0.5, viewportPoint.Z)
	end
	return Vector2.new(viewportPoint.X, viewportPoint.Y)
end

local function computeBurstCount(amount: number): number
	local scaled = math.floor(amount / 120)
	local count = MIN_BURST + math.clamp(scaled, 0, MAX_BURST - MIN_BURST)
	return math.clamp(count, MIN_BURST, MAX_BURST)
end

local function spawnMoneyBurst(amount: number)
	local mailboxPosition = getMailboxPosition()
	if not mailboxPosition then
		return
	end
	local startScreen = worldToScreen(mailboxPosition + Vector3.new(0, 4, 0))
	if not startScreen then
		return
	end
	local targetAbsolute = TargetImage.AbsolutePosition + (TargetImage.AbsoluteSize * 0.5)
	local imageAsset = TargetImage.Image
	local imageColor = TargetImage.ImageColor3
	local imageTransparency = TargetImage.ImageTransparency
	local targetZIndex = math.max(TargetImage.ZIndex + 5, EFFECT_Z_INDEX)
	local coinSize = math.clamp(math.floor(math.min(TargetImage.AbsoluteSize.X, TargetImage.AbsoluteSize.Y)), 24, 36)

	local burstCount = computeBurstCount(amount)

	for index = 1, burstCount do
		task.delay((index - 1) * BURST_INTERVAL, function()
			if not TargetImage.Parent then
				return
			end

			local scatterX = (math.random() - 0.5) * 80
			local scatterY = math.random() * -60
			local apex = Vector2.new(startScreen.X + scatterX, startScreen.Y + scatterY)

			local coin = Instance.new("ImageLabel")
			coin.Name = "MailboxCashSprite"
			coin.BackgroundTransparency = 1
			coin.AnchorPoint = Vector2.new(0.5, 0.5)
			coin.Image = imageAsset
			coin.ImageColor3 = imageColor
			coin.ImageTransparency = math.clamp(imageTransparency, 0, 1)
			coin.Size = UDim2.fromOffset(coinSize, coinSize)
			coin.Position = UDim2.fromOffset(startScreen.X, startScreen.Y)
			coin.Rotation = math.random(-18, 18)
			coin.ZIndex = targetZIndex
			coin.Parent = EffectContainer

			local apexTween = TweenService:Create(
				coin,
				TweenInfo.new(0.22, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ Position = UDim2.fromOffset(apex.X, apex.Y) }
			)

			local settleOffsetX = (math.random() - 0.5) * 12
			local settleOffsetY = (math.random() - 0.5) * 8
			local targetTween = TweenService:Create(
				coin,
				TweenInfo.new(0.45 + math.random() * 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Position = UDim2.fromOffset(targetAbsolute.X + settleOffsetX, targetAbsolute.Y + settleOffsetY) }
			)

			local fadeTween = TweenService:Create(
				coin,
				TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ ImageTransparency = 1 }
			)

			apexTween:Play()
			apexTween.Completed:Connect(function()
				targetTween:Play()
			end)

			targetTween.Completed:Connect(function()
				fadeTween:Play()
			end)

			fadeTween.Completed:Connect(function()
				if coin.Parent then
					coin:Destroy()
				end
			end)
		end)
	end

	playSound(CollectSound)
end

local function onPayrollUpdate(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local collectedAmount = payload.CollectedAmount
	local mailboxEmptyFlag = payload.MailboxEmpty

	if typeof(mailboxEmptyFlag) == "boolean" and mailboxEmptyFlag then
		playSound(EmptyClickSound)
		return
	end

	if typeof(collectedAmount) ~= "number" or collectedAmount <= 0 then
		return
	end

	spawnMoneyBurst(collectedAmount)
end

local MailboxCashEffect = {}

function MailboxCashEffect.Init()
	refreshMailboxReference()

	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(refreshMailboxReference)
	PayrollPackets.PayrollUpdate.OnClientEvent:Connect(onPayrollUpdate)
end

return MailboxCashEffect
