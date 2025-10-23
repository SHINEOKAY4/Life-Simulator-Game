--!strict
--[[
Camera Module Utility

This module provides a lightweight and reusable interface for controlling the
client‑side camera in Roblox experiences.  It encapsulates common camera
behaviours such as following a subject, offsetting the camera for side‑scrolling
or isometric perspectives, smoothly transitioning the field of view, and
applying simple camera shake effects.  The module is designed to be
stateless from a global perspective; each camera controller instance
maintains its own configuration without polluting the global namespace.  It
exposes a minimal API so that consumers only pay for what they use (YAGNI).

Example usage:

    local CameraUtils = require(path.to.camera_module)

    -- Create a camera controller that follows the local player's character
    local controller = CameraUtils.new({
        followSubject = game.Players.LocalPlayer.Character,
        offset = Vector3.new(0, 5, -12),
    })

    -- Start updating the camera each frame
    controller:start()

    -- Later, adjust the field of view smoothly
    controller:tweenFieldOfView(50, 1.0)

    -- Trigger a subtle camera shake
    controller:shake(0.5, 0.25, 8)

    -- When finished, stop the controller
    controller:stop()

This module uses `RunService:BindToRenderStep()` to update the camera
during the render step.  According to Roblox's documentation, the render step
executes every frame and can be used to synchronise the camera with the
player's actions:contentReference[oaicite:0]{index=0}.  It also leverages
`CFrame.lookAt()` to construct camera frames that look from one point to
another:contentReference[oaicite:1]{index=1}.  By using these APIs the module stays
compatible with the current (2025) Roblox engine.

Author: SHINE
License: MIT
]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

type FollowSubject = Model | BasePart
type CustomUpdateFunction = (deltaTime: number) -> (Vector3?, Vector3?)
type CameraSubject = BasePart | Humanoid
type FocusTarget = Model | BasePart | CFrame

type CameraConfig = {
	followSubject: FollowSubject?,
	offset: Vector3?,
	upVector: Vector3?,
	priority: number?,
	customUpdate: CustomUpdateFunction?,
}

type FocusOnOptions = {
	duration: number?,
	easingStyle: Enum.EasingStyle?,
	easingDirection: Enum.EasingDirection?,
	distance: number?,
	heightOffset: number?,
	offset: Vector3?,
	lookAtOffset: Vector3?,
	lookVector: Vector3?,
	restoreOnComplete: boolean?,
	cameraTypeOnComplete: Enum.CameraType?,
	cameraSubjectOnComplete: CameraSubject?,
	onComplete: (() -> ())?,
}

type CameraController = {
	camera: Camera,
	followSubject: FollowSubject?,
	offset: Vector3,
	upVector: Vector3?,
	priority: number,
	customUpdate: CustomUpdateFunction?,
	bindName: string,
	isRunning: boolean,
	shakeTotalDuration: number,
	shakeDurationRemaining: number,
	shakeMagnitude: number,
	shakeSpeed: number,
	shakeTime: number,
	_fovTween: Tween?,
}

local CameraUtils = {}
CameraUtils.__index = CameraUtils

local DEFAULT_FOCUS_DURATION_SECONDS = 0.75
local DEFAULT_FOCUS_DISTANCE_STUDS = 12
local DEFAULT_FOCUS_HEIGHT_STUDS = 5

local storedCameraState: { cameraType: Enum.CameraType, cameraSubject: CameraSubject? }? = nil
local activeFocusTween: Tween? = nil
local activeFocusIdentifier = 0

local function getCurrentCamera(): Camera?
	return workspace.CurrentCamera
end

local function castCameraSubject(instance: Instance?): CameraSubject?
	if instance and (instance:IsA("BasePart") or instance:IsA("Humanoid")) then
		return instance :: CameraSubject
	end
	return nil
end

local function resolveFocusFrame(target: FocusTarget, options: FocusOnOptions?): CFrame?
	if typeof(target) == "CFrame" then
		return target
	end
	local baseFrame: CFrame?
	local forwardVector: Vector3?
	if typeof(target) == "Instance" then
		if target:IsA("Model") then
			local pivot = target:GetPivot()
			baseFrame = pivot
			forwardVector = pivot.LookVector
		elseif target:IsA("BasePart") then
			local partCFrame = target.CFrame
			baseFrame = partCFrame
			forwardVector = partCFrame.LookVector
		else
			return nil
		end
	else
		return nil
	end
	if baseFrame == nil then
		return nil
	end
	local lookAtOffset = if options and options.lookAtOffset then options.lookAtOffset else Vector3.new()
	local focusPosition = baseFrame.Position + lookAtOffset
	local desiredForward = if options and options.lookVector
		then options.lookVector
		else (forwardVector or Vector3.new(0, 0, -1))
	if desiredForward.Magnitude == 0 then
		desiredForward = Vector3.new(0, 0, -1)
	end
	desiredForward = desiredForward.Unit
	local distance = if options and options.distance then options.distance else DEFAULT_FOCUS_DISTANCE_STUDS
	local heightOffset = if options and options.heightOffset then options.heightOffset else DEFAULT_FOCUS_HEIGHT_STUDS
	local positionOffset = if options and options.offset then options.offset else Vector3.new()
	local cameraPosition = focusPosition
		- (desiredForward * distance)
		+ Vector3.new(0, heightOffset, 0)
		+ positionOffset
	return CFrame.lookAt(cameraPosition, focusPosition)
end

-- Generates a unique identifier for the render step binding.  We use
-- os.clock() and math.random() to reduce the chance of collisions.
local function generateBindName(): string
	return string.format("CameraUtilsUpdate_%d_%d", os.time(), math.random(1, 1e6))
end

--[[
Creates a new camera controller.  The returned object holds configuration
and update logic for a single camera session.  It does not affect global
state outside of binding and unbinding to the render step.

Options:
• followSubject (Instance | nil): The instance the camera should follow.  Can
  be a Model, BasePart or any Instance that has a `PrimaryPart` or
  `HumanoidRootPart`.  If nil, the controller expects a custom update
  function to set the camera.
• offset (Vector3): Positional offset from the follow subject.  Defaults to
  Vector3.zero.
• upVector (Vector3 | nil): Optional custom up vector for CFrame.lookAt().
  If nil, Roblox chooses a reasonable default.
• priority (number | nil): Render priority for BindToRenderStep.  If nil,
  defaults to Enum.RenderPriority.Camera.Value + 1 so the update runs
  immediately after the default camera update:contentReference[oaicite:2]{index=2}.
• customUpdate (function | nil): A function(deltaTime: number)
  that returns (position: Vector3, lookAtTarget: Vector3).  When provided,
  this function overrides the default follow behaviour.
--]]
function CameraUtils.new(options: CameraConfig?): CameraController
	assert(RunService:IsClient(), "CameraUtils must be required from a client context")
	local config = (options or {}) :: CameraConfig
	local camera = workspace.CurrentCamera
	assert(camera, "CurrentCamera is not available")
	local cameraInstance = camera :: Camera

	local controllerData = {
		camera = cameraInstance,
		followSubject = config.followSubject,
		offset = config.offset or Vector3.new(),
		upVector = config.upVector,
		priority = config.priority or (Enum.RenderPriority.Camera.Value + 1),
		customUpdate = config.customUpdate,
		bindName = generateBindName(),
		isRunning = false,
		shakeTotalDuration = 0,
		shakeDurationRemaining = 0,
		shakeMagnitude = 0,
		shakeSpeed = 0,
		shakeTime = 0,
		_fovTween = nil,
	} :: CameraController

	setmetatable(controllerData :: any, CameraUtils)
	return controllerData
end

-- Resolves the follow target's primary part.  Accepts models or parts.  If
-- the subject is a model, tries HumanoidRootPart then PrimaryPart.  Returns
-- nil if no suitable part is found.
local function getRootPart(subject: FollowSubject?): BasePart?
	if subject == nil then
		return nil
	end
	if subject:IsA("BasePart") then
		return subject :: BasePart
	end
	if subject:IsA("Model") then
		-- HumanoidRootPart is common for characters:contentReference[oaicite:3]{index=3}
		local humanoidRootPart = subject:FindFirstChild("HumanoidRootPart")
		if humanoidRootPart and humanoidRootPart:IsA("BasePart") then
			return humanoidRootPart :: BasePart
		end
		-- Fallback to PrimaryPart
		local primaryPart = subject.PrimaryPart
		if primaryPart then
			return primaryPart
		end
	end
	return nil
end

-- Computes per‑frame camera position and target for default follow behaviour.
-- Returns two Vector3 values: cameraPosition and lookAtTarget.  When the
-- subject is not valid, returns nil.
function CameraUtils._computeFollow(self: CameraController, _deltaTime: number): (Vector3?, Vector3?)
	local subjectPart = getRootPart(self.followSubject)
	if subjectPart == nil then
		return nil, nil
	end
	-- Position the camera at the subject's position plus the configured offset.
	-- A height or depth component in the offset can create side‑scrolling or
	-- overhead perspectives:contentReference[oaicite:4]{index=4}.
	local desiredPosition = subjectPart.Position + self.offset
	local lookAtTarget = subjectPart.Position
	return desiredPosition, lookAtTarget
end

-- Applies camera shake to a given CFrame.  Uses a simple perlin‑like noise by
-- combining sine waves at different frequencies.  The effect decays over
-- time based on remaining duration.
function CameraUtils._applyShake(self: CameraController, cframe: CFrame, deltaTime: number): CFrame
	-- If no shake is active, return the original CFrame.
	if self.shakeDurationRemaining <= 0 or self.shakeTotalDuration <= 0 then
		return cframe
	end
	self.shakeTime = self.shakeTime + deltaTime
	-- Reduce remaining duration
	self.shakeDurationRemaining = math.max(0, self.shakeDurationRemaining - deltaTime)
	-- Progress decreases from 1 to 0 over the shake duration
	local progress = self.shakeDurationRemaining / self.shakeTotalDuration
	-- Compute offsets using sine waves at different frequencies to avoid
	-- repetitive patterns.  Multiply by magnitude and decay factor.
	local offsetX = math.sin(self.shakeTime * self.shakeSpeed * 1.1) * self.shakeMagnitude * progress
	local offsetY = math.sin(self.shakeTime * self.shakeSpeed * 2.3) * self.shakeMagnitude * progress
	local offsetZ = math.sin(self.shakeTime * self.shakeSpeed * 0.7) * self.shakeMagnitude * progress
	local offset = Vector3.new(offsetX, offsetY, offsetZ)
	return cframe * CFrame.new(offset)
end

-- Internal update called each render step.  Determines the desired camera frame
-- then applies optional shake and assigns the result to the Camera.CFrame.
function CameraUtils._update(self: CameraController, deltaTime: number)
	local cameraPosition: Vector3?
	local lookAtTarget: Vector3?
	if self.customUpdate then
		-- When a custom update function is supplied, call it.  It should
		-- return position and target.  If it returns nil then no update is
		-- applied this frame.
		local customPosition, customTarget = self.customUpdate(deltaTime)
		cameraPosition, lookAtTarget = customPosition, customTarget
	else
		cameraPosition, lookAtTarget = CameraUtils._computeFollow(self, deltaTime)
	end
	if cameraPosition and lookAtTarget then
		local newCFrame = CFrame.lookAt(cameraPosition, lookAtTarget, self.upVector)
		newCFrame = CameraUtils._applyShake(self, newCFrame, deltaTime)
		self.camera.CFrame = newCFrame
	end
end

-- Starts the render step binding.  While running, the camera will update
-- every frame.  Subsequent calls have no effect until `stop()` is called.
function CameraUtils.start(self: CameraController)
	if self.isRunning then
		return
	end
	self.isRunning = true
	RunService:BindToRenderStep(self.bindName, self.priority, function(deltaTime)
		CameraUtils._update(self, deltaTime)
	end)
end

-- Stops the render step binding and resets running state.  Any active
-- field of view tween continues to run unless cancelled separately.
function CameraUtils.stop(self: CameraController)
	if not self.isRunning then
		return
	end
	self.isRunning = false
	RunService:UnbindFromRenderStep(self.bindName)
end

-- Changes the instance that the camera follows.  Accepts a model or part.
function CameraUtils.setFollowSubject(self: CameraController, newSubject: FollowSubject?)
	self.followSubject = newSubject
end

-- Sets the positional offset relative to the follow subject.  Useful for
-- custom perspectives such as shoulder or side views.  Provide a Vector3.
function CameraUtils.setOffset(self: CameraController, newOffset: Vector3)
	assert(typeof(newOffset) == "Vector3", "Offset must be a Vector3")
	self.offset = newOffset
end

-- Sets a custom up vector for CFrame.lookAt().  When nil, Roblox chooses
-- the up direction automatically.  Only set this if you need to control
-- roll behaviour.
function CameraUtils.setUpVector(self: CameraController, newUpVector: Vector3?)
	if newUpVector ~= nil then
		assert(typeof(newUpVector) == "Vector3", "Up vector must be a Vector3 or nil")
	end
	self.upVector = newUpVector
end

-- Supplies a custom update function.  The provided function is invoked
-- every render step with deltaTime and should return (position, lookAtTarget).
-- Returning nil or invalid types skips updating the camera that frame.
function CameraUtils.setCustomUpdate(self: CameraController, customFunction: CustomUpdateFunction?)
	assert(customFunction == nil or typeof(customFunction) == "function", "Custom update must be a function or nil")
	self.customUpdate = customFunction
end

-- Immediately sets the camera's field of view.  Accepts a number in degrees.
function CameraUtils.setFieldOfView(self: CameraController, newFieldOfView: number)
	assert(type(newFieldOfView) == "number", "Field of view must be a number")
	self.camera.FieldOfView = newFieldOfView
end

-- Tweens the camera's field of view to a new value over the specified duration.
-- Optionally accepts easing style and direction.  Returns the created Tween.
function CameraUtils.tweenFieldOfView(
	self: CameraController,
	targetFieldOfView: number,
	duration: number,
	easingStyle: Enum.EasingStyle?,
	easingDirection: Enum.EasingDirection?
): Tween
	assert(type(targetFieldOfView) == "number", "Target field of view must be a number")
	assert(type(duration) == "number" and duration > 0, "Duration must be a positive number")
	-- Cancel any existing tween to avoid conflicts
	if self._fovTween then
		self._fovTween:Cancel()
		self._fovTween = nil
	end
	local info =
		TweenInfo.new(duration, easingStyle or Enum.EasingStyle.Sine, easingDirection or Enum.EasingDirection.Out)
	local tween = TweenService:Create(self.camera, info, { FieldOfView = targetFieldOfView })
	self._fovTween = tween
	tween:Play()
	-- Clean up reference when tween completes
	tween.Completed:Once(function()
		if self._fovTween == tween then
			self._fovTween = nil
		end
	end)
	return tween
end

-- Applies a camera shake effect.  Duration is in seconds, magnitude controls
-- the maximum positional offset in studs, and speed controls oscillation
-- frequency.  Higher magnitude and speed produce more intense shakes.
function CameraUtils.shake(self: CameraController, duration: number, magnitude: number, speed: number)
	assert(type(duration) == "number" and duration > 0, "Duration must be a positive number")
	assert(type(magnitude) == "number" and magnitude >= 0, "Magnitude must be non‑negative")
	assert(type(speed) == "number" and speed > 0, "Speed must be a positive number")
	self.shakeTotalDuration = duration
	self.shakeDurationRemaining = duration
	self.shakeMagnitude = magnitude
	self.shakeSpeed = speed
	self.shakeTime = 0
end

-- Convenience function that sets the player's camera mode.  Accepts
-- Enum.CameraMode.Classic or Enum.CameraMode.LockFirstPerson.  According to
-- Roblox's documentation, the `CameraMode` enum determines when first person
-- and third person cameras should be used:contentReference[oaicite:5]{index=5}.
function CameraUtils.setCameraMode(_controller: CameraController, cameraMode: Enum.CameraMode)
	local player = game.Players.LocalPlayer
	if not player then
		return
	end
	if cameraMode == Enum.CameraMode.Classic or cameraMode == Enum.CameraMode.LockFirstPerson then
		player.CameraMode = cameraMode
	else
		error("Unsupported camera mode: " .. tostring(cameraMode))
	end
end

-- Convenience method to enable first person view.  This sets the player's
-- CameraMode to LockFirstPerson and optionally adjusts the field of view.
function CameraUtils.enableFirstPerson(self: CameraController, optionalFieldOfView: number?)
	CameraUtils.setCameraMode(self, Enum.CameraMode.LockFirstPerson)
	if optionalFieldOfView then
		CameraUtils.setFieldOfView(self, optionalFieldOfView)
	end
end

-- Convenience method to enable third person view.  This sets the player's
-- CameraMode back to Classic and optionally adjusts the zoom distances on
-- the player so they cannot zoom inside the character.  Useful for
-- toggling between first and third person perspectives.
function CameraUtils.enableThirdPerson(
	self: CameraController,
	minimumZoomDistance: number?,
	maximumZoomDistance: number?
)
	CameraUtils.setCameraMode(self, Enum.CameraMode.Classic)
	local player = game.Players.LocalPlayer
	if player then
		if type(minimumZoomDistance) == "number" then
			player.CameraMinZoomDistance = minimumZoomDistance
		end
		if type(maximumZoomDistance) == "number" then
			player.CameraMaxZoomDistance = maximumZoomDistance
		end
	end
end

function CameraUtils.RestoreCamera(expectedFocusIdentifier: number?)
	if expectedFocusIdentifier ~= nil and expectedFocusIdentifier ~= activeFocusIdentifier then
		return
	end
	local camera = getCurrentCamera()
	if activeFocusTween then
		activeFocusTween:Cancel()
		activeFocusTween = nil
	end
	if not camera then
		storedCameraState = nil
		return
	end
	if storedCameraState then
		camera.CameraType = storedCameraState.cameraType
		camera.CameraSubject = storedCameraState.cameraSubject
	else
		camera.CameraType = Enum.CameraType.Custom
	end
	storedCameraState = nil
end

function CameraUtils.CancelFocus()
	activeFocusIdentifier += 1
	CameraUtils.RestoreCamera(nil)
end

function CameraUtils.FocusOn(target: FocusTarget, options: FocusOnOptions?): Tween?
	local camera = getCurrentCamera()
	if not camera then
		return nil
	end
	local targetFrame = resolveFocusFrame(target, options)
	if not targetFrame then
		return nil
	end
	activeFocusIdentifier += 1
	local focusIdentifier = activeFocusIdentifier
	if activeFocusTween then
		activeFocusTween:Cancel()
		activeFocusTween = nil
	end
	if storedCameraState == nil then
		storedCameraState = {
			cameraType = camera.CameraType,
			cameraSubject = castCameraSubject(camera.CameraSubject),
		}
	end
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CameraSubject = nil
	local duration = if options and options.duration then options.duration else DEFAULT_FOCUS_DURATION_SECONDS
	local easingStyle = if options and options.easingStyle then options.easingStyle else Enum.EasingStyle.Sine
	local easingDirection = if options and options.easingDirection
		then options.easingDirection
		else Enum.EasingDirection.InOut
	local tweenInfo = TweenInfo.new(duration, easingStyle, easingDirection)
	local tween = TweenService:Create(camera, tweenInfo, { CFrame = targetFrame })
	activeFocusTween = tween
	tween.Completed:Once(function()
		if activeFocusIdentifier ~= focusIdentifier then
			return
		end
		activeFocusTween = nil
		local shouldRestore = true
		if options and options.restoreOnComplete ~= nil then
			shouldRestore = options.restoreOnComplete
		end
		if shouldRestore then
			CameraUtils.RestoreCamera(focusIdentifier)
		else
			local cameraAfterTween = getCurrentCamera()
			if cameraAfterTween then
				cameraAfterTween.CameraType = if options and options.cameraTypeOnComplete
					then options.cameraTypeOnComplete
					else Enum.CameraType.Custom
				if options and options.cameraSubjectOnComplete ~= nil then
					local newSubject = castCameraSubject(options.cameraSubjectOnComplete)
					if newSubject then
						cameraAfterTween.CameraSubject = newSubject
					end
				end
			end
		end
		if options and options.onComplete then
			options.onComplete()
		end
	end)
	tween:Play()
	return tween
end

return CameraUtils
