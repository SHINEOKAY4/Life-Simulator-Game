--!strict
--[[
    Billboard Text Module

    This module provides an easy‑to‑use, highly configurable way to create
    floating text in 3D space using a `BillboardGui`.  It supports both
    legacy `Enum.Font` values and the modern `Font` datatype, and exposes
    most of the properties documented by Roblox for fine‑tuned control.

    The defaults are chosen to be sensible while encouraging you to
    explicitly set the behaviour you need; unnecessary work is avoided
    unless you opt into distance‑based fading or scaling.

    Usage:

        local BillboardText = require(path.to.billboard_text_module)
        local part = workspace:WaitForChild("SomePart")

        local textHandle = BillboardText.new({
            adornee = part,
            text = "Hello world!",
            textColor = Color3.new(1, 1, 1),
            backgroundTransparency = 1,
            size = UDim2.fromScale(4, 1),
            studsOffset = Vector3.new(0, 3, 0),
            maxDistance = 100,
            alwaysOnTop = true,
            font = Enum.Font.Gotham,
            textSize = 24,
            richText = false,
        })

        -- later, update the text
        textHandle:setText("Updated!")

        -- when you no longer need it
        textHandle:destroy()

    The module avoids maintaining any global state.  Each instance holds
    only its own connections and cleans up after itself when destroyed.

    Author: SHINE
]]

local RunService = game:GetService("RunService")

export type FadeSettings = {
	fadeInDistance: number, -- distance at which text is fully visible
	fadeOutDistance: number, -- distance at which text becomes fully invisible
	minTransparency: number?, -- optional: transparency when fully visible (default 0)
	maxTransparency: number?, -- optional: transparency when fully invisible (default 1)
}

export type ScaleSettings = {
	nearDistance: number, -- distance at which scale is at `nearScale`
	farDistance: number, -- distance at which scale is at `farScale`
	nearScale: number, -- scale multiplier when camera is near
	farScale: number, -- scale multiplier when camera is far
}

export type BillboardOptions = {
	adornee: Instance?, -- BasePart or Attachment to follow (required for visible output)
	parent: Instance?, -- parent to assign the BillboardGui to; defaults to `adornee`
	text: string?, -- initial label text
	textColor: Color3?, -- colour of the text; defaults to white
	textTransparency: number?, -- text transparency (0–1); defaults to 0
	textSize: number?, -- font size in points (legacy); defaults to 14
	textScaled: boolean?, -- whether to scale text to fill available space
	font: Enum.Font?, -- legacy Font enum
	fontFace: Font?, -- modern Font datatype; overrides `font` if provided
	fontWeight: Enum.FontWeight?, -- optional weight for Font.fromName/fromId
	fontStyle: Enum.FontStyle?, -- optional style for Font.fromName/fromId
	richText: boolean?, -- enable rich text markup; defaults to false
	backgroundColor: Color3?, -- background colour; defaults to black
	backgroundTransparency: number?, -- background transparency; defaults to 1 (fully transparent)
	outline: boolean?, -- whether to draw an outline around text; defaults to false
	outlineColor: Color3?, -- colour of the outline stroke; defaults to black
	outlineTransparency: number?, -- transparency of the outline; defaults to 0
	size: UDim2?, -- size of the billboard on screen; defaults to UDim2.fromScale(4, 1)
	sizeOffset: Vector2?, -- acts like AnchorPoint for billboards; defaults to (0, 0)
	studsOffset: Vector3?, -- offset relative to the camera orientation
	studsOffsetWorldSpace: Vector3?, -- offset relative to world axes
	extentsOffset: Vector3?, -- offset relative to camera orientation scaled by bounding box
	extentsOffsetWorldSpace: Vector3?, -- offset relative to world axes scaled by bounding box
	maxDistance: number?, -- distance in studs before the gui stops rendering
	alwaysOnTop: boolean?, -- if true the gui renders on top of 3D content
	lightInfluence: number?, -- influence of world lighting (0–1)
	brightness: number?, -- scale of light applied when lightInfluence is 0
	playerToHideFrom: Player?, -- player to hide this billboard from
	clipsDescendants: boolean, -- whether to clip children; defaults to true
	zIndex: number?, -- zIndex of the text label; defaults to 1
	fadeSettings: FadeSettings?, -- optional distance‑based fade configuration
	scaleSettings: ScaleSettings?, -- optional distance‑based scale configuration
}

export type BillboardTextHandle = {
	instance: BillboardGui,
	label: TextLabel,
	setText: (self: BillboardTextHandle, text: string) -> (),
	update: (self: BillboardTextHandle, options: BillboardOptions) -> (),
	destroy: (self: BillboardTextHandle) -> (),
}

-- Internal helper to create a FontFace from options.
local function resolveFont(options: BillboardOptions): Font? | Enum.Font?
	-- Prefer a provided FontFace directly
	if options.fontFace then
		return options.fontFace
	end

	-- If a font name is provided via the legacy Enum, convert it into a FontFace.
	if options.font then
		-- Font.fromEnum may error on Enum.Font.Unknown; guard accordingly.
		local ok, result = pcall(function()
			return Font.fromEnum(options.font :: Enum.Font)
		end)
		if ok and result then
			return result
		else
			-- Fallback: return the Enum directly and let Roblox handle it.
			return options.font
		end
	end

	return nil
end

-- Compute transparency based on distance for fade settings.
local function computeTransparency(distance: number, settings: FadeSettings): number
	local minT = settings.minTransparency or 0
	local maxT = settings.maxTransparency or 1
	local fadeIn = settings.fadeInDistance
	local fadeOut = settings.fadeOutDistance
	if distance <= fadeIn then
		return minT
	elseif distance >= fadeOut then
		return maxT
	else
		local alpha = (distance - fadeIn) / (fadeOut - fadeIn)
		return minT + alpha * (maxT - minT)
	end
end

-- Compute scale multiplier based on distance for scale settings.
local function computeScale(distance: number, settings: ScaleSettings): number
	local nearD, farD = settings.nearDistance, settings.farDistance
	local nearS, farS = settings.nearScale, settings.farScale
	if distance <= nearD then
		return nearS
	elseif distance >= farD then
		return farS
	else
		local alpha = (distance - nearD) / (farD - nearD)
		return nearS + alpha * (farS - nearS)
	end
end

local BillboardText = {}
BillboardText.__index = BillboardText

-- Update the billboard and label according to new options.
function BillboardText:update(options: BillboardOptions)
	-- update adornee and parent first if provided
	if options.adornee then
		self.instance.Adornee = options.adornee
		-- Default parent to the adornee when parent is unspecified
		if options.parent == nil then
			self.instance.Parent = options.adornee
		end
	end
	if options.parent then
		self.instance.Parent = options.parent
	end

	-- text content
	if options.text ~= nil then
		self.label.Text = options.text
	end

	-- colours and transparency
	if options.textColor then
		self.label.TextColor3 = options.textColor
	end
	if options.textTransparency then
		self.label.TextTransparency = options.textTransparency
	end
	if options.backgroundColor then
		self.label.BackgroundColor3 = options.backgroundColor
	end
	if options.backgroundTransparency ~= nil then
		self.label.BackgroundTransparency = options.backgroundTransparency
	end
	if options.outline ~= nil then
		if options.outline then
			self.label.TextStrokeTransparency = options.outlineTransparency or 0
			self.label.TextStrokeColor3 = options.outlineColor or Color3.new(0, 0, 0)
		else
			self.label.TextStrokeTransparency = 1
		end
	end

	-- font handling
	local resolvedFont = resolveFont(options)
	if resolvedFont then
		-- Use FontFace property when the resolved font is a Font instance
		if typeof(resolvedFont) == "Font" then
			self.label.FontFace = resolvedFont
		elseif typeof(resolvedFont) == "EnumItem" then
			self.label.Font = resolvedFont :: Enum.Font
		end
	end
	-- fallback to explicit properties if provided
	if options.textSize then
		self.label.TextSize = options.textSize
	end
	if options.textScaled ~= nil then
		self.label.TextScaled = options.textScaled
	end
	if options.richText ~= nil then
		self.label.RichText = options.richText
	end

	-- billboard sizing
	if options.size then
		self.instance.Size = options.size
	end
	if options.sizeOffset then
		self.instance.SizeOffset = options.sizeOffset
	end

	-- offsets
	if options.studsOffset then
		self.instance.StudsOffset = options.studsOffset
	end
	if options.studsOffsetWorldSpace then
		self.instance.StudsOffsetWorldSpace = options.studsOffsetWorldSpace
	end
	if options.extentsOffset then
		self.instance.ExtentsOffset = options.extentsOffset
	end
	if options.extentsOffsetWorldSpace then
		self.instance.ExtentsOffsetWorldSpace = options.extentsOffsetWorldSpace
	end

	-- distance and rendering
	if options.maxDistance then
		self.instance.MaxDistance = options.maxDistance
	end
	if options.alwaysOnTop ~= nil then
		self.instance.AlwaysOnTop = options.alwaysOnTop
	end
	if options.lightInfluence ~= nil then
		self.instance.LightInfluence = options.lightInfluence
	end
	if options.brightness ~= nil then
		self.instance.Brightness = options.brightness
	end
	if options.playerToHideFrom then
		self.instance.PlayerToHideFrom = options.playerToHideFrom
	end
	if options.clipsDescendants ~= nil then
		self.instance.ClipsDescendants = options.clipsDescendants
	end
	if options.zIndex ~= nil then
		self.label.ZIndex = options.zIndex
	end

	-- update fade and scale settings
	if options.fadeSettings then
		self._fadeSettings = options.fadeSettings
	end
	if options.scaleSettings then
		self._scaleSettings = options.scaleSettings
	end

	-- refresh distance update based on presence of fade/scale settings
	self:_updateDistanceUpdateConnection()
end

-- Internal: ensure RenderStepped connection exists only when needed
function BillboardText:_updateDistanceUpdateConnection()
	-- disconnect existing connection if present
	self._distanceConnection = self._distanceConnection or nil
	if self._distanceConnection then
		self._distanceConnection:Disconnect()
		self._distanceConnection = nil
	end

	if not self._fadeSettings and not self._scaleSettings then
		return
	end

	-- local references for performance
	local camera = workspace.CurrentCamera
	local billboard = self.instance
	local label = self.label
	local originalSize: UDim2 = billboard.Size
	local fadeSettings = self._fadeSettings
	local scaleSettings = self._scaleSettings

	self._distanceConnection = RunService.RenderStepped:Connect(function()
		if not billboard.Parent then
			return
		end
		-- compute distance from camera to adornee
		local adornee = billboard.Adornee
		if not adornee then
			return
		end
		local worldPos: Vector3
		local success: boolean, result = pcall(function()
			if adornee:IsA("Attachment") then
				return adornee.WorldPosition
			elseif adornee:IsA("BasePart") then
				return adornee.Position
			else
				return (adornee :: any).Position
			end
		end)
		if success then
			worldPos = result
		else
			return
		end
		local camPos = camera.CFrame.Position
		local distance = (camPos - worldPos).Magnitude

		-- handle fading
		if fadeSettings then
			local transparency = computeTransparency(distance, fadeSettings)
			label.TextTransparency = transparency
			-- maintain outline transparency relative to text
			label.TextStrokeTransparency = transparency
		end

		-- handle scaling
		if scaleSettings then
			local scaleFactor = computeScale(distance, scaleSettings)
			billboard.Size = UDim2.new(
				originalSize.X.Scale * scaleFactor,
				originalSize.X.Offset * scaleFactor,
				originalSize.Y.Scale * scaleFactor,
				originalSize.Y.Offset * scaleFactor
			)
		end
	end)
end

-- Constructor
function BillboardText.new(options: BillboardOptions): BillboardTextHandle
	assert(options ~= nil, "BillboardText.new requires an options table")
	local self = setmetatable({} :: any, BillboardText)

	-- Create billboard container
	local gui = Instance.new("BillboardGui")
	gui.Active = false
	gui.ClipsDescendants = options.clipsDescendants == nil and true or options.clipsDescendants
	gui.ResetOnSpawn = false
	gui.LightInfluence = options.lightInfluence or 0
	gui.Brightness = options.brightness or 1
	gui.AlwaysOnTop = options.alwaysOnTop or false
	if options.maxDistance then
		gui.MaxDistance = options.maxDistance
	end
	if options.playerToHideFrom then
		gui.PlayerToHideFrom = options.playerToHideFrom
	end
	-- assign adornee and default parent
	if options.adornee then
		gui.Adornee = options.adornee
		gui.Parent = options.parent or options.adornee
	elseif options.parent then
		gui.Parent = options.parent
	end
	-- apply base size and offsets
	gui.Size = options.size or UDim2.fromScale(4, 1)
	gui.SizeOffset = options.sizeOffset or Vector2.new(0, 0)
	if options.studsOffset then
		gui.StudsOffset = options.studsOffset
	end
	if options.studsOffsetWorldSpace then
		gui.StudsOffsetWorldSpace = options.studsOffsetWorldSpace
	end
	if options.extentsOffset then
		gui.ExtentsOffset = options.extentsOffset
	end
	if options.extentsOffsetWorldSpace then
		gui.ExtentsOffsetWorldSpace = options.extentsOffsetWorldSpace
	end

	-- Create the text label inside the billboard
	local label = Instance.new("TextLabel")
	label.Name = "BillboardText"
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.5)
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = options.backgroundColor or Color3.new(0, 0, 0)
	label.BackgroundTransparency = options.backgroundTransparency or 1
	label.TextColor3 = options.textColor or Color3.new(1, 1, 1)
	label.TextTransparency = options.textTransparency or 0
	label.Text = options.text or ""
	label.TextScaled = options.textScaled or false
	label.TextSize = options.textSize or 14
	label.RichText = options.richText or false
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.ClipsDescendants = false
	label.BorderSizePixel = 0
	label.ZIndex = options.zIndex or 1
	-- set font
	local resolvedFont = resolveFont(options)
	if resolvedFont then
		if typeof(resolvedFont) == "Font" then
			label.FontFace = resolvedFont
		elseif typeof(resolvedFont) == "EnumItem" then
			label.Font = resolvedFont :: Enum.Font
		end
	end
	-- outline
	if options.outline then
		label.TextStrokeColor3 = options.outlineColor or Color3.new(0, 0, 0)
		label.TextStrokeTransparency = options.outlineTransparency or 0
	else
		label.TextStrokeTransparency = 1
	end

	label.Parent = gui

	-- assign to self
	self.instance = gui
	self.label = label
	self._fadeSettings = options.fadeSettings
	self._scaleSettings = options.scaleSettings
	self._distanceConnection = nil

	-- create methods

	-- call update to apply any remaining options and start distance updates
	self:update(options)
	return self :: any
end

function BillboardText:setText(text: string)
	self.label.Text = text
end
function BillboardText:destroy()
	if self._distanceConnection then
		self._distanceConnection:Disconnect()
	end
	self.instance:Destroy()
	-- clear references
	setmetatable(self, nil)
end
return BillboardText
