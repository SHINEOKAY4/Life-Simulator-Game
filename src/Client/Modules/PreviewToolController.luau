--!strict
-- StarterPlayerScripts/Client/Modules/PreviewToolController.luau

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local BuildPaletteUI = require(script.Parent.Parent.UserInterface.BuildPaletteUI)
local PlotBuilderUI = require(script.Parent.Parent.UserInterface.PlotBuilderUI)

local PreviewToolController = {}

local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local ToolsFolder = AssetsFolder:WaitForChild("Tools")

local PaintBucketTool = ToolsFolder:FindFirstChild("PaintBucket") :: Tool?
local HammerTool = ToolsFolder:FindFirstChild("Hammer") :: Tool?

if PaintBucketTool then
	PaintBucketTool.CanBeDropped = false
else
	warn("[PreviewToolController] Missing PaintBucket tool under Assets/Tools")
end

if HammerTool then
	HammerTool.CanBeDropped = false
else
	warn("[PreviewToolController] Missing Hammer tool under Assets/Tools")
end

local paintPreviewActive = false
local upgradePreviewActive = false
local paletteVisible = false
local currentMode: "None" | "Paint" | "Upgrade" = "None"
local headFollowEnabled = false
local backpackSuppressed = false
local previousBackpackState: boolean? = nil
local headFollowConnection: RBXScriptConnection? = nil
local humanoidRootPart: BasePart? = nil
local neckMotor: Motor6D? = nil
local neckOriginC0: CFrame? = nil
local waistMotor: Motor6D? = nil
local waistOriginC0: CFrame? = nil

local HEAD_MAX_YAW = math.rad(55)
local HEAD_MAX_PITCH = math.rad(32)
local WAIST_YAW_SHARE = 0.35
local WAIST_PITCH_SHARE = 0.2
local HEAD_LERP_ALPHA = 0.18
local DEFAULT_LOOK_DISTANCE = 96

local function getCharacter(): Model?
	return LocalPlayer.Character
end

local function getHumanoid(): Humanoid?
	local character = getCharacter()
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function equipTool(tool: Tool?)
	if not tool then
		return
	end
	local character = getCharacter()
	local humanoid = getHumanoid()
	if not character or not humanoid then
		return
	end
	if tool.Parent ~= character then
		tool.Parent = character
	end
	humanoid:EquipTool(tool)
end

local function stowTool(tool: Tool?)
	if not tool then
		return
	end
	if tool.Parent ~= ToolsFolder then
		tool.Parent = ToolsFolder
	end
end

local function updatePaintBucketState()
	if currentMode == "Upgrade" then
		stowTool(PaintBucketTool)
		return
	end
	if paletteVisible or paintPreviewActive then
		equipTool(PaintBucketTool)
		return
	end
	stowTool(PaintBucketTool)
end

local function ensureRigReferences()
	local character = getCharacter()
	if not character then
		humanoidRootPart = nil
		neckMotor = nil
		neckOriginC0 = nil
		waistMotor = nil
		waistOriginC0 = nil
		return
	end
	if not humanoidRootPart or humanoidRootPart.Parent ~= character then
		local rootCandidate = character:FindFirstChild("HumanoidRootPart")
		if rootCandidate and rootCandidate:IsA("BasePart") then
			humanoidRootPart = rootCandidate
		else
			humanoidRootPart = nil
		end
	end
	if not neckMotor or neckMotor.Parent == nil or neckMotor.Parent.Parent ~= character then
		local head = character:FindFirstChild("Head")
		local nextNeck = head and head:FindFirstChild("Neck")
		if nextNeck and nextNeck:IsA("Motor6D") then
			neckMotor = nextNeck
			neckOriginC0 = nextNeck.C0
		else
			neckMotor = nil
			neckOriginC0 = nil
		end
	end
	if not waistMotor or waistMotor.Parent == nil or waistMotor.Parent.Parent ~= character then
		local upperTorso = character:FindFirstChild("UpperTorso")
		local nextWaist = upperTorso and upperTorso:FindFirstChild("Waist")
		if nextWaist and nextWaist:IsA("Motor6D") then
			waistMotor = nextWaist
			waistOriginC0 = nextWaist.C0
		else
			waistMotor = nil
			waistOriginC0 = nil
		end
	end
end

local function restoreHeadPose()
	if neckMotor and neckOriginC0 then
		neckMotor.C0 = neckOriginC0
	end
	if waistMotor and waistOriginC0 then
		waistMotor.C0 = waistOriginC0
	end
end

local function getCursorWorldPosition(): Vector3?
	local hit = Mouse.Hit
	if typeof(hit) == "CFrame" then
		return hit.Position
	end
	local camera = Workspace.CurrentCamera
	if camera then
		return camera.CFrame.Position + camera.CFrame.LookVector * DEFAULT_LOOK_DISTANCE
	end
	return nil
end

local function updateHeadLook()
	ensureRigReferences()
	if not humanoidRootPart then
		return
	end
	local currentNeck = neckMotor
	local currentWaist = waistMotor
	if not currentNeck or not currentWaist or not neckOriginC0 or not waistOriginC0 then
		return
	end
	local headPart = currentNeck.Part1
	local targetWorld = getCursorWorldPosition()
	if not headPart or not targetWorld then
		return
	end
	local direction = targetWorld - headPart.Position
	if direction.Magnitude < 0.001 then
		return
	end
	local rootCFrame = humanoidRootPart.CFrame
	local lookAtTarget = rootCFrame.Position + direction
	local targetFrame = CFrame.lookAt(rootCFrame.Position, lookAtTarget, Vector3.yAxis)
	local delta = rootCFrame:ToObjectSpace(targetFrame)
	local pitch, yaw = delta:ToOrientation()
	pitch *= -1
	local clampedYaw = math.clamp(yaw, -HEAD_MAX_YAW, HEAD_MAX_YAW)
	local clampedPitch = math.clamp(pitch, -HEAD_MAX_PITCH, HEAD_MAX_PITCH)
	local waistYaw = clampedYaw * WAIST_YAW_SHARE
	local neckYaw = clampedYaw - waistYaw
	local waistPitch = clampedPitch * WAIST_PITCH_SHARE
	local neckPitch = clampedPitch - waistPitch
	local neckTarget = neckOriginC0 * CFrame.Angles(-neckPitch, neckYaw, 0)
	local waistTarget = waistOriginC0 * CFrame.Angles(-waistPitch, waistYaw, 0)
	currentNeck.C0 = currentNeck.C0:Lerp(neckTarget, HEAD_LERP_ALPHA)
	currentWaist.C0 = currentWaist.C0:Lerp(waistTarget, HEAD_LERP_ALPHA)
end

local function stopHeadTracking()
	if headFollowConnection then
		headFollowConnection:Disconnect()
		headFollowConnection = nil
	end
	restoreHeadPose()
end

local function startHeadTracking()
	if headFollowConnection then
		return
	end
	ensureRigReferences()
	headFollowConnection = RunService.RenderStepped:Connect(updateHeadLook)
end

local function setHeadFollowEnabled(enabled: boolean)
	if headFollowEnabled == enabled then
		return
	end
	headFollowEnabled = enabled
	if enabled then
		startHeadTracking()
	else
		stopHeadTracking()
	end
end

local function setBackpackSuppressed(shouldSuppress: boolean)
	if backpackSuppressed == shouldSuppress then
		return
	end
	backpackSuppressed = shouldSuppress
	if shouldSuppress then
		local ok, enabled = pcall(StarterGui.GetCoreGuiEnabled, StarterGui, Enum.CoreGuiType.Backpack)
		if ok then
			previousBackpackState = enabled
		else
			previousBackpackState = nil
		end
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		return
	end
	if previousBackpackState ~= nil then
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, previousBackpackState)
	end
	previousBackpackState = nil
end

local function applyMode(mode: "None" | "Paint" | "Upgrade")
	if currentMode == mode then
		return
	end
	if mode ~= "Upgrade" then
		stowTool(HammerTool)
	end

	currentMode = mode
	if mode == "Upgrade" then
		equipTool(HammerTool)
	end
	updatePaintBucketState()

	local previewActive = mode ~= "None"
	setHeadFollowEnabled(previewActive)
	setBackpackSuppressed(previewActive)
end

local function evaluateMode()
	if upgradePreviewActive then
		applyMode("Upgrade")
	elseif paintPreviewActive then
		applyMode("Paint")
	else
		applyMode("None")
	end
end

local function onCharacterAdded(character: Model)
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		local connection: RBXScriptConnection?
		connection = character.ChildAdded:Connect(function(child)
			if not child:IsA("Humanoid") then
				return
			end
			if connection then
				connection:Disconnect()
				connection = nil
			end
			ensureRigReferences()
			if headFollowEnabled then
				startHeadTracking()
			end
			task.defer(evaluateMode)
			task.defer(updatePaintBucketState)
		end)
	else
		ensureRigReferences()
		if headFollowEnabled then
			startHeadTracking()
		end
		task.defer(evaluateMode)
		task.defer(updatePaintBucketState)
	end
end

local function onCharacterRemoving()
	stowTool(PaintBucketTool)
	stowTool(HammerTool)
	stopHeadTracking()
	neckMotor = nil
	waistMotor = nil
	neckOriginC0 = nil
	waistOriginC0 = nil
	humanoidRootPart = nil
end

function PreviewToolController.Init()
	paintPreviewActive = BuildPaletteUI.IsSelectModeActive()
	upgradePreviewActive = PlotBuilderUI.IsUpgradeViewActive()
	paletteVisible = BuildPaletteUI.IsVisible()

	BuildPaletteUI.OnSelectModeChanged(function(isActive)
		paintPreviewActive = isActive
		evaluateMode()
	end)

	BuildPaletteUI.OnVisibilityChanged(function(isVisible)
		paletteVisible = isVisible
		updatePaintBucketState()
	end)

	PlotBuilderUI.OnUpgradeViewChanged(function(isActive)
		upgradePreviewActive = isActive
		evaluateMode()
	end)

	LocalPlayer.CharacterAdded:Connect(onCharacterAdded)
	LocalPlayer.CharacterRemoving:Connect(onCharacterRemoving)

	local character = LocalPlayer.Character
	if character then
		onCharacterAdded(character)
	end

	evaluateMode()
	updatePaintBucketState()
end

return PreviewToolController
