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

local dragBeam: Beam? = nil
local dragAtt0: Attachment? = nil
local dragAtt1: Attachment? = nil
local dragConnection: RBXScriptConnection? = nil
local snapVisual: BasePart? = nil
local lastValidTargetKey: string? = nil

local currentValidTargetKey: string? = nil
local currentValidTargetPos: Vector3? = nil

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

local function createDragVisuals(startPos: Vector3)
	local terrain = Workspace.Terrain

	local att0 = Instance.new("Attachment")
	att0.WorldPosition = startPos
	att0.Parent = terrain

	local att1 = Instance.new("Attachment")
	att1.WorldPosition = startPos
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

	dragBeam = beam
	dragAtt0 = att0
	dragAtt1 = att1
	snapVisual = snap
end

local function destroyDragVisuals()
	UtilityVisuals.SetForceShow(false)
	if dragBeam then
		dragBeam:Destroy()
	end
	if dragAtt0 then
		dragAtt0:Destroy()
	end
	if dragAtt1 then
		dragAtt1:Destroy()
	end
	if snapVisual then
		snapVisual:Destroy()
	end
	dragBeam = nil
	dragAtt0 = nil
	dragAtt1 = nil
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

			if targetObj and targetObj ~= sourceInstance and sourceSpec and dragAtt0 then
				local tKey = targetObj.Name
				local tEntry = PlotStateStore.GetPlacementEntry(tKey)
				if tEntry then
					local tSpec = ItemFinder.FindItemById(tEntry.id)
					if tSpec then
						local isPower = (sourceSpec.PowerSource or sourceSpec.PowerConductor)
							and (tSpec.PowerConductor or tSpec.PowerSource)
						local isWater = (sourceSpec.WaterSource or sourceSpec.WaterConductor)
							and (tSpec.WaterConductor or tSpec.WaterSource)

						if isPower or isWater then
							-- Check radius
							local r1 = sourceSpec.ConnectionRadius or 20 -- Default fallback
							local r2 = tSpec.ConnectionRadius or 20
							local maxR = math.max(r1, r2)

							-- Snap to target attachment
							local snapPos = getWireAttachmentPosition(targetObj, tSpec)
							local dist = (dragAtt0.WorldPosition - snapPos).Magnitude

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

			if dragAtt1 then
				dragAtt1.WorldPosition = targetPos
			end

			if dragBeam then
				if isValid then
					if isDisconnect then
						dragBeam.Color = ColorSequence.new(Color3.fromRGB(255, 50, 50)) -- Red for disconnect
						if snapVisual then
							snapVisual.Color = Color3.fromRGB(255, 50, 50)
							snapVisual.Position = targetPos
							snapVisual.Transparency = 0.2
						end
					else
						-- Determine color based on type
						local isWater = sourceSpec and (sourceSpec.WaterSource or sourceSpec.WaterConductor)
						local color = if isWater then Color3.fromRGB(0, 150, 255) else Color3.fromRGB(0, 255, 0)

						dragBeam.Color = ColorSequence.new(color)
						if snapVisual then
							snapVisual.Color = color
							snapVisual.Position = targetPos
							snapVisual.Transparency = 0.2
						end
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
					dragBeam.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255)) -- White/Default
					if snapVisual then
						snapVisual.Transparency = 1
					end
					lastValidTargetKey = nil
				end
			end
		end)
	end
end

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		local hitObj, _ = raycast()
		if hitObj then
			local key = hitObj.Name
			local entry = PlotStateStore.GetPlacementEntry(key)
			if entry then
				local spec = ItemFinder.FindItemById(entry.id)
				if spec and (spec.PowerSource or spec.PowerConductor or spec.WaterSource or spec.WaterConductor) then
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
