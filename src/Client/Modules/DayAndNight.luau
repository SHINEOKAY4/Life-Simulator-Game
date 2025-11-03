-- StarterPlayerScripts/Client/Modules/DayAndNight.lua
-- Client-only day/night controller synced by workspace:GetServerTimeNow().
-- Single owner for Lighting on the client. Remove any other client scripts that write to Lighting.

local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")

-- ================= Config (can be overridden via Lighting attributes) =================
local DefaultSecondsPerFullDay = 1440 -- 24 minutes for a full 24h cycle
local DefaultStartClockTime = 16.5 -- hours (0..24). 16.5 ~ 4:30 PM

local Connection = nil :: RBXScriptConnection?
local lastUpdateTime = 0
local UPDATE_INTERVAL = 1 / 30 -- Update lighting at 30 FPS instead of render FPS

-- ================= Helpers =================
local function ensureEffect(className: string, parent: Instance)
	local existing = parent:FindFirstChildOfClass(className)
	if existing then
		return existing
	end
	local created = Instance.new(className)
	created.Parent = parent
	return created
end

local function setIfChanged(object: Instance, property: string, value: any)
	if object[property] ~= value then
		object[property] = value
	end
end

local function lerpNumber(a: number, b: number, alpha: number): number
	return a + (b - a) * alpha
end

local function lerpColor(a: Color3, b: Color3, alpha: number): Color3
	return a:Lerp(b, alpha)
end

-- ================= One-time stable foundation =================
Lighting.GlobalShadows = true
Lighting.ShadowSoftness = 0.5
Lighting.EnvironmentDiffuseScale = 0.45
Lighting.EnvironmentSpecularScale = 0.35
Lighting.GeographicLatitude = 12

local ColorCorrection = ensureEffect("ColorCorrectionEffect", Lighting) :: ColorCorrectionEffect
--local Bloom = ensureEffect("BloomEffect", Lighting) :: BloomEffect
local DepthOfField = ensureEffect("DepthOfFieldEffect", Lighting) :: DepthOfFieldEffect
local SunRays = ensureEffect("SunRaysEffect", Lighting) :: SunRaysEffect
local Atmosphere = ensureEffect("Atmosphere", Lighting) :: Atmosphere
local Clouds = Workspace.Terrain:FindFirstChildOfClass("Clouds")
if not Clouds then
	Clouds = Instance.new("Clouds")
	Clouds.Parent = Workspace.Terrain
end

-- Depth of Field (camera-agnostic baseline)
DepthOfField.Enabled = true
DepthOfField.FocusDistance = 30
DepthOfField.InFocusRadius = 40
DepthOfField.NearIntensity = 0.25
DepthOfField.FarIntensity = 0.35

-- Static effect knobs (do not change every frame)
ColorCorrection.Enabled = true
--Bloom.Enabled = true
--Bloom.Threshold = 0.8
--Bloom.Size = 24
SunRays.Enabled = true
SunRays.Spread = 0.15
Atmosphere.Offset = 0.05
Atmosphere.Glare = 0.08

-- ================= Keyframes =================
type Keyframe = {
	time: number,
	brightness: number,
	exposure: number,
	ambient: Color3,
	outdoorAmbient: Color3,
	colorShiftTop: Color3,
	colorShiftBottom: Color3,
	ccBrightness: number,
	ccContrast: number,
	ccSaturation: number,
	ccTint: Color3,
	bloomIntensity: number,
	sunRaysIntensity: number,
	atmoDensity: number,
	atmoColor: Color3,
	atmoDecay: Color3,
	atmoHaze: number,
	cloudCover: number,
	cloudDensity: number,
	cloudColor: Color3,
}

local Keyframes: { Keyframe } = {
	-- Dawn
	{
		time = 5.6,
		brightness = 2.0,
		exposure = -0.05,
		ambient = Color3.fromRGB(60, 70, 85),
		outdoorAmbient = Color3.fromRGB(90, 100, 120),
		colorShiftTop = Color3.fromRGB(255, 210, 170),
		colorShiftBottom = Color3.fromRGB(140, 170, 210),
		ccBrightness = 0.02,
		ccContrast = 0.08,
		ccSaturation = -0.03,
		ccTint = Color3.fromRGB(255, 230, 210),
		bloomIntensity = 0.45,
		sunRaysIntensity = 0.05,
		atmoDensity = 0.40,
		atmoColor = Color3.fromRGB(255, 225, 205),
		atmoDecay = Color3.fromRGB(70, 55, 40),
		atmoHaze = 1.2,
		cloudCover = 0.40,
		cloudDensity = 0.45,
		cloudColor = Color3.fromRGB(255, 220, 200),
	},
	-- Midday
	{
		time = 12.0,
		brightness = 3.0,
		exposure = -0.10,
		ambient = Color3.fromRGB(90, 100, 110),
		outdoorAmbient = Color3.fromRGB(120, 130, 140),
		colorShiftTop = Color3.fromRGB(255, 255, 255),
		colorShiftBottom = Color3.fromRGB(255, 255, 255),
		ccBrightness = 0.00,
		ccContrast = 0.06,
		ccSaturation = -0.02,
		ccTint = Color3.fromRGB(255, 245, 235),
		bloomIntensity = 0.35,
		sunRaysIntensity = 0.03,
		atmoDensity = 0.30,
		atmoColor = Color3.fromRGB(240, 240, 255),
		atmoDecay = Color3.fromRGB(80, 80, 95),
		atmoHaze = 0.9,
		cloudCover = 0.30,
		cloudDensity = 0.40,
		cloudColor = Color3.fromRGB(240, 245, 255),
	},
	-- Golden hour
	{
		time = 17.2,
		brightness = 3.0,
		exposure = -0.15,
		ambient = Color3.fromRGB(40, 50, 65),
		outdoorAmbient = Color3.fromRGB(70, 80, 95),
		colorShiftTop = Color3.fromRGB(255, 198, 140),
		colorShiftBottom = Color3.fromRGB(120, 150, 190),
		ccBrightness = 0.03,
		ccContrast = 0.12,
		ccSaturation = -0.05,
		ccTint = Color3.fromRGB(255, 224, 196),
		bloomIntensity = 0.60,
		sunRaysIntensity = 0.08,
		atmoDensity = 0.36,
		atmoColor = Color3.fromRGB(255, 230, 205),
		atmoDecay = Color3.fromRGB(60, 45, 30),
		atmoHaze = 1.4,
		cloudCover = 0.35,
		cloudDensity = 0.45,
		cloudColor = Color3.fromRGB(255, 200, 170),
	},
	-- Night
	{
		time = 20.0,
		brightness = 2.4,
		exposure = 0.25,
		ambient = Color3.fromRGB(45, 60, 85),
		outdoorAmbient = Color3.fromRGB(70, 85, 115),
		colorShiftTop = Color3.fromRGB(210, 230, 255),
		colorShiftBottom = Color3.fromRGB(175, 195, 235),
		ccBrightness = 0.04,
		ccContrast = 0.08,
		ccSaturation = -0.02,
		ccTint = Color3.fromRGB(215, 230, 255),
		bloomIntensity = 0.65,
		sunRaysIntensity = 0.00,
		atmoDensity = 0.36,
		atmoColor = Color3.fromRGB(200, 220, 255),
		atmoDecay = Color3.fromRGB(40, 55, 85),
		atmoHaze = 0.8,
		cloudCover = 0.40,
		cloudDensity = 0.45,
		cloudColor = Color3.fromRGB(220, 230, 255),
	},
}
table.sort(Keyframes, function(a, b)
	return a.time < b.time
end)

-- ================= Blending =================
local function findBracket(clockTime: number)
	local lower = Keyframes[#Keyframes]
	for i = 1, #Keyframes do
		local current = Keyframes[i]
		local nextIndex = (i % #Keyframes) + 1
		local nextKey = Keyframes[nextIndex]
		if clockTime >= current.time and clockTime < nextKey.time then
			lower = current
			local upper = nextKey
			local span = (upper.time - lower.time) % 24
			if span == 0 then
				span = 24
			end
			local progressed = (clockTime - lower.time) % 24
			local alpha = math.clamp(progressed / span, 0, 1)
			return lower, upper, alpha
		end
	end
	-- Wrap-around: between last and first
	local upper = Keyframes[1]
	local span = (upper.time - lower.time) % 24
	if span == 0 then
		span = 24
	end
	local progressed = (clockTime - lower.time) % 24
	local alpha = math.clamp(progressed / span, 0, 1)
	return lower, upper, alpha
end

local function applyBlend(lower: Keyframe, upper: Keyframe, alpha: number)
	setIfChanged(Lighting, "Brightness", lerpNumber(lower.brightness, upper.brightness, alpha))
	setIfChanged(Lighting, "ExposureCompensation", lerpNumber(lower.exposure, upper.exposure, alpha))
	setIfChanged(Lighting, "Ambient", lerpColor(lower.ambient, upper.ambient, alpha))
	setIfChanged(Lighting, "OutdoorAmbient", lerpColor(lower.outdoorAmbient, upper.outdoorAmbient, alpha))
	setIfChanged(Lighting, "ColorShift_Top", lerpColor(lower.colorShiftTop, upper.colorShiftTop, alpha))
	setIfChanged(Lighting, "ColorShift_Bottom", lerpColor(lower.colorShiftBottom, upper.colorShiftBottom, alpha))

	setIfChanged(ColorCorrection, "Brightness", lerpNumber(lower.ccBrightness, upper.ccBrightness, alpha))
	setIfChanged(ColorCorrection, "Contrast", lerpNumber(lower.ccContrast, upper.ccContrast, alpha))
	setIfChanged(ColorCorrection, "Saturation", lerpNumber(lower.ccSaturation, upper.ccSaturation, alpha))
	setIfChanged(ColorCorrection, "TintColor", lerpColor(lower.ccTint, upper.ccTint, alpha))

	--setIfChanged(Bloom, "Intensity", lerpNumber(lower.bloomIntensity, upper.bloomIntensity, alpha))
	setIfChanged(SunRays, "Intensity", lerpNumber(lower.sunRaysIntensity, upper.sunRaysIntensity, alpha))

	setIfChanged(Atmosphere, "Density", lerpNumber(lower.atmoDensity, upper.atmoDensity, alpha))
	setIfChanged(Atmosphere, "Color", lerpColor(lower.atmoColor, upper.atmoColor, alpha))
	setIfChanged(Atmosphere, "Decay", lerpColor(lower.atmoDecay, upper.atmoDecay, alpha))
	setIfChanged(Atmosphere, "Haze", lerpNumber(lower.atmoHaze, upper.atmoHaze, alpha))

	setIfChanged(Clouds, "Cover", lerpNumber(lower.cloudCover, upper.cloudCover, alpha))
	setIfChanged(Clouds, "Density", lerpNumber(lower.cloudDensity, upper.cloudDensity, alpha))
	setIfChanged(Clouds, "Color", lerpColor(lower.cloudColor, upper.cloudColor, alpha))
end

-- ================= Time derivation from server clock (stateless sync) =================
local function computeClockTimeFromServerNow(): number
	local secondsPerFullDayAttr = Lighting:GetAttribute("SecondsPerFullDay")
	local startClockTimeAttr = Lighting:GetAttribute("StartClockTime")

	local secondsPerFullDay = math.max(1, tonumber(secondsPerFullDayAttr) or DefaultSecondsPerFullDay)
	local startClockTime = (tonumber(startClockTimeAttr) or DefaultStartClockTime) % 24

	local serverSeconds = Workspace:GetServerTimeNow()
	local phase = (serverSeconds % secondsPerFullDay) / secondsPerFullDay
	return (phase * 24 + startClockTime) % 24
end

local DayAndNight = {}
-- ================= Main loop =================
function DayAndNight.Init()
	DayAndNight.Enable()
end

function DayAndNight.Enable()
	Connection = RunService.PreRender:Connect(function()
		local currentTime = os.clock()
		if currentTime - lastUpdateTime < UPDATE_INTERVAL then
			return
		end
		lastUpdateTime = currentTime

		local clockTime = computeClockTimeFromServerNow()
		setIfChanged(Lighting, "ClockTime", clockTime)

		local lower, upper, alpha = findBracket(clockTime)
		applyBlend(lower, upper, alpha)
	end)
end

function DayAndNight.Disable()
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end
end

return DayAndNight
