--!strict
-- StarterPlayerScripts/Client/UserInterface/BillboardRadialUI.lua

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ObjectAction = require(script.Parent.Parent.Modules.ObjectAction)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local ObjectSelectorContext = InputContextsFolder:WaitForChild("ObjectSelectorContext")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local RadialBillboardButtonEnabled = ActiveQueryFolder:WaitForChild("RadialBillboardButtonEnabled") :: BoolValue

local RadialBillboard = PlayerGui:WaitForChild("RadialBillboard") :: BillboardGui
local HubFrame = RadialBillboard:WaitForChild("Root"):FindFirstChild("Hub") :: Frame
local CenterLabel = HubFrame:FindFirstChild("CenterLabel") :: TextLabel

local BillboardRadialUI = {}
local AdorneeModel: Model? = nil

local OriginalButtonPositions: { [TextButton]: UDim2 } = {}

local function registerButton(button: TextButton)
	if OriginalButtonPositions[button] then
		return
	end

	OriginalButtonPositions[button] = button.Position
end

local function tryRegisterDescendant(descendant: Instance)
	if descendant:IsA("TextButton") then
		registerButton(descendant)
	end
end

for _, descendant in ipairs(RadialBillboard:GetDescendants()) do
	tryRegisterDescendant(descendant)
end

RadialBillboard.DescendantAdded:Connect(function(descendant)
	tryRegisterDescendant(descendant)
end)

local function AnimateButtonsOut()
	for _, button in pairs(RadialBillboard:GetDescendants()) do
		if button:IsA("TextButton") then
			-- Tween the button back to its original position, by default the position of buttons are already in original position so might have to set it to hubframe position first
			-- Need to find a way to store original position
			registerButton(button)

			button.Position = HubFrame.Position
			local originalPosition = OriginalButtonPositions[button]
			if originalPosition then
				local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
				local tween = TweenService:Create(button, tweenInfo, { Position = originalPosition })
				tween:Play()
			end
		end
	end
end

local function UiClickGuard(length: number?)
	if RadialBillboardButtonEnabled.Value then
		return
	end
	local cooldown = length or 0.18
	RadialBillboardButtonEnabled.Value = true
	task.delay(cooldown, function()
		RadialBillboardButtonEnabled.Value = false
	end)
end

function BillboardRadialUI.Init()
	ObjectSelectorContext.CloseSelector.Pressed:Connect(function()
		BillboardRadialUI.Hide()
		ObjectAction.Close()
		UiClickGuard() -- The order here is important to prevent input conflicts, this must be called after hiding the UI
		print("CloseSelector action triggered")
	end)

	ObjectSelectorContext.MoveObject.Pressed:Connect(function()
		print("MoveObject action triggered")
		UiClickGuard()
		if not AdorneeModel then
			warn("No model selected for move action.")
			return
		end

		ObjectAction.Move(AdorneeModel, Vector3.new(0, 0, 0))
		--#TODO: You can add functionality here to handle the move action
	end)

	ObjectSelectorContext.RotateObject.Pressed:Connect(function()
		print("RotateObject action triggered")
		UiClickGuard()
		if not AdorneeModel then
			warn("No model selected for rotate action.")
			return
		end
		ObjectAction.Rotate(AdorneeModel, Vector3.new(0, 0, 0))
	end)

	ObjectSelectorContext.DeleteObject.Pressed:Connect(function()
		print("DeleteObject action triggered")
		UiClickGuard()
		if not AdorneeModel then
			warn("No model selected for delete action.")
			return
		end
		ObjectAction.Delete(AdorneeModel)
	end)

	ObjectSelectorContext.CopyObject.Pressed:Connect(function()
		print("CopyObject action triggered")
		UiClickGuard()
		if not AdorneeModel then
			warn("No model selected for copy action.")
			return
		end
		ObjectAction.Copy(AdorneeModel)
	end)
end

function BillboardRadialUI.Show(adornee: Model)
	local plotModel = PlotFinder.FindPlot(Player:GetAttribute("OwnedPlotIndex") :: number)
	if not plotModel then
		warn("No plot model found.")
		return
	end
	if AdorneeModel == adornee and RadialBillboard.Enabled then
		return
	end
	RadialBillboard.Enabled = true
	RadialBillboard.Adornee = adornee
	AdorneeModel = adornee
	local itemIdValue = adornee:GetAttribute("ItemId")
	local displayId = if typeof(itemIdValue) == "string" and itemIdValue ~= "" then itemIdValue else adornee.Name
	CenterLabel.Text = displayId
	AnimateButtonsOut()
end

function BillboardRadialUI.Hide()
	RadialBillboardButtonEnabled.Value = false
	AdorneeModel = nil
	RadialBillboard.Parent = PlayerGui
	RadialBillboard.Adornee = PlayerGui
	RadialBillboard.Enabled = false
	CenterLabel.Text = "Object"
	ObjectAction.Close()
end

function BillboardRadialUI.IsVisible(): boolean
	return RadialBillboard.Enabled
end

function BillboardRadialUI.IsVisibleFor(model: Model): boolean
	return RadialBillboard.Enabled and AdorneeModel == model
end

function BillboardRadialUI.GetCurrentAdornee(): Model?
	return AdorneeModel
end
return BillboardRadialUI
