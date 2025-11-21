--!strict
-- Client/Modules/WireController.luau
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local UtilityVisuals = require(script.Parent.UtilityVisuals)

local WireController = {}

local isDragging = false
local potentialDrag = false
local dragStartPos: Vector2? = nil
local DRAG_THRESHOLD = 5 -- pixels

local sourceKey: string? = nil
local sourceInstance: Instance? = nil
local sourceSpec: { [string]: any }? = nil

local dragSegments = {} -- { {Beam, Att0, Att1}, ... }
local dragConnection: RBXScriptConnection? = nil
local snapVisual: BasePart? = nil
local lastValidTargetKey: string? = nil

local currentValidTargetKey: string? = nil
local currentValidTargetPos: Vector3? = nil

local function getFloorY(level: number?): number
	local surface = PlotStateStore.GetSurface()
	if not surface then
		return 0
	end
	local baseHeight = surface.Position.Y + surface.Size.Y / 2
	local lvl = level or PlotStateStore.GetActiveLevel()
	return baseHeight + (lvl * PlotStateStore.GetFloorHeightStuds()) + 0.2
end

local function getWireAttachmentPosition(instance: Instance, spec: any): Vector3
	if instance:IsA("Model") then
		local att = instance:FindFirstChild("WireAttachment", true)
		if att and att:IsA("Attachment") then
			return att.WorldPosition
		end
		local cf, size = instance:GetBoundingBox()
		if spec and spec.PlacementType == "Wall" then
			return cf.Position -- Center for wall items
		end
		return cf.Position - Vector3.new(0, size.Y / 2, 0) -- Bottom for floor items
	elseif instance:IsA("BasePart") then
		if spec and spec.PlacementType == "Wall" then
			return instance.Position
		end
		return instance.Position - Vector3.new(0, instance.Size.Y / 2, 0)
	end
	return Vector3.zero
end

local function getMouseRay()
	local mouse = Players.LocalPlayer:GetMouse()
	return mouse.UnitRay
end

local function raycast(): (Instance?, Vector3)
	local plotModel = PlotStateStore.GetPlotModel()
	if not plotModel then
		return nil, Vector3.zero
	end
	local container = plotModel:FindFirstChild("Container")
	if not container then
		return nil, Vector3.zero
	end

	local ray = getMouseRay()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { container }
	params.IgnoreWater = true

	local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)
	if result and result.Instance then
		local candidate = result.Instance
		while candidate and candidate.Parent ~= container do
			candidate = candidate.Parent
		end
		if candidate and candidate.Parent == container then
			return candidate, result.Position
		end
	end

	-- Raycast against terrain/baseplate for drag position if no object hit
	local terrainParams = RaycastParams.new()
	terrainParams.FilterType = Enum.RaycastFilterType.Include
	terrainParams.FilterDescendantsInstances = { Workspace.Terrain, Workspace:FindFirstChild("Baseplate") }
	local terrainResult = Workspace:Raycast(ray.Origin, ray.Direction * 1000, terrainParams)

	return nil, terrainResult and terrainResult.Position or (ray.Origin + ray.Direction * 20)
end

local function ensureDragSegment(index: number)
	if not dragSegments[index] then
		local terrain = Workspace.Terrain
		local att0 = Instance.new("Attachment")
		att0.Parent = terrain
		local att1 = Instance.new("Attachment")
		att1.Parent = terrain

		local beam = Instance.new("Beam")
		beam.Attachment0 = att0
		beam.Attachment1 = att1
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
		beam.FaceCamera = true
		beam.Width0 = 0.3
		beam.Width1 = 0.3
		beam.Texture = "rbxassetid://7151723058" -- Dashed line
		beam.TextureMode = Enum.TextureMode.Wrap
		beam.TextureLength = 2
		beam.TextureSpeed = 2
		beam.Transparency = NumberSequence.new(0.2)
		beam.Parent = terrain

		dragSegments[index] = { Beam = beam, Attachment0 = att0, Attachment1 = att1 }
	end
	return dragSegments[index]
end

local function createDragVisuals(_startPos: Vector3)
	local terrain = Workspace.Terrain
	local snap = Instance.new("Part")
	snap.Name = "WireSnapVisual"
	snap.Shape = Enum.PartType.Ball
	snap.Size = Vector3.new(0.8, 0.8, 0.8)
	snap.Material = Enum.Material.Neon
	snap.Color = Color3.fromRGB(0, 255, 0)
	snap.Transparency = 1 -- Hidden initially
	snap.Anchored = true
	snap.CanCollide = false
	snap.CastShadow = false
	snap.Parent = terrain

	snapVisual = snap
end

local function destroyDragVisuals()
	UtilityVisuals.SetForceShow(false)
	for _, seg in ipairs(dragSegments) do
		seg.Beam:Destroy()
		seg.Attachment0:Destroy()
		seg.Attachment1:Destroy()
	end
	dragSegments = {}

	if snapVisual then
		snapVisual:Destroy()
	end
	snapVisual = nil
	lastValidTargetKey = nil
end

local function areConnected(key1: string, key2: string): boolean
	local entry1 = PlotStateStore.GetPlacementEntry(key1)
	if not entry1 or not entry1.Metadata or not entry1.Metadata.Connections then
		return false
	end
	for _, conn in ipairs(entry1.Metadata.Connections) do
		if conn == key2 then
			return true
		end
	end
	return false
end

local function startDragging()
	if not sourceInstance or not sourceSpec then
		return
	end

	isDragging = true
	UtilityVisuals.SetForceShow(true)

	local startPos = getWireAttachmentPosition(sourceInstance, sourceSpec)

	if startPos ~= Vector3.zero then
		createDragVisuals(startPos)

		dragConnection = RunService.RenderStepped:Connect(function()
			local targetObj, hitPos = raycast()
			local targetPos = hitPos

			currentValidTargetKey = nil
			currentValidTargetPos = nil

			-- Validate target
			local isValid = false
			local isDisconnect = false

			if targetObj and targetObj ~= sourceInstance and sourceSpec then
				local tKey = targetObj.Name
				local tEntry = PlotStateStore.GetPlacementEntry(tKey)
				if tEntry then
					local tSpec = ItemFinder.FindItemById(tEntry.id)
					if tSpec then
						-- Power: At least one must be provider, both must be power-related
						local sourceIsPowerProvider = sourceSpec.PowerSource or sourceSpec.PowerConductor
						local tIsPowerProvider = tSpec.PowerConductor or tSpec.PowerSource
						local sourceIsPowerConsumer = sourceSpec.RequiresPower
						local tIsPowerConsumer = tSpec.RequiresPower

						local isPower = (sourceIsPowerProvider or tIsPowerProvider)
							and (sourceIsPowerProvider or sourceIsPowerConsumer)
							and (tIsPowerProvider or tIsPowerConsumer)

						-- Water: At least one must be provider, both must be water-related
						local sourceIsWaterProvider = sourceSpec.WaterSource or sourceSpec.WaterConductor
						local tIsWaterProvider = tSpec.WaterConductor or tSpec.WaterSource
						local sourceIsWaterConsumer = sourceSpec.RequiresWater
						local tIsWaterConsumer = tSpec.RequiresWater

						local isWater = (sourceIsWaterProvider or tIsWaterProvider)
							and (sourceIsWaterProvider or sourceIsWaterConsumer)
							and (tIsWaterProvider or tIsWaterConsumer)

						if isPower or isWater then
							-- Check radius
							local r1 = sourceSpec.ConnectionRadius or 20 -- Default fallback
							local r2 = tSpec.ConnectionRadius or 20
							local maxR = math.max(r1, r2)

							-- Snap to target attachment
							local snapPos = getWireAttachmentPosition(targetObj, tSpec)
							local dist = (startPos - snapPos).Magnitude

							if dist <= maxR + 1 then
								isValid = true
								targetPos = snapPos
								currentValidTargetKey = tKey
								currentValidTargetPos = snapPos

								if sourceKey and areConnected(sourceKey, tKey) then
									isDisconnect = true
								end
							end
						end
					end
				end
			end

			-- Update Visuals
			local floorY = getFloorY()

			-- Enforce deterministic path direction to match UtilityVisuals
			local p1 = startPos
			local p2 = targetPos
			if sourceKey and currentValidTargetKey then
				if sourceKey > currentValidTargetKey then
					p1 = targetPos
					p2 = startPos
				end
			end

			local path = UtilityVisuals.GetWirePath(p1, p2, floorY)

			-- Ensure segments
			for i = 1, #path - 1 do
				local seg = ensureDragSegment(i)
				seg.Attachment0.WorldPosition = path[i]
				seg.Attachment1.WorldPosition = path[i + 1]
				seg.Beam.Enabled = true

				if isValid then
					if isDisconnect then
						seg.Beam.Color = ColorSequence.new(Color3.fromRGB(255, 50, 50))
					else
						local isWater = sourceSpec and (sourceSpec.WaterSource or sourceSpec.WaterConductor)
						local color = if isWater then Color3.fromRGB(0, 150, 255) else Color3.fromRGB(0, 255, 0)
						seg.Beam.Color = ColorSequence.new(color)
					end
				else
					seg.Beam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255))
				end
			end

			-- Hide unused segments
			for i = #path, #dragSegments do
				dragSegments[i].Beam.Enabled = false
			end

			if snapVisual then
				if isValid then
					if isDisconnect then
						snapVisual.Color = Color3.fromRGB(255, 50, 50) -- Red for disconnect
						snapVisual.Position = targetPos
						snapVisual.Transparency = 0.2
					else
						-- Determine color based on type
						local isWater = sourceSpec and (sourceSpec.WaterSource or sourceSpec.WaterConductor)
						local color = if isWater then Color3.fromRGB(0, 150, 255) else Color3.fromRGB(0, 255, 0)

						snapVisual.Color = color
						snapVisual.Position = targetPos
						snapVisual.Transparency = 0.2
					end

					-- Hover Sound
					if currentValidTargetKey ~= lastValidTargetKey then
						lastValidTargetKey = currentValidTargetKey
						local sound = Instance.new("Sound")
						sound.SoundId = "rbxassetid://4612375233" -- Click/Snap sound
						sound.Volume = 0.2
						sound.PlayOnRemove = true
						sound.Parent = Players.LocalPlayer.Character or Workspace
						sound:Destroy()
					end
				else
					if snapVisual then
						snapVisual.Transparency = 1
					end
					lastValidTargetKey = nil
				end
			end
		end)
	end
end

local function isAnyConflictingUIActive(): boolean
	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not PlayerGui then
		return false
	end

	local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
	if ActiveQueryFolder then
		local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
		if PlotBuilderEnabled and PlotBuilderEnabled:IsA("BoolValue") and PlotBuilderEnabled.Value then
			return true
		end

		local ResidentUIEnabled = ActiveQueryFolder:FindFirstChild("ResidentUIEnabled")
		if ResidentUIEnabled and ResidentUIEnabled:IsA("BoolValue") and ResidentUIEnabled.Value then
			return true
		end

		local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
		if PlotExpansionEnabled and PlotExpansionEnabled:IsA("BoolValue") and PlotExpansionEnabled.Value then
			return true
		end
	end

	local MainHUD = PlayerGui:FindFirstChild("MainHUD")
	if MainHUD then
		local BillFrame = MainHUD:FindFirstChild("BillFrame")
		if BillFrame and BillFrame:IsA("Frame") and BillFrame.Visible then
			return true
		end
	end

	local ReviewsUI = PlayerGui:FindFirstChild("ReviewsUI")
	if ReviewsUI and ReviewsUI:IsA("ScreenGui") and ReviewsUI.Enabled then
		return true
	end

	return false
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if isAnyConflictingUIActive() then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local hitObj, _ = raycast()
		if hitObj then
			local key = hitObj.Name
			local entry = PlotStateStore.GetPlacementEntry(key)
			if entry then
				local spec = ItemFinder.FindItemById(entry.id)
				if
					spec
					and (
						spec.PowerSource
						or spec.PowerConductor
						or spec.RequiresPower
						or spec.WaterSource
						or spec.WaterConductor
						or spec.RequiresWater
					)
				then
					potentialDrag = true
					dragStartPos = Vector2.new(input.Position.X, input.Position.Y)
					sourceKey = key
					sourceInstance = hitObj
					sourceSpec = spec
				end
			end
		end
	end
end

local function onInputChanged(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if potentialDrag and not isDragging and dragStartPos then
		if
			input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch
		then
			local delta = (
				Vector2.new(input.Position.X, input.Position.Y) - Vector2.new(dragStartPos.X, dragStartPos.Y)
			).Magnitude
			if delta > DRAG_THRESHOLD then
				potentialDrag = false
				startDragging()
			end
		end
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		potentialDrag = false
		dragStartPos = nil

		if isDragging then
			isDragging = false
			if dragConnection then
				dragConnection:Disconnect()
				dragConnection = nil
			end

			if currentValidTargetKey and currentValidTargetPos and sourceKey and sourceInstance then
				if areConnected(sourceKey, currentValidTargetKey) then
					-- Disconnect!
					Packets.DisconnectUtilityRequest:Fire({
						SourceKey = sourceKey,
						TargetKey = currentValidTargetKey,
					})

					-- Disconnect Feedback
					local sound = Instance.new("Sound")
					sound.SoundId = "rbxassetid://9119713951" -- Reuse chime but maybe pitch down?
					sound.PlaybackSpeed = 0.8
					sound.Volume = 0.5
					sound.PlayOnRemove = true
					sound.Parent = sourceInstance
					sound:Destroy()
				else
					-- Connect!
					Packets.ConnectUtilityRequest:Fire({
						SourceKey = sourceKey,
						TargetKey = currentValidTargetKey,
					})

					-- Success Feedback
					local sound = Instance.new("Sound")
					sound.SoundId = "rbxassetid://9119713951" -- Success chime
					sound.Volume = 0.5
					sound.PlayOnRemove = true
					sound.Parent = sourceInstance -- Play at source
					sound:Destroy()

					-- Particle Burst
					local att = Instance.new("Attachment")
					att.WorldPosition = currentValidTargetPos
					att.Parent = Workspace.Terrain

					local emitter = Instance.new("ParticleEmitter")
					emitter.Texture = "rbxassetid://13399338336" -- Bolt
					emitter.Size = NumberSequence.new(0.5)
					emitter.Lifetime = NumberRange.new(0.5)
					emitter.Rate = 0
					emitter.Speed = NumberRange.new(5)
					emitter.SpreadAngle = Vector2.new(180, 180)
					emitter.Parent = att
					emitter:Emit(10)

					task.delay(1, function()
						att:Destroy()
					end)
				end
			end

			destroyDragVisuals()
			sourceKey = nil
			sourceInstance = nil
			sourceSpec = nil
			currentValidTargetKey = nil
			currentValidTargetPos = nil
		else
			-- Clean up potential drag state if we just clicked without dragging
			sourceKey = nil
			sourceInstance = nil
			sourceSpec = nil
		end
	end
end

function WireController.Init()
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputChanged:Connect(onInputChanged)
	UserInputService.InputEnded:Connect(onInputEnded)
end

return WireController
