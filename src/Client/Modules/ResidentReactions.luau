--!strict
-- Client/Modules/ResidentReactions.luau
-- Handles procedural animations and reactions for residents based on environment.

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
		-- TODO: Play shiver animation
	elseif tempF > 85 then
		state.CurrentMood = "Hot"
		-- TODO: Play wipe brow animation
	else
		if state.CurrentMood == "Cold" or state.CurrentMood == "Hot" then
			state.CurrentMood = "Neutral"
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
	States[model] = {
		LastTempCheck = 0,
		LastTrashCheck = 0,
		CurrentMood = "Neutral",
		LookTarget = nil,
		LookWeight = 0,
	}
end

function ResidentReactions.Unregister(model: Model)
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
