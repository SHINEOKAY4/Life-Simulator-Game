--!strict
-- StarterPlayerScripts/Client/Modules/MiningInteractionController.luau
-- Client-side interaction controller for mining shared rock nodes.

----------------------------------------------------------------------
-- Services
----------------------------------------------------------------------

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

----------------------------------------------------------------------
-- World Refs
----------------------------------------------------------------------

local WorldFolder = Workspace:WaitForChild("World")
local ForestFolder = WorldFolder:WaitForChild("Forest")
local RockFolder = ForestFolder:WaitForChild("Rocks") :: Folder

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

----------------------------------------------------------------------
-- Modules
----------------------------------------------------------------------

local MiningPackets = require(ReplicatedStorage.Network.MiningPackets)
local MiningConfig = require(ReplicatedStorage.Shared.Definitions.MiningConfig)
local MaterialDefinitions = require(ReplicatedStorage.Shared.Definitions.MaterialDefinitions)
local PromptWidgetBinder = require(script.Parent:WaitForChild("PromptWidgetBinder"))
local PlacementCelebration = require(script.Parent.PlacementCelebration)
local MovementLock = require(script.Parent.Character.MovementLock)
local TimedProgressHud = require(script.Parent.Parent.UserInterface.TimedProgressHud)
local WorldPickupDisplay = require(script.Parent.Parent.UserInterface.WorldPickupDisplay)

----------------------------------------------------------------------
-- Assets / Tool Hooks
----------------------------------------------------------------------

local AssetsFolder = ReplicatedStorage:FindFirstChild("Assets")
local ToolsFolder = AssetsFolder and AssetsFolder:FindFirstChild("Tools")
local PickaxeTool = ToolsFolder and ToolsFolder:FindFirstChild("Pickaxe")
if PickaxeTool and PickaxeTool:IsA("Tool") then
	PickaxeTool.CanBeDropped = false
else
	PickaxeTool = nil
end

----------------------------------------------------------------------
-- Types
----------------------------------------------------------------------

export type RockSpec = MiningConfig.RockSpec
export type MaterialSpec = MaterialDefinitions.MaterialSpec

export type RockStatePayload = {
	Guid: string,
	TypeId: string,
	State: string,
	RespawnAt: number,
	Position: Vector3,
	BusyUserId: number?,
}

export type TrackedRock = {
	Model: Model,
	Prompt: ProximityPrompt,
	Spec: RockSpec,
	Guid: string,
	State: string,
	RespawnAt: number,
	BusyUserId: number?,
	Pending: boolean,
	CreatedPrompt: boolean,

	MineSound: Sound?,
	MineSoundConnection: RBXScriptConnection?,

	Connections: { RBXScriptConnection },
	ExpectedMineDuration: number?,
}

----------------------------------------------------------------------
-- Config / Constants
----------------------------------------------------------------------

local DEFAULT_MAX_DISTANCE = 8
local RESTOCK_LABEL_UPDATE_INTERVAL = 0.5

local RockStateAttributes = MiningConfig.RockStateAttributes
local RockStates = MiningConfig.RockStateEnum

local PICK_SWING_SOUND_ID = MiningConfig.PickSwingSoundId or ""
local PICK_SWING_VOLUME = MiningConfig.PickSwingSoundVolume or 0.7
local ROCK_BREAK_SOUND_ID = MiningConfig.RockBreakSoundId or ""
local ROCK_BREAK_VOLUME = MiningConfig.RockBreakSoundVolume or 0.9
local DEFAULT_MINING_DURATION = 4

----------------------------------------------------------------------
-- Module State
----------------------------------------------------------------------

local MiningInteractionController = {}

local movementLock = MovementLock.new(LocalPlayer)
local progressHud = TimedProgressHud.new({
	PlayerGui = PlayerGui,
	GuiName = "MiningProgressHud",
	IconAsset = MiningConfig.RockImageAssetId,
	IconSize = UDim2.fromOffset(36, 36),
	FillColor = Color3.fromRGB(149, 189, 213),
	BarColor = Color3.fromRGB(38, 49, 64),
	TextColor = Color3.fromRGB(237, 243, 255),
})
local pickupDisplay = WorldPickupDisplay.new({
	DisplayDuration = 2.6,
	MaxDistance = 90,
	GuiSize = UDim2.fromOffset(188, 66),
	IconSize = UDim2.fromOffset(46, 46),
	DefaultIcon = MiningConfig.RockImageAssetId,
})

local FALLBACK_MATERIAL_SPEC: MaterialSpec = MaterialDefinitions.Get("Stone")
	or { Id = "Stone" :: any, Name = "Stone", IconImage = MiningConfig.RockImageAssetId }

local trackedByModel: { [Model]: TrackedRock } = {}
local trackedByPrompt: { [ProximityPrompt]: TrackedRock } = {}
local trackedByGuid: { [string]: TrackedRock } = {}
local pendingGuidWait: { [Model]: RBXScriptConnection } = {}
local knownStates: { [string]: RockStatePayload } = {}

local restockAccumulator = 0
local currentLocalRockGuid: string? = nil

----------------------------------------------------------------------
-- Tool Helpers
----------------------------------------------------------------------

local PickaxeToolHomeParent: Instance? = PickaxeTool and PickaxeTool.Parent or nil

local function equipPickaxe()
	if not PickaxeTool then
		return
	end
	local character = LocalPlayer.Character
	if not character then
		return
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if PickaxeTool.Parent ~= character then
		PickaxeTool.Parent = character
	end
	humanoid:EquipTool(PickaxeTool)
end

local function stowPickaxe()
	if not PickaxeTool then
		return
	end
	if PickaxeToolHomeParent and PickaxeTool.Parent ~= PickaxeToolHomeParent then
		PickaxeTool.Parent = PickaxeToolHomeParent
	end
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
	return remaining <= 1 and "Rebuilding" or string.format("Rebuilding (%s)", timeAsText(remaining))
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
	if nextState == RockStates.Busy and LocalPlayer.UserId == 0 then
		return 0
	end
	return nil
end

local function connect(record: TrackedRock, signal: RBXScriptSignal, handler: (...any) -> ())
	record.Connections[#record.Connections + 1] = signal:Connect(handler)
end

local function disconnectAll(record: TrackedRock)
	for _, connection in ipairs(record.Connections) do
		connection:Disconnect()
	end
	table.clear(record.Connections)
end

local function setPromptText(prompt: ProximityPrompt, text: string)
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

local function getRockWorldPosition(record: TrackedRock): Vector3?
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

local function showWorldMessage(record: TrackedRock, message: string, color: Color3)
	PlacementCelebration.ShowMessage(getRockWorldPosition(record), message, color)
end

----------------------------------------------------------------------
-- Audio Helpers
----------------------------------------------------------------------

local function stopMineSound(record: TrackedRock)
	if record.MineSoundConnection then
		record.MineSoundConnection:Disconnect()
		record.MineSoundConnection = nil
	end
	local sound = record.MineSound
	if sound then
		sound:Stop()
		sound:Destroy()
		record.MineSound = nil
	end
end

local function playMineLoop(record: TrackedRock)
	if PICK_SWING_SOUND_ID == "" then
		return
	end

	local parent = resolvePromptBasePart(record.Prompt)
	if not parent then
		return
	end

	local sound = Instance.new("Sound")
	sound.Name = "_MiningSwingLoop"
	sound.SoundId = PICK_SWING_SOUND_ID
	sound.Volume = (isLocalPlayerUserId(record.BusyUserId) and PICK_SWING_VOLUME)
		or math.max(0, PICK_SWING_VOLUME * 0.55)
	sound.RollOffMaxDistance = 55
	sound.RollOffMinDistance = 5
	sound.Looped = true
	sound.Parent = parent
	sound:Play()

	record.MineSound = sound
	record.MineSoundConnection = sound.DidLoop:Connect(function()
		if record.MineSound ~= sound or not sound.IsPlaying then
			return
		end
		if record.State ~= RockStates.Busy then
			return
		end
		if not (isLocalPlayerUserId(record.BusyUserId) or currentLocalRockGuid == record.Guid) then
			return
		end
		-- Provide a subtle camera wiggle via Tweening the prompt base part (visual nudge without camera shake).
		local basePart = resolvePromptBasePart(record.Prompt)
		if not basePart then
			return
		end
		local originalCFrame = basePart.CFrame
		local offset = CFrame.new(0, 0.08, 0)
		local wiggle =
			TweenService:Create(basePart, TweenInfo.new(0.08, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				CFrame = originalCFrame * offset,
			})
		wiggle:Play()
		task.delay(0.08, function()
			if basePart.Parent then
				basePart.CFrame = originalCFrame
			end
		end)
	end)
end

local function playRockBreak(record: TrackedRock)
	if ROCK_BREAK_SOUND_ID == "" then
		return
	end
	local parent = resolvePromptBasePart(record.Prompt)
	if not parent then
		return
	end
	local sound = Instance.new("Sound")
	sound.Name = "_MiningRockBreak"
	sound.SoundId = ROCK_BREAK_SOUND_ID
	sound.Volume = ROCK_BREAK_VOLUME
	sound.RollOffMaxDistance = 80
	sound.RollOffMinDistance = 8
	sound.Parent = parent
	sound:Play()
	task.spawn(function()
		sound.Ended:Wait()
		sound:Destroy()
	end)
end

local function updatePrompt(record: TrackedRock)
	local prompt = record.Prompt
	if record.Pending then
		prompt.Enabled = false
		PromptWidgetBinder.SetSuppressed(prompt, true)
		setPromptText(prompt, "Mining...")
		return
	end

	PromptWidgetBinder.SetSuppressed(prompt, false)

	if record.State == RockStates.Ready then
		prompt.Enabled = true
		setPromptText(prompt, "Mine " .. record.Spec.Name)
		return
	end

	prompt.Enabled = false

	if record.State == RockStates.Busy then
		setPromptText(prompt, (isLocalPlayerUserId(record.BusyUserId) and "Mining...") or "In use")
		return
	end

	setPromptText(prompt, buildRestockText(math.max(0, record.RespawnAt - serverNow())))
end

----------------------------------------------------------------------
-- State Application
----------------------------------------------------------------------

local function showMiningProgress(durationSeconds: number?, rockName: string)
	local duration = (durationSeconds and durationSeconds > 0) and durationSeconds or DEFAULT_MINING_DURATION
	progressHud:Show(duration, string.format("Mining %s", rockName ~= "" and rockName or "Rock"))
end

local function hideMiningProgress()
	progressHud:Hide()
end

local function lockCharacter(record: TrackedRock)
	local basePart = resolvePromptBasePart(record.Prompt)
	movementLock:Acquire(record.Guid, {
		FacePosition = basePart and basePart.Position or nil,
	})
end

local function unlockCharacter(recordGuid: string?)
	movementLock:Release(recordGuid)
end

local function startMiningEffects(record: TrackedRock)
	local localPlayerBusy = isLocalPlayerUserId(record.BusyUserId) or currentLocalRockGuid == record.Guid
	if localPlayerBusy then
		currentLocalRockGuid = record.Guid
	end

	stopMineSound(record)
	playMineLoop(record)

	if localPlayerBusy then
		equipPickaxe()
		lockCharacter(record)
		showMiningProgress(record.ExpectedMineDuration, record.Spec.Name)
		record.ExpectedMineDuration = nil
	end
end

local function stopMiningEffects(record: TrackedRock, previousBusyUserId: number?)
	stopMineSound(record)

	if isLocalPlayerUserId(previousBusyUserId) or currentLocalRockGuid == record.Guid then
		currentLocalRockGuid = nil
		stowPickaxe()
		hideMiningProgress()
		unlockCharacter(record.Guid)
	end

	record.ExpectedMineDuration = nil
end

local function applyState(record: TrackedRock, payload: RockStatePayload)
	local previousState = record.State
	local previousBusyUserId = record.BusyUserId

	record.State = payload.State
	record.RespawnAt = payload.RespawnAt
	record.BusyUserId = normalizeBusyUserId(payload.BusyUserId, record.State)

	if record.State == RockStates.Busy then
		if previousState ~= RockStates.Busy then
			startMiningEffects(record)
		end
	elseif previousState == RockStates.Busy then
		stopMiningEffects(record, previousBusyUserId)
		if record.State == RockStates.Regrowing then
			playRockBreak(record)
		end
	end

	updatePrompt(record)
end

----------------------------------------------------------------------
-- Network Callbacks
----------------------------------------------------------------------

local function onStateChanged(payload: RockStatePayload)
	if payload.Guid == "" then
		return
	end
	knownStates[payload.Guid] = payload
	local record = trackedByGuid[payload.Guid]
	if record then
		applyState(record, payload)
	end
end

local function notifyFailure(record: TrackedRock, reason: string)
	if reason == "Rock already in use" then
		showWorldMessage(record, "Someone else is mining", Color3.fromRGB(180, 210, 255))
		return
	end

	if reason == "Rock is regrowing" then
		local remaining = math.max(0, record.RespawnAt - serverNow())
		local text = (remaining > 1) and string.format("%s ready in %s", record.Spec.Name, timeAsText(remaining))
			or string.format("%s is rebuilding", record.Spec.Name)
		showWorldMessage(record, text, Color3.fromRGB(255, 226, 124))
		return
	end

	showWorldMessage(record, "Unable to mine right now", Color3.fromRGB(255, 118, 118))
end

local function onPromptTriggered(prompt: ProximityPrompt, player: Player)
	if player ~= LocalPlayer then
		return
	end

	local record = trackedByPrompt[prompt]
	if not record or record.Pending then
		return
	end

	if record.State ~= RockStates.Ready then
		notifyFailure(record, (record.State == RockStates.Busy) and "Rock already in use" or "Rock is regrowing")
		updatePrompt(record)
		return
	end

	record.Pending = true
	updatePrompt(record)

	task.defer(function()
		local ok, successFlag, message, duration = pcall(function()
			return MiningPackets.RockMineRequest:Fire(record.Guid)
		end)

		record.Pending = false

		if not ok then
			warn("Rock mine request failed", successFlag)
			notifyFailure(record, "Unable to mine right now")
			updatePrompt(record)
			return
		end

		if not successFlag then
			record.ExpectedMineDuration = nil
			notifyFailure(record, message)
		else
			record.ExpectedMineDuration = duration
			currentLocalRockGuid = record.Guid
			equipPickaxe()
			lockCharacter(record)
			showMiningProgress(record.ExpectedMineDuration, record.Spec.Name)
		end

		updatePrompt(record)
	end)
end

local function resolveMaterialSpecFromItem(inventoryDefinitionId: string): MaterialSpec
	local inventoryDefinition = MiningConfig.InventoryDefinitions[inventoryDefinitionId]
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
			local icon = metadata.IconImage
			if typeof(icon) == "string" and icon ~= "" then
				return {
					Id = metadata.MaterialId or inventoryDefinition.defId,
					Name = metadata.DisplayName or inventoryDefinition.defId,
					IconImage = icon,
				}
			end
		end
	end
	return FALLBACK_MATERIAL_SPEC
end

local function onYieldNotice(payload: { Guid: string, ItemDefId: string, Quantity: number })
	local record = trackedByGuid[payload.Guid]
	local character = LocalPlayer.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")

	local targetPart: BasePart? = nil
	local studsOffset = Vector3.new(2.4, 2.2, 0.35)

	if rootPart and rootPart:IsA("BasePart") then
		targetPart = rootPart
		studsOffset = rootPart.CFrame:VectorToWorldSpace(studsOffset)
	end

	if not targetPart and record then
		targetPart = resolvePromptBasePart(record.Prompt)
	end

	local materialSpec = resolveMaterialSpecFromItem(payload.ItemDefId)

	if targetPart then
		pickupDisplay:Show({
			Id = tostring(materialSpec.Id),
			Name = materialSpec.Name,
			IconImage = materialSpec.IconImage,
		}, payload.Quantity, targetPart, studsOffset)
		return
	end

	local position: Vector3? = record and getRockWorldPosition(record)
		or (rootPart and rootPart:IsA("BasePart") and rootPart.Position or nil)
	PlacementCelebration.ShowMessage(
		position,
		string.format("+%d %s", payload.Quantity, materialSpec.Name),
		Color3.fromRGB(199, 228, 255)
	)
end

----------------------------------------------------------------------
-- Model Registration / Cleanup
----------------------------------------------------------------------

local function clearGuidWait(model: Model)
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

local function cleanupModel(model: Model)
	clearGuidWait(model)

	local record = trackedByModel[model]
	if not record then
		return
	end

	stopMiningEffects(record, record.BusyUserId)
	stopMineSound(record)

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

local function registerModel(model: Model)
	if trackedByModel[model] then
		return
	end

	local spec = (function(): RockSpec?
		local typeId = model:GetAttribute(RockStateAttributes.TypeId)
		if typeof(typeId) == "string" and typeId ~= "" then
			local byAttribute = MiningConfig.RockTypes[typeId]
			if byAttribute then
				return byAttribute
			end
		end
		local byName = MiningConfig.RockTypes[model.Name]
		if byName then
			return byName
		end
		for _, candidate in pairs(MiningConfig.RockTypes) do
			if candidate.ModelName and candidate.ModelName == model.Name then
				return candidate
			end
		end
		return nil
	end)()

	if not spec then
		return
	end

	local guidAttribute = model:GetAttribute(RockStateAttributes.Guid)
	if typeof(guidAttribute) ~= "string" or guidAttribute == "" then
		if not pendingGuidWait[model] then
			pendingGuidWait[model] = model:GetAttributeChangedSignal(RockStateAttributes.Guid):Connect(function()
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

	local existingPrompt = interactPart:FindFirstChild("MiningPrompt")
	local prompt: ProximityPrompt
	local createdPrompt = false

	if existingPrompt and existingPrompt:IsA("ProximityPrompt") then
		prompt = existingPrompt
	else
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "MiningPrompt"
		createdPrompt = true
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
		prompt.ObjectText = spec.Name
		prompt.ActionText = "Mine " .. spec.Name
		prompt.HoldDuration = 0
		prompt.RequiresLineOfSight = false
		prompt.MaxActivationDistance = DEFAULT_MAX_DISTANCE
		prompt.Parent = interactPart
	end

	prompt.Style = Enum.ProximityPromptStyle.Custom
	if prompt.Parent ~= interactPart then
		prompt.Parent = interactPart
	end

	if prompt:GetAttribute("WidgetOffset") ~= nil then
		prompt:SetAttribute("WidgetOffset", nil)
	end
	prompt:SetAttribute("WidgetOffsetY", 0)

	local leftoverAttachment = interactPart:FindFirstChild("MiningPromptAttachment")
	if leftoverAttachment and leftoverAttachment:IsA("Attachment") then
		leftoverAttachment:Destroy()
	end

	local record: TrackedRock = {
		Model = model,
		Prompt = prompt,
		Spec = spec,
		Guid = guidAttribute,
		State = RockStates.Ready,
		RespawnAt = 0,
		BusyUserId = nil,
		Pending = false,
		CreatedPrompt = createdPrompt,

		MineSound = nil,
		MineSoundConnection = nil,

		Connections = {},
		ExpectedMineDuration = nil,
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

	PromptWidgetBinder.Attach(prompt)

	trackedByModel[model] = record
	trackedByPrompt[prompt] = record
	trackedByGuid[record.Guid] = record

	local known = knownStates[record.Guid]
	if known then
		applyState(record, known)
	else
		local stateAttribute = model:GetAttribute(RockStateAttributes.State)
		if typeof(stateAttribute) == "string" then
			record.State = stateAttribute
		end

		local respawnAttribute = model:GetAttribute(RockStateAttributes.RespawnAt)
		if typeof(respawnAttribute) == "number" then
			record.RespawnAt = respawnAttribute
		end

		updatePrompt(record)
	end
end

local function bindRockFolder(folder: Instance)
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

local function hydrateSnapshot()
	local ok, response = pcall(function()
		return MiningPackets.RequestMineSnapshot:Fire()
	end)
	if not ok or not response then
		warn("MiningInteractionController: failed to request mining snapshot", response)
		return
	end

	local rocks = (response.Rocks :: any) or {}
	for _, payload in ipairs(rocks) do
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
		if record.State == RockStates.Regrowing and not record.Pending then
			if record.Prompt.Parent then
				setPromptText(record.Prompt, buildRestockText(math.max(0, record.RespawnAt - now)))
			end
		end
	end
end)

----------------------------------------------------------------------
-- Character lifecycle
----------------------------------------------------------------------

LocalPlayer.CharacterAdded:Connect(function()
	currentLocalRockGuid = nil
	hideMiningProgress()
	unlockCharacter(nil)
	movementLock:Reset()
	stowPickaxe()
end)

LocalPlayer.CharacterRemoving:Connect(function()
	currentLocalRockGuid = nil
	hideMiningProgress()
	unlockCharacter(nil)
	movementLock:Reset()
	stowPickaxe()
end)

----------------------------------------------------------------------
-- Public API
----------------------------------------------------------------------

function MiningInteractionController.Init()
	MiningPackets.RockStateChanged.OnClientEvent:Connect(onStateChanged)
	MiningPackets.RockYieldNotice.OnClientEvent:Connect(onYieldNotice)

	hydrateSnapshot()
	bindRockFolder(RockFolder)
end

return MiningInteractionController
