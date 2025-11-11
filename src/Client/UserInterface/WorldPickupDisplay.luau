--!strict
-- Billboard-based display for showing material pickups near a target part.

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

export type Options = {
	DisplayDuration: number?,
	MaxDistance: number?,
	GuiSize: UDim2?,
	IconSize: UDim2?,
	DefaultIcon: string?,
}

export type MaterialSpec = {
	Id: string,
	Name: string,
	IconImage: string?,
}

export type Controller = {
	Show: (
		self: Controller,
		materialSpec: MaterialSpec,
		quantity: number,
		targetPart: BasePart?,
		studsOffset: Vector3?
	) -> number,
	Reset: (self: Controller) -> (),
}

type DisplayState = {
	Gui: BillboardGui,
	Frame: Frame,
	Icon: ImageLabel,
	AmountLabel: TextLabel,
	Value: NumberValue,
	AmountTween: Tween?,
	HideToken: number,
}

type Private = {
	_displayDuration: number,
	_maxDistance: number,
	_guiSize: UDim2,
	_iconSize: UDim2,
	_defaultIcon: string,
	_materialTotals: { [string]: number },
	_displays: { [string]: DisplayState },
}

local DEFAULT_DURATION = 2.6
local DEFAULT_MAX_DISTANCE = 90
local DEFAULT_GUI_SIZE = UDim2.fromOffset(188, 66)
local DEFAULT_ICON_SIZE = UDim2.fromOffset(46, 46)
local DEFAULT_ICON = ""
local DEFAULT_BACKGROUND = Color3.fromRGB(24, 28, 32)
local DEFAULT_STROKE_COLOR = Color3.fromRGB(68, 82, 96)
local DEFAULT_TEXT_COLOR = Color3.new(1, 1, 1)

local WorldPickupDisplay = {}
WorldPickupDisplay.__index = WorldPickupDisplay

local function createDisplay(
	self: Private,
	materialId: string,
	materialSpec: MaterialSpec,
	targetPart: BasePart,
	studsOffset: Vector3?
): DisplayState
	local billboard = Instance.new("BillboardGui")
	billboard.Name = string.format("_Pickup_%s", materialId)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = self._maxDistance
	billboard.Size = self._guiSize
	billboard.ResetOnSpawn = false
	billboard.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	billboard.StudsOffsetWorldSpace = studsOffset or Vector3.zero
	billboard.Adornee = targetPart
	billboard.Parent = targetPart

	local frame = Instance.new("Frame")
	frame.Name = "Container"
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = UDim2.fromScale(0.5, 0.5)
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundTransparency = 1
	frame.BackgroundColor3 = DEFAULT_BACKGROUND
	frame.BorderSizePixel = 0
	frame.Parent = billboard

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = frame

	local stroke = Instance.new("UIStroke")
	stroke.Color = DEFAULT_STROKE_COLOR
	stroke.Thickness = 1.2
	stroke.Transparency = 1
	stroke.Parent = frame

	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 12)
	padding.Parent = frame

	local icon = Instance.new("ImageLabel")
	icon.Name = "Icon"
	icon.BackgroundTransparency = 1
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.fromScale(0, 0.5)
	icon.Size = self._iconSize
	icon.ScaleType = Enum.ScaleType.Fit
	icon.Image = (materialSpec.IconImage ~= "" and materialSpec.IconImage) or self._defaultIcon
	icon.ImageTransparency = 0
	icon.Parent = frame

	local amountLabel = Instance.new("TextLabel")
	amountLabel.Name = "AmountLabel"
	amountLabel.BackgroundTransparency = 1
	amountLabel.AnchorPoint = Vector2.new(0, 0)
	amountLabel.Position = UDim2.fromOffset(self._iconSize.X.Offset + 12, 0)
	amountLabel.Size = UDim2.new(1, -(self._iconSize.X.Offset + 16), 0, 30)
	amountLabel.Font = Enum.Font.GothamBold
	amountLabel.Text = "0"
	amountLabel.TextColor3 = DEFAULT_TEXT_COLOR
	amountLabel.TextStrokeTransparency = 0.55
	amountLabel.TextXAlignment = Enum.TextXAlignment.Left
	amountLabel.TextScaled = false
	amountLabel.TextSize = 26
	amountLabel.Parent = frame

	local valueObject = Instance.new("NumberValue")
	valueObject.Name = "DisplayValue"
	valueObject.Value = 0
	valueObject.Parent = billboard

	local state: DisplayState = {
		Gui = billboard,
		Frame = frame,
		Icon = icon,
		AmountLabel = amountLabel,
		Value = valueObject,
		AmountTween = nil,
		HideToken = 0,
	}

	local connection: RBXScriptConnection
	connection = valueObject:GetPropertyChangedSignal("Value"):Connect(function()
		if not billboard.Parent then
			connection:Disconnect()
			return
		end
		amountLabel.Text = string.format("%d", math.floor(valueObject.Value + 0.5))
	end)

	self._displays[materialId] = state
	return state
end

local function getDisplay(
	self: Private,
	materialId: string,
	materialSpec: MaterialSpec,
	targetPart: BasePart,
	studsOffset: Vector3?
): DisplayState
	local state = self._displays[materialId]
	if state and state.Gui.Parent then
		state.Gui.Adornee = targetPart
		state.Gui.Parent = targetPart
		state.Gui.StudsOffsetWorldSpace = studsOffset or Vector3.zero
		state.Frame.BackgroundTransparency = 1
	else
		state = createDisplay(self, materialId, materialSpec, targetPart, studsOffset)
	end

	state.Icon.Image = (materialSpec.IconImage ~= "" and materialSpec.IconImage) or self._defaultIcon
	return state
end

local function cancelTween(state: DisplayState)
	local tween = state.AmountTween
	if tween then
		tween:Cancel()
		state.AmountTween = nil
	end
end

local function fadeOut(self: Private, materialId: string, state: DisplayState, hideToken: number)
	local frameTween = TweenService:Create(
		state.Frame,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }
	)
	local iconTween = TweenService:Create(
		state.Icon,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ ImageTransparency = 1 }
	)
	local amountTween = TweenService:Create(
		state.AmountLabel,
		TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ TextTransparency = 1 }
	)

	frameTween:Play()
	iconTween:Play()
	amountTween:Play()

	amountTween.Completed:Connect(function()
		if self._displays[materialId] ~= state or state.HideToken ~= hideToken then
			return
		end
		if state.Gui.Parent then
			state.Gui.Enabled = false
			state.Gui:Destroy()
		end
		self._displays[materialId] = nil
	end)
end

function WorldPickupDisplay.new(options: Options?): Controller
	local self = setmetatable({
		_displayDuration = (options and options.DisplayDuration) or DEFAULT_DURATION,
		_maxDistance = (options and options.MaxDistance) or DEFAULT_MAX_DISTANCE,
		_guiSize = (options and options.GuiSize) or DEFAULT_GUI_SIZE,
		_iconSize = (options and options.IconSize) or DEFAULT_ICON_SIZE,
		_defaultIcon = (options and options.DefaultIcon) or DEFAULT_ICON,
		_materialTotals = {},
		_displays = {},
	}, WorldPickupDisplay) :: any
	return self
end

function WorldPickupDisplay:Show(
	materialSpec: MaterialSpec,
	quantity: number,
	targetPart: BasePart?,
	studsOffset: Vector3?
): number
	local selfPrivate = self :: Private
	local materialId = materialSpec.Id
	local previous = selfPrivate._materialTotals[materialId] or 0
	local newTotal = previous + quantity
	selfPrivate._materialTotals[materialId] = newTotal

	if not targetPart or not targetPart:IsDescendantOf(Workspace) then
		return newTotal
	end

	local state = getDisplay(selfPrivate, materialId, materialSpec, targetPart :: BasePart, studsOffset)
	state.Gui.Enabled = true
	state.Frame.BackgroundTransparency = 1
	state.Icon.ImageTransparency = 0
	state.AmountLabel.TextTransparency = 0
	state.AmountLabel.Text = string.format("%d", previous)
	state.Value.Value = previous

	cancelTween(state)

	local amountTween = TweenService:Create(
		state.Value,
		TweenInfo.new(0.34, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Value = newTotal }
	)
	state.AmountTween = amountTween
	amountTween.Completed:Connect(function()
		if state.AmountTween then
			state.AmountTween = nil
		end
	end)
	amountTween:Play()

	state.HideToken += 1
	local hideToken = state.HideToken

	task.delay(selfPrivate._displayDuration, function()
		if selfPrivate._displays[materialId] ~= state or state.HideToken ~= hideToken then
			return
		end
		cancelTween(state)
		fadeOut(selfPrivate, materialId, state, hideToken)
	end)

	return newTotal
end

function WorldPickupDisplay:Reset()
	local selfPrivate = self :: Private
	for materialId, state in pairs(selfPrivate._displays) do
		if state.Gui.Parent then
			state.Gui:Destroy()
		end
		selfPrivate._displays[materialId] = nil
	end
	selfPrivate._materialTotals = {}
end

return WorldPickupDisplay
