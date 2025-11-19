--!strict
-- StarterPlayerScripts/Client/UserInterface/TenantEvictionBillboard.luau
-- World-space confirmation UI used when evicting active renters.

local Players = game:GetService("Players")

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

export type ShowOptions = {
	ResidentName: string?,
	TenantLabel: string?,
	OnConfirm: (() -> ())?,
	OnCancel: (() -> ())?,
}

local TenantEvictionBillboard = {}

local billboardGui: BillboardGui?
local titleLabel: TextLabel?
local statusLabel: TextLabel?
local confirmButton: TextButton?
local cancelButton: TextButton?
local buttonHintLabel: TextLabel?

local currentModel: Model?
local confirmCallback: (() -> ())?
local cancelCallback: (() -> ())?
local isBusy = false
local isVisible = false

local STATUS_COLOR = Color3.fromRGB(200, 210, 244)
local ERROR_COLOR = Color3.fromRGB(255, 120, 120)
local BILLBOARD_NAME = "TenantEvictionBillboard"
local ROOT_NAME = "Root"
local BUTTONS_NAME = "Buttons"
local CANCEL_BUTTON_NAME = "CancelButton"
local CONFIRM_BUTTON_NAME = "ConfirmButton"

local function resolveModelAdornee(model: Model?): Instance?
	if not model then
		return nil
	end
	local primaryPart = model.PrimaryPart
	if primaryPart then
		return primaryPart
	end
	local humanoidRoot = model:FindFirstChild("HumanoidRootPart")
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		return humanoidRoot
	end
	return model:FindFirstChildWhichIsA("BasePart")
end

local function setButtonEnabled(button: TextButton?, enabled: boolean)
	if not button then
		return
	end
	button.Active = enabled
	button.AutoButtonColor = enabled
	button.TextTransparency = if enabled then 0 else 0.4
	local uiStroke = button:FindFirstChildWhichIsA("UIStroke")
	if uiStroke then
		uiStroke.Transparency = if enabled then 0.2 else 0.6
	end
	button.TextStrokeTransparency = if enabled then 0.2 else 0.6
end

local function applyBusyState()
	setButtonEnabled(confirmButton, not isBusy)
	setButtonEnabled(cancelButton, not isBusy)
	if confirmButton then
		confirmButton.Text = if isBusy then "Working..." else "Evict"
	end
	if cancelButton then
		cancelButton.Text = if isBusy then "" else "Cancel"
	end
	if buttonHintLabel then
		buttonHintLabel.Visible = not isBusy
	end
end

local function ensureGui()
	if billboardGui then
		return
	end

	local gui = PlayerGui:FindFirstChild(BILLBOARD_NAME)
	if not gui then
		gui = PlayerGui:WaitForChild(BILLBOARD_NAME, 5)
	end
	if not gui or not gui:IsA("BillboardGui") then
		warn("TenantEvictionBillboard: BillboardGui not found in PlayerGui")
		return
	end

	local root = gui:FindFirstChild(ROOT_NAME)
	if not root or not root:IsA("Frame") then
		warn("TenantEvictionBillboard: Root frame missing inside billboard")
		return
	end

	billboardGui = gui
	titleLabel = root:FindFirstChild("Title") :: TextLabel?
	statusLabel = root:FindFirstChild("Status") :: TextLabel?
	buttonHintLabel = root:FindFirstChild("Hint") :: TextLabel?

	local buttonsContainer = root:FindFirstChild(BUTTONS_NAME)
	if buttonsContainer and buttonsContainer:IsA("Frame") then
		cancelButton = buttonsContainer:FindFirstChild(CANCEL_BUTTON_NAME) :: TextButton?
		confirmButton = buttonsContainer:FindFirstChild(CONFIRM_BUTTON_NAME) :: TextButton?
	else
		warn("TenantEvictionBillboard: Buttons container missing")
	end

	if cancelButton then
		cancelButton.Activated:Connect(function()
			if isBusy then
				return
			end
			if cancelCallback then
				cancelCallback()
			end
			TenantEvictionBillboard.Hide()
		end)
	end

	if confirmButton then
		confirmButton.Activated:Connect(function()
			if isBusy then
				return
			end
			if confirmCallback then
				confirmCallback()
			end
		end)
	end
end

local function setStatus(message: string?, isError: boolean?)
	if not statusLabel then
		return
	end
	if message and message ~= "" then
		statusLabel.Visible = true
		statusLabel.Text = message
		statusLabel.TextColor3 = if isError then ERROR_COLOR else STATUS_COLOR
	else
		statusLabel.Visible = false
		statusLabel.Text = ""
	end
end

function TenantEvictionBillboard.Show(model: Model, options: ShowOptions?)
	ensureGui()
	local gui = billboardGui
	if not gui then
		return
	end
	local adornee = resolveModelAdornee(model)
	if not adornee then
		return
	end

	currentModel = model
	confirmCallback = options and options.OnConfirm or nil
	cancelCallback = options and options.OnCancel or nil
	local residentName = options and options.ResidentName
	local tenantLabel = options and options.TenantLabel

	if titleLabel then
		local nameLabel = residentName or tenantLabel or "Tenant"
		titleLabel.Text = string.format("Evict %s?", nameLabel)
	end

	setStatus(nil, false)
	isBusy = false
	applyBusyState()

	gui.Adornee = adornee
	gui.Enabled = true
	gui.Parent = PlayerGui
	isVisible = true
end

function TenantEvictionBillboard.Hide()
	local gui = billboardGui
	if not gui then
		return
	end
	gui.Enabled = false
	(gui :: any).Adornee = nil
	currentModel = nil
	confirmCallback = nil
	cancelCallback = nil
	isBusy = false
	isVisible = false
	setStatus(nil, false)
	applyBusyState()
end

function TenantEvictionBillboard.Init()
	ensureGui()
	TenantEvictionBillboard.Hide()
end

function TenantEvictionBillboard.SetBusy(busy: boolean, message: string?)
	isBusy = busy
	applyBusyState()
	if message then
		setStatus(message, false)
	end
end

function TenantEvictionBillboard.SetStatus(message: string?, isError: boolean?)
	setStatus(message, isError)
end

function TenantEvictionBillboard.IsVisible(): boolean
	return isVisible
end

function TenantEvictionBillboard.IsVisibleFor(model: Model): boolean
	return isVisible and currentModel == model
end

function TenantEvictionBillboard.GetCurrentModel(): Model?
	return currentModel
end

return TenantEvictionBillboard
