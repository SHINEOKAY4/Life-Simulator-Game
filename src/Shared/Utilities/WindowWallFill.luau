local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local SurfacePalette = require(ReplicatedStorage.Shared.Configurations.Build.SurfacePalette)

export type WindowSpec = {
	WallVariant: string?,
	RequiresExistingWall: boolean?,
	WindowCutoutConfig: { [string]: any }?,
}

export type ApplyOptions = {
	previousWallId: string?,
	metadata: { [string]: any }?,
}

local WindowWallFill = {}

local FRAME_FOLDER_NAME = "WindowWallFill"
local SEGMENT_NAME = "_WindowFillSegment"

export type VisualInfo = {
	Size: Vector3,
	Material: Enum.Material,
	Color: Color3,
	Transparency: number,
	Reflectance: number,
}

export type SegmentDefinition = {
	Size: Vector3,
	CFrame: CFrame,
}

export type SegmentSolution = {
	Visual: VisualInfo,
	Segments: { SegmentDefinition },
	Geometry: {
		FrameThickness: number,
		WallWidth: number,
		WallHeight: number,
		WallThickness: number,
		EffectiveWallWidth: number,
		CutoutWidth: number,
		CutoutHeight: number,
		HeightOffset: number,
		LocalCenterY: number,
		OffsetFromWall: number,
		BaseCFrame: CFrame,
	},
}

local WallVisualCache: { [string]: VisualInfo } = {}

local function findFirstBasePart(model: Model): BasePart?
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function getWallVisualInfo(wallId: string): VisualInfo?
	local cached = WallVisualCache[wallId]
	if cached then
		return cached
	end

	local wallModel = ItemFinder.CloneModel(wallId)
	if not wallModel then
		return nil
	end

	local _, size = wallModel:GetBoundingBox()
	local samplePart = findFirstBasePart(wallModel)

	local info: VisualInfo = {
		Size = size,
		Material = samplePart and samplePart.Material or Enum.Material.SmoothPlastic,
		Color = samplePart and samplePart.Color or Color3.new(1, 1, 1),
		Transparency = samplePart and samplePart.Transparency or 0,
		Reflectance = samplePart and samplePart.Reflectance or 0,
	}

	wallModel:Destroy()
	WallVisualCache[wallId] = info
	return info
end

local function resolveSurfaceIdFromMetadata(metadata: { [string]: any }?): string?
	if typeof(metadata) ~= "table" then
		return nil
	end

	local surfaceId = metadata.SurfaceId
	if typeof(surfaceId) == "string" and surfaceId ~= "" then
		return surfaceId
	end

	local original = metadata.OriginalWallMetadata
	if typeof(original) == "table" then
		local originalSurfaceId = original.SurfaceId
		if typeof(originalSurfaceId) == "string" and originalSurfaceId ~= "" then
			return originalSurfaceId
		end
	end

	return nil
end

local function resolvePaintColorFromMetadata(metadata: { [string]: any }?): Color3?
	if typeof(metadata) ~= "table" then
		return nil
	end

	local record = metadata.PaintColor
	if typeof(record) ~= "table" then
		return nil
	end
	local r = tonumber(record.R or record.r)
	local g = tonumber(record.G or record.g)
	local b = tonumber(record.B or record.b)
	if typeof(r) ~= "number" or typeof(g) ~= "number" or typeof(b) ~= "number" then
		return nil
	end
	return Color3.new(math.clamp(r, 0, 1), math.clamp(g, 0, 1), math.clamp(b, 0, 1))
end

local function createVisualOverride(baseInfo: VisualInfo?, surfaceId: string?, paintColor: Color3?): VisualInfo?
	if not baseInfo then
		return nil
	end

	local visual: VisualInfo = {
		Size = baseInfo.Size,
		Material = baseInfo.Material,
		Color = baseInfo.Color,
		Transparency = baseInfo.Transparency,
		Reflectance = baseInfo.Reflectance,
	}

	if typeof(surfaceId) == "string" and surfaceId ~= "" then
		local definition = SurfacePalette.GetSurface(surfaceId)
		if definition then
			visual.Material = definition.Material
			if not paintColor then
				visual.Color = definition.Color
			end
			if typeof(definition.Transparency) == "number" then
				visual.Transparency = math.clamp(definition.Transparency, 0, 1)
			end
		end
	end

	if paintColor then
		visual.Color = paintColor
	end

	return visual
end

local function buildSegment(parent: Instance, visual: VisualInfo, size: Vector3, cf: CFrame)
	local part = Instance.new("Part")
	part.Name = SEGMENT_NAME
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = true
	part.Material = visual.Material
	part.Color = visual.Color
	part.Transparency = visual.Transparency
	part.Reflectance = visual.Reflectance
	part.Size = size
	part.CFrame = cf
	part.Parent = parent
end

local function vectorFromTable(value: any): Vector3?
	if typeof(value) == "Vector3" then
		return value
	end
	if typeof(value) ~= "table" then
		return nil
	end
	local xValue = value.X or value.x
	local yValue = value.Y or value.y
	local zValue = value.Z or value.z
	if typeof(xValue) ~= "number" or typeof(yValue) ~= "number" or typeof(zValue) ~= "number" then
		return nil
	end
	return Vector3.new(xValue, yValue, zValue)
end

local function buildSegmentSolution(model: Model, windowData: { [string]: any }, visual: VisualInfo): SegmentSolution?
	local frameThickness = 0.2
	if typeof(windowData.FrameThickness) == "number" and windowData.FrameThickness > 0 then
		frameThickness = windowData.FrameThickness
	end

	local rawWallWidth = visual.Size.X
	if typeof(windowData.WallSizeX) == "number" then
		rawWallWidth = math.max(windowData.WallSizeX, frameThickness * 2)
	end

	local effectiveWallWidth = rawWallWidth
	if typeof(windowData.EffectiveWallWidth) == "number" then
		effectiveWallWidth = math.max(windowData.EffectiveWallWidth, frameThickness * 2)
	end

	local wallWidth = effectiveWallWidth

	local wallHeight = visual.Size.Y
	if typeof(windowData.WallSizeY) == "number" then
		wallHeight = math.max(windowData.WallSizeY, frameThickness * 2)
	end

	local wallThickness = visual.Size.Z
	if typeof(windowData.WallSizeZ) == "number" then
		wallThickness = math.max(windowData.WallSizeZ, 0.05)
	end

	local cutoutWidth = wallWidth * 0.6
	if typeof(windowData.CutoutWidth) == "number" then
		cutoutWidth = math.min(math.max(windowData.CutoutWidth, frameThickness * 2), wallWidth - frameThickness * 0.5)
	end

	local cutoutHeight = wallHeight * 0.6
	if typeof(windowData.CutoutHeight) == "number" then
		cutoutHeight =
			math.min(math.max(windowData.CutoutHeight, frameThickness * 2), wallHeight - frameThickness * 0.5)
	end

	local halfCutoutWidth = cutoutWidth * 0.5
	local halfCutoutHeight = cutoutHeight * 0.5
	local halfWallWidth = wallWidth * 0.5
	local halfWallHeight = wallHeight * 0.5

	local heightOffset = halfWallHeight
	if typeof(windowData.HeightOffset) == "number" then
		heightOffset = windowData.HeightOffset
	end
	local localCenterY = heightOffset - halfWallHeight

	local offsetFromWall = 0
	if typeof(windowData.OffsetFromWall) == "number" then
		offsetFromWall = windowData.OffsetFromWall
	end

	local edgePosition = vectorFromTable(windowData.EdgePosition)
	local edgeUp = vectorFromTable(windowData.EdgeUp)
	local edgeForward = vectorFromTable(windowData.EdgeForward)
	local edgeRight = vectorFromTable(windowData.EdgeRight)

	local baseOrigin: Vector3
	local rightVector: Vector3
	local upVector: Vector3
	local forwardVector: Vector3

	if edgePosition and edgeUp and edgeForward then
		local normalizedUp = edgeUp.Magnitude > 1e-3 and edgeUp.Unit or Vector3.yAxis
		local outward = edgeForward.Magnitude > 1e-3 and edgeForward.Unit or Vector3.new(0, 0, 1)
		local inward = -outward
		local computedRight: Vector3
		if edgeRight and edgeRight.Magnitude > 1e-3 then
			computedRight = edgeRight.Unit
		else
			computedRight = normalizedUp:Cross(inward)
			if computedRight.Magnitude < 1e-3 then
				computedRight = inward:Cross(normalizedUp)
			end
		end
		computedRight = computedRight.Unit
		baseOrigin = edgePosition + normalizedUp * heightOffset + outward * offsetFromWall
		rightVector = computedRight
		upVector = normalizedUp
		forwardVector = inward
	else
		local pivotCF = model:GetPivot()
		local pivotUp = pivotCF.UpVector.Magnitude > 1e-3 and pivotCF.UpVector or Vector3.yAxis
		local pivotForward = pivotCF.LookVector.Magnitude > 1e-3 and pivotCF.LookVector or Vector3.new(0, 0, -1)
		local pivotRight = pivotCF.RightVector.Magnitude > 1e-3 and pivotCF.RightVector or Vector3.new(1, 0, 0)
		baseOrigin = pivotCF.Position
		rightVector = pivotRight.Unit
		upVector = pivotUp.Unit
		forwardVector = pivotForward.Unit
	end

	local windowTop = localCenterY + halfCutoutHeight
	local windowBottom = localCenterY - halfCutoutHeight

	local topHeight = math.max(halfWallHeight - windowTop, frameThickness)
	local bottomHeight = math.max(windowBottom + halfWallHeight, frameThickness)
	local sideWidth = math.max(halfWallWidth - halfCutoutWidth, frameThickness)

	local baseCF = CFrame.fromMatrix(baseOrigin, rightVector, upVector, forwardVector)

	local segments: { SegmentDefinition } = {
		{
			Size = Vector3.new(wallWidth, topHeight, wallThickness),
			CFrame = baseCF * CFrame.new(0, halfCutoutHeight + topHeight * 0.5, 0),
		},
		{
			Size = Vector3.new(wallWidth, bottomHeight, wallThickness),
			CFrame = baseCF * CFrame.new(0, -(halfCutoutHeight + bottomHeight * 0.5), 0),
		},
		{
			Size = Vector3.new(sideWidth, cutoutHeight, wallThickness),
			CFrame = baseCF * CFrame.new(-(halfCutoutWidth + sideWidth * 0.5), 0, 0),
		},
		{
			Size = Vector3.new(sideWidth, cutoutHeight, wallThickness),
			CFrame = baseCF * CFrame.new(halfCutoutWidth + sideWidth * 0.5, 0, 0),
		},
	}

	return {
		Visual = visual,
		Segments = segments,
		Geometry = {
			FrameThickness = frameThickness,
			WallWidth = wallWidth,
			WallHeight = wallHeight,
			WallThickness = wallThickness,
			EffectiveWallWidth = effectiveWallWidth,
			CutoutWidth = cutoutWidth,
			CutoutHeight = cutoutHeight,
			HeightOffset = heightOffset,
			LocalCenterY = localCenterY,
			OffsetFromWall = offsetFromWall,
			BaseCFrame = baseCF,
		},
	}
end

function WindowWallFill.ComputeSegments(
	model: Model,
	windowData: { [string]: any }?,
	previousWallId: string?,
	visualOverride: VisualInfo?
): SegmentSolution?
	if not model or typeof(windowData) ~= "table" then
		return nil
	end

	local visual: VisualInfo?
	if visualOverride then
		visual = visualOverride
	elseif typeof(previousWallId) == "string" and previousWallId ~= "" then
		visual = getWallVisualInfo(previousWallId)
	end

	if not visual then
		return nil
	end

	return buildSegmentSolution(model, windowData, visual)
end

function WindowWallFill.Remove(model: Model?)
	if not model then
		return
	end

	local existing = model:FindFirstChild(FRAME_FOLDER_NAME)
	if existing then
		existing:Destroy()
	end
end

function WindowWallFill.Apply(model: Model, spec: WindowSpec?, options: ApplyOptions?)
	if not model or not spec or spec.WallVariant ~= "Window" then
		WindowWallFill.Remove(model)
		return
	end

	local metadata = options and options.metadata or nil
	local windowData = metadata and metadata.WindowCutoutData
	if typeof(windowData) ~= "table" then
		WindowWallFill.Remove(model)
		return
	end

	local previousWallId = options and options.previousWallId or nil
	if not previousWallId and metadata then
		local prev = metadata.PreviousId
		if typeof(prev) == "string" and prev ~= "" then
			previousWallId = prev
		end
	end
	if not previousWallId then
		local attrPrev = model:GetAttribute("PreviousWallId")
		if typeof(attrPrev) == "string" and attrPrev ~= "" then
			previousWallId = attrPrev
		end
	end
	if typeof(previousWallId) ~= "string" or previousWallId == "" then
		WindowWallFill.Remove(model)
		return
	end

	local surfaceId = resolveSurfaceIdFromMetadata(metadata)
	local paintColor = resolvePaintColorFromMetadata(metadata)
	local visualOverride = createVisualOverride(getWallVisualInfo(previousWallId), surfaceId, paintColor)
	local solution = WindowWallFill.ComputeSegments(model, windowData, previousWallId, visualOverride)
	if not solution then
		WindowWallFill.Remove(model)
		return
	end

	local existingFolder = model:FindFirstChild(FRAME_FOLDER_NAME)
	if existingFolder then
		existingFolder:Destroy()
	end

	local frameFolder = Instance.new("Folder")
	frameFolder.Name = FRAME_FOLDER_NAME
	frameFolder.Parent = model

	for _, segment in solution.Segments do
		buildSegment(frameFolder, solution.Visual, segment.Size, segment.CFrame)
	end
end

return WindowWallFill
