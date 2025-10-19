--!strict
-- ClickBinder.lua
-- Binds click events with optional debounce and UISignal firing.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UISignals = require(script.Parent.UISignals)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

local ClickBinder = {}

type Callback = () -> any

export type ButtonConnectionMap = { [string]: RBXScriptConnection? }
type InternalButtonConnectionMap = ButtonConnectionMap & { __AutoCleanup: RBXScriptConnection? }

-- Weak-keyed table: GuiButton → (identifier → connection)
local connections: { [GuiButton]: InternalButtonConnectionMap } = {}
setmetatable(connections, { __mode = "k" })

local DOUBLE_CLICK_WINDOW_SECONDS = 0.25

local function monotonicNow(): number
	-- Monotonic clock for timing logic
	return os.clock()
end

-- Internal: ensure we auto-unbind when the button is destroyed
local function ensureAutoCleanup(button: GuiButton, perButtonMap: InternalButtonConnectionMap)
	if perButtonMap.__AutoCleanup ~= nil then
		return
	end
	perButtonMap.__AutoCleanup = button.Destroying:Connect(function()
		ClickBinder.Unbind(button, nil)
	end)
end

-- Internal: generate a unique debounce key
local function makeDebounceKey(prefix: string, button: GuiButton): string
	local success, fullName = pcall(button.GetFullName, button)
	return prefix .. (success and fullName or tostring(button))
end

-- Internal: shared bind logic for various button signals
local function bindInternal(
	button: GuiButton,
	identifier: string,
	handler: string | Callback,
	debounceSeconds: number?,
	getSignal: (GuiButton) -> RBXScriptSignal
): ()
	assert(button:IsA("GuiButton"), "Expected GuiButton.")
	assert(typeof(handler) == "function" or typeof(handler) == "string", "Expected a function or UISignal name.")
	if debounceSeconds ~= nil then
		assert(debounceSeconds >= 0, "Debounce seconds must be non-negative.")
	end

	local debounceKey = makeDebounceKey("ClickBinder_" .. identifier .. "_", button)

	local perButtonMap = connections[button]
	if perButtonMap == nil then
		perButtonMap = {} :: InternalButtonConnectionMap
		connections[button] = perButtonMap
	end
	ensureAutoCleanup(button, perButtonMap)

	-- Disconnect previous binding of the same identifier
	local existing = perButtonMap[identifier]
	if existing ~= nil then
		existing:Disconnect()
	end

	local signal = getSignal(button)
	perButtonMap[identifier] = signal:Connect(function()
		if debounceSeconds ~= nil then
			if not Debounce.TryAcquire(debounceKey, debounceSeconds, nil) then
				return
			end
		end

		if typeof(handler) == "function" then
			local callback = handler :: Callback
			local success, result = pcall(function(): any
				return callback()
			end)
			if not success then
				warn("[ClickBinder] Error running handler:", result)
			end
		else
			local signalName = handler :: string
			local success, result = pcall(function()
				UISignals.Get(signalName):Fire()
			end)
			if not success then
				warn("[ClickBinder] Error firing UISignal:", result)
			end
		end
	end)
end

--- Bind an Activated click with optional debounce and either a UISignal name or a callback function.
--- @param button GuiButton
--- @param handler string | fun(): ()
--- @param debounceSeconds number?  -- Optional debounce window in seconds.
function ClickBinder.BindActivated(button: GuiButton, handler: string | Callback, debounceSeconds: number?): ()
	bindInternal(button, "Activated", handler, debounceSeconds, function(btn)
		return btn.Activated
	end)
end

--- Bind a right-click (MouseButton2Click) with optional debounce and a callback function.
--- @param button GuiButton
--- @param callbackFunction fun(): ()
--- @param debounceSeconds number?  -- Optional debounce window in seconds.
function ClickBinder.BindRightClick(button: GuiButton, callbackFunction: Callback, debounceSeconds: number?): ()
	bindInternal(button, "RightClick", callbackFunction, debounceSeconds, function(btn)
		return btn.MouseButton2Click
	end)
end

--- Bind a double-click (two Activations within the window) with optional debounce and a callback function.
--- @param button GuiButton
--- @param callbackFunction fun(): ()
--- @param debounceSeconds number?  -- Optional debounce window in seconds.
function ClickBinder.BindDoubleClick(button: GuiButton, callbackFunction: Callback, debounceSeconds: number?): ()
	assert(button:IsA("GuiButton"), "Expected GuiButton.")
	assert(typeof(callbackFunction) == "function", "Expected a function.")
	if debounceSeconds ~= nil then
		assert(debounceSeconds >= 0, "Debounce seconds must be non-negative.")
	end

	local debounceKey = makeDebounceKey("ClickBinder_Double_", button)
	local lastActivationTime = 0.0

	local perButtonMap = connections[button]
	if perButtonMap == nil then
		perButtonMap = {} :: InternalButtonConnectionMap
		connections[button] = perButtonMap
	end
	ensureAutoCleanup(button, perButtonMap)

	-- Disconnect previous double-click binding, if any
	local existing: RBXScriptConnection? = perButtonMap.DoubleClick
	if existing ~= nil then
		existing:Disconnect()
	end

	perButtonMap.DoubleClick = button.Activated:Connect(function()
		local nowSeconds = monotonicNow()
		if (nowSeconds - lastActivationTime) <= DOUBLE_CLICK_WINDOW_SECONDS then
			if debounceSeconds == nil or Debounce.TryAcquire(debounceKey, debounceSeconds, nil) then
				local success, result = pcall(function(): any
					return callbackFunction()
				end)
				if not success then
					warn("[ClickBinder] Error running double-click callback:", result)
				end
			end
		end
		lastActivationTime = nowSeconds
	end)
end

--- Bind a click that triggers only once, then automatically unbinds.
--- @param button GuiButton
--- @param callbackFunction fun(): ()
--- @param debounceSeconds number?  -- Optional debounce window in seconds.
function ClickBinder.BindOnce(button: GuiButton, callbackFunction: Callback, debounceSeconds: number?): ()
	assert(button:IsA("GuiButton"), "Expected GuiButton.")
	assert(typeof(callbackFunction) == "function", "Expected a function.")
	if debounceSeconds ~= nil then
		assert(debounceSeconds >= 0, "Debounce seconds must be non-negative.")
	end

	local debounceKey = makeDebounceKey("ClickBinder_Once_", button)

	local perButtonMap = connections[button]
	if perButtonMap == nil then
		perButtonMap = {} :: InternalButtonConnectionMap
		connections[button] = perButtonMap
	end
	ensureAutoCleanup(button, perButtonMap)

	-- Disconnect previous one-shot binding, if any
	local existing: RBXScriptConnection? = perButtonMap.Once
	if existing ~= nil then
		existing:Disconnect()
	end

	local connectionObject: RBXScriptConnection
	connectionObject = button.Activated:Connect(function()
		if debounceSeconds ~= nil and not Debounce.TryAcquire(debounceKey, debounceSeconds, nil) then
			return
		end

		ClickBinder.Unbind(button, "Once")

		local success, result = pcall(function(): any
			return callbackFunction()
		end)
		if not success then
			warn("[ClickBinder] Error running one-shot callback:", result)
		end
	end)

	perButtonMap.Once = connectionObject
end

--- Unbind a specific identifier, or all identifiers, from a button.
--- @param button GuiButton
--- @param identifier string?  -- Example: "Activated", "RightClick", "DoubleClick", "Once"
function ClickBinder.Unbind(button: GuiButton, identifier: string?): ()
	local perButtonMap = connections[button]
	if perButtonMap == nil then
		return
	end

	if identifier ~= nil then
		local connectionObject = perButtonMap[identifier]
		if connectionObject ~= nil then
			connectionObject:Disconnect()
			perButtonMap[identifier] = nil
		end
		-- If no identifiers remain, remove the per-button table
		local hasEntries = false
		for key in pairs(perButtonMap) do
			if key ~= "__AutoCleanup" then
				hasEntries = true
				break
			end
		end
		if not hasEntries then
			-- Also disconnect the auto-cleanup connection if present
			local autoCleanup = perButtonMap.__AutoCleanup
			if autoCleanup ~= nil then
				(autoCleanup :: RBXScriptConnection):Disconnect()
				perButtonMap.__AutoCleanup = nil :: any
			end
			connections[button] = nil
		end
	else
		for key, connectionObject in pairs(perButtonMap) do
			if typeof(connectionObject) == "RBXScriptConnection" then
				connectionObject:Disconnect()
			end
			perButtonMap[key] = nil :: any
		end
		-- Remove the entry for this button entirely
		connections[button] = nil
	end
end

--- Unbind all active button connections.
function ClickBinder.UnbindAll(): ()
	-- Copy keys to avoid mutating while iterating
	local buttonsToClear: { GuiButton } = {}
	for button in pairs(connections) do
		table.insert(buttonsToClear, button)
	end
	for _, button in ipairs(buttonsToClear) do
		ClickBinder.Unbind(button, nil)
	end
end

return table.freeze(ClickBinder)
