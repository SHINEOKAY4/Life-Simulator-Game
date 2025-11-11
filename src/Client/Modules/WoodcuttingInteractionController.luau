--!strict
-- StarterPlayerScripts/Client/Modules/WoodcuttingInteractionController.luau
-- Client interaction flow for chopping shared forest trees + subtle camera shake for impact weight.

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local StarterGui = game:GetService("StarterGui")

----------------------------------------------------------------------
-- World Refs
----------------------------------------------------------------------

local WorldFolder = Workspace:WaitForChild("World")
local ForestFolder = WorldFolder:WaitForChild("Forest")
local TreeFolder = ForestFolder:WaitForChild("Trees") :: Folder

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)

----------------------------------------------------------------------
-- Modules
----------------------------------------------------------------------

local WoodcuttingPackets = require(ReplicatedStorage.Network.WoodcuttingPackets)
local WoodcuttingConfig = require(ReplicatedStorage.Shared.Definitions.WoodcuttingConfig)
local MaterialDefinitions = require(ReplicatedStorage.Shared.Definitions.MaterialDefinitions)
local PromptWidgetBinder = require(script.Parent:WaitForChild("PromptWidgetBinder"))
local PlacementCelebration = require(script.Parent.PlacementCelebration)
local MovementLock = require(script.Parent.Character.MovementLock)
local CameraShakeController = require(script.Parent.Camera.CameraShakeController)
local TimedProgressHud = require(script.Parent.Parent.UserInterface.TimedProgressHud)
local WorldPickupDisplay = require(script.Parent.Parent.UserInterface.WorldPickupDisplay)

local AssetsFolder = ReplicatedStorage.Assets
local ToolsFolder = AssetsFolder.Tools :: Folder
local AxeTool = ToolsFolder:WaitForChild("Axe") :: Tool

AxeTool.CanBeDropped = false

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------

export type TreeSpec = WoodcuttingConfig.TreeSpec
export type MaterialSpec = MaterialDefinitions.MaterialSpec

export type TreeStatePayload = {
	Guid: string,
	TypeId: string,
	State: string,
	RespawnAt: number,
	Position: Vector3,
	BusyUserId: number?,
}

export type TrackedTree = {
	Model: Model,
	Prompt: ProximityPrompt,
	Spec: TreeSpec,
	Guid: string,
	State: string,
	RespawnAt: number,
	BusyUserId: number?,
	Pending: boolean,
	CreatedPrompt: boolean,

	OriginalPivot: CFrame,
	BasePivot: CFrame?,
	HalfHeight: number?,

	TreeFallen: boolean,
	HackSound: Sound?,
	HackSoundConnection: RBXScriptConnection?,
	FallTween: Tween | RBXScriptConnection | nil,
	LastFallAngles: Vector2?,

	Connections: { RBXScriptConnection },
	ExpectedChopDuration: number?,
}

----------------------------------------------------------------------
-- Config / Constants
----------------------------------------------------------------------

local randomizer = Random.new()

local HARVEST_PROMPT_NAME = "TreeChopPrompt"
local DEFAULT_MAX_DISTANCE = 8
local RESTOCK_LABEL_UPDATE_INTERVAL = 0.5

local TreeStateAttributes = WoodcuttingConfig.TreeStateAttributes
local TreeStates = WoodcuttingConfig.TreeStateEnum

local HACK_SOUND_ID = WoodcuttingConfig.HackSoundId or ""
local HACK_SOUND_VOLUME = WoodcuttingConfig.HackSoundVolume or 0.6
local TREE_FALL_SOUND_ID = WoodcuttingConfig.TreeFallSoundId or ""
local TREE_FALL_SOUND_VOLUME = WoodcuttingConfig.TreeFallSoundVolume or 0.85
local TREE_FALL_ANGLE_DEGREES = WoodcuttingConfig.TreeFallAngleDegrees or 70
local TREE_FALL_DURATION = WoodcuttingConfig.TreeFallDuration or 1.2

local DEFAULT_FALL_ANGLES = Vector2.new(math.rad(TREE_FALL_ANGLE_DEGREES), 0)

local PLAYER_CHOP_ANIMATION_ID = WoodcuttingConfig.PlayerChopAnimationId or ""
local PLAYER_CHOP_ANIMATION_FADE = WoodcuttingConfig.ChopAnimationFadeTime or 0.1

-- Material pickup billboard
local MATERIAL_DISPLAY_LOCAL_OFFSET = Vector3.new(2.8, 2.4, 0.35)
local MATERIAL_DISPLAY_SIZE = UDim2.fromOffset(188, 66)
local MATERIAL_ICON_SIZE = UDim2.fromOffset(46, 46)
local MATERIAL_DISPLAY_DURATION = 2.6
local MATERIAL_DISPLAY_MAX_DISTANCE = 90
local MATERIAL_MESSAGE_COLOR = Color3.fromRGB(168, 233, 143)
local DEFAULT_REWARD_ICON = MaterialDefinitions.DefaultIconImage or "rbxassetid://134727745079555"

-- ProximityPrompt placement
local TREE_PROMPT_ATTACHMENT_NAME = "WoodcuttingPromptAttachment"
local TREE_PROMPT_ATTACHMENT_DEFAULT_OFFSET_Y = -8
local TREE_PROMPT_BOTTOM_MARGIN = 1.25
local TREE_PROMPT_FROM_TOP_OFFSET = 8
local TREE_PROMPT_TOP_FRACTION = 0.45 -- taller trees push the prompt farther from the canopy

-- Chop progress UI
local CHOP_PROGRESS_GUI_NAME = "WoodcuttingChopProgress"
local CHOP_PROGRESS_FILL_COLOR = Color3.fromRGB(130, 214, 154)
local CHOP_PROGRESS_BAR_COLOR = Color3.fromRGB(40, 53, 69)
local CHOP_PROGRESS_TEXT_COLOR = Color3.fromRGB(238, 244, 255)
local CHOP_PROGRESS_ICON_ASSET = "rbxassetid://122965005057325"
local CHOP_PROGRESS_ICON_SIZE = UDim2.fromOffset(40, 40)
local DEFAULT_CHOP_DURATION = 3.5

-- Camera shake (tuned for subtle, weighty feel; uses Humanoid.CameraOffset so it works first/third person)
local CAMERA_SHAKE_MAX_OFFSET = Vector3.new(1, 1, 1)
local CAMERA_SHAKE_FREQUENCY = 13.0
local CAMERA_SHAKE_DECAY_PER_SECOND = 3.0
local TREE_FALL_SHAKE_STRENGTH = 1.0 -- peak strength applied on ground impact
local TREE_FALL_SHAKE_MAX_DISTANCE = 70 -- studs; fall shake scales down with distance

local WoodcuttingInteractionController = {}

local movementLock = MovementLock.new(LocalPlayer)
local cameraShake = CameraShakeController.new({
	Player = LocalPlayer,
	MaxOffset = CAMERA_SHAKE_MAX_OFFSET,
	Frequency = CAMERA_SHAKE_FREQUENCY,
	DecayPerSecond = CAMERA_SHAKE_DECAY_PER_SECOND,
	MaxMagnitude = 2.0,
})
local progressHud = TimedProgressHud.new({
	PlayerGui = PlayerGui,
	GuiName = CHOP_PROGRESS_GUI_NAME,
	IconAsset = CHOP_PROGRESS_ICON_ASSET,
	IconSize = CHOP_PROGRESS_ICON_SIZE,
	FillColor = CHOP_PROGRESS_FILL_COLOR,
	BarColor = CHOP_PROGRESS_BAR_COLOR,
	TextColor = CHOP_PROGRESS_TEXT_COLOR,
})
local pickupDisplay = WorldPickupDisplay.new({
	DisplayDuration = MATERIAL_DISPLAY_DURATION,
	MaxDistance = MATERIAL_DISPLAY_MAX_DISTANCE,
	GuiSize = MATERIAL_DISPLAY_SIZE,
	IconSize = MATERIAL_ICON_SIZE,
	DefaultIcon = DEFAULT_REWARD_ICON,
})

local FALLBACK_MATERIAL_SPEC: MaterialSpec = MaterialDefinitions.Get("Wood")
	or { Id = "Wood" :: any, Name = "Wood", IconImage = DEFAULT_REWARD_ICON }

-- Trees
local trackedByModel: { [Model]: TrackedTree } = {}
local trackedByPrompt: { [ProximityPrompt]: TrackedTree } = {}
local trackedByGuid: { [string]: TrackedTree } = {}
local originalPivotsByGuid: { [string]: CFrame } = {}
local pendingGuidWait: { [Model]: RBXScriptConnection } = {}
local knownStates: { [string]: TreeStatePayload } = {}

local restockAccumulator = 0
local currentLocalTreeGuid: string? = nil

-- Animation
local cachedChopTrack: AnimationTrack? = nil
local cachedChopAnimation: Animation? = nil
local chopAnimationStoppedConnection: RBXScriptConnection? = nil

----------------------------------------------------------------------
-- Camera Shake (local-only helper)
----------------------------------------------------------------------
local function applyTreeFallShake(worldPosition: Vector3)
	cameraShake:ImpulseAtPosition(worldPosition, TREE_FALL_SHAKE_STRENGTH, TREE_FALL_SHAKE_MAX_DISTANCE)
end

local function resetCameraShake()
	cameraShake:Reset()
end

local AxeToolHomeParent: Instance = ToolsFolder

----------------------------------------------------------------------
-- Tool Equip Helpers
----------------------------------------------------------------------

local function equipAxeToolForLocalPlayer()
	local character = LocalPlayer.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if AxeTool.Parent ~= character then
		AxeTool.Parent = character
	end

	humanoid:EquipTool(AxeTool)
end

local function returnAxeToolHome()
	if AxeTool.Parent ~= AxeToolHomeParent then
		AxeTool.Parent = AxeToolHomeParent
	end
end

local function disconnectChopAnimationSignals(): ()
	if chopAnimationStoppedConnection then
		chopAnimationStoppedConnection:Disconnect()
		chopAnimationStoppedConnection = nil
	end
end

local function attachChopAnimationSignals(track: AnimationTrack): ()
	disconnectChopAnimationSignals()
	chopAnimationStoppedConnection = track.Stopped:Connect(function()
		disconnectChopAnimationSignals()
	end)
end

----------------------------------------------------------------------
-- Util
----------------------------------------------------------------------

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function timeAsText(seconds: number): string
	local clampedSeconds = math.max(0, math.ceil(seconds))
	local minutes = math.floor(clampedSeconds / 60)
	local remainingSeconds = clampedSeconds % 60
	if minutes > 0 then
		return remainingSeconds > 0 and string.format("%dm %02ds", minutes, remainingSeconds)
			or string.format("%dm", minutes)
	end
	return string.format("%ds", remainingSeconds)
end

local function buildRestockText(remaining: number): string
	return remaining <= 1 and "Regrowing" or string.format("Regrowing (%s)", timeAsText(remaining))
end

local function isLocalPlayerUserId(userId: number?): boolean
	if userId == nil then
		return false
	end
	if userId == LocalPlayer.UserId then
		return true
	end
	return userId == 0 and LocalPlayer.UserId == 0
end

local function normalizeBusyUserId(rawUserId: number?, nextState: string): number?
	local value = (typeof(rawUserId) == "number") and (rawUserId :: number) or 0
	if value ~= 0 then
		return value
	end
	if nextState == TreeStates.Busy and LocalPlayer.UserId == 0 then
		return 0
	end
	return nil
end

-- Clear out any stale hack loop connections; per-chop camera shake is disabled.
local function updateHackSoundShake(record: TrackedTree): ()
	if record.HackSoundConnection then
		record.HackSoundConnection:Disconnect()
		record.HackSoundConnection = nil
	end
end

local function connect(record: TrackedTree, signal: RBXScriptSignal, handler: (...any) -> ()): ()
	record.Connections[#record.Connections + 1] = signal:Connect(handler)
end

local function disconnectAll(record: TrackedTree): ()
	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end
	table.clear(record.Connections)
end

local function setPromptText(prompt: ProximityPrompt, text: string): ()
	if prompt.ActionText ~= text then
		prompt.ActionText = text
		PromptWidgetBinder.Refresh(prompt)
	end
end

local function resolvePromptBasePart(prompt: ProximityPrompt): BasePart?
	local parent = prompt.Parent
	if not parent then
		return nil
	end
	if parent:IsA("BasePart") then
		return parent
	end
	if parent:IsA("Attachment") then
		local attachmentParent = parent.Parent
		if attachmentParent and attachmentParent:IsA("BasePart") then
			return attachmentParent
		end
	end
	return nil
end

local function getTreeWorldPosition(record: TrackedTree): Vector3?
	local basePart = resolvePromptBasePart(record.Prompt)
	if basePart then
		return basePart.Position
	end
	local ok, pivot = pcall(record.Model.GetPivot, record.Model)
	if ok then
		return pivot.Position
	end
	return nil
end

local function showWorldMessage(record: TrackedTree, message: string, color: Color3): ()
	PlacementCelebration.ShowMessage(getTreeWorldPosition(record), message, color)
end

local function safePivotTo(model: Model, pivot: CFrame): ()
	if model.Parent then
		model:PivotTo(pivot)
	end
end

----------------------------------------------------------------------
-- Specs / Materials
----------------------------------------------------------------------

local function resolveTreeSpec(model: Model): TreeSpec?
	local typeId = model:GetAttribute(TreeStateAttributes.TypeId)
	if typeof(typeId) == "string" and typeId ~= "" then
		local fromAttribute = WoodcuttingConfig.TreeTypes[typeId]
		if fromAttribute then
			return fromAttribute
		end
	end

	local byName = WoodcuttingConfig.TreeTypes[model.Name]
	if byName then
		return byName
	end

	for _, candidate in pairs(WoodcuttingConfig.TreeTypes) do
		if candidate.ModelName and candidate.ModelName == model.Name then
			return candidate
		end
	end
	return nil
end

local function resolveMaterialSpecFromItem(inventoryDefinitionId: string): MaterialSpec
	local inventoryDefinition = WoodcuttingConfig.InventoryDefinitions[inventoryDefinitionId]
	if inventoryDefinition then
		local metadata = inventoryDefinition.metadata
		if metadata then
			local materialId = metadata.MaterialId
			if typeof(materialId) == "string" then
				local spec = MaterialDefinitions.Get(materialId)
				if spec then
					return spec
				end
			end
		end
	end
	return FALLBACK_MATERIAL_SPEC
end

local function resolveChopTitle(treeName: string): string
	return string.format("Chopping %s", (treeName ~= "" and treeName) or "Tree")
end

local function showChopProgress(durationSeconds: number?, treeName: string)
	local duration = (durationSeconds and durationSeconds > 0) and durationSeconds or DEFAULT_CHOP_DURATION
	progressHud:Show(duration, resolveChopTitle(treeName))
end

local function hideChopProgress()
	progressHud:Hide()
end

----------------------------------------------------------------------
-- Character Lock & Animation (fixed: always unlock after fall)
----------------------------------------------------------------------

local function resolveTreeFacePosition(record: TrackedTree): Vector3?
	local base = resolvePromptBasePart(record.Prompt)
	if base then
		return base.Position
	end

	local primary = record.Model.PrimaryPart
	if primary then
		return primary.Position
	end

	local ok, pivot = pcall(record.Model.GetPivot, record.Model)
	if ok then
		return pivot.Position
	end

	return nil
end

local function lockCharacter(record: TrackedTree)
	movementLock:Acquire(record.Guid, {
		FacePosition = resolveTreeFacePosition(record),
	})
end

local function unlockCharacter(recordGuid: string?)
	movementLock:Release(recordGuid)
end

local function ensureChopAnimationTrack(): AnimationTrack?
	if PLAYER_CHOP_ANIMATION_ID == "" then
		return nil
	end

	local character = LocalPlayer.Character
	if not character then
		return nil
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return nil
	end

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid

	if cachedChopTrack and cachedChopTrack.Parent == animator then
		return cachedChopTrack
	end

	disconnectChopAnimationSignals()

	local animationObject: Animation = cachedChopAnimation or Instance.new("Animation")
	animationObject.Name = "_WoodcuttingChopAnimation"
	animationObject.AnimationId = PLAYER_CHOP_ANIMATION_ID
	cachedChopAnimation = animationObject

	local ok, trackResult = pcall(function()
		return animator:LoadAnimation(animationObject)
	end)
	if not ok or not trackResult then
		warn("WoodcuttingInteractionController: failed to load chop animation", trackResult)
		cachedChopTrack = nil
		return nil
	end

	local animationTrack = trackResult :: AnimationTrack
	animationTrack.Priority = Enum.AnimationPriority.Action
	animationTrack.Looped = true
	cachedChopTrack = animationTrack
	return animationTrack
end

local function playChopAnimation(): ()
	local animationTrack = ensureChopAnimationTrack()
	if not animationTrack then
		return
	end

	attachChopAnimationSignals(animationTrack)
	if not animationTrack.IsPlaying then
		animationTrack:Play(PLAYER_CHOP_ANIMATION_FADE)
	end
end

local function stopChopAnimation(): ()
	if cachedChopTrack and cachedChopTrack.IsPlaying then
		cachedChopTrack:Stop(PLAYER_CHOP_ANIMATION_FADE)
	end
	disconnectChopAnimationSignals()
	returnAxeToolHome()
end

LocalPlayer.CharacterAdded:Connect(function()
	if cachedChopTrack and cachedChopTrack.IsPlaying then
		cachedChopTrack:Stop(0)
	end
	cachedChopTrack = nil
	cachedChopAnimation = nil
	disconnectChopAnimationSignals()
	currentLocalTreeGuid = nil
	hideChopProgress()
	unlockCharacter(nil)
	movementLock:Reset()
	returnAxeToolHome()
	resetCameraShake()
end)

LocalPlayer.CharacterRemoving:Connect(function()
	if cachedChopTrack and cachedChopTrack.IsPlaying then
		cachedChopTrack:Stop(0)
	end
	cachedChopTrack = nil
	cachedChopAnimation = nil
	disconnectChopAnimationSignals()
	currentLocalTreeGuid = nil
	hideChopProgress()
	unlockCharacter(nil)
	movementLock:Reset()
	returnAxeToolHome()
	resetCameraShake()
end)

----------------------------------------------------------------------
-- Audio
----------------------------------------------------------------------

local function playHackLoop(record: TrackedTree): ()
	if HACK_SOUND_ID == "" then
		return
	end

	local parent = resolvePromptBasePart(record.Prompt)
	if not parent then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "_WoodcuttingHackLoop"
	sound.SoundId = HACK_SOUND_ID
	sound.Volume = (isLocalPlayerUserId(record.BusyUserId) and HACK_SOUND_VOLUME)
		or math.max(0, HACK_SOUND_VOLUME * 0.55)
	sound.RollOffMaxDistance = 55
	sound.RollOffMinDistance = 5
	sound.Looped = true
	sound.Parent = parent
	sound:Play()
	record.HackSound = sound

	updateHackSoundShake(record)
end

local function stopHackLoop(record: TrackedTree): ()
	if record.HackSoundConnection then
		record.HackSoundConnection:Disconnect()
		record.HackSoundConnection = nil
	end
	local sound = record.HackSound
	if sound then
		sound:Stop()
		sound:Destroy()
		record.HackSound = nil
	end
end

----------------------------------------------------------------------
-- Tree Pose / Shake / Fall
----------------------------------------------------------------------

local function ensureBasePivot(record: TrackedTree): (CFrame?, number)
	if record.BasePivot and record.HalfHeight and record.HalfHeight > 0 then
		return record.BasePivot, record.HalfHeight
	end

	local ok, _pivot, size = pcall(record.Model.GetBoundingBox, record.Model)
	if not ok or not size then
		record.BasePivot = nil
		record.HalfHeight = nil
		return nil, 0
	end

	local halfHeight = math.max(size.Y * 0.5, 0)
	record.HalfHeight = halfHeight
	if halfHeight <= 0 then
		record.BasePivot = nil
		return nil, 0
	end

	local basePivot = record.OriginalPivot * CFrame.new(0, -halfHeight, 0)
	record.BasePivot = basePivot
	return basePivot, halfHeight
end

local function computeTiltedPivot(record: TrackedTree, xAngle: number, zAngle: number): CFrame
	local basePivot, halfHeight = ensureBasePivot(record)
	if not basePivot or halfHeight <= 0 then
		return record.OriginalPivot * CFrame.Angles(xAngle, 0, zAngle)
	end
	return basePivot * CFrame.Angles(xAngle, 0, zAngle) * CFrame.new(0, halfHeight, 0)
end

local function applyTilt(record: TrackedTree, xAngle: number, zAngle: number): ()
	if not record.Model.Parent then
		return
	end
	safePivotTo(record.Model, computeTiltedPivot(record, xAngle, zAngle))
end

local function applyStoredFallPose(record: TrackedTree): ()
	if not record.LastFallAngles then
		return
	end
	applyTilt(record, record.LastFallAngles.X, record.LastFallAngles.Y)
end

local function stopChopCameraShake(record: TrackedTree): ()
	disconnectChopAnimationSignals()
	if record.HackSoundConnection then
		record.HackSoundConnection:Disconnect()
		record.HackSoundConnection = nil
	end
end

local function startChopCameraShake(record: TrackedTree): ()
	updateHackSoundShake(record)
end

local function cancelFallTween(record: TrackedTree): ()
	local current = record.FallTween
	if not current then
		return
	end

	if typeof(current) == "RBXScriptConnection" then
		local connection = current :: RBXScriptConnection
		if connection.Connected then
			connection:Disconnect()
		end
	elseif typeof(current) == "Instance" and (current :: Instance):IsA("Tween") then
		(current :: Tween):Cancel()
	end
	record.FallTween = nil
end

local function playTreeFall(record: TrackedTree): ()
	if record.TreeFallen then
		return
	end

	stopChopCameraShake(record)
	record.TreeFallen = true

	local parent = resolvePromptBasePart(record.Prompt)
	if TREE_FALL_SOUND_ID ~= "" and parent then
		local fallSound = Instance.new("Sound")
		fallSound.Name = "_WoodcuttingTreeFall"
		fallSound.SoundId = TREE_FALL_SOUND_ID
		fallSound.Volume = TREE_FALL_SOUND_VOLUME
		fallSound.RollOffMaxDistance = 100
		fallSound.RollOffMinDistance = 10
		fallSound.Parent = parent
		fallSound:Play()
		task.spawn(function()
			fallSound.Ended:Wait()
			fallSound:Destroy()
		end)
	end

	cancelFallTween(record)

	local radians = math.rad(TREE_FALL_ANGLE_DEGREES)
	local directionAngle = randomizer:NextNumber(0, math.pi * 2)
	local direction = Vector3.new(math.cos(directionAngle), 0, math.sin(directionAngle))
	if direction.Magnitude < 0.001 then
		direction = Vector3.new(0, 0, 1)
	end
	direction = direction.Unit

	local xAngle = direction.Z * radians
	local zAngle = -direction.X * radians
	record.LastFallAngles = Vector2.new(xAngle, zAngle)
	local targetPivot = computeTiltedPivot(record, xAngle, zAngle)

	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Value = record.Model:GetPivot()

	local connection: RBXScriptConnection?
	connection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
		if record.Model.Parent then
			record.Model:PivotTo(pivotValue.Value)
		else
			if connection then
				connection:Disconnect()
			end
			pivotValue:Destroy()
		end
	end)

	local tween = TweenService:Create(
		pivotValue,
		TweenInfo.new(TREE_FALL_DURATION, Enum.EasingStyle.Cubic, Enum.EasingDirection.In),
		{ Value = targetPivot }
	)

	tween.Completed:Connect(function()
		if connection then
			connection:Disconnect()
		end
		pivotValue:Destroy()
		record.FallTween = nil

		-- Heavy camera shake on ground impact for nearby players.
		local worldPosition = getTreeWorldPosition(record)
		if worldPosition then
			applyTreeFallShake(worldPosition)
		end

		-- Guarantee player regains control even if a network event drops.
		if currentLocalTreeGuid == record.Guid then
			currentLocalTreeGuid = nil
			hideChopProgress()
			unlockCharacter(record.Guid)
			stopChopAnimation()
		end
	end)

	record.FallTween = tween
	tween:Play()
end

local function restoreTree(record: TrackedTree): ()
	cancelFallTween(record)
	record.TreeFallen = false
	record.LastFallAngles = nil
	record.BasePivot = nil
	record.HalfHeight = nil
	if record.Model.Parent then
		record.Model:PivotTo(record.OriginalPivot)
	end
end

----------------------------------------------------------------------
-- Material Pickup Billboard
----------------------------------------------------------------------

local function showMaterialPickup(
	materialSpec: MaterialSpec,
	quantity: number,
	targetPart: BasePart?,
	studsOffset: Vector3
): number
	return pickupDisplay:Show({
		Id = tostring(materialSpec.Id),
		Name = materialSpec.Name,
		IconImage = materialSpec.IconImage,
	}, quantity, targetPart, studsOffset)
end

----------------------------------------------------------------------
-- Prompt Helpers
----------------------------------------------------------------------

local function ensurePromptAttachment(interactPart: BasePart, prompt: ProximityPrompt): Attachment
	local desiredCFrame = CFrame.new(0, TREE_PROMPT_ATTACHMENT_DEFAULT_OFFSET_Y, 0)

	local currentParent = prompt.Parent
	if currentParent and currentParent:IsA("Attachment") then
		if currentParent.Parent ~= interactPart then
			currentParent.Parent = interactPart
		end
		if currentParent.CFrame ~= desiredCFrame then
			currentParent.CFrame = desiredCFrame
		end
		return currentParent
	end

	local existing = interactPart:FindFirstChild(TREE_PROMPT_ATTACHMENT_NAME)
	if existing and existing:IsA("Attachment") then
		if existing.Parent ~= interactPart then
			existing.Parent = interactPart
		end
		if existing.CFrame ~= desiredCFrame then
			existing.CFrame = desiredCFrame
		end
		return existing
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = TREE_PROMPT_ATTACHMENT_NAME
	attachment.CFrame = desiredCFrame
	attachment.Parent = interactPart
	return attachment
end

local function updatePromptAttachmentAlignment(record: TrackedTree): ()
	local prompt = record.Prompt
	local interactPart = resolvePromptBasePart(prompt)
	if not interactPart then
		return
	end

	local attachmentParent = prompt.Parent
	local attachment: Attachment

	if attachmentParent and attachmentParent:IsA("Attachment") then
		attachment = attachmentParent
		if attachment.Parent ~= interactPart then
			attachment.Parent = interactPart
		end
	else
		attachment = ensurePromptAttachment(interactPart, prompt)
	end

	if prompt.Parent ~= attachment then
		prompt.Parent = attachment
	end

	local basePivot, halfHeight = ensureBasePivot(record)
	if not basePivot or halfHeight <= 0 then
		attachment.CFrame = CFrame.new(0, TREE_PROMPT_ATTACHMENT_DEFAULT_OFFSET_Y, 0)
		return
	end

	local minimumAllowed = math.min(TREE_PROMPT_BOTTOM_MARGIN, halfHeight)
	local adaptiveTopOffset = math.max(TREE_PROMPT_FROM_TOP_OFFSET, halfHeight * TREE_PROMPT_TOP_FRACTION)
	local desiredHeightFromBase = math.clamp(halfHeight - adaptiveTopOffset, minimumAllowed, halfHeight)

	local targetWorldPosition = (basePivot * CFrame.new(0, desiredHeightFromBase, 0)).Position
	local localOffset = interactPart.CFrame:PointToObjectSpace(targetWorldPosition)

	attachment.Position = localOffset
end

local function updatePrompt(record: TrackedTree): ()
	local prompt = record.Prompt
	if record.Pending then
		prompt.Enabled = false
		PromptWidgetBinder.SetSuppressed(prompt, true)
		setPromptText(prompt, "Chopping...")
		return
	end

	PromptWidgetBinder.SetSuppressed(prompt, false)

	if record.State == TreeStates.Ready then
		prompt.Enabled = true
		setPromptText(prompt, "Chop " .. record.Spec.Name)
		return
	end

	prompt.Enabled = false

	if record.State == TreeStates.Busy then
		setPromptText(prompt, (isLocalPlayerUserId(record.BusyUserId) and "Chopping...") or "In use")
		return
	end

	setPromptText(prompt, buildRestockText(math.max(0, record.RespawnAt - serverNow())))
end

----------------------------------------------------------------------
-- State Application
----------------------------------------------------------------------

-- FIX: Set currentLocalTreeGuid BEFORE starting the hack loop so updateHackSoundShake
-- binds on the first call (prevents "local player not chopping" race).
local function startChopEffects(record: TrackedTree): ()
	record.TreeFallen = false
	record.LastFallAngles = nil

	-- Determine whether this client should own the local chop experience,
	-- and stamp the guid BEFORE starting audio binding.
	local localPlayerBusy = isLocalPlayerUserId(record.BusyUserId) or currentLocalTreeGuid == record.Guid
	if localPlayerBusy then
		currentLocalTreeGuid = record.Guid
	end

	stopHackLoop(record)
	stopChopCameraShake(record)
	playHackLoop(record)
	startChopCameraShake(record)

	-- Ensure UI shows reliably for local player:
	if localPlayerBusy then
		lockCharacter(record)
		equipAxeToolForLocalPlayer()
		showChopProgress(record.ExpectedChopDuration, record.Spec.Name)
		playChopAnimation()
		record.ExpectedChopDuration = nil
	end
end

local function stopChopEffects(record: TrackedTree, previousBusyUserId: number?): ()
	stopHackLoop(record)
	stopChopCameraShake(record)

	if isLocalPlayerUserId(previousBusyUserId) or currentLocalTreeGuid == record.Guid then
		currentLocalTreeGuid = nil
		returnAxeToolHome()
		hideChopProgress()
		unlockCharacter(record.Guid)
		stopChopAnimation()
	end

	record.ExpectedChopDuration = nil
end

local function applyState(record: TrackedTree, payload: TreeStatePayload): ()
	local previousState = record.State
	local previousBusyUserId = record.BusyUserId

	record.State = payload.State
	record.RespawnAt = payload.RespawnAt
	record.BusyUserId = normalizeBusyUserId(payload.BusyUserId, record.State)

	if record.State == TreeStates.Busy then
		if previousState ~= TreeStates.Busy then
			startChopEffects(record)
		end
	elseif previousState == TreeStates.Busy then
		stopChopEffects(record, previousBusyUserId)
		if record.State == TreeStates.Regrowing then
			playTreeFall(record) -- unlock is guaranteed in tween.Completed fallback
		end
	end

	if record.State == TreeStates.Ready then
		restoreTree(record)
	elseif record.State == TreeStates.Regrowing and previousState ~= TreeStates.Regrowing then
		if previousState ~= TreeStates.Busy then
			cancelFallTween(record)
			record.TreeFallen = true
			record.LastFallAngles = record.LastFallAngles or DEFAULT_FALL_ANGLES
			ensureBasePivot(record)
			applyStoredFallPose(record)
		end
	end

	updatePrompt(record)
end

----------------------------------------------------------------------
-- Network
----------------------------------------------------------------------

local function onStateChanged(payload: TreeStatePayload): ()
	if payload.Guid == "" then
		return
	end
	knownStates[payload.Guid] = payload
	local record = trackedByGuid[payload.Guid]
	if record then
		applyState(record, payload)
	end
end

local function notifyFailure(record: TrackedTree, reason: string): ()
	if reason == "Tree already in use" then
		showWorldMessage(record, "Someone else is chopping", Color3.fromRGB(180, 210, 255))
		return
	end

	if reason == "Tree is regrowing" then
		local remaining = math.max(0, record.RespawnAt - serverNow())
		local text = (remaining > 1) and string.format("%s ready in %s", record.Spec.Name, timeAsText(remaining))
			or string.format("%s is regrowing", record.Spec.Name)
		showWorldMessage(record, text, Color3.fromRGB(255, 226, 124))
		return
	end

	showWorldMessage(record, "Unable to chop right now", Color3.fromRGB(255, 118, 118))
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player): ()
	if player ~= LocalPlayer then
		return
	end

	local record = trackedByPrompt[prompt]
	if not record or record.Pending then
		return
	end

	if record.State ~= TreeStates.Ready then
		notifyFailure(record, (record.State == TreeStates.Busy) and "Tree already in use" or "Tree is regrowing")
		updatePrompt(record)
		return
	end

	record.Pending = true
	updatePrompt(record)

	task.defer(function()
		local ok, successFlag, message, duration = pcall(function()
			return WoodcuttingPackets.TreeChopRequest:Fire(record.Guid)
		end)

		record.Pending = false

		if not ok then
			warn("Tree chop request failed", successFlag)
			notifyFailure(record, "Unable to chop right now")
			updatePrompt(record)
			return
		end

		if not successFlag then
			record.ExpectedChopDuration = nil
			notifyFailure(record, message)
		else
			record.ExpectedChopDuration = duration
			currentLocalTreeGuid = record.Guid
			lockCharacter(record)
			equipAxeToolForLocalPlayer()
			showChopProgress(record.ExpectedChopDuration, record.Spec.Name)
			playChopAnimation()
		end

		updatePrompt(record)
	end)
end

local function onYieldNotice(payload: { Guid: string, ItemDefId: string, Quantity: number }): ()
	local record = trackedByGuid[payload.Guid]
	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	local targetPart: BasePart? = nil
	local studsOffset = MATERIAL_DISPLAY_LOCAL_OFFSET

	if rootPart and rootPart:IsA("BasePart") then
		targetPart = rootPart
		studsOffset = rootPart.CFrame:VectorToWorldSpace(MATERIAL_DISPLAY_LOCAL_OFFSET)
	end

	if not targetPart and record then
		targetPart = resolvePromptBasePart(record.Prompt)
	end

	local materialSpec = resolveMaterialSpecFromItem(payload.ItemDefId)
	local inventoryDefinition = WoodcuttingConfig.InventoryDefinitions[payload.ItemDefId]
	local displayName: string? = nil
	if inventoryDefinition and inventoryDefinition.metadata then
		local metadata = inventoryDefinition.metadata
		local label = metadata.DisplayName
		if typeof(label) == "string" then
			displayName = label
		end
	end
	local fallbackName = displayName or materialSpec.Name

	if targetPart then
		showMaterialPickup(materialSpec, payload.Quantity, targetPart, studsOffset)
		return
	end

	local position: Vector3? = record and getTreeWorldPosition(record)
		or (rootPart and rootPart:IsA("BasePart") and rootPart.Position or nil)
	PlacementCelebration.ShowMessage(
		position,
		string.format("+%d %s", payload.Quantity, fallbackName),
		MATERIAL_MESSAGE_COLOR
	)
end

----------------------------------------------------------------------
-- Model Registration / Cleanup
----------------------------------------------------------------------

local function clearGuidWait(model: Model): ()
	local connection = pendingGuidWait[model]
	if connection then
		connection:Disconnect()
		pendingGuidWait[model] = nil
	end
end

local function findInteractPart(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function cleanupModel(model: Model): ()
	clearGuidWait(model)

	local record = trackedByModel[model]
	if not record then
		return
	end

	stopChopEffects(record, record.BusyUserId)
	cancelFallTween(record)

	trackedByModel[model] = nil
	trackedByGuid[record.Guid] = nil
	trackedByPrompt[record.Prompt] = nil

	disconnectAll(record)

	PromptWidgetBinder.Detach(record.Prompt)
	if record.CreatedPrompt then
		record.Prompt:Destroy()
	elseif record.Prompt.Parent then
		record.Prompt.Enabled = true
	end
end

local function registerModel(model: Model): ()
	if trackedByModel[model] then
		return
	end

	local spec = resolveTreeSpec(model)
	if not spec then
		return
	end

	local guidAttribute = model:GetAttribute(TreeStateAttributes.Guid)
	if typeof(guidAttribute) ~= "string" or guidAttribute == "" then
		if not pendingGuidWait[model] then
			pendingGuidWait[model] = model:GetAttributeChangedSignal(TreeStateAttributes.Guid):Connect(function()
				clearGuidWait(model)
				registerModel(model)
			end)
		end
		return
	end

	local interactPart = findInteractPart(model)
	if not interactPart then
		return
	end

	local existingPrompt = interactPart:FindFirstChild(HARVEST_PROMPT_NAME)
	local prompt: ProximityPrompt
	local createdPrompt = false

	if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
		prompt = existingPrompt
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = HARVEST_PROMPT_NAME
		createdPrompt = true
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.ObjectText = spec.Name
		prompt.ActionText = "Chop " .. spec.Name
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = DEFAULT_MAX_DISTANCE
		prompt.MaxIndicatorDistance = 40
		prompt.Parent = interactPart
	end

	prompt.Style = Enum.ProximityPromptStyle.Custom
	if prompt.Parent ~= interactPart then
		prompt.Parent = interactPart
	end

	-- reset any legacy widget offset attributes so UI is not suppressed
	if prompt:GetAttribute("WidgetOffset") ~= nil then
		prompt:SetAttribute("WidgetOffset", nil)
	end
	prompt:SetAttribute("WidgetOffsetY", 0)

	local attachment = ensurePromptAttachment(interactPart, prompt)
	if prompt.Parent ~= attachment then
		prompt.Parent = attachment
	end

	local originalPivot = originalPivotsByGuid[guidAttribute]
	if not originalPivot then
		local ok, pivot = pcall(model.GetPivot, model)
		if ok then
			originalPivot = pivot
		else
			local okBounds, boundsCFrame, _boundsSize = pcall(function(): (CFrame, Vector3)
				return model:GetBoundingBox()
			end)
			originalPivot = (okBounds and boundsCFrame) or CFrame.identity
		end
		originalPivotsByGuid[guidAttribute] = originalPivot
	end

	local record: TrackedTree = {
		Model = model,
		Prompt = prompt,
		Spec = spec,
		Guid = guidAttribute,
		State = TreeStates.Ready,
		RespawnAt = 0,
		BusyUserId = nil,
		Pending = false,
		CreatedPrompt = createdPrompt,

		OriginalPivot = originalPivot,
		BasePivot = nil,
		HalfHeight = nil,

		TreeFallen = false,
		HackSound = nil,
		HackSoundConnection = nil,
		FallTween = nil,
		LastFallAngles = nil,

		Connections = {},
		ExpectedChopDuration = nil,
	}

	connect(record, prompt.Triggered, function(player)
		onPromptTriggered(prompt, player)
	end)
	connect(record, model.Destroying, function()
		cleanupModel(model)
	end)
	connect(record, model.AncestryChanged, function(_, parent)
		if not parent then
			cleanupModel(model)
		end
	end)
	connect(record, model:GetAttributeChangedSignal(TreeStateAttributes.TypeId), function()
		local updatedSpec = resolveTreeSpec(model)
		if updatedSpec then
			record.Spec = updatedSpec
		end
		record.BasePivot = nil
		record.HalfHeight = nil
		updatePromptAttachmentAlignment(record)
		updatePrompt(record)
	end)

	PromptWidgetBinder.Attach(prompt)

	trackedByModel[model] = record
	trackedByPrompt[prompt] = record
	trackedByGuid[record.Guid] = record

	ensureBasePivot(record)
	updatePromptAttachmentAlignment(record)

	local known = knownStates[record.Guid]
	if known then
		applyState(record, known)
	else
		local stateAttribute = model:GetAttribute(TreeStateAttributes.State)
		if typeof(stateAttribute) == "string" then
			record.State = stateAttribute
		end

		local respawnAttribute = model:GetAttribute(TreeStateAttributes.RespawnAt)
		if typeof(respawnAttribute) == "number" then
			record.RespawnAt = respawnAttribute
		end

		updatePrompt(record)
	end
end

local function bindTreeFolder(folder: Instance): ()
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			registerModel(child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			registerModel(child)
		end
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			cleanupModel(child)
		end
	end)
end

----------------------------------------------------------------------
-- Snapshot
----------------------------------------------------------------------

local function hydrateSnapshot(): ()
	local ok, response = pcall(function()
		return WoodcuttingPackets.RequestForestSnapshot:Fire()
	end)
	if not ok or not response then
		warn("WoodcuttingInteractionController: failed to request forest snapshot", response)
		return
	end

	local trees = (response.Trees :: any) or {}
	for _, payload in ipairs(trees) do
		knownStates[payload.Guid] = payload
		local record = trackedByGuid[payload.Guid]
		if record then
			applyState(record, payload)
		end
	end
end

----------------------------------------------------------------------
-- Heartbeat (restock label refresh)
----------------------------------------------------------------------

RunService.Heartbeat:Connect(function(deltaTime)
	restockAccumulator += deltaTime
	if restockAccumulator < RESTOCK_LABEL_UPDATE_INTERVAL then
		return
	end
	restockAccumulator = 0

	local now = serverNow()
	for _, record in pairs(trackedByGuid) do
		if record.State == TreeStates.Regrowing and not record.Pending then
			if record.Prompt.Parent then
				setPromptText(record.Prompt, buildRestockText(math.max(0, record.RespawnAt - now)))
			end
		end
	end
end)

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function WoodcuttingInteractionController.Init()
	WoodcuttingPackets.TreeStateChanged.OnClientEvent:Connect(onStateChanged)
	WoodcuttingPackets.TreeYieldNotice.OnClientEvent:Connect(onYieldNotice)

	hydrateSnapshot()
	bindTreeFolder(TreeFolder)
end

return WoodcuttingInteractionController
