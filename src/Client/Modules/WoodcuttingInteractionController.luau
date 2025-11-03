--!strict
-- StarterPlayerScripts/Client/Modules/WoodcuttingInteractionController.luau
-- Handles client-side interaction flow for chopping shared forest trees.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local WorldFolder = Workspace:WaitForChild("World")
local ForestFolder = WorldFolder:WaitForChild("Forest")
local TreeFolder = ForestFolder:WaitForChild("Trees") :: Folder

local LocalPlayer = Players.LocalPlayer

local WoodcuttingPackets = require(ReplicatedStorage.Network.WoodcuttingPackets)
local WoodcuttingConfig = require(ReplicatedStorage.Shared.Definitions.WoodcuttingConfig)
local PromptWidgetBinder = require(script.Parent:WaitForChild("PromptWidgetBinder"))
local PlacementCelebration = require(script.Parent.PlacementCelebration)

export type TreeSpec = WoodcuttingConfig.TreeSpec

local WoodcuttingInteractionController = {}

local randomizer = Random.new()

local HARVEST_PROMPT_NAME = "TreeChopPrompt"
local DEFAULT_MAX_DISTANCE = 10
local RESTOCK_LABEL_UPDATE_INTERVAL = 0.5

local TreeStateAttributes = WoodcuttingConfig.TreeStateAttributes
local TreeStates = WoodcuttingConfig.TreeStateEnum

local HACK_SOUND_ID = WoodcuttingConfig.HackSoundId or ""
local HACK_SOUND_VOLUME = WoodcuttingConfig.HackSoundVolume or 0.6
local TREE_FALL_SOUND_ID = WoodcuttingConfig.TreeFallSoundId or ""
local TREE_FALL_SOUND_VOLUME = WoodcuttingConfig.TreeFallSoundVolume or 0.85
local TREE_SHAKE_ANGLE_DEGREES = WoodcuttingConfig.TreeShakeAngleDegrees or 4
local TREE_FALL_ANGLE_DEGREES = WoodcuttingConfig.TreeFallAngleDegrees or 70
local TREE_FALL_DURATION = WoodcuttingConfig.TreeFallDuration or 1.2
local TREE_IMPACT_RETURN = WoodcuttingConfig.TreeImpactReturnSeconds or 0.2

local DEFAULT_FALL_ANGLES = Vector2.new(math.rad(TREE_FALL_ANGLE_DEGREES), 0)

local PLAYER_CHOP_ANIMATION_ID = WoodcuttingConfig.PlayerChopAnimationId or ""
local PLAYER_CHOP_ANIMATION_FADE = WoodcuttingConfig.ChopAnimationFadeTime or 0.1

export type TreeStatePayload = {
	Guid: string,
	TypeId: string,
	State: string,
	RespawnAt: number,
	Position: Vector3,
	BusyUserId: number,
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
	ShakeLoopToken: number,
	ShakeThread: thread?,
	TreeFallen: boolean,
	HackSound: Sound?,
	FallTween: Tween | RBXScriptConnection | nil,
	LastFallAngles: Vector2?,
	ImpactToken: number,
	ImpactDirectionSign: number,
	Connections: { RBXScriptConnection },
}

local trackedByModel: { [Model]: TrackedTree } = {}
local trackedByPrompt: { [ProximityPrompt]: TrackedTree } = {}
local trackedByGuid: { [string]: TrackedTree } = {}
local originalPivotsByGuid: { [string]: CFrame } = {}

local pendingGuidWait: { [Model]: RBXScriptConnection } = {}
local knownStates: { [string]: TreeStatePayload } = {}

local restockAccumulator = 0

local function nowServer(): number
	return Workspace:GetServerTimeNow()
end

local function formatTimeRemaining(seconds: number): string
	local clamped = math.max(0, math.ceil(seconds))
	local minutes = math.floor(clamped / 60)
	local secs = clamped % 60
	if minutes > 0 then
		if secs > 0 then
			return string.format("%dm %02ds", minutes, secs)
		end
		return string.format("%dm", minutes)
	end
	return string.format("%ds", math.max(secs, 0))
end

local function buildRestockText(remaining: number): string
	if remaining <= 1 then
		return "Regrowing"
	end
	return string.format("Regrowing (%s)", formatTimeRemaining(remaining))
end

local function resolveTreeSpec(model: Model): TreeSpec?
	local typeAttr = model:GetAttribute(TreeStateAttributes.TypeId)
	if typeof(typeAttr) == "string" and typeAttr ~= "" then
		local fromAttr = WoodcuttingConfig.TreeTypes[typeAttr]
		if fromAttr then
			return fromAttr
		end
	end

	local direct = WoodcuttingConfig.TreeTypes[model.Name]
	if direct then
		return direct
	end

	for _, spec in pairs(WoodcuttingConfig.TreeTypes) do
		if spec.ModelName and spec.ModelName == model.Name then
			return spec
		end
	end

	return nil
end

local function clearGuidWait(model: Model)
	local connection = pendingGuidWait[model]
	if connection then
		connection:Disconnect()
		pendingGuidWait[model] = nil
	end
end

local function showNotice(record: TrackedTree, message: string, color: Color3)
	local adornee = record.Prompt.Parent
	local position: Vector3? = nil
	if adornee and adornee:IsA("BasePart") then
		position = adornee.Position
	else
		local ok, pivot = pcall(record.Model.GetPivot, record.Model)
		if ok then
			position = pivot.Position
		end
	end
	PlacementCelebration.ShowMessage(position, message, color)
end

local function notifyFailure(record: TrackedTree, reason: string)
	local spec = record.Spec
	if reason == "Tree already in use" then
		showNotice(record, "Someone else is chopping", Color3.fromRGB(180, 210, 255))
	elseif reason == "Tree is regrowing" then
		local remaining = math.max(0, record.RespawnAt - nowServer())
		local text = if remaining > 1
			then string.format("%s ready in %s", spec.Name, formatTimeRemaining(remaining))
			else string.format("%s is regrowing", spec.Name)
		showNotice(record, text, Color3.fromRGB(255, 226, 124))
	else
		showNotice(record, "Unable to chop right now", Color3.fromRGB(255, 118, 118))
	end
end

local currentLocalTreeGuid: string? = nil
local cachedChopTrack: AnimationTrack? = nil
local cachedChopAnimation: Animation? = nil

LocalPlayer.CharacterAdded:Connect(function()
	if cachedChopTrack and cachedChopTrack.IsPlaying then
		cachedChopTrack:Stop(0)
	end
	cachedChopTrack = nil
	cachedChopAnimation = nil
	currentLocalTreeGuid = nil
end)

LocalPlayer.CharacterRemoving:Connect(function()
	if cachedChopTrack and cachedChopTrack.IsPlaying then
		cachedChopTrack:Stop(0)
	end
	cachedChopTrack = nil
	cachedChopAnimation = nil
	currentLocalTreeGuid = nil
end)

local function ensureChopTrack(): AnimationTrack?
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
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	if cachedChopTrack and cachedChopTrack.Parent == animator then
		return cachedChopTrack
	end

	local animationObject: Animation
	if cachedChopAnimation then
		animationObject = cachedChopAnimation
	else
		animationObject = Instance.new("Animation")
		animationObject.Name = "_WoodcuttingChopAnimation"
		cachedChopAnimation = animationObject
	end
	animationObject.AnimationId = PLAYER_CHOP_ANIMATION_ID

	local ok, trackOrErr = pcall(function()
		return animator:LoadAnimation(animationObject)
	end)
	if not ok or not trackOrErr then
		warn("WoodcuttingInteractionController: failed to load chop animation", trackOrErr)
		cachedChopTrack = nil
		return nil
	end

	local track = trackOrErr :: AnimationTrack
	track.Priority = Enum.AnimationPriority.Action
	track.Looped = true
	cachedChopTrack = track
	return track
end

local function playChopAnimation()
	local track = ensureChopTrack()
	if track and not track.IsPlaying then
		track:Play(PLAYER_CHOP_ANIMATION_FADE)
	end
end

local function stopChopAnimation()
	if cachedChopTrack and cachedChopTrack.IsPlaying then
		cachedChopTrack:Stop(PLAYER_CHOP_ANIMATION_FADE)
	end
end

local function playHackLoop(record: TrackedTree)
	if HACK_SOUND_ID == "" then
		return
	end
	local parent = record.Prompt.Parent
	if not parent or not parent:IsA("BasePart") then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "_WoodcuttingHackLoop"
	sound.SoundId = HACK_SOUND_ID
	sound.Volume = if record.BusyUserId == LocalPlayer.UserId
		then HACK_SOUND_VOLUME
		else math.max(0, HACK_SOUND_VOLUME * 0.55)
	sound.RollOffMaxDistance = 55
	sound.RollOffMinDistance = 5
	sound.Looped = true
	sound.Parent = parent
	sound:Play()
	record.HackSound = sound
end

local function stopHackLoop(record: TrackedTree)
	local sound = record.HackSound
	if sound then
		sound:Stop()
		sound:Destroy()
		record.HackSound = nil
	end
end

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
	local rotation = CFrame.Angles(xAngle, 0, zAngle)
	return basePivot * rotation * CFrame.new(0, halfHeight, 0)
end

local function applyTilt(record: TrackedTree, xAngle: number, zAngle: number)
	if not record.Model.Parent then
		return
	end
	record.Model:PivotTo(computeTiltedPivot(record, xAngle, zAngle))
end

local function applyStoredFallPose(record: TrackedTree)
	if not record.LastFallAngles then
		return
	end
	applyTilt(record, record.LastFallAngles.X, record.LastFallAngles.Y)
end

local function triggerImpact(record: TrackedTree)
	if record.TreeFallen then
		return
	end
	if not record.Model.Parent then
		return
	end
	ensureBasePivot(record)
	local amplitude = math.rad(TREE_SHAKE_ANGLE_DEGREES)
	record.ImpactToken += 1
	local token = record.ImpactToken
	local xAngle = amplitude * record.ImpactDirectionSign
	local zAngle = amplitude * randomizer:NextNumber(-0.4, 0.4)
	applyTilt(record, xAngle, zAngle)
	record.ImpactDirectionSign *= -1
	task.delay(TREE_IMPACT_RETURN, function()
		if record.ImpactToken == token and not record.TreeFallen then
			applyTilt(record, 0, 0)
		end
	end)
end

local function stopTreeShake(record: TrackedTree)
	record.ShakeLoopToken += 1
	record.ImpactToken += 1
	local threadRef = record.ShakeThread
	if threadRef then
		task.cancel(threadRef)
		record.ShakeThread = nil
	end
	if not record.TreeFallen and record.Model.Parent then
		applyTilt(record, 0, 0)
	end
end

local function startTreeShake(record: TrackedTree)
	if record.TreeFallen then
		return
	end
	stopTreeShake(record)
	record.ImpactDirectionSign = 1
	local sound = record.HackSound
	if not sound then
		return
	end
	record.ShakeLoopToken += 1
	local token = record.ShakeLoopToken
	record.ShakeThread = task.spawn(function()
		local lastTime = -1
		local sawPlayback = false
		while record.ShakeLoopToken == token and record.State == TreeStates.Busy do
			local currentSound = record.HackSound
			if currentSound and currentSound.IsPlaying then
				local currentTime = currentSound.TimePosition
				if not sawPlayback then
					sawPlayback = true
					lastTime = currentTime
					triggerImpact(record)
				elseif lastTime >= 0 and currentTime < lastTime - 0.02 then
					triggerImpact(record)
				end
				lastTime = currentTime
			else
				sawPlayback = false
				lastTime = -1
			end
			RunService.Heartbeat:Wait()
		end
	end)
end

local function cancelFallTween(record: TrackedTree)
	local current = record.FallTween
	if not current then
		return
	end
	local kind = typeof(current)
	if kind == "RBXScriptConnection" then
		local connection = current :: RBXScriptConnection
		if connection.Connected then
			connection:Disconnect()
		end
	elseif kind == "Instance" then
		local tween = current :: Tween
		tween:Cancel()
	end
	record.FallTween = nil
end

local function playTreeFall(record: TrackedTree)
	if record.TreeFallen then
		return
	end
	stopTreeShake(record)
	record.TreeFallen = true

	local parent = record.Prompt.Parent
	if TREE_FALL_SOUND_ID ~= "" and parent and parent:IsA("BasePart") then
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
	end)
	record.FallTween = tween
	tween:Play()
end

local function restoreTree(record: TrackedTree)
	cancelFallTween(record)
	record.TreeFallen = false
	record.LastFallAngles = nil
	record.BasePivot = nil
	record.HalfHeight = nil
	if record.Model.Parent then
		record.Model:PivotTo(record.OriginalPivot)
	end
end

local function startChopEffects(record: TrackedTree)
	record.TreeFallen = false
	record.LastFallAngles = nil
	record.ImpactToken += 1
	record.ImpactDirectionSign = 1
	stopHackLoop(record)
	playHackLoop(record)
	ensureBasePivot(record)
	applyTilt(record, 0, 0)
	startTreeShake(record)
	if record.BusyUserId == LocalPlayer.UserId then
		currentLocalTreeGuid = record.Guid
		playChopAnimation()
	end
end

local function stopChopEffects(record: TrackedTree, previousBusyUserId: number?)
	stopHackLoop(record)
	stopTreeShake(record)
	if previousBusyUserId == LocalPlayer.UserId or currentLocalTreeGuid == record.Guid then
		currentLocalTreeGuid = nil
		stopChopAnimation()
	end
end

local function updatePrompt(record: TrackedTree)
	local prompt = record.Prompt
	if record.Pending then
		prompt.Enabled = false
		PromptWidgetBinder.SetSuppressed(prompt, true)
		if prompt.ActionText ~= "Chopping..." then
			prompt.ActionText = "Chopping..."
			PromptWidgetBinder.Refresh(prompt)
		end
		return
	end

	PromptWidgetBinder.SetSuppressed(prompt, false)

	if record.State == TreeStates.Ready then
		prompt.Enabled = true
		local text = "Chop " .. record.Spec.Name
		if prompt.ActionText ~= text then
			prompt.ActionText = text
			PromptWidgetBinder.Refresh(prompt)
		end
		return
	end

	prompt.Enabled = false

	if record.State == TreeStates.Busy then
		local busyText = if record.BusyUserId == LocalPlayer.UserId then "Chopping..." else "In use"
		if prompt.ActionText ~= busyText then
			prompt.ActionText = busyText
			PromptWidgetBinder.Refresh(prompt)
		end
		return
	end

	local remaining = math.max(0, record.RespawnAt - nowServer())
	local text = buildRestockText(remaining)
	if prompt.ActionText ~= text then
		prompt.ActionText = text
		PromptWidgetBinder.Refresh(prompt)
	end
end

local function applyState(record: TrackedTree, payload: TreeStatePayload)
	local previousState = record.State
	local previousBusyUserId = record.BusyUserId
	record.State = payload.State
	record.RespawnAt = payload.RespawnAt
	record.BusyUserId = if payload.BusyUserId ~= 0 then payload.BusyUserId else nil

	if record.State == TreeStates.Busy then
		if previousState ~= TreeStates.Busy then
			startChopEffects(record)
		end
	elseif previousState == TreeStates.Busy then
		stopChopEffects(record, previousBusyUserId)
		if record.State == TreeStates.Regrowing then
			playTreeFall(record)
		end
	end

	if record.State == TreeStates.Ready then
		restoreTree(record)
	elseif record.State == TreeStates.Regrowing and previousState ~= TreeStates.Regrowing then
		if previousState ~= TreeStates.Busy then
			cancelFallTween(record)
			record.TreeFallen = true
			if not record.LastFallAngles then
				record.LastFallAngles = DEFAULT_FALL_ANGLES
			end
			ensureBasePivot(record)
			applyStoredFallPose(record)
		end
	end

	updatePrompt(record)
end

local function onStateChanged(payload: TreeStatePayload)
	if payload.Guid == "" then
		return
	end
	knownStates[payload.Guid] = payload
	local record = trackedByGuid[payload.Guid]
	if record then
		applyState(record, payload)
	end
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if player ~= LocalPlayer then
		return
	end
	local record = trackedByPrompt[prompt]
	if not record or record.Pending then
		return
	end
	if record.State ~= TreeStates.Ready then
		notifyFailure(record, record.State == TreeStates.Busy and "Tree already in use" or "Tree is regrowing")
		updatePrompt(record)
		return
	end

	record.Pending = true
	updatePrompt(record)

	task.defer(function()
		local ok, success, message, duration = pcall(function()
			return WoodcuttingPackets.TreeChopRequest:Fire(record.Guid)
		end)

		record.Pending = false
		if not ok then
			warn("Tree chop request failed", success)
			notifyFailure(record, "Unable to chop right now")
			updatePrompt(record)
			return
		end

		if not success then
			notifyFailure(record, message)
		else
			if duration and duration > 0 then
				prompt.ActionText = string.format("Chopping (%.1fs)", duration)
			end
		end
		updatePrompt(record)
	end)
end

local function cleanupModel(model: Model)
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

	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end

	PromptWidgetBinder.Detach(record.Prompt)
	if record.CreatedPrompt then
		record.Prompt:Destroy()
	elseif record.Prompt.Parent then
		record.Prompt.Enabled = true
	end
end

local function findInteractPart(model: Model): BasePart?
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function registerModel(model: Model)
	if trackedByModel[model] then
		return
	end

	local spec = resolveTreeSpec(model)
	if not spec then
		return
	end

	local guidAttr = model:GetAttribute(TreeStateAttributes.Guid)
	if typeof(guidAttr) ~= "string" or guidAttr == "" then
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

	local existing = interactPart:FindFirstChild(HARVEST_PROMPT_NAME)
	local prompt: ProximityPrompt
	local createdPrompt = false
	if existing and existing:IsA("ProximityPrompt") then
		prompt = existing
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
		prompt.Parent = interactPart
	end
	prompt.Style = Enum.ProximityPromptStyle.Custom

	local originalPivot = originalPivotsByGuid[guidAttr]
	if not originalPivot then
		local ok, pivot = pcall(model.GetPivot, model)
		if ok then
			originalPivot = pivot
		else
			local okBounds, boundsCFrame, _boundsSize = pcall(function(): (CFrame, Vector3)
				return model:GetBoundingBox()
			end)
			if okBounds and boundsCFrame then
				originalPivot = boundsCFrame
			else
				warn("WoodcuttingInteractionController: failed to read pivot for", model:GetFullName())
				originalPivot = CFrame.identity
			end
		end
		originalPivotsByGuid[guidAttr] = originalPivot
	end

	local record: TrackedTree = {
		Model = model,
		Prompt = prompt,
		Spec = spec,
		Guid = guidAttr,
		State = TreeStates.Ready,
		RespawnAt = 0,
		BusyUserId = nil,
		Pending = false,
		CreatedPrompt = createdPrompt,
		OriginalPivot = originalPivot,
		BasePivot = nil,
		HalfHeight = nil,
		ShakeLoopToken = 0,
		ShakeThread = nil,
		TreeFallen = false,
		HackSound = nil,
		FallTween = nil,
		LastFallAngles = nil,
		ImpactToken = 0,
		ImpactDirectionSign = 1,
		Connections = {},
	}

	record.Connections[#record.Connections + 1] = prompt.Triggered:Connect(function(player)
		onPromptTriggered(prompt, player)
	end)

	record.Connections[#record.Connections + 1] = model.Destroying:Connect(function()
		cleanupModel(model)
	end)

	record.Connections[#record.Connections + 1] = model.AncestryChanged:Connect(function(_, parent)
		if not parent then
			cleanupModel(model)
		end
	end)

	PromptWidgetBinder.Attach(prompt)

	trackedByModel[model] = record
	trackedByPrompt[prompt] = record
	trackedByGuid[record.Guid] = record
	ensureBasePivot(record)

	local known = knownStates[record.Guid]
	if known then
		applyState(record, known)
	else
		local stateAttr = model:GetAttribute(TreeStateAttributes.State)
		if typeof(stateAttr) == "string" then
			record.State = stateAttr
		end
		local respawnAttr = model:GetAttribute(TreeStateAttributes.RespawnAt)
		if typeof(respawnAttr) == "number" then
			record.RespawnAt = respawnAttr
		end
		updatePrompt(record)
	end
end

local function bindTreeFolder(folder: Instance)
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

local function hydrateSnapshot()
	local ok, response = pcall(function()
		return WoodcuttingPackets.RequestForestSnapshot:Fire()
	end)
	if not ok or not response then
		warn("WoodcuttingInteractionController: failed to request forest snapshot", response)
		return
	end

	for _, payload in ipairs(response.Trees) do
		knownStates[payload.Guid] = payload
		local record = trackedByGuid[payload.Guid]
		if record then
			applyState(record, payload)
		end
	end
end

local function onYieldNotice(payload: { Guid: string, ItemDefId: string, Quantity: number })
	local record = trackedByGuid[payload.Guid]
	local message: string
	local color = Color3.fromRGB(168, 233, 143)
	local position: Vector3? = nil
	if record then
		message = string.format("+%d %s", payload.Quantity, record.Spec.Name)
		local adornee = record.Prompt.Parent
		if adornee and adornee:IsA("BasePart") then
			position = adornee.Position
		else
			local ok, pivot = pcall(record.Model.GetPivot, record.Model)
			if ok then
				position = pivot.Position
			end
		end
	else
		message = string.format("+%d logs", payload.Quantity)
		local character = LocalPlayer.Character
		if character then
			local rootPart = character:FindFirstChild("HumanoidRootPart")
			if rootPart and rootPart:IsA("BasePart") then
				position = rootPart.Position
			end
		end
	end
	PlacementCelebration.ShowMessage(position, message, color)
end

RunService.Heartbeat:Connect(function(dt)
	restockAccumulator += dt
	if restockAccumulator < RESTOCK_LABEL_UPDATE_INTERVAL then
		return
	end
	restockAccumulator = 0
	local currentNow = nowServer()
	for _, record in pairs(trackedByGuid) do
		if record.State == TreeStates.Regrowing and not record.Pending then
			local text = buildRestockText(math.max(0, record.RespawnAt - currentNow))
			if record.Prompt.ActionText ~= text then
				record.Prompt.ActionText = text
				PromptWidgetBinder.Refresh(record.Prompt)
			end
		end
	end
end)

function WoodcuttingInteractionController.Init()
	WoodcuttingPackets.TreeStateChanged.OnClientEvent:Connect(onStateChanged)
	WoodcuttingPackets.TreeYieldNotice.OnClientEvent:Connect(onYieldNotice)

	hydrateSnapshot()

	bindTreeFolder(TreeFolder)
end

return WoodcuttingInteractionController
