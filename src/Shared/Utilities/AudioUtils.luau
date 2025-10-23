--!strict
--[[
    AudioUtility

    A small utility module for working with Roblox's modern audio API.  This module
    exposes a function for setting up a listener on the camera and a factory
    function for constructing and controlling `AudioPlayer`/`AudioEmitter` pairs.  It
    emphasises clear type annotations, minimal state and predictable behaviour.

    This module does not automatically create global listeners.  Call
    `AudioUtility.setupListener()` once per client to initialise an `AudioListener`
    and associated `AudioDeviceOutput` on the current camera before creating
    players.  Keeping listener setup separate makes the module stateless; it
    doesn't persist internal singletons across calls.

    Each audio wrapper returned by `AudioUtility.createPlayer()` manages its own
    `AudioPlayer`, `AudioEmitter` and the chain of `Wire` objects connecting them.
    Effects (such as `AudioLimiter`, `AudioEcho` or `AudioTremolo`) can be
    dynamically inserted into the signal path with `addEffect()`.  Effects are
    always appended to the end of the chain and can be cleared with
    `clearEffects()`.

    Example usage:

        local AudioUtility = require(path.to.AudioUtility)

        -- Set up a listener on the camera once on the client
        AudioUtility.setupListener()

        -- Create a new audio player attached to a part in the workspace
        local wrapper = AudioUtility.createPlayer("rbxassetid://1841647093", workspace)
        wrapper:setVolume(0.5)
        wrapper:play()

        -- Add an echo effect with custom parameters
        wrapper:addEffect("AudioEcho", {
            DelayTime = 0.25,
            Feedback = 0.6,
            DryLevel = 1,
            WetLevel = 0.5,
        })

        -- Connect to the ended event
        wrapper:onEnded(function()
            print("Audio finished!")
        end)

    Author: SHINE
    License: MIT
]]

local Workspace = game:GetService("Workspace")

-- type aliases for strict mode.
type AudioPlayer = typeof(Instance.new("AudioPlayer"))
type AudioEmitter = typeof(Instance.new("AudioEmitter"))
type AudioListener = typeof(Instance.new("AudioListener"))
type AudioDeviceOutput = typeof(Instance.new("AudioDeviceOutput"))
type AudioEffectInstance = Instance
type Wire = typeof(Instance.new("Wire"))
type RBXScriptConnection = typeof((Instance.new("BindableEvent")).Event:Connect(function() end))

-- Public wrapper type: encapsulates a player/emitter pair.
export type AudioWrapper = {
	player: AudioPlayer,
	emitter: AudioEmitter,
	play: (self: AudioWrapper) -> (),
	pause: (self: AudioWrapper) -> (),
	resume: (self: AudioWrapper) -> (),
	stop: (self: AudioWrapper) -> (),
	setVolume: (self: AudioWrapper, volume: number) -> (),
	setPlaybackSpeed: (self: AudioWrapper, speed: number) -> (),
	setLooping: (self: AudioWrapper, looping: boolean) -> (),
	addEffect: (
		self: AudioWrapper,
		effectClassName: string,
		effectProperties: { [string]: any }?
	) -> AudioEffectInstance,
	clearEffects: (self: AudioWrapper) -> (),
	onEnded: (self: AudioWrapper, callback: () -> ()) -> RBXScriptConnection,
	onLooped: (self: AudioWrapper, callback: () -> ()) -> RBXScriptConnection,
	destroy: (self: AudioWrapper) -> (),
	_private: any,
}

local AudioUtility = {}

-- Create a listener and device output on the current camera if none exist.
function AudioUtility.setupListener(camera: Camera?)
	local currentCamera: Camera = camera or Workspace.CurrentCamera
	if not currentCamera then
		error("AudioUtility.setupListener: Workspace.CurrentCamera is nil. Call after camera has been created.")
	end

	local existingListener = currentCamera:FindFirstChildOfClass("AudioListener")
	local existingOutput = currentCamera:FindFirstChildOfClass("AudioDeviceOutput")
	if existingListener and existingOutput then
		return existingListener :: AudioListener, existingOutput :: AudioDeviceOutput
	end

	local listener: AudioListener = Instance.new("AudioListener")
	listener.Name = "CameraAudioListener"
	listener.Parent = currentCamera

	local output: AudioDeviceOutput = Instance.new("AudioDeviceOutput")
	output.Name = "CameraAudioDeviceOutput"
	output.Parent = currentCamera

	-- Wire the listener to the output so audio can be heard.
	local wire: Wire = Instance.new("Wire")
	wire.Name = "ListenerWire"
	wire.SourceInstance = listener
	wire.TargetInstance = output
	wire.Parent = currentCamera

	return listener, output
end

-- Internal structure for tracking effect nodes.
type EffectRecord = {
	node: AudioEffectInstance,
	inputWire: Wire,
	outputWire: Wire,
}

-- Create and return an audio wrapper.
function AudioUtility.createPlayer(assetId: string, parent: Instance?, emitterParent: Instance?): AudioWrapper
	if typeof(assetId) ~= "string" then
		error("AudioUtility.createPlayer: assetId must be a string")
	end

	local playerParent: Instance = parent or Workspace
	local emitterParentActual: Instance = emitterParent or parent or Workspace

	-- Create the AudioPlayer and assign the asset id.
	local audioPlayer: AudioPlayer = Instance.new("AudioPlayer")
	audioPlayer.Name = "AudioPlayer"
	local ok: boolean = pcall(function()
		(audioPlayer :: any).Asset = assetId
	end)
	if not ok then
		(audioPlayer :: any).AssetId = assetId
	end
	audioPlayer.Parent = playerParent

	-- Create the AudioEmitter.
	local emitter: AudioEmitter = Instance.new("AudioEmitter")
	emitter.Name = "AudioEmitter"
	emitter.Parent = emitterParentActual

	-- Wire player -> emitter.
	local wire: Wire = Instance.new("Wire")
	wire.Name = "AudioWire"
	wire.SourceInstance = audioPlayer
	wire.TargetInstance = emitter
	wire.Parent = emitter

	-- Internal state.
	local effects: { EffectRecord } = {}
	local lastNode: Instance = audioPlayer
	local lastWire: Wire = wire
	local connections: { RBXScriptConnection } = {}

	local function cleanupAll()
		for _, conn in ipairs(connections) do
			conn:Disconnect()
		end
		table.clear(connections)
		for _, record in ipairs(effects) do
			record.inputWire:Destroy()
			record.outputWire:Destroy()
			record.node:Destroy()
		end
		table.clear(effects)
		if lastWire and lastWire.Parent then
			lastWire:Destroy()
		end
		if audioPlayer and audioPlayer.Parent then
			audioPlayer:Destroy()
		end
		if emitter and emitter.Parent then
			emitter:Destroy()
		end
	end

	local wrapper: AudioWrapper = {
		player = audioPlayer,
		emitter = emitter,
		_private = {
			lastNode = lastNode,
			lastWire = lastWire,
			effects = effects,
			connections = connections,
		},
	} :: any

	function wrapper:play(): ()
		self.player:Play()
	end

	function wrapper:pause(): ()
		self.player:Stop()
	end

	function wrapper:resume(): ()
		self.player:Play()
	end

	function wrapper:stop(): ()
		self.player:Stop()
		self.player.TimePosition = 0
	end

	function wrapper:setVolume(volume: number): ()
		self.player.Volume = volume
	end

	function wrapper:setPlaybackSpeed(speed: number): ()
		self.player.PlaybackSpeed = speed
	end

	function wrapper:setLooping(looping: boolean): ()
		self.player.Looping = looping
	end

	function wrapper:addEffect(effectClassName: string, effectProperties: { [string]: any }?): AudioEffectInstance
		if typeof(effectClassName) ~= "string" then
			error("AudioWrapper.addEffect: effectClassName must be a string")
		end

		local effect: AudioEffectInstance = Instance.new(effectClassName)
		effect.Name = effectClassName
		effect.Parent = self.emitter

		if effectProperties then
			for propertyName, value in effectProperties do
				pcall(function()
					(effect :: any)[propertyName] = value
				end)
			end
		end

		local state = (self :: any)._private
		local prevNode: Instance = state.lastNode
		local currentEmitter: AudioEmitter = self.emitter
		local prevWire: Wire = state.lastWire

		if prevWire and prevWire.Parent then
			prevWire:Destroy()
		end

		local wireIn: Wire = Instance.new("Wire")
		wireIn.SourceInstance = prevNode
		wireIn.TargetInstance = effect
		wireIn.Parent = prevNode

		local wireOut: Wire = Instance.new("Wire")
		wireOut.SourceInstance = effect
		wireOut.TargetInstance = currentEmitter
		wireOut.Parent = effect

		state.lastNode = effect
		state.lastWire = wireOut
		table.insert(state.effects, {
			node = effect,
			inputWire = wireIn,
			outputWire = wireOut,
		})

		return effect
	end

	function wrapper:clearEffects(): ()
		local state = (self :: any)._private
		for _, record: EffectRecord in ipairs(state.effects) do
			record.inputWire:Destroy()
			record.outputWire:Destroy()
			record.node:Destroy()
		end
		table.clear(state.effects)
		if state.lastWire and state.lastWire.Parent then
			state.lastWire:Destroy()
		end
		local newWire: Wire = Instance.new("Wire")
		newWire.SourceInstance = self.player
		newWire.TargetInstance = self.emitter
		newWire.Parent = self.emitter
		state.lastNode = self.player
		state.lastWire = newWire
	end

	function wrapper:onEnded(callback: () -> ()): RBXScriptConnection
		local connection: RBXScriptConnection = self.player.Ended:Connect(callback)
		table.insert((self :: any)._private.connections, connection)
		return connection
	end

	function wrapper:onLooped(callback: () -> ()): RBXScriptConnection
		local connection: RBXScriptConnection = self.player.Looped:Connect(callback)
		table.insert((self :: any)._private.connections, connection)
		return connection
	end

	function wrapper:destroy(): ()
		cleanupAll()
	end

	return wrapper
end

return AudioUtility
