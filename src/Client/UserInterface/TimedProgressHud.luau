--!strict
-- Reusable timed progress HUD for interaction sequences.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

export type Options = {
	PlayerGui: PlayerGui?,
	GuiName: string?,
	IconAsset: string?,
	IconSize: UDim2?,
	AnchorPoint: Vector2?,
	Position: UDim2?,
	ContainerSize: UDim2?,
	FillColor: Color3?,
	BarColor: Color3?,
	TextColor: Color3?,
}

export type Controller = {
	Show: (self: Controller, durationSeconds: number?, title: string) -> (),
	Hide: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

type Private = {
	_playerGui: PlayerGui,
	_screenGui: ScreenGui,
	_container: Frame,
	_icon: ImageLabel,
	_title: TextLabel,
	_timerLabel: TextLabel,
	_fill: Frame,
	_renderConnection: RBXScriptConnection?,
	_token: number,
	_defaultFillColor: Color3,
	_defaultBarColor: Color3,
	_defaultTextColor: Color3,
}

local DEFAULT_GUI_NAME = "InteractionProgress"
local DEFAULT_ICON_ASSET = ""
local DEFAULT_ICON_SIZE = UDim2.fromOffset(40, 40)
local DEFAULT_ANCHOR = Vector2.new(0.5, 1)
local DEFAULT_POSITION = UDim2.fromScale(0.5, 0.92)
local DEFAULT_CONTAINER_SIZE = UDim2.fromOffset(320, 74)
local DEFAULT_FILL_COLOR = Color3.fromRGB(130, 214, 154)
local DEFAULT_BAR_COLOR = Color3.fromRGB(40, 53, 69)
local DEFAULT_TEXT_COLOR = Color3.fromRGB(238, 244, 255)

local TimedProgressHud = {}
TimedProgressHud.__index = TimedProgressHud

local function createGui(options: Options?): Private
	local playerGui = (options and options.PlayerGui) or Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = (options and options.GuiName) or DEFAULT_GUI_NAME
	screenGui.IgnoreGuiInset = true
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Global
	screenGui.Parent = playerGui

	local container = Instance.new("Frame")
	container.Name = "ProgressContainer"
	container.AnchorPoint = (options and options.AnchorPoint) or DEFAULT_ANCHOR
	container.Position = (options and options.Position) or DEFAULT_POSITION
	container.Size = (options and options.ContainerSize) or DEFAULT_CONTAINER_SIZE
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.Visible = false
	container.Parent = screenGui

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 20, 0.5, -8)
	icon.Size = (options and options.IconSize) or DEFAULT_ICON_SIZE
	icon.Image = (options and options.IconAsset) or DEFAULT_ICON_ASSET
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Parent = container

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0, 0)
	title.Position = UDim2.fromOffset(72, 12)
	title.Size = UDim2.new(1, -176, 0, 28)
	title.Font = Enum.Font.GothamMedium
	title.TextSize = 20
	title.TextColor3 = (options and options.TextColor) or DEFAULT_TEXT_COLOR
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextYAlignment = Enum.TextYAlignment.Center
	title.Text = ""
	title.Parent = container

	local timerLabel = Instance.new("TextLabel")
	timerLabel.Name = "Timer"
	timerLabel.BackgroundTransparency = 1
	timerLabel.AnchorPoint = Vector2.new(1, 0)
	timerLabel.Position = UDim2.new(1, -16, 0, 16)
	timerLabel.Size = UDim2.fromOffset(80, 20)
	timerLabel.Font = Enum.Font.Gotham
	timerLabel.TextSize = 16
	timerLabel.TextColor3 = (options and options.TextColor) or DEFAULT_TEXT_COLOR
	timerLabel.TextXAlignment = Enum.TextXAlignment.Right
	timerLabel.TextYAlignment = Enum.TextYAlignment.Center
	timerLabel.Text = ""
	timerLabel.Parent = container

	local bar = Instance.new("Frame")
	bar.Name = "ProgressBar"
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.fromScale(0.5, 1)
	bar.Size = UDim2.new(1, -32, 0, 12)
	bar.BackgroundColor3 = (options and options.BarColor) or DEFAULT_BAR_COLOR
	bar.BorderSizePixel = 0
	bar.Parent = container

	local barCorner = Instance.new("UICorner")
	barCorner.CornerRadius = UDim.new(1, 0)
	barCorner.Parent = bar

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 0.5)
	fill.Position = UDim2.fromScale(0, 0.5)
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = (options and options.FillColor) or DEFAULT_FILL_COLOR
	fill.BorderSizePixel = 0
	fill.Parent = bar

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill

	return {
		_playerGui = playerGui,
		_screenGui = screenGui,
		_container = container,
		_icon = icon,
		_title = title,
		_timerLabel = timerLabel,
		_fill = fill,
		_renderConnection = nil,
		_token = 0,
		_defaultFillColor = fill.BackgroundColor3,
		_defaultBarColor = bar.BackgroundColor3,
		_defaultTextColor = title.TextColor3,
	} :: Private
end

function TimedProgressHud.new(options: Options?): Controller
	local self = setmetatable(createGui(options), TimedProgressHud) :: any
	return self
end

local function stopRender(self: Private)
	local connection = self._renderConnection
	if connection then
		connection:Disconnect()
		self._renderConnection = nil
	end
end

function TimedProgressHud:Show(durationSeconds: number?, titleText: string)
	local selfPrivate = self :: Private
	local duration = (durationSeconds and durationSeconds > 0) and durationSeconds or 0
	local token = selfPrivate._token + 1
	selfPrivate._token = token

	stopRender(selfPrivate)

	selfPrivate._container.Visible = true
	selfPrivate._title.Text = titleText
	selfPrivate._timerLabel.Text = string.format("%.1fs", duration)
	selfPrivate._fill.Size = UDim2.fromScale(if duration > 0 then 0 else 1, 1)

	if duration <= 0 then
		return
	end

	local startClock = os.clock()
	selfPrivate._renderConnection = RunService.RenderStepped:Connect(function()
		if selfPrivate._token ~= token then
			return
		end
		local elapsed = os.clock() - startClock
		local alpha = math.clamp(elapsed / duration, 0, 1)
		selfPrivate._fill.Size = UDim2.fromScale(alpha, 1)
		selfPrivate._timerLabel.Text = string.format("%.1fs", math.max(duration - elapsed, 0))
		if alpha >= 1 then
			stopRender(selfPrivate)
			selfPrivate._fill.Size = UDim2.fromScale(1, 1)
			selfPrivate._timerLabel.Text = "0.0s"
		end
	end)
end

function TimedProgressHud:Hide()
	local selfPrivate = self :: Private
	selfPrivate._token += 1
	stopRender(selfPrivate)
	selfPrivate._fill.Size = UDim2.fromScale(0, 1)
	selfPrivate._container.Visible = false
end

function TimedProgressHud:Destroy()
	local selfPrivate = self :: Private
	self:Hide()
	selfPrivate._screenGui:Destroy()
end

return TimedProgressHud
