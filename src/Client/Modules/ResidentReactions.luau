--!strict
-- Client/Modules/ResidentReactions.luau
-- Handles procedural animations and reactions for residents based on environment.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TemperatureController = require(script.Parent.TemperatureController)
local ChoreController = require(script.Parent.ChoreController)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local InsulationConstants = require(ReplicatedStorage.Shared.Configurations.InsulationConstants)

local ResidentReactions = {}

type ReactionState = {
	LastTempCheck: number,
	LastTrashCheck: number,
	CurrentMood: "Neutral" | "Cold" | "Hot" | "Disgusted",
	LookTarget: Vector3?,
	LookWeight: number,
	ShiverTween: Tween?,
	HeatSwayTween: Tween?,
	WaistMotor: Motor6D?,
	WaistOriginalC0: CFrame?,
	ActiveWeatherAnim: "None" | "Shiver" | "HeatSway",
}

local States: { [Model]: ReactionState } = {}

local HEAD_TURN_SPEED = 5
local MAX_LOOK_ANGLE = math.rad(70)
local TRASH_DETECT_RADIUS = 8

-- Helper to get neck motor
local function getNeck(model: Model): Motor6D?
	local head = model:FindFirstChild("Head")
	if head then
		return head:FindFirstChild("Neck") :: Motor6D
	end
	return nil
end

local function getRoot(model: Model): BasePart?
	return model:FindFirstChild("HumanoidRootPart") :: BasePart
end

-- Locate the Waist Motor6D in either R15 (UpperTorso.Waist) or R6 (Torso.Root Joint) rigs
local function getWaistMotor(model: Model): Motor6D?
	local upperTorso = model:FindFirstChild("UpperTorso")
	if upperTorso then
		local waist = upperTorso:FindFirstChild("Waist")
		if waist and waist:IsA("Motor6D") then
			return waist :: Motor6D
		end
	end
	-- R6 fallback: Torso contains a Motor6D called "Root Joint"
	local torso = model:FindFirstChild("Torso")
	if torso then
		local rootJoint = torso:FindFirstChild("Root Joint")
		if rootJoint and rootJoint:IsA("Motor6D") then
			return rootJoint :: Motor6D
		end
	end
	return nil
end

-- Ensure waist motor reference is cached on the state
local function ensureWaistMotor(model: Model, state: ReactionState)
	if state.WaistMotor and state.WaistMotor.Parent then
		return -- already valid
	end
	local motor = getWaistMotor(model)
	if motor then
		state.WaistMotor = motor
		state.WaistOriginalC0 = motor.C0
	else
		state.WaistMotor = nil
		state.WaistOriginalC0 = nil
	end
end

-- Stop any active weather animation tweens and restore the waist to its original C0
local function stopWeatherAnimation(state: ReactionState)
	if state.ShiverTween then
		state.ShiverTween:Cancel()
		state.ShiverTween = nil
	end
	if state.HeatSwayTween then
		state.HeatSwayTween:Cancel()
		state.HeatSwayTween = nil
	end
	-- Restore waist to original pose (direct assignment; the next frame's head-tracking
	-- lerp will smooth it out visually)
	if state.WaistMotor and state.WaistOriginalC0 then
		local motor = state.WaistMotor
		if motor.Parent then
			motor.C0 = state.WaistOriginalC0
		end
	end
	state.ActiveWeatherAnim = "None"
end

-- Create a looping shiver tween: rapid small oscillation on the waist joint
local function startShiverAnimation(state: ReactionState)
	if state.ActiveWeatherAnim == "Shiver" then
		return -- already shivering
	end
	stopWeatherAnimation(state)

	local motor = state.WaistMotor
	local originalC0 = state.WaistOriginalC0
	if not motor or not originalC0 or not motor.Parent then
		return
	end

	-- Shiver: quick oscillation +-2 degrees on Z axis with slight X tremor
	local shiverAngleZ = math.rad(2.0)
	local shiverAngleX = math.rad(0.8)
	local shiverTarget = originalC0 * CFrame.Angles(shiverAngleX, 0, shiverAngleZ)
	local shiverInfo = TweenInfo.new(
		0.12, -- very fast
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1, -- repeat forever
		true, -- reverses
		0 -- no delay
	)

	-- We need a CFrameValue proxy because Motor6D.C0 is not directly tweenable
	local proxy = Instance.new("CFrameValue")
	proxy.Name = "ShiverProxy"
	proxy.Value = originalC0
	proxy.Parent = motor.Parent

	proxy.Changed:Connect(function()
		if motor.Parent then
			motor.C0 = proxy.Value
		end
	end)

	local tween = TweenService:Create(proxy, shiverInfo, { Value = shiverTarget })
	tween:Play()

	-- Store reference so we can cancel later
	state.ShiverTween = tween
	state.ActiveWeatherAnim = "Shiver"

	-- Clean up proxy when tween is cancelled
	tween.Completed:Connect(function()
		proxy:Destroy()
	end)
end

-- Create a looping slow sway tween: sluggish heat-exhaustion movement on waist
local function startHeatSwayAnimation(state: ReactionState)
	if state.ActiveWeatherAnim == "HeatSway" then
		return -- already swaying
	end
	stopWeatherAnimation(state)

	local motor = state.WaistMotor
	local originalC0 = state.WaistOriginalC0
	if not motor or not originalC0 or not motor.Parent then
		return
	end

	-- Heat exhaustion: slow droop forward + gentle side sway
	local droopAngleX = math.rad(4.0) -- lean forward slightly
	local swayAngleZ = math.rad(2.5) -- side sway
	local swayTarget = originalC0 * CFrame.Angles(droopAngleX, 0, swayAngleZ)
	local swayInfo = TweenInfo.new(
		1.2, -- slow, lethargic
		Enum.EasingStyle.Sine,
		Enum.EasingDirection.InOut,
		-1, -- repeat forever
		true, -- reverses
		0 -- no delay
	)

	local proxy = Instance.new("CFrameValue")
	proxy.Name = "HeatSwayProxy"
	proxy.Value = originalC0
	proxy.Parent = motor.Parent

	proxy.Changed:Connect(function()
		if motor.Parent then
			motor.C0 = proxy.Value
		end
	end)

	local tween = TweenService:Create(proxy, swayInfo, { Value = swayTarget })
	tween:Play()

	state.HeatSwayTween = tween
	state.ActiveWeatherAnim = "HeatSway"

	tween.Completed:Connect(function()
		proxy:Destroy()
	end)
end

local function updateTemperatureReaction(model: Model, state: ReactionState)
	local root = getRoot(model)
	if not root then
		return
	end

	local grid = PlotStateStore.GetGrid()
	if not grid then
		return
	end

	local inBounds, cx, cz = grid:WorldPointToCell(root.Position)
	if not inBounds then
		return
	end

	local originY = grid.OriginTopCFrame.Position.Y
	local relY = root.Position.Y - originY
	local floorHeight = PlotStateStore.GetFloorHeightStuds()
	local level = math.floor(relY / floorHeight + 0.5)
	if level < 0 then
		level = 0
	end

	local roomId = PlotStateStore.GetRoomIdAtCell(level, cx, cz)
	local temp = nil

	if roomId then
		temp = TemperatureController.GetTemperature(level, roomId)
	else
		temp = InsulationConstants.AmbientTemperature
	end

	if not temp then
		return
	end

	local tempF = (temp * 9 / 5) + 32

	if tempF < 55 then
		state.CurrentMood = "Cold"
		ensureWaistMotor(model, state)
		startShiverAnimation(state)
	elseif tempF > 85 then
		state.CurrentMood = "Hot"
		ensureWaistMotor(model, state)
		startHeatSwayAnimation(state)
	else
		if state.CurrentMood == "Cold" or state.CurrentMood == "Hot" then
			state.CurrentMood = "Neutral"
			stopWeatherAnimation(state)
		end
	end
end

local function updateTrashReaction(model: Model, state: ReactionState)
	local root = getRoot(model)
	if not root then
		return
	end

	local chores = ChoreController.GetNearbyChores(root.Position, TRASH_DETECT_RADIUS)
	if #chores > 0 then
		state.CurrentMood = "Disgusted"
		-- Look at the closest trash
		state.LookTarget = chores[1].Position
	else
		if state.CurrentMood == "Disgusted" then
			state.CurrentMood = "Neutral"
		end
		state.LookTarget = nil
	end
end

local function updateHeadTracking(model: Model, state: ReactionState, dt: number)
	local neck = getNeck(model)
	local root = getRoot(model)
	if not neck or not root then
		return
	end

	local targetLook = state.LookTarget

	-- If no specific target, maybe look at other residents?
	-- (Optimization: Don't scan every frame)

	local desiredAngleY = 0
	local desiredAngleX = 0

	if targetLook then
		local part0 = neck.Part0
		if not part0 then
			return
		end
		-- Calculate relative angles
		local relative = root.CFrame:PointToObjectSpace(targetLook)
		local angleY = math.atan2(-relative.X, -relative.Z) -- Yaw
		local angleX = math.atan2(relative.Y, -relative.Z) -- Pitch

		-- Clamp
		if math.abs(angleY) < MAX_LOOK_ANGLE then
			desiredAngleY = angleY
			desiredAngleX = math.clamp(angleX, -0.5, 0.5)
			state.LookWeight = math.min(state.LookWeight + dt * 2, 1)
		else
			state.LookWeight = math.max(state.LookWeight - dt * 2, 0)
		end
	else
		state.LookWeight = math.max(state.LookWeight - dt * 2, 0)
	end

	-- Interpolate Neck C0
	-- Default C0 is usually CFrame.new(0, Y, 0)
	-- We want to rotate it.
	-- Note: R15 Neck C0 is usually CFrame.new(0, 0.8, 0) or similar.
	-- We should read the OriginalC0 if we want to be safe, but for now we assume standard R15/R6 rig.
	-- Actually, let's just apply rotation on top of current C0 if we assume it's static,
	-- OR better: store original C0.

	local originalC0 = neck:GetAttribute("OriginalC0")
	if typeof(originalC0) ~= "CFrame" then
		originalC0 = neck.C0
		neck:SetAttribute("OriginalC0", originalC0)
	end
	local baseC0 = originalC0 :: CFrame

	if state.LookWeight > 0 then
		local currentC0 = neck.C0
		local targetCFrame = baseC0
			* CFrame.Angles(desiredAngleX * state.LookWeight, desiredAngleY * state.LookWeight, 0)
		neck.C0 = currentC0:Lerp(targetCFrame, dt * HEAD_TURN_SPEED)
	else
		neck.C0 = neck.C0:Lerp(baseC0, dt * HEAD_TURN_SPEED)
	end
end

function ResidentReactions.Register(model: Model)
	local state: ReactionState = {
		LastTempCheck = 0,
		LastTrashCheck = 0,
		CurrentMood = "Neutral",
		LookTarget = nil,
		LookWeight = 0,
		ShiverTween = nil,
		HeatSwayTween = nil,
		WaistMotor = nil,
		WaistOriginalC0 = nil,
		ActiveWeatherAnim = "None",
	}
	States[model] = state
end

function ResidentReactions.Unregister(model: Model)
	local state = States[model]
	if state then
		stopWeatherAnimation(state)
	end
	States[model] = nil
end

function ResidentReactions.Update(model: Model, dt: number)
	local state = States[model]
	if not state then
		return
	end

	local now = os.clock()

	-- 1. Check Temperature (Low frequency)
	if now - state.LastTempCheck > 1.0 then
		state.LastTempCheck = now
		updateTemperatureReaction(model, state)
	end

	-- 2. Check Trash (Medium frequency)
	if now - state.LastTrashCheck > 0.5 then
		state.LastTrashCheck = now
		updateTrashReaction(model, state)
	end

	-- 3. Head Tracking (Every frame)
	updateHeadTracking(model, state, dt)

	-- 4. Visual Feedback (Emotes/Particles)
	-- If mood changed, maybe show a bubble?
	-- For now, we rely on head tracking (looking at trash) and maybe simple particles later.
end

return ResidentReactions
