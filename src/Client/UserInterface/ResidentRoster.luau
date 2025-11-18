--!strict
-- StarterPlayerScripts/Client/UserInterface/ResidentRoster.lua

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ResidentNeedsUI = require(script.Parent.ResidentNeedsUI)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local CameraUtils = require(ReplicatedStorage.Shared.Utilities.CameraUtils)
local ResidentsStore = require(script.Parent.Parent.ClientStores.ResidentsStore) :: any
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local VisualFX = require(ReplicatedStorage.Shared.Utilities.VisualFX)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ResidentGui = PlayerGui:WaitForChild("ResidentGui")
local Profile = ResidentGui:WaitForChild("Profile")
local ResidentSelectionFrame = ResidentGui:WaitForChild("ResidentSelectionFrame")
local ResidentNeedsFrame = ResidentGui:WaitForChild("ResidentNeedsFrame")
local ResidentButtons = ResidentGui:WaitForChild("ResidentButtons")
local CustomizeButton = ResidentButtons:FindFirstChild("CustomizeButton") :: TextButton?
local ProfileButton = ResidentButtons:WaitForChild("ProfileButton") :: TextButton
local CareerButton = ResidentButtons:FindFirstChild("CareerButton") :: TextButton?

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled") :: BoolValue
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled") :: BoolValue
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled") :: BoolValue
local RadialBillboardButtonEnabled = ActiveQueryFolder:WaitForChild("RadialBillboardButtonEnabled") :: BoolValue
local _ResidentRadialEnabled = ActiveQueryFolder:FindFirstChild("ResidentRadialEnabled") :: BoolValue
local ResidentRosterEnabled = ActiveQueryFolder:FindFirstChild("ResidentRosterEnabled") :: BoolValue

local Roster = ResidentSelectionFrame.Background.Roster
local AddResidentButton = Roster:FindFirstChild("AddResidentButton")

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local InterfacesTemplates = AssetsFolder:WaitForChild("InterfacesTemplates")
local TemplateFrame = InterfacesTemplates:WaitForChild("ResidentFrameTemplate")

local HoverTweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local HoverSizeGoal = UDim2.fromScale(0.155, 1.525)
local ButtonHoverScale = 1.08

local isRosterVisible = ResidentSelectionFrame.Visible

local function setRosterVisible(isVisible: boolean)
	ResidentSelectionFrame.Visible = isVisible
	isRosterVisible = isVisible
end

local function isRosterBlocked(): boolean
	if ObjectSelectorEnabled and ObjectSelectorEnabled.Value then
		return true
	end
	if PlotBuilderEnabled and PlotBuilderEnabled.Value then
		return true
	end
	if PlotExpansionEnabled and PlotExpansionEnabled.Value then
		return true
	end
	if RadialBillboardButtonEnabled and RadialBillboardButtonEnabled.Value then
		return true
	end
	return false
end

local INPUT_DEBOUNCE_SECONDS = 0.2
local NEED_ATTRIBUTE_NAMES = { "Hunger", "Energy", "Fun", "Social", "Hygiene" }
local GRADIENT_GOOD_COLOR = Color3.fromRGB(54, 199, 82)
local GRADIENT_BAD_COLOR = Color3.fromRGB(215, 71, 63)
local GRADIENT_HIGHLIGHT_COLOR = Color3.new(1, 1, 1)
local GRADIENT_SHADOW_COLOR = Color3.new(0, 0, 0)
local CAMERA_FOCUS_DURATION_SECONDS = 0
local CAMERA_ISO_DISTANCE_STUDS = 26
local CAMERA_ISO_PITCH_DEGREES = 55
local CAMERA_ISO_YAW_DEGREES = 45
local DEFAULT_WALK_SPEED = 16
local DEFAULT_JUMP_POWER = 50

type FrameInfo = {
	Frame: Frame,
	DefaultSize: UDim2,
	PlaySizeTween: (UDim2) -> (),
	UpdateGradient: () -> (),
	UpdateResidentSnapshot: (any) -> (),
	ResidentModel: Model?,
	GetResidentSnapshot: () -> any?,
}

local ResidentRoster = {}
local Connections = {} :: { [string]: { RBXScriptConnection } }
local FrameData = {} :: { [string]: FrameInfo }
local SelectedResidentName: string? = nil
local cachedMovementState: { WalkSpeed: number?, JumpPower: number?, AutoJumpEnabled: boolean? }? = nil
local isMovementDisabled = false

local function getOffsiteFolder(): Folder?
	local container = ReplicatedStorage:FindFirstChild("ResidentOffsite")
	if container and container:IsA("Folder") then
		return container
	end
	return nil
end

local function scaleUDim2(baseSize: UDim2, multiplier: number): UDim2
	return UDim2.new(
		baseSize.X.Scale * multiplier,
		math.round(baseSize.X.Offset * multiplier),
		baseSize.Y.Scale * multiplier,
		math.round(baseSize.Y.Offset * multiplier)
	)
end

local function resolveResidentModel(residentName: string): Model?
	local plotIndexValue = Player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndexValue) == "number" then
		local plotModel = PlotFinder.FindPlot(plotIndexValue)
		if plotModel then
			local residentsFolder = plotModel:FindFirstChild("Residents")
			if residentsFolder then
				local instance = residentsFolder:FindFirstChild(residentName)
				if instance and instance:IsA("Model") then
					local frameInfo = FrameData[residentName]
					if frameInfo then
						frameInfo.ResidentModel = instance
					end
					return instance
				end
			end
		end
	end

	local offsite = getOffsiteFolder()
	if offsite then
		local instance = offsite:FindFirstChild(residentName)
		if instance and instance:IsA("Model") then
			local frameInfo = FrameData[residentName]
			if frameInfo then
				frameInfo.ResidentModel = instance
			end
			return instance
		end
	end

	local frameInfo = FrameData[residentName]
	if frameInfo and frameInfo.ResidentModel and frameInfo.ResidentModel.Parent then
		return frameInfo.ResidentModel
	end

	return nil
end

-- Shift status display removed; roster frames focus on name and needs only.

local function registerButtonHover(button: TextButton, registryKey: string)
	local imageFrame = button:FindFirstChild("Image")
	if not imageFrame or not imageFrame:IsA("GuiObject") then
		return
	end

	local defaultSize = imageFrame.Size
	local hoverSize = scaleUDim2(defaultSize, ButtonHoverScale)
	local activeTween: Tween? = nil

	local function tweenTo(targetSize: UDim2)
		if activeTween then
			activeTween:Cancel()
		end
		activeTween = VisualFX.TweenSize(imageFrame, HoverTweenInfo, targetSize)
	end

	local mouseEnterConnection: RBXScriptConnection
	local mouseLeaveConnection: RBXScriptConnection
	local ancestryConnection: RBXScriptConnection

	mouseEnterConnection = button.MouseEnter:Connect(function()
		tweenTo(hoverSize)
	end)
	mouseLeaveConnection = button.MouseLeave:Connect(function()
		tweenTo(defaultSize)
	end)
	ancestryConnection = button.AncestryChanged:Connect(function(_, parent)
		if parent then
			return
		end
		if mouseEnterConnection.Connected then
			mouseEnterConnection:Disconnect()
		end
		if mouseLeaveConnection.Connected then
			mouseLeaveConnection:Disconnect()
		end
		if ancestryConnection.Connected then
			ancestryConnection:Disconnect()
		end
	end)

	Connections[registryKey] = { mouseEnterConnection, mouseLeaveConnection, ancestryConnection }
end

local function setPlayerMovementEnabled(isEnabled: boolean)
	-- Locks the player's humanoid movement while a resident is actively selected.
	local character = Player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil

	if isEnabled then
		if not isMovementDisabled then
			return
		end

		isMovementDisabled = false

		local state = cachedMovementState
		if humanoid then
			local storedSpeed = if state and typeof(state.WalkSpeed) == "number"
				then state.WalkSpeed
				else DEFAULT_WALK_SPEED
			humanoid.WalkSpeed = storedSpeed
			local storedJumpPower = if state and typeof(state.JumpPower) == "number"
				then state.JumpPower
				else DEFAULT_JUMP_POWER
			humanoid.JumpPower = storedJumpPower
		end

		if state and typeof(state.AutoJumpEnabled) == "boolean" then
			Player.AutoJumpEnabled = state.AutoJumpEnabled
		else
			Player.AutoJumpEnabled = true
		end

		cachedMovementState = nil
		return
	end

	if isMovementDisabled then
		return
	end

	isMovementDisabled = true

	if humanoid then
		cachedMovementState = {
			WalkSpeed = humanoid.WalkSpeed,
			JumpPower = humanoid.JumpPower,
			AutoJumpEnabled = Player.AutoJumpEnabled,
		}
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	else
		cachedMovementState = {
			WalkSpeed = nil,
			JumpPower = nil,
			AutoJumpEnabled = Player.AutoJumpEnabled,
		}
	end

	Player.AutoJumpEnabled = false
end

local function computeIsometricCameraCFrame(residentModel: Model): CFrame?
	local residentPivot = residentModel:GetPivot()
	local focusPosition = residentPivot.Position
	local yaw = math.rad(CAMERA_ISO_YAW_DEGREES)
	local pitch = math.rad(CAMERA_ISO_PITCH_DEGREES)
	local horizontalDirection = Vector3.new(math.cos(yaw), 0, math.sin(yaw))
	if horizontalDirection.Magnitude == 0 then
		horizontalDirection = Vector3.new(0, 0, -1)
	end
	horizontalDirection = horizontalDirection.Unit
	local direction = (horizontalDirection * math.cos(pitch)) + Vector3.new(0, -math.sin(pitch), 0)
	direction = direction.Unit
	local cameraPosition = focusPosition - (direction * CAMERA_ISO_DISTANCE_STUDS)
	return CFrame.lookAt(cameraPosition, focusPosition)
end

local function findResidentCameraSubject(residentModel: Model): BasePart?
	local humanoidRoot = residentModel:FindFirstChild("HumanoidRootPart")
	if humanoidRoot and humanoidRoot:IsA("BasePart") then
		return humanoidRoot
	end
	local primaryPart = residentModel.PrimaryPart
	if primaryPart then
		return primaryPart
	end
	local anyPart = residentModel:FindFirstChildWhichIsA("BasePart")
	return anyPart
end

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("ResidentRoster/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, Player.UserId)
end

local function deselectResident()
	local currentName = SelectedResidentName
	if currentName then
		local currentData = FrameData[currentName]
		if currentData then
			currentData.PlaySizeTween(currentData.DefaultSize)
		end
	end
	SelectedResidentName = nil
	ResidentNeedsFrame.Visible = false
	ResidentButtons.Visible = false
	Profile.Visible = false
	ResidentNeedsUI.Hide()
	CameraUtils.CancelFocus()
	setPlayerMovementEnabled(true)
end

local function refreshRosterVisibility()
	local shouldShow = ResidentRosterEnabled.Value and not isRosterBlocked()
	if shouldShow then
		setRosterVisible(true)
		if SelectedResidentName then
			ResidentNeedsFrame.Visible = true
		end
		return
	end

	if isRosterVisible then
		deselectResident()
	end

	setRosterVisible(false)
end

local function selectResident(residentName: string)
	if SelectedResidentName == residentName then
		deselectResident()
		return
	end

	local previousName = SelectedResidentName
	if previousName and previousName ~= residentName then
		local previousData = FrameData[previousName]
		if previousData then
			previousData.PlaySizeTween(previousData.DefaultSize)
		end
	end

	if isRosterBlocked() then
		return
	end

	local residentModel = resolveResidentModel(residentName)
	if not residentModel then
		warn(string.format("[ResidentRoster] Could not locate resident model for '%s'", residentName))
		return
	end

	SelectedResidentName = residentName
	ResidentRosterEnabled.Value = true
	setRosterVisible(true)
	ResidentNeedsFrame.Visible = true
	ResidentButtons.Visible = true
	ResidentNeedsUI.Show(residentModel)

	local currentData = FrameData[residentName]
	if currentData then
		currentData.PlaySizeTween(HoverSizeGoal)
		currentData.ResidentModel = residentModel
	end
	if residentModel:IsDescendantOf(workspace) then
		local focusFrame = computeIsometricCameraCFrame(residentModel)
		if focusFrame then
			local cameraSubject = findResidentCameraSubject(residentModel)
			CameraUtils.FocusOn(focusFrame, {
				duration = CAMERA_FOCUS_DURATION_SECONDS,
				restoreOnComplete = false,
				cameraTypeOnComplete = Enum.CameraType.Custom,
				cameraSubjectOnComplete = cameraSubject,
			})
		end
	else
		CameraUtils.CancelFocus()
	end
	setPlayerMovementEnabled(false)
end

local function CreateResidentImageButton(residentData: any)
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local residentsFolder = plotModel:FindFirstChild("Residents") :: Folder
	local residentModel = residentsFolder:FindFirstChild(residentData.Name) :: Model
	local imageModel = residentModel:Clone()

	local newFrame = TemplateFrame:Clone()
	newFrame.Name = residentData.Name
	local portraitButton = newFrame.PortraitButton
	local residentNameLabel = newFrame.ResidentName
	local viewportFrame = portraitButton.Image.ViewportFrame
	local worldModel = viewportFrame.WorldModel
	local imageLabel = portraitButton.Image.ImageLabel
	local portraitGradient = imageLabel:FindFirstChildOfClass("UIGradient") :: UIGradient?
	if not portraitGradient then
		local newGradient = Instance.new("UIGradient") :: UIGradient
		newGradient.Name = "NeedsGradient"
		newGradient.Parent = imageLabel
		portraitGradient = newGradient
	end

	local currentResidentSnapshot = residentData

	local function getNeedValue(attributeName: string): number?
		local attributeValue = residentModel:GetAttribute(attributeName)
		if typeof(attributeValue) == "number" then
			return attributeValue
		end
		local needsSnapshot = currentResidentSnapshot and currentResidentSnapshot.Needs
		if typeof(needsSnapshot) == "table" then
			local fallbackValue = needsSnapshot[attributeName]
			if typeof(fallbackValue) == "number" then
				return fallbackValue
			end
		end
		return nil
	end

	local function calculateNeedSatisfaction(): number
		local totalNeedValue = 0
		local validNeedCount = 0
		for _, attributeName in ipairs(NEED_ATTRIBUTE_NAMES) do
			local needValue = getNeedValue(attributeName)
			if typeof(needValue) == "number" then
				totalNeedValue += math.clamp(needValue, 0, 100)
				validNeedCount += 1
			end
		end
		if validNeedCount == 0 then
			return 1
		end
		return math.clamp(totalNeedValue / (validNeedCount * 100), 0, 1)
	end

	local function updateResidentGradient()
		if not portraitGradient then
			return
		end
		local satisfactionRatio = calculateNeedSatisfaction()
		local baseColor = GRADIENT_BAD_COLOR:Lerp(GRADIENT_GOOD_COLOR, satisfactionRatio)
		local highlightColor = baseColor:Lerp(GRADIENT_HIGHLIGHT_COLOR, 0.2)
		local shadowColor = baseColor:Lerp(GRADIENT_SHADOW_COLOR, 0.25)
		portraitGradient.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, highlightColor),
			ColorSequenceKeypoint.new(0.5, baseColor),
			ColorSequenceKeypoint.new(1, shadowColor),
		})
	end

	local function updateResidentSnapshot(newResidentData: any)
		if typeof(newResidentData) ~= "table" then
			return
		end
		currentResidentSnapshot = newResidentData
		updateResidentGradient()
	end

	local targetPivot = CFrame.new(0, -1, 4, -1, 0, 0, 0, 1, 0, 0, 0, -1)
	local defaultSize = newFrame.Size
	local activeTween: Tween? = nil

	local function playSizeTween(targetSize: UDim2)
		if activeTween then
			activeTween:Cancel()
		end
		activeTween = VisualFX.TweenSize(newFrame, HoverTweenInfo, targetSize)
	end
	residentNameLabel.Text = residentData.Name
	local animateScript = imageModel:FindFirstChild("Animate") :: Script
	if animateScript then
		animateScript:Destroy()
	end
	imageModel.Parent = worldModel
	imageModel:PivotTo(targetPivot)

	local mouseEnterConnection = portraitButton.MouseEnter:Connect(function()
		playSizeTween(HoverSizeGoal)
	end)
	local mouseLeaveConnection = portraitButton.MouseLeave:Connect(function()
		if SelectedResidentName == residentData.Name then
			return
		end
		playSizeTween(defaultSize)
	end)
	Connections[residentData.Name] = { mouseEnterConnection, mouseLeaveConnection }
	for _, attributeName in ipairs(NEED_ATTRIBUTE_NAMES) do
		local attributeConnection = residentModel:GetAttributeChangedSignal(attributeName):Connect(function()
			updateResidentGradient()
		end)
		table.insert(Connections[residentData.Name], attributeConnection)
	end
	FrameData[residentData.Name] = {
		Frame = newFrame,
		DefaultSize = defaultSize,
		PlaySizeTween = playSizeTween,
		UpdateGradient = updateResidentGradient,
		UpdateResidentSnapshot = updateResidentSnapshot,
		ResidentModel = residentModel,
		GetResidentSnapshot = function()
			return currentResidentSnapshot
		end,
	}
	updateResidentGradient()
	newFrame.Parent = Roster
	return newFrame, residentModel
end

function ResidentRoster.Init(): ()
	-- Placeholder for future Resident Roster UI initialization.

	if CustomizeButton and CustomizeButton:IsA("TextButton") then
		CustomizeButton.Visible = false
		CustomizeButton.Active = false
		registerButtonHover(CustomizeButton, "Buttons/Customize")
	end
	if AddResidentButton and AddResidentButton:IsA("GuiButton") then
		AddResidentButton.Visible = false
		AddResidentButton.Active = false
	end
	if CareerButton and CareerButton:IsA("TextButton") then
		CareerButton.Visible = false
		CareerButton.Active = false
	end
	registerButtonHover(ProfileButton, "Buttons/Profile")

	if ResidentRosterEnabled then
		ResidentRosterEnabled.Changed:Connect(refreshRosterVisibility)
	end
	if ObjectSelectorEnabled then
		ObjectSelectorEnabled.Changed:Connect(refreshRosterVisibility)
	end
	if PlotBuilderEnabled then
		PlotBuilderEnabled.Changed:Connect(refreshRosterVisibility)
	end
	if PlotExpansionEnabled then
		PlotExpansionEnabled.Changed:Connect(refreshRosterVisibility)
	end
	if RadialBillboardButtonEnabled then
		RadialBillboardButtonEnabled.Changed:Connect(refreshRosterVisibility)
	end

	refreshRosterVisibility()
	ResidentsStore.ResidentAdded:Connect(function(userId: number, residentData: any)
		print("Resident added for userId:", userId, "Resident Name:", residentData.Name)
		if userId ~= Player.UserId then
			return
		end
		if not ResidentGui.Enabled then
			ResidentGui.Enabled = true
		end
		local residentFrame = CreateResidentImageButton(residentData)
		local portraitButton = residentFrame.PortraitButton :: TextButton
		local activationConnection = portraitButton.Activated:Connect(function()
			runDebounced(string.format("Select/%s", residentData.Name), function()
				print("Selected resident:", residentData.Name)
				selectResident(residentData.Name)
			end)
		end)
		Connections[residentData.Name] = Connections[residentData.Name] or {}
		table.insert(Connections[residentData.Name], activationConnection)
	end)

	ResidentsStore.ResidentsUpdated:Connect(function(userId: number, updatedResidentData: any)
		if userId ~= Player.UserId then
			return
		end
		if type(updatedResidentData.Name) ~= "string" then
			return
		end
		local frameInfo = FrameData[updatedResidentData.Name]
		if frameInfo then
			frameInfo.UpdateResidentSnapshot(updatedResidentData)
		end
	end)

	ResidentsStore.ResidentRemoved:Connect(function(userId: number, residentName: string)
		print("Resident removed for userId:", userId, "Resident Name:", residentName)
		local residentFrame = Roster:FindFirstChild(residentName) :: Frame
		if residentFrame then
			residentFrame:Destroy()
		end
		local residentConnections = Connections[residentName]
		if residentConnections then
			for _, connection in ipairs(residentConnections) do
				connection:Disconnect()
			end
			Connections[residentName] = nil
		end
		FrameData[residentName] = nil
		if SelectedResidentName == residentName then
			deselectResident()
		end
	end)
end

function ResidentRoster.Hide(shouldDisableEnabledValue: boolean?)
	deselectResident()
	setRosterVisible(false)
	if shouldDisableEnabledValue ~= false then
		ResidentRosterEnabled.Value = false
	end
end
return ResidentRoster
