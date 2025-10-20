--!strict
-- ReplicatedStorage/Shared/Utilities/DoorWallFill.luau
-- Creates a wall "header" filler above door models so replacing a wall with a door keeps the upper segment filled.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

export type DoorSpec = {
	RequiresExistingWall: boolean?,
}

export type ApplyOptions = {
	previousWallId: string?,
	metadata: { [string]: any }?,
}

local DoorWallFill = {}

local FILL_NAME = "DoorWallFill"
local MIN_GAP_HEIGHT = 0.05

type WallVisualInfo = {
	Size: Vector3,
	Material: Enum.Material,
	Color: Color3,
	Transparency: number,
	Reflectance: number,
}

local WallCache: { [string]: WallVisualInfo } = {}

local function findFirstBasePart(model: Model): BasePart?
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function getWallVisualInfo(wallId: string): WallVisualInfo?
	local cached = WallCache[wallId]
	if cached then
		return cached
	end

	local wallModel = ItemFinder.CloneModel(wallId)
	if not wallModel then
		return nil
	end

	local _, wallSize = wallModel:GetBoundingBox()
	local samplePart = findFirstBasePart(wallModel)
	
	local defaultMaterial = Enum.Material.SmoothPlastic
	local defaultColor = Color3.fromRGB(255, 255, 255)

	local info: WallVisualInfo = {
		Size = wallSize,
		Material = if samplePart then samplePart.Material else defaultMaterial,
		Color = if samplePart then samplePart.Color else defaultColor,
		Transparency = if samplePart then samplePart.Transparency else 0,
		Reflectance = if samplePart then samplePart.Reflectance else 0,
	}

	wallModel:Destroy()

	WallCache[wallId] = info
	return info
end

local function ensureDoorAttributes(model: Model)
	if model:GetAttribute("DoorWallFillCenterOffsetX") then
		return
	end

	local ok, pivotCF = pcall(function()
		return model:GetPivot()
	end)
	if not ok then
		return
	end

	local bboxCF, bboxSize = model:GetBoundingBox()
	local offset = pivotCF:PointToObjectSpace(bboxCF.Position)

	model:SetAttribute("DoorWallFillCenterOffsetX", offset.X)
	model:SetAttribute("DoorWallFillCenterOffsetY", offset.Y)
	model:SetAttribute("DoorWallFillCenterOffsetZ", offset.Z)
	model:SetAttribute("DoorWallFillDoorHeight", bboxSize.Y)
end

local function computeDoorCenterWorld(model: Model): CFrame?
	local ok, pivotCF = pcall(function()
		return model:GetPivot()
	end)
	if not ok then
		return nil
	end

	local rawX = model:GetAttribute("DoorWallFillCenterOffsetX")
	local rawY = model:GetAttribute("DoorWallFillCenterOffsetY")
	local rawZ = model:GetAttribute("DoorWallFillCenterOffsetZ")
	local offset = Vector3.new(
		typeof(rawX) == "number" and rawX or 0,
		typeof(rawY) == "number" and rawY or 0,
		typeof(rawZ) == "number" and rawZ or 0
	)
	local worldPosition = pivotCF:PointToWorldSpace(offset)
	local orientation = pivotCF - pivotCF.Position
	return CFrame.new(worldPosition) * orientation
end

local function removeExistingFill(model: Model)
	local existing = model:FindFirstChild(FILL_NAME)
	if existing and existing:IsA("BasePart") then
		existing:Destroy()
	end
	model:SetAttribute("DoorWallFillLastWallId", nil)
end

function DoorWallFill.Remove(model: Model)
	removeExistingFill(model)
end

function DoorWallFill.Apply(model: Model, spec: DoorSpec?, options: ApplyOptions?)
	if not model or not spec or spec.RequiresExistingWall ~= true then
		removeExistingFill(model :: Model)
		return
	end

	ensureDoorAttributes(model)

	local metadata = options and options.metadata or nil
	local previousWallId = options and options.previousWallId or nil
	if not previousWallId and metadata then
		local metaPrev = metadata.PreviousId
		if typeof(metaPrev) == "string" and metaPrev ~= "" then
			previousWallId = metaPrev
		end
	end
	if not previousWallId then
		local attrPrev = model:GetAttribute("PreviousWallId")
		if typeof(attrPrev) == "string" and attrPrev ~= "" then
			previousWallId = attrPrev
		end
	end

	if not previousWallId or previousWallId == "" then
		removeExistingFill(model :: Model)
		return
	end

	local info = getWallVisualInfo(previousWallId)
	if not info then
		removeExistingFill(model :: Model)
		return
	end

	local rawDoorHeight = model:GetAttribute("DoorWallFillDoorHeight")
	local doorHeight = if typeof(rawDoorHeight) == "number" then rawDoorHeight else nil
	if typeof(doorHeight) ~= "number" then
		removeExistingFill(model :: Model)
		return
	end

	local gapHeight = info.Size.Y - doorHeight
	if gapHeight <= MIN_GAP_HEIGHT then
		removeExistingFill(model :: Model)
		return
	end

	local fillerInstance = model:FindFirstChild(FILL_NAME)
	local filler: BasePart
	if fillerInstance and fillerInstance:IsA("BasePart") then
		filler = fillerInstance
	else
		filler = Instance.new("Part")
		filler.Name = FILL_NAME
		filler.Anchored = true
		filler.CanCollide = false
		filler.CanTouch = false
		filler.CanQuery = true
		filler.TopSurface = Enum.SurfaceType.Smooth
		filler.BottomSurface = Enum.SurfaceType.Smooth
		filler.Parent = model
	end

	filler.Material = info.Material
	filler.Color = info.Color
	filler.Transparency = info.Transparency
	filler.Reflectance = info.Reflectance
	filler.Size = Vector3.new(info.Size.X, gapHeight, info.Size.Z)

	local doorCenterCF = computeDoorCenterWorld(model)
	if not doorCenterCF then
		removeExistingFill(model)
		return
	end
	local fillerOffsetY = (doorHeight * 0.5) + (gapHeight * 0.5)
	filler.CFrame = doorCenterCF * CFrame.new(0, fillerOffsetY, 0)

	filler:SetAttribute("IsDoorWallFill", true)
	filler:SetAttribute("SourceWallId", previousWallId)

	model:SetAttribute("PreviousWallId", previousWallId)
	model:SetAttribute("DoorWallFillLastWallId", previousWallId)
end

return DoorWallFill
