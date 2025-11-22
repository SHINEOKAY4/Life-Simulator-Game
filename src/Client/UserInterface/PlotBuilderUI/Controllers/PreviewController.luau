--!strict

local UserInputService = game:GetService("UserInputService")

local PlotBuilder = require(script.Parent.Parent.Parent.Parent.Modules.PlotBuilder)
local SurfacePaintController = require(script.Parent.Parent.Parent.Parent.Modules.SurfacePaintController)

export type PreviewCallbacks = {
	onPreviewCancelled: (() -> ())?,
	onHideRequested: (() -> ())?,
}

export type PreviewConfig = {
	PlotBuilderGui: ScreenGui,
	CancelButtonTemplate: TextButton,
	PlotBuilderEnabledValue: BoolValue?,
	ObjectPreviewEnabledValue: BoolValue?,
	CancelPreviewAction: Instance?,
}

type CancelHandler = () -> ()
type PreviewControllerState = {
	_plotBuilderGui: ScreenGui,
	_cancelButtonTemplate: TextButton,
	_plotBuilderEnabledValue: BoolValue?,
	_objectPreviewEnabledValue: BoolValue?,
	_cancelPreviewAction: Instance?,
	_callbacks: PreviewCallbacks,
	_previewControlsFrame: Frame?,
	_cancelPreviewButton: TextButton?,
	_cancelActionConnection: RBXScriptConnection?,
	_cancelRKeyConnection: RBXScriptConnection?,
	_previewToggleConnection: RBXScriptConnection?,
	_externalCancelSource: string?,
	_externalCancelHandler: CancelHandler?,
}

local PreviewController = {}
PreviewController.__index = PreviewController

function PreviewController.new(config: PreviewConfig, callbacks: PreviewCallbacks)
	local self = setmetatable({} :: PreviewControllerState, PreviewController)
	self._plotBuilderGui = config.PlotBuilderGui
	self._cancelButtonTemplate = config.CancelButtonTemplate
	self._plotBuilderEnabledValue = config.PlotBuilderEnabledValue
	self._objectPreviewEnabledValue = config.ObjectPreviewEnabledValue
	self._cancelPreviewAction = config.CancelPreviewAction
	self._callbacks = callbacks
	self._previewControlsFrame = nil
	self._cancelPreviewButton = nil
	self._cancelActionConnection = nil
	self._cancelRKeyConnection = nil
	self._previewToggleConnection = nil
	self._externalCancelSource = nil
	self._externalCancelHandler = nil
	return self
end

local function boolValueTrue(value: BoolValue?): boolean
	return value ~= nil and value.Value == true
end

function PreviewController:IsPreviewActive(): boolean
	return boolValueTrue(self._plotBuilderEnabledValue) and boolValueTrue(self._objectPreviewEnabledValue)
end

function PreviewController:_ensureFrame(): Frame
	local state = self :: PreviewControllerState
	if state._previewControlsFrame and state._previewControlsFrame.Parent then
		return state._previewControlsFrame
	end

	local plotBuilderGui = state._plotBuilderGui
	local existing = plotBuilderGui:FindFirstChild("PreviewControls")
	if existing and existing:IsA("Frame") then
		state._previewControlsFrame = existing
		return existing
	end

	local container = Instance.new("Frame")
	container.Name = "PreviewControls"
	container.AnchorPoint = Vector2.new(1, 1)
	container.Position = UDim2.new(1, -24, 1, -24)
	container.Size = UDim2.fromOffset(260, 64)
	container.BackgroundTransparency = 1
	container.BorderSizePixel = 0
	container.ZIndex = 100
	container.Visible = false
	container.Parent = plotBuilderGui

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Padding = UDim.new(0, 12)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = container

	state._previewControlsFrame = container
	return container
end

function PreviewController:_ensureCancelButton(): TextButton
	local state = self :: PreviewControllerState
	local frame: Frame = self:_ensureFrame()
	local existing = frame:FindFirstChild("CancelPreviewButton")
	if existing and existing:IsA("TextButton") then
		state._cancelPreviewButton = existing
		return existing
	end

	local clonedButton = state._cancelButtonTemplate:Clone()
	local button = clonedButton :: TextButton
	button.Name = "CancelPreviewButton"
	button.LayoutOrder = 100
	button.ZIndex = frame.ZIndex + 1
	button.Parent = frame

	local keyHint = button:FindFirstChild("KeyHint")
	if keyHint and keyHint:IsA("TextLabel") then
		keyHint.ZIndex = button.ZIndex + 1
	end

	state._cancelPreviewButton = button
	return button
end

function PreviewController:_handlePreviewCancelled()
	local state = self :: PreviewControllerState
	if state._callbacks.onPreviewCancelled then
		state._callbacks.onPreviewCancelled()
	end
	self:UpdateCancelButtonState()
end

function PreviewController:_handlePreviewButtonActivated()
	local state = self :: PreviewControllerState
	if self:IsPreviewActive() then
		self:_handlePreviewCancelled()
		PlotBuilder.RemovePreview()
		return
	end
	if state._externalCancelHandler then
		state._externalCancelHandler()
	end
end

function PreviewController:_bindActionButton()
	local button = self:_ensureCancelButton()
	if button:GetAttribute("CancelHandlerBound") == true then
		return
	end
	button:SetAttribute("CancelHandlerBound", true)
	button.Activated:Connect(function()
		self:_handlePreviewButtonActivated()
	end)
end

function PreviewController:UpdateCancelButtonState()
	local state = self :: PreviewControllerState
	if not state._cancelPreviewButton then
		self:_ensureCancelButton()
	end
	local button = state._cancelPreviewButton :: TextButton
	local previewActive = self:IsPreviewActive()
	local externalActive = state._externalCancelSource ~= nil
	local buttonVisible = previewActive or externalActive

	local frame = self:_ensureFrame()
	frame.Visible = buttonVisible

	button.Active = buttonVisible
	button.AutoButtonColor = buttonVisible
	button.Selectable = buttonVisible
	button.Visible = buttonVisible
	button:SetAttribute("PreviewActive", previewActive)

	local keyHint = button:FindFirstChild("KeyHint")
	if keyHint and keyHint:IsA("TextLabel") then
		keyHint.Visible = buttonVisible
	end
end

function PreviewController:_bindCancelAction()
	local state = self :: PreviewControllerState
	local button = self:_ensureCancelButton()
	local action = state._cancelPreviewAction
	if action and action:IsA("InputAction") then
		local binding = (action :: any).InputBinding
		if binding then
			(binding :: any).UIButton = button
		end

		local keyHint = button:FindFirstChild("KeyHint")
		if keyHint and keyHint:IsA("TextLabel") then
			local resolvedHint = keyHint.Text ~= "" and keyHint.Text or "Esc"
			local attributeCandidates = { "KeyboardHint", "KeyHint", "DisplayLabel" }
			for _, attributeName in ipairs(attributeCandidates) do
				local hintValue = action:GetAttribute(attributeName)
				if typeof(hintValue) == "string" and hintValue ~= "" then
					resolvedHint = hintValue
					break
				end
			end
			keyHint.Text = resolvedHint
		end

		if not state._cancelActionConnection then
			state._cancelActionConnection = action.Pressed:Connect(function()
				self:_handlePreviewCancelled()
			end)
		end
	end
end

function PreviewController:_bindKeyboardShortcuts()
	local state = self :: PreviewControllerState
	if not state._cancelRKeyConnection then
		state._cancelRKeyConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode ~= Enum.KeyCode.R then
				return
			end
			if UserInputService:GetFocusedTextBox() then
				return
			end
			if not self:IsPreviewActive() then
				return
			end
			self:_handlePreviewCancelled()
			PlotBuilder.RemovePreview()
		end)
	end

	if not state._previewToggleConnection then
		state._previewToggleConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
			if gameProcessed then
				return
			end
			if input.KeyCode ~= Enum.KeyCode.B then
				return
			end
			if UserInputService:GetFocusedTextBox() then
				return
			end
			if not boolValueTrue(self._plotBuilderEnabledValue) then
				return
			end
			if not boolValueTrue(self._objectPreviewEnabledValue) then
				return
			end
			SurfacePaintController.Stop()
			self:_handlePreviewCancelled()
			if self._callbacks.onHideRequested then
				self._callbacks.onHideRequested()
			else
				PlotBuilder.Hide()
			end
		end)
	end
end

function PreviewController:Init()
	self:_bindActionButton()
	self:_bindCancelAction()
	self:_bindKeyboardShortcuts()
	self:UpdateCancelButtonState()
end

function PreviewController:Destroy()
	local state = self :: PreviewControllerState
	local cancelActionConnection = state._cancelActionConnection
	if cancelActionConnection then
		cancelActionConnection:Disconnect()
	end
	state._cancelActionConnection = nil

	local cancelRKeyConnection = state._cancelRKeyConnection
	if cancelRKeyConnection then
		cancelRKeyConnection:Disconnect()
	end
	state._cancelRKeyConnection = nil

	local previewToggleConnection = state._previewToggleConnection
	if previewToggleConnection then
		previewToggleConnection:Disconnect()
	end
	state._previewToggleConnection = nil
end

function PreviewController:AcquireCancelButton(sourceId: string, handler: (() -> ())?)
	local state = self :: PreviewControllerState
	if typeof(sourceId) ~= "string" or sourceId == "" then
		error("PreviewController.AcquireCancelButton requires a non-empty source identifier")
	end
	if handler ~= nil and typeof(handler) ~= "function" then
		error("PreviewController.AcquireCancelButton handler must be a function or nil")
	end
	if state._externalCancelSource and state._externalCancelSource ~= sourceId then
		warn(string.format("[PreviewController] Cancel button already owned by %s", state._externalCancelSource))
	end
	state._externalCancelSource = sourceId
	state._externalCancelHandler = handler
	self:UpdateCancelButtonState()
end

function PreviewController:ReleaseCancelButton(sourceId: string)
	local state = self :: PreviewControllerState
	if typeof(sourceId) ~= "string" or sourceId == "" then
		return
	end
	if state._externalCancelSource ~= sourceId then
		return
	end
	state._externalCancelSource = nil
	state._externalCancelHandler = nil
	self:UpdateCancelButtonState()
end

return PreviewController
