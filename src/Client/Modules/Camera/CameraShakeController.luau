--!strict
-- Local camera shake helper using Humanoid.CameraOffset.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraShakeController = {}
CameraShakeController.__index = CameraShakeController

export type Config = {
	Player: Player?,
	MaxOffset: Vector3?,
	Frequency: number?,
	DecayPerSecond: number?,
	MaxMagnitude: number?,
}

export type Controller = {
	Kick: (self: Controller, strength: number) -> (),
	ImpulseAtPosition: (self: Controller, worldPosition: Vector3, baseStrength: number, maxDistance: number) -> (),
	Reset: (self: Controller) -> (),
	Destroy: (self: Controller) -> (),
}

type Private = {
	_player: Player,
	_maxOffset: Vector3,
	_frequency: number,
	_decayPerSecond: number,
	_maxMagnitude: number,
	_renderConnection: RBXScriptConnection?,
	_currentMagnitude: number,
	_noiseTime: number,
	_lastOffset: Vector3,
}

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	if not character then
		return nil
	end
	return character:FindFirstChildOfClass("Humanoid")
end

local function applyOffset(self: Private, offset: Vector3)
	local humanoid = getHumanoid(self._player)
	if not humanoid then
		return
	end

	local baseOffset = humanoid.CameraOffset - self._lastOffset
	local newOffset = baseOffset + offset

	humanoid.CameraOffset = newOffset
	self._lastOffset = offset
end

local function stopRender(self: Private)
	local connection = self._renderConnection
	if connection then
		connection:Disconnect()
		self._renderConnection = nil
	end
	if self._lastOffset.Magnitude > 0 then
		applyOffset(self, Vector3.zero)
	end
	self._lastOffset = Vector3.zero
end

local function startRender(self: Private)
	if self._renderConnection then
		return
	end

	self._renderConnection = RunService.RenderStepped:Connect(function(deltaTime: number)
		self._currentMagnitude *= math.exp(-self._decayPerSecond * deltaTime)
		if self._currentMagnitude < 0.01 then
			self._currentMagnitude = 0
		end

		if self._currentMagnitude <= 0 then
			stopRender(self)
			return
		end

		self._noiseTime += deltaTime * self._frequency

		local noiseX = math.noise(self._noiseTime, 0, 0)
		local noiseY = math.noise(0, self._noiseTime, 0)
		local noiseZ = math.noise(0, 0, self._noiseTime)

		local targetOffset = Vector3.new(
			noiseX * self._maxOffset.X,
			noiseY * self._maxOffset.Y,
			noiseZ * self._maxOffset.Z
		) * math.clamp(self._currentMagnitude, 0, self._maxMagnitude)

		applyOffset(self, targetOffset)
	end)
end

local function addMagnitude(self: Private, strength: number)
	if strength <= 0 then
		return
	end
	self._currentMagnitude = math.clamp(self._currentMagnitude + strength, 0, self._maxMagnitude)
	if not self._renderConnection then
		startRender(self)
	end
end

function CameraShakeController.new(config: Config?): Controller
	local resolvedPlayer = if config and config.Player then config.Player else Players.LocalPlayer
	local maxOffset = if config and config.MaxOffset then config.MaxOffset else Vector3.new(1, 1, 1)
	local frequency = if config and config.Frequency then config.Frequency else 13
	local decayPerSecond = if config and config.DecayPerSecond then config.DecayPerSecond else 3
	local maxMagnitude = if config and config.MaxMagnitude then config.MaxMagnitude else 2

	local self = setmetatable({
		_player = resolvedPlayer,
		_maxOffset = maxOffset,
		_frequency = frequency,
		_decayPerSecond = decayPerSecond,
		_maxMagnitude = maxMagnitude,
		_renderConnection = nil,
		_currentMagnitude = 0,
		_noiseTime = 0,
		_lastOffset = Vector3.zero,
	}, CameraShakeController) :: any
	return self
end

function CameraShakeController:Kick(strength: number)
	addMagnitude(self :: Private, strength)
end

function CameraShakeController:ImpulseAtPosition(worldPosition: Vector3, baseStrength: number, maxDistance: number)
	local privateSelf = self :: Private
	local character = privateSelf._player.Character
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not rootPart or not rootPart:IsA("BasePart") then
		return
	end

	local distance = (rootPart.Position - worldPosition).Magnitude
	if distance > maxDistance then
		return
	end

	local distanceAlpha = 1 - math.clamp(distance / maxDistance, 0, 1)
	addMagnitude(privateSelf, baseStrength * distanceAlpha)
end

function CameraShakeController:Reset()
	local privateSelf = self :: Private
	privateSelf._currentMagnitude = 0
	privateSelf._noiseTime = 0
	stopRender(privateSelf)
end

function CameraShakeController:Destroy()
	self:Reset()
end

return CameraShakeController
