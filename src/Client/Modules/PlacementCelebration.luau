--!strict

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BillboardText = require(script.Parent.Parent.UserInterface.BillboardText)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local SUCCESS_COLOR = Color3.fromRGB(120, 244, 198)
local FAILURE_COLOR = Color3.fromRGB(255, 118, 118)
local HIGHLIGHT_COLOR = Color3.fromRGB(111, 244, 200)
local TEXT_SIZE = UDim2.fromScale(5, 1.6)
local FLOAT_OFFSET_START = Vector3.new(0, 1.8, 0)
local FLOAT_OFFSET_END = Vector3.new(0, 4.5, 0)
local DISPLAY_TIME = 1.25
local MODEL_LOOKUP_TIMEOUT = 0.9
local ANCHOR_SIZE = Vector3.new(0.1, 0.1, 0.1)
local EMERGE_OFFSET = Vector3.new(0, -2.2, 0)
local EMERGE_TWEEN_INFO = TweenInfo.new(0.42, Enum.EasingStyle.Back, Enum.EasingDirection.Out)

local PlacementCelebration = {}

type OptionalString = string?

local function resolveItemName(itemId: OptionalString): string
	if typeof(itemId) ~= "string" or itemId == "" then
		return "Item"
	end
	local spec = ItemFinder.FindItemById(itemId)
	local specName = spec and spec.Name
	if typeof(specName) == "string" and specName ~= "" then
		return specName
	end
	return itemId
end

local function fallbackPosition(): Vector3
	local camera = Workspace.CurrentCamera
	if camera then
		local origin = camera.CFrame
		return (origin.Position + origin.LookVector * 12) + Vector3.new(0, 4, 0)
	end
	return Vector3.new()
end

local function spawnFloatingText(position: Vector3, message: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Name = "_PlacementTextAnchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.CastShadow = false
	anchor.Size = ANCHOR_SIZE
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace.Terrain

	local attachment = Instance.new("Attachment")
	attachment.Name = "_PlacementCelebration"
	attachment.CFrame = CFrame.new()
	attachment.Parent = anchor

	local billboard = BillboardText.new({
		adornee = attachment,
		text = message,
		textColor = color,
		backgroundTransparency = 1,
		textScaled = true,
		font = Enum.Font.GothamBold,
		size = TEXT_SIZE,
		studsOffsetWorldSpace = FLOAT_OFFSET_START,
		alwaysOnTop = true,
		clipsDescendants = false,
	})

	local gui = billboard.instance
	local label = billboard.label
	label.TextTransparency = 1
	label.TextStrokeTransparency = 1
	label.TextStrokeColor3 = color:Lerp(Color3.fromRGB(32, 58, 49), 0.55)

	TweenService:Create(label, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		TextTransparency = 0,
		TextStrokeTransparency = 0.35,
	}):Play()

	TweenService:Create(gui, TweenInfo.new(DISPLAY_TIME, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = FLOAT_OFFSET_END,
	}):Play()

	task.delay(DISPLAY_TIME * 0.65, function()
		local fadeOut =
			TweenService:Create(label, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				TextTransparency = 1,
				TextStrokeTransparency = 1,
			})
		fadeOut.Completed:Once(function()
			billboard:destroy()
			anchor:Destroy()
		end)
		fadeOut:Play()
	end)
end

local function showText(position: Vector3?, message: string, color: Color3)
	local worldPosition = if position then position + Vector3.new(0, 2.6, 0) else fallbackPosition()
	spawnFloatingText(worldPosition, message, color)
end

local function getPlotContainer(): Instance?
	local plotModel = PlotStateStore.GetPlotModel()
	if not plotModel then
		return nil
	end
	return plotModel:FindFirstChild("Container")
end

local function waitForPlacedModel(itemId: OptionalString, cellX: number, cellZ: number, facing: string): Model?
	if typeof(itemId) ~= "string" or itemId == "" then
		return nil
	end

	local spec = ItemFinder.FindItemById(itemId)
	local placementType = spec and (spec.PlacementType or spec.Type) or "CellObject"
	local normalizedFacing: "North" | "East" | "South" | "West" | "NorthEast" | "NorthWest" | "SouthEast" | "SouthWest" =
		PlacementKey.NormalizeFacing(facing :: any)

	local container = getPlotContainer()
	if not container then
		return nil
	end

	local key = PlacementKey.ForPlacementType(cellX, cellZ, normalizedFacing, placementType)
	local model = container:FindFirstChild(key)
	if model then
		return model :: Model
	end

	local deadline = os.clock() + MODEL_LOOKUP_TIMEOUT
	while os.clock() < deadline do
		RunService.Heartbeat:Wait()
		model = container:FindFirstChild(key)
		if model then
			return model :: Model
		end
	end

	return nil
end

local function playModelBurst(model: Model)
	local highlight = Instance.new("Highlight")
	highlight.Name = "_PlacementHighlight"
	highlight.Adornee = model
	highlight.FillColor = HIGHLIGHT_COLOR
	highlight.FillTransparency = 0.7
	highlight.OutlineColor = HIGHLIGHT_COLOR:Lerp(Color3.new(1, 1, 1), 0.35)
	highlight.OutlineTransparency = 0.35
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Parent = model

	local fadeTween =
		TweenService:Create(highlight, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FillTransparency = 1,
			OutlineTransparency = 1,
		})
	fadeTween.Completed:Once(function()
		highlight:Destroy()
	end)
	fadeTween:Play()

	local primary = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	if not primary then
		return
	end

	local attachment = Instance.new("Attachment")
	attachment.Name = "_PlacementBurst"
	attachment.Parent = primary

	local emitter = Instance.new("ParticleEmitter")
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(4, 8)
	emitter.Lifetime = NumberRange.new(0.35, 0.55)
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.4),
		NumberSequenceKeypoint.new(0.45, 0.9),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, HIGHLIGHT_COLOR),
		ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)),
	})
	emitter.SpreadAngle = Vector2.new(45, 45)
	emitter.LightInfluence = 0
	emitter.Parent = attachment
	emitter:Emit(14)

	task.delay(1.2, function()
		attachment:Destroy()
	end)
end

local function animateModelEmergence(model: Model, finalPivot: CFrame)
	local pivotValue = Instance.new("CFrameValue")
	pivotValue.Name = "_PlacementPivot"
	pivotValue.Value = finalPivot * CFrame.new(EMERGE_OFFSET)
	local ok = pcall(function()
		model:PivotTo(pivotValue.Value)
	end)
	if not ok then
		pivotValue:Destroy()
		return false
	end

	local connection = pivotValue:GetPropertyChangedSignal("Value"):Connect(function()
		model:PivotTo(pivotValue.Value)
	end)

	local tween = TweenService:Create(pivotValue, EMERGE_TWEEN_INFO, {
		Value = finalPivot,
	})
	tween.Completed:Once(function()
		connection:Disconnect()
		model:PivotTo(finalPivot)
		pivotValue:Destroy()
	end)
	tween:Play()

	return true
end

local function animateModelWithBurst(model: Model): Vector3
	local finalPivot = model:GetPivot()
	local pivotPosition = finalPivot.Position
	local animated = animateModelEmergence(model, finalPivot)
	if animated then
		task.delay(0.12, function()
			playModelBurst(model)
		end)
	else
		playModelBurst(model)
	end
	return pivotPosition
end

function PlacementCelebration.CellObjectSuccess(itemId: OptionalString, cellX: number, cellZ: number, facing: string)
	task.spawn(function()
		local model = waitForPlacedModel(itemId, cellX, cellZ, facing)
		local position: Vector3? = nil
		if model then
			position = animateModelWithBurst(model)
		end
		showText(position, string.format("%s placed!", resolveItemName(itemId)), SUCCESS_COLOR)
	end)
end

function PlacementCelebration.CelebrateFloorArea(
	itemId: OptionalString,
	anchorCellX: number,
	anchorCellZ: number,
	_widthCells: number,
	_depthCells: number
)
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end

	task.spawn(function()
		local model = waitForPlacedModel(itemId, anchorCellX, anchorCellZ, "North")
		if not model then
			return
		end
		animateModelWithBurst(model)
	end)
end

function PlacementCelebration.CelebrateWallStrip(
	itemId: OptionalString,
	startCellX: number,
	endCellX: number,
	startCellZ: number,
	endCellZ: number,
	facing: string,
	orientation: string
)
	if typeof(itemId) ~= "string" or itemId == "" then
		return
	end
	if typeof(facing) ~= "string" or facing == "" then
		return
	end
	local isDiagonalForward = orientation == "DiagonalForward"
	local isDiagonalBackward = orientation == "DiagonalBackward"
	local isDiagonal = isDiagonalForward or isDiagonalBackward

	if orientation ~= "Horizontal" and orientation ~= "Vertical" and not isDiagonal then
		return
	end

	task.spawn(function()
		local minCellX = math.min(startCellX, endCellX)
		local maxCellX = math.max(startCellX, endCellX)
		local minCellZ = math.min(startCellZ, endCellZ)
		local maxCellZ = math.max(startCellZ, endCellZ)
		local index = 0
		local function celebrateAt(cellX: number, cellZ: number)
			index += 1
			local delaySeconds = (index - 1) * 0.05
			task.delay(delaySeconds, function()
				local model = waitForPlacedModel(itemId, cellX, cellZ, facing)
				if not model then
					return
				end
				animateModelWithBurst(model)
			end)
		end

		if orientation == "Horizontal" then
			local row = minCellZ
			for cellX = minCellX, maxCellX do
				celebrateAt(cellX, row)
			end
		elseif orientation == "Vertical" then
			local column = minCellX
			for cellZ = minCellZ, maxCellZ do
				celebrateAt(column, cellZ)
			end
		else
			local deltaX = endCellX - startCellX
			local deltaZ = endCellZ - startCellZ
			local span = math.max(math.abs(deltaX), math.abs(deltaZ))
			local stepX = if deltaX >= 0 then 1 else -1
			local stepZ = if isDiagonalForward then stepX else -stepX
			for i = 0, span do
				local cellX = startCellX + stepX * i
				local cellZ = startCellZ + stepZ * i
				celebrateAt(cellX, cellZ)
			end
		end
	end)
end

function PlacementCelebration.ShowSuccess(position: Vector3?, itemId: OptionalString)
	showText(position, string.format("%s placed!", resolveItemName(itemId)), SUCCESS_COLOR)
end

function PlacementCelebration.ShowFailure(position: Vector3?, itemId: OptionalString, message: OptionalString)
	local resolvedText: string
	if typeof(message) == "string" and message ~= "" then
		resolvedText = message
	else
		resolvedText = string.format("Cannot place %s here.", resolveItemName(itemId))
	end
	showText(position, resolvedText, FAILURE_COLOR)
end

function PlacementCelebration.ShowMessage(position: Vector3?, message: string, color: Color3?)
	if typeof(message) ~= "string" or message == "" then
		return
	end
	local resolvedColor = color or SUCCESS_COLOR
	showText(position, message, resolvedColor)
end

return PlacementCelebration
