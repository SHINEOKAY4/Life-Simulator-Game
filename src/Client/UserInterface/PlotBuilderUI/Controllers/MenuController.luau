--!strict

local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

type MenuButtons = {
	Paint: GuiButton?,
	Storage: GuiButton?,
	Select: GuiButton?,
	Upgrade: GuiButton?,
	Back: GuiButton?,
}

type MenuHandlers = {
	onPaint: (() -> ())?,
	onStorage: (() -> ())?,
	onSelect: (() -> ())?,
	onUpgrade: (() -> ())?,
	onBack: (() -> ())?,
}

local MENU_BUTTON_HOVER_SCALE = 1.08
local MENU_BUTTON_TWEEN = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local MENU_BUTTON_SOUND_ID = "rbxassetid://103307955424380"
local MENU_BUTTON_SOUND_VOLUME = 0.55

local MenuController = {}
MenuController.__index = MenuController

function MenuController.new(buttons: MenuButtons, handlers: MenuHandlers)
	local self = setmetatable({}, MenuController)
	self._buttons = buttons
	self._handlers = handlers
	self._buttonTweens = {} :: { [GuiButton]: Tween }
	self._buttonScales = {} :: { [GuiButton]: UIScale }
	return self
end

local function playMenuButtonClickSound()
	local sound = Instance.new("Sound")
	sound.Name = "MenuButtonClick"
	sound.SoundId = MENU_BUTTON_SOUND_ID
	sound.Volume = MENU_BUTTON_SOUND_VOLUME
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function ensureUIScale(target: GuiObject, scaleName: string): UIScale
	local existing = target:FindFirstChild(scaleName)
	if existing and existing:IsA("UIScale") then
		return existing
	end
	local scale = Instance.new("UIScale")
	scale.Name = scaleName
	scale.Scale = 1
	scale.Parent = target
	return scale
end

function MenuController:_tweenScale(button: GuiButton, targetScale: number)
	local scale = self._buttonScales[button]
	if not scale then
		scale = ensureUIScale(button, "MenuButtonHoverScale")
		self._buttonScales[button] = scale
	end

	local activeTween = self._buttonTweens[button]
	if activeTween then
		activeTween:Cancel()
	end

	local tween = TweenService:Create(scale, MENU_BUTTON_TWEEN, {
		Scale = targetScale,
	})
	self._buttonTweens[button] = tween
	tween.Completed:Connect(function()
		if self._buttonTweens[button] == tween then
			self._buttonTweens[button] = nil
		end
	end)
	tween:Play()
end

function MenuController:_attachButtonEffects(button: GuiButton)
	if self._buttonScales[button] then
		return
	end

	local scale = ensureUIScale(button, "MenuButtonHoverScale")
	self._buttonScales[button] = scale
	scale.Scale = 1

	button.MouseEnter:Connect(function()
		self:_tweenScale(button, MENU_BUTTON_HOVER_SCALE)
	end)

	button.MouseLeave:Connect(function()
		self:_tweenScale(button, 1)
	end)

	button.InputEnded:Connect(function(input)
		local inputType = input.UserInputType
		if inputType == Enum.UserInputType.Touch or inputType == Enum.UserInputType.MouseButton1 then
			self:_tweenScale(button, 1)
		end
	end)

	button.SelectionLost:Connect(function()
		self:_tweenScale(button, 1)
	end)

	button.Activated:Connect(function()
		self:_tweenScale(button, 1)
		playMenuButtonClickSound()
	end)

	button.Destroying:Connect(function()
		local activeTween = self._buttonTweens[button]
		if activeTween then
			activeTween:Cancel()
		end
		self._buttonTweens[button] = nil
		self._buttonScales[button] = nil
	end)
end

local HandlerKeys = {
	Paint = "onPaint",
	Storage = "onStorage",
	Select = "onSelect",
	Upgrade = "onUpgrade",
	Back = "onBack",
}

function MenuController:Init()
	for name, button in pairs(self._buttons) do
		if button then
			self:_attachButtonEffects(button)
			local handlerKey = HandlerKeys[name]
			local handler = handlerKey and self._handlers[handlerKey]
			button.Activated:Connect(function()
				if handler then
					handler()
				end
			end)
		end
	end
end

function MenuController:Destroy()
	for button, tween in pairs(self._buttonTweens) do
		tween:Cancel()
		self._buttonTweens[button] = nil
	end
	self._buttonScales = {}
end

return MenuController
