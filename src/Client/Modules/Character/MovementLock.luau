--!strict
-- Utility for temporarily locking local player movement during interactive sequences.

local Players = game:GetService("Players")

local MovementLock = {}
MovementLock.__index = MovementLock

export type Options = {
	FacePosition: Vector3?,
}

export type MovementLockController = {
	Acquire: (self: MovementLockController, key: string, options: Options?) -> boolean,
	Release: (self: MovementLockController, key: string?) -> (),
	Reset: (self: MovementLockController) -> (),
}

type InternalState = {
	Key: string,
	WalkSpeed: number?,
	JumpPower: number?,
	AutoRotate: boolean?,
	AutoJumpEnabled: boolean?,
}

type Private = {
	_player: Player,
	_state: InternalState?,
}

local function getCharacterComponents(player: Player): (Model?, Humanoid?, BasePart?)
	local character = player.Character
	if not character then
		return nil, nil, nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return character, nil, nil
	end
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		return character, humanoid, rootPart :: BasePart
	end
	return character, humanoid, nil
end

local function facePosition(rootPart: BasePart?, targetPosition: Vector3?)
	if not rootPart or not targetPosition then
		return
	end

	local origin = rootPart.Position
	local lookTarget = Vector3.new(targetPosition.X, origin.Y, targetPosition.Z)
	if (lookTarget - origin).Magnitude < 0.05 then
		return
	end

	rootPart.CFrame = CFrame.lookAt(origin, lookTarget)
	rootPart.AssemblyLinearVelocity = Vector3.zero
	rootPart.AssemblyAngularVelocity = Vector3.zero
end

function MovementLock.new(player: Player?): MovementLockController
	local resolvedPlayer = player or Players.LocalPlayer
	local self = setmetatable({
		_player = resolvedPlayer,
		_state = nil,
	}, MovementLock) :: any
	return self
end

function MovementLock:Acquire(key: string, options: Options?): boolean
	local selfPrivate = self :: Private
	if key == "" then
		return false
	end

	local state = selfPrivate._state
	local _, humanoid, rootPart = getCharacterComponents(selfPrivate._player)
	if not humanoid or not rootPart then
		return false
	end

	if state and state.Key == key then
		facePosition(rootPart, options and options.FacePosition)
		return true
	end

	if state then
		self:Release()
	end

	selfPrivate._state = {
		Key = key,
		WalkSpeed = humanoid.WalkSpeed,
		JumpPower = humanoid.JumpPower,
		AutoRotate = humanoid.AutoRotate,
		AutoJumpEnabled = selfPrivate._player.AutoJumpEnabled,
	}

	humanoid.WalkSpeed = 0
	humanoid.JumpPower = 0
	humanoid.AutoRotate = false
	selfPrivate._player.AutoJumpEnabled = false
	humanoid:Move(Vector3.zero)

	facePosition(rootPart, options and options.FacePosition)
	return true
end

function MovementLock:Release(key: string?)
	local selfPrivate = self :: Private
	local state = selfPrivate._state
	if not state then
		return
	end
	if key and state.Key ~= key then
		return
	end

	local _, humanoid, _ = getCharacterComponents(selfPrivate._player)
	if humanoid then
		if typeof(state.WalkSpeed) == "number" then
			humanoid.WalkSpeed = state.WalkSpeed
		end
		if typeof(state.JumpPower) == "number" then
			humanoid.JumpPower = state.JumpPower
		end
		humanoid.AutoRotate = (typeof(state.AutoRotate) == "boolean") and state.AutoRotate or true
		humanoid:Move(Vector3.zero)
	end

	selfPrivate._player.AutoJumpEnabled = (typeof(state.AutoJumpEnabled) == "boolean") and state.AutoJumpEnabled or true
	selfPrivate._state = nil
end

function MovementLock:Reset()
	self:Release()
end

return MovementLock
