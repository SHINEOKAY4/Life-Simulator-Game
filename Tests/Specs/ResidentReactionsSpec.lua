--!strict
-- Unit tests for ResidentReactions weather animation implementation

local function readFile(path)
	local file = assert(io.open(path, "r"), "missing file: " .. path)
	local contents = file:read("*a")
	file:close()
	return contents
end

local SRC_PATH = "src/Client/Modules/ResidentReactions.luau"

describe("ResidentReactions: module structure", function()
	local contents

	before_each(function()
		contents = readFile(SRC_PATH)
	end)

	it("requires TweenService for animation playback", function()
		assert.is_truthy(
			string.find(contents, 'TweenService = game:GetService("TweenService")', 1, true),
			"must require TweenService"
		)
	end)

	it("defines ReactionState type with weather animation fields", function()
		assert.is_truthy(
			string.find(contents, "ShiverTween: Tween?", 1, true),
			"ReactionState must include ShiverTween field"
		)
		assert.is_truthy(
			string.find(contents, "HeatSwayTween: Tween?", 1, true),
			"ReactionState must include HeatSwayTween field"
		)
		assert.is_truthy(
			string.find(contents, "WaistMotor: Motor6D?", 1, true),
			"ReactionState must cache WaistMotor reference"
		)
		assert.is_truthy(
			string.find(contents, "WaistOriginalC0: CFrame?", 1, true),
			"ReactionState must store original waist C0 for restoration"
		)
		assert.is_truthy(
			string.find(contents, "ActiveWeatherAnim:", 1, true),
			"ReactionState must track which weather animation is active"
		)
	end)

	it("initializes all new state fields in Register", function()
		local regStart = string.find(contents, "function ResidentReactions.Register", 1, true)
		assert.is_truthy(regStart)
		local regBody = string.sub(contents, regStart, regStart + 600)
		assert.is_truthy(string.find(regBody, "ShiverTween = nil", 1, true), "Register must init ShiverTween")
		assert.is_truthy(string.find(regBody, "HeatSwayTween = nil", 1, true), "Register must init HeatSwayTween")
		assert.is_truthy(string.find(regBody, "WaistMotor = nil", 1, true), "Register must init WaistMotor")
		assert.is_truthy(string.find(regBody, "WaistOriginalC0 = nil", 1, true), "Register must init WaistOriginalC0")
		assert.is_truthy(
			string.find(regBody, 'ActiveWeatherAnim = "None"', 1, true),
			"Register must init ActiveWeatherAnim to None"
		)
	end)
end)

describe("ResidentReactions: shiver animation (cold)", function()
	local contents

	before_each(function()
		contents = readFile(SRC_PATH)
	end)

	it("defines a startShiverAnimation function", function()
		assert.is_truthy(
			string.find(contents, "local function startShiverAnimation", 1, true),
			"must define startShiverAnimation"
		)
	end)

	it("guards against redundant shiver starts", function()
		local fnStart = string.find(contents, "local function startShiverAnimation", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 300)
		assert.is_truthy(
			string.find(fnBody, '"Shiver"', 1, true),
			"must check if already shivering before starting"
		)
	end)

	it("uses a CFrameValue proxy for tweening Motor6D.C0", function()
		local fnStart = string.find(contents, "local function startShiverAnimation", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 1000)
		assert.is_truthy(
			string.find(fnBody, 'Instance.new("CFrameValue")', 1, true),
			"must use CFrameValue proxy since Motor6D.C0 is not directly tweenable"
		)
		assert.is_truthy(
			string.find(fnBody, "ShiverProxy", 1, true),
			"proxy must be named ShiverProxy for debugging"
		)
	end)

	it("creates a fast looping reversing tween for shiver effect", function()
		local fnStart = string.find(contents, "local function startShiverAnimation", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 1000)
		-- Must use a short duration for rapid shivering
		assert.is_truthy(
			string.find(fnBody, "0.12", 1, true),
			"shiver tween must use fast duration (~0.12s)"
		)
		-- Must loop indefinitely
		assert.is_truthy(
			string.find(fnBody, "-1,", 1, true),
			"shiver tween must repeat indefinitely"
		)
		-- Must reverse for oscillation
		assert.is_truthy(
			string.find(fnBody, "true, -- reverses", 1, true),
			"shiver tween must reverse for back-and-forth oscillation"
		)
	end)

	it("cleans up proxy when tween completes", function()
		local fnStart = string.find(contents, "local function startShiverAnimation", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 2500)
		assert.is_truthy(
			string.find(fnBody, "proxy:Destroy()", 1, true),
			"must destroy CFrameValue proxy when tween completes"
		)
	end)

	it("triggers shiver when temperature is below 55F", function()
		local fnStart = string.find(contents, "local function updateTemperatureReaction", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 2500)
		assert.is_truthy(
			string.find(fnBody, "tempF < 55", 1, true),
			"cold threshold must be 55F"
		)
		assert.is_truthy(
			string.find(fnBody, "startShiverAnimation", 1, true),
			"must call startShiverAnimation when cold"
		)
	end)
end)

describe("ResidentReactions: heat sway animation (hot)", function()
	local contents

	before_each(function()
		contents = readFile(SRC_PATH)
	end)

	it("defines a startHeatSwayAnimation function", function()
		assert.is_truthy(
			string.find(contents, "local function startHeatSwayAnimation", 1, true),
			"must define startHeatSwayAnimation"
		)
	end)

	it("uses a slow lethargic tween for heat exhaustion", function()
		local fnStart = string.find(contents, "local function startHeatSwayAnimation", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 1000)
		assert.is_truthy(
			string.find(fnBody, "1.2", 1, true),
			"heat sway tween must use slow duration (~1.2s)"
		)
		assert.is_truthy(
			string.find(fnBody, "HeatSwayProxy", 1, true),
			"proxy must be named HeatSwayProxy"
		)
	end)

	it("includes forward droop angle for heat exhaustion posture", function()
		local fnStart = string.find(contents, "local function startHeatSwayAnimation", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 600)
		assert.is_truthy(
			string.find(fnBody, "droopAngleX", 1, true),
			"must define a forward droop angle for heat exhaustion"
		)
	end)

	it("triggers heat sway when temperature exceeds 85F", function()
		local fnStart = string.find(contents, "local function updateTemperatureReaction", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 2500)
		assert.is_truthy(
			string.find(fnBody, "tempF > 85", 1, true),
			"hot threshold must be 85F"
		)
		assert.is_truthy(
			string.find(fnBody, "startHeatSwayAnimation", 1, true),
			"must call startHeatSwayAnimation when hot"
		)
	end)
end)

describe("ResidentReactions: animation lifecycle", function()
	local contents

	before_each(function()
		contents = readFile(SRC_PATH)
	end)

	it("defines stopWeatherAnimation to cancel active tweens", function()
		assert.is_truthy(
			string.find(contents, "local function stopWeatherAnimation", 1, true),
			"must define stopWeatherAnimation"
		)
		local fnStart = string.find(contents, "local function stopWeatherAnimation", 1, true)
		local fnBody = string.sub(contents, fnStart, fnStart + 600)
		assert.is_truthy(
			string.find(fnBody, "ShiverTween", 1, true),
			"must handle ShiverTween cancellation"
		)
		assert.is_truthy(
			string.find(fnBody, "HeatSwayTween", 1, true),
			"must handle HeatSwayTween cancellation"
		)
		assert.is_truthy(
			string.find(fnBody, ":Cancel()", 1, true),
			"must call :Cancel() on active tweens"
		)
	end)

	it("restores waist C0 to original when stopping animation", function()
		local fnStart = string.find(contents, "local function stopWeatherAnimation", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 600)
		assert.is_truthy(
			string.find(fnBody, "WaistOriginalC0", 1, true),
			"must reference WaistOriginalC0 to restore original pose"
		)
	end)

	it("stops weather animation when temperature returns to neutral", function()
		local fnStart = string.find(contents, "local function updateTemperatureReaction", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 2500)
		assert.is_truthy(
			string.find(fnBody, "stopWeatherAnimation", 1, true),
			"must call stopWeatherAnimation when mood returns to neutral"
		)
	end)

	it("cleans up animations on Unregister", function()
		local fnStart = string.find(contents, "function ResidentReactions.Unregister", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 300)
		assert.is_truthy(
			string.find(fnBody, "stopWeatherAnimation", 1, true),
			"Unregister must call stopWeatherAnimation to prevent orphan tweens"
		)
	end)

	it("caches waist motor reference before starting animations", function()
		local fnStart = string.find(contents, "local function updateTemperatureReaction", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 2500)
		assert.is_truthy(
			string.find(fnBody, "ensureWaistMotor", 1, true),
			"must call ensureWaistMotor before starting animations"
		)
	end)
end)

describe("ResidentReactions: waist motor discovery", function()
	local contents

	before_each(function()
		contents = readFile(SRC_PATH)
	end)

	it("supports R15 rig (UpperTorso.Waist)", function()
		assert.is_truthy(
			string.find(contents, '"UpperTorso"', 1, true),
			"must look for UpperTorso (R15)"
		)
		assert.is_truthy(
			string.find(contents, '"Waist"', 1, true),
			"must look for Waist motor in UpperTorso"
		)
	end)

	it("supports R6 rig fallback (Torso.Root Joint)", function()
		assert.is_truthy(
			string.find(contents, '"Torso"', 1, true),
			"must look for Torso (R6 fallback)"
		)
		assert.is_truthy(
			string.find(contents, '"Root Joint"', 1, true),
			"must look for Root Joint motor in Torso"
		)
	end)

	it("validates motor parent is still alive before reusing cached reference", function()
		local fnStart = string.find(contents, "local function ensureWaistMotor", 1, true)
		assert.is_truthy(fnStart)
		local fnBody = string.sub(contents, fnStart, fnStart + 300)
		assert.is_truthy(
			string.find(fnBody, "WaistMotor.Parent", 1, true),
			"must check motor.Parent before reusing cached reference"
		)
	end)
end)

describe("ResidentReactions: no stale TODO comments for weather animations", function()
	it("does not contain TODO for shiver animation", function()
		local contents = readFile(SRC_PATH)
		assert.is_falsy(
			string.find(contents, "TODO: Play shiver", 1, true),
			"shiver TODO should be resolved"
		)
	end)

	it("does not contain TODO for wipe brow animation", function()
		local contents = readFile(SRC_PATH)
		assert.is_falsy(
			string.find(contents, "TODO: Play wipe brow", 1, true),
			"wipe brow TODO should be resolved"
		)
	end)
end)

describe("ObjectSelector: stale debounce TODO cleanup", function()
	it("does not contain the resolved debounce TODO", function()
		local contents = readFile("src/Client/Modules/ObjectSelector.luau")
		assert.is_falsy(
			string.find(contents, "#TODO: Add a debounce here", 1, true),
			"debounce TODO should be removed since runDebounced is already used"
		)
	end)

	it("still uses runDebounced for select action", function()
		local contents = readFile("src/Client/Modules/ObjectSelector.luau")
		assert.is_truthy(
			string.find(contents, 'runDebounced("Select"', 1, true),
			"must still debounce the select action"
		)
	end)
end)
