--!strict
-- ActionBinder.lua
-- Cross-device input binding via ContextActionService.
-- Supports keyboard, gamepad, mouse, and touch (optional on-screen buttons).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")

local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

local ActionBinder = {}

export type BindingOptions = {
	inputTypes: { Enum.KeyCode | Enum.UserInputType }, -- e.g. { Enum.KeyCode.E, Enum.KeyCode.ButtonA }
	createTouchButton: boolean?, -- true to show a mobile on-screen button
	debounceSeconds: number?, -- optional debounce duration
	title: string?, -- touch button title (ContextActionService:SetTitle)
	image: string?, -- rbxassetid for touch button (ContextActionService:SetImage)
	position: UDim2?, -- touch button screen position
	defaultResult: Enum.ContextActionResult?, -- fallback ContextActionResult when handler returns nil
}

local PASS_RESULT = Enum.ContextActionResult.Pass
local SINK_RESULT = Enum.ContextActionResult.Sink

-- actionName -> cleanup function
local active: { [string]: () -> () } = {}

local function defaultHandlerWrapper(
	actionName: string,
	callback: (state: Enum.UserInputState, input: InputObject) -> Enum.ContextActionResult?,
	debounceSeconds: number?,
	defaultResult: Enum.ContextActionResult
)
	return function(_: string, state: Enum.UserInputState, input: InputObject)
		-- Fire only on "Begin" to avoid repeats from "Change" or "End"
		if state ~= Enum.UserInputState.Begin then
			return PASS_RESULT
		end

		if debounceSeconds ~= nil then
			local key = ("ActionBinder::%s"):format(actionName)
			if not Debounce.TryAcquire(key, debounceSeconds, nil) then
				return PASS_RESULT
			end
		end

		local success, result = pcall(callback, state, input)
		if not success then
			warn("[ActionBinder] Handler error for action:", actionName, result)
			return PASS_RESULT
		end

		if result ~= nil then
			return result :: Enum.ContextActionResult
		end

		return defaultResult
	end
end

--- Bind an action across devices.
--- @param actionName string
--- @param handler fun(state: Enum.UserInputState, input: InputObject): Enum.ContextActionResult?
--- @param options BindingOptions
function ActionBinder.BindAction(
	actionName: string,
	handler: (Enum.UserInputState, InputObject) -> Enum.ContextActionResult?,
	options: BindingOptions
): ()
	assert(typeof(actionName) == "string" and actionName ~= "", "Action name must be a nonempty string.")
	assert(typeof(handler) == "function", "Handler must be a function.")
	assert(typeof(options) == "table" and options.inputTypes ~= nil, "Options must include inputTypes.")
	assert(#options.inputTypes > 0, "Options.inputTypes must contain at least one input.")

	-- Unbind if already present
	if active[actionName] ~= nil then
		active[actionName]()
		active[actionName] = nil
	end

	local wrapped =
		defaultHandlerWrapper(actionName, handler, options.debounceSeconds, options.defaultResult or SINK_RESULT)
	local inputTypes = options.inputTypes
	ContextActionService:BindAction(
		actionName,
		wrapped,
		options.createTouchButton == true,
		table.unpack(inputTypes, 1, #inputTypes)
	)

	-- Optional touch customization
	if options.createTouchButton == true then
		if options.title ~= nil then
			ContextActionService:SetTitle(actionName, options.title)
		end
		if options.image ~= nil then
			ContextActionService:SetImage(actionName, options.image)
		end
		if options.position ~= nil then
			ContextActionService:SetPosition(actionName, options.position)
		end
	end

	active[actionName] = function()
		ContextActionService:UnbindAction(actionName)
	end
end

--- Unbind a single action.
function ActionBinder.UnbindAction(actionName: string): ()
	local cleanup = active[actionName]
	if cleanup ~= nil then
		cleanup()
		active[actionName] = nil
	end
end

--- Unbind all actions.
function ActionBinder.UnbindAll(): ()
	for name, cleanup in pairs(active) do
		cleanup()
		active[name] = nil
	end
end

return table.freeze(ActionBinder)
