--!strict
-- StarterPlayerScripts/Client/UserInterface/ResidentStationBillboard.luau
-- Shows a simple need bar above residents while they use a station.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")

local NeedByStation: { [string]: string } = {
	RestStation = "Energy",
	CookStation = "Hunger",
	SocialStation = "Social",
	HygieneStation = "Hygiene",
	FunStation = "Fun",
}

local NeedDefs = NeedConfig.Needs

export type Tracker = {
	Model: Model,
	Billboard: BillboardGui,
	Fill: Frame,
	Connections: { RBXScriptConnection },
	NeedConnection: RBXScriptConnection?,
	NeedName: string?,
}

local ResidentStationBillboard = {}
local trackers: { [Model]: Tracker } = {}
local residentsFolderConnections: { RBXScriptConnection } = {}
local currentPlotIndex: number? = nil

local function getAdornee(model: Model): BasePart?
	local head = model:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		return head
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary
	end
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end
	return nil
end

local function setFill(tracker: Tracker, fraction: number)
	local clamped = math.clamp(fraction, 0, 1)
	tracker.Fill.Size = UDim2.fromScale(1, clamped)
	tracker.Fill.BackgroundColor3 = Color3.fromHSV(clamped * 0.33, 1, 1)
end

local function updateFill(tracker: Tracker)
	local needName = tracker.NeedName
	if not needName then
		setFill(tracker, 0)
		return
	end
	local def = NeedDefs[needName]
	if not def then
		setFill(tracker, 0)
		return
	end
	local valueAttr = tracker.Model:GetAttribute(needName)
	if typeof(valueAttr) ~= "number" then
		setFill(tracker, 0)
		return
	end
	local range = def.Max - def.Min
	local fraction = if range > 0 then (valueAttr - def.Min) / range else 0
	setFill(tracker, fraction)
end

local function setNeedBinding(tracker: Tracker, needName: string?)
	if tracker.NeedConnection then
		tracker.NeedConnection:Disconnect()
		tracker.NeedConnection = nil
	end
	tracker.NeedName = needName
	if not needName then
		updateFill(tracker)
		return
	end
	tracker.NeedConnection = tracker.Model:GetAttributeChangedSignal(needName):Connect(function()
		updateFill(tracker)
	end)
	updateFill(tracker)
end

local function resolveNeedName(model: Model): string?
	local stationAttr = model:GetAttribute("StationActivityType")
	if typeof(stationAttr) ~= "string" then
		return nil
	end
	return NeedByStation[stationAttr]
end

local function createBillboard(model: Model): Tracker
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "StationNeed"
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 40
	billboard.Size = UDim2.fromOffset(14, 50)
	billboard.StudsOffsetWorldSpace = Vector3.new(2, 0, 0)
	billboard.Enabled = false

	local adornee = getAdornee(model)
	if adornee then
		billboard.Adornee = adornee
	end
	billboard.Parent = PlayerGui

	local background = Instance.new("Frame")
	background.Name = "Background"
	background.AnchorPoint = Vector2.new(0.5, 0.5)
	background.Position = UDim2.fromScale(0.5, 0.5)
	background.Size = UDim2.fromScale(0.45, 0.78)
	background.BackgroundColor3 = Color3.fromRGB(18, 20, 26)
	background.BackgroundTransparency = 0.35
	background.BorderSizePixel = 0
	background.Parent = billboard

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 4)
	bgCorner.Parent = background

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.AnchorPoint = Vector2.new(0, 1)
	fill.Position = UDim2.fromScale(0, 1)
	fill.Size = UDim2.fromScale(1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(120, 210, 255)
	fill.BorderSizePixel = 0
	fill.Parent = background

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 4)
	fillCorner.Parent = fill

	return {
		Model = model,
		Billboard = billboard,
		Fill = fill,
		Connections = {},
		NeedConnection = nil,
		NeedName = nil,
	}
end

local function cleanupTracker(tracker: Tracker)
	if tracker.NeedConnection then
		tracker.NeedConnection:Disconnect()
	end
	for _, connection in ipairs(tracker.Connections) do
		connection:Disconnect()
	end
	tracker.Connections = {}
	tracker.NeedConnection = nil
	tracker.Billboard:Destroy()
end

local function detachResident(model: Model)
	local tracker = trackers[model]
	if not tracker then
		return
	end
	trackers[model] = nil
	cleanupTracker(tracker)
end

local function showBillboard(tracker: Tracker)
	if not tracker.Billboard.Adornee then
		local adornee = getAdornee(tracker.Model)
		if adornee then
			tracker.Billboard.Adornee = adornee
		end
	end
	tracker.Billboard.Enabled = true
end

local function hideBillboard(tracker: Tracker)
	tracker.Billboard.Enabled = false
	setNeedBinding(tracker, nil)
end

local function handleActiveChanged(tracker: Tracker)
	local active = tracker.Model:GetAttribute("StationActivityActive") == true
	if not active then
		hideBillboard(tracker)
		return
	end
	setNeedBinding(tracker, resolveNeedName(tracker.Model))
	showBillboard(tracker)
end

local function handleStationTypeChanged(tracker: Tracker)
	if tracker.Model:GetAttribute("StationActivityActive") == true then
		setNeedBinding(tracker, resolveNeedName(tracker.Model))
	else
		setNeedBinding(tracker, nil)
	end
end

local function attachResident(model: Model)
	if trackers[model] then
		return
	end
	if not model:IsA("Model") then
		return
	end
	if not model:FindFirstChildOfClass("Humanoid") then
		return
	end
	local tracker = createBillboard(model)
	trackers[model] = tracker

	local function bind(connection: RBXScriptConnection)
		table.insert(tracker.Connections, connection)
	end

	bind(model:GetAttributeChangedSignal("StationActivityActive"):Connect(function()
		handleActiveChanged(tracker)
	end))
	bind(model:GetAttributeChangedSignal("StationActivityType"):Connect(function()
		handleStationTypeChanged(tracker)
	end))
	bind(model.Destroying:Connect(function()
		detachResident(model)
	end))
	bind(model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			detachResident(model)
		end
	end))

	handleActiveChanged(tracker)
end

local function clearAllTrackers()
	for model, tracker in pairs(trackers) do
		trackers[model] = nil
		cleanupTracker(tracker)
	end
end

local function disconnectResidentsFolder()
	for _, connection in ipairs(residentsFolderConnections) do
		connection:Disconnect()
	end
	residentsFolderConnections = {}
end

local function bindResidentsFolder(folder: Instance)
	disconnectResidentsFolder()
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			attachResident(child)
		end
	end
	table.insert(
		residentsFolderConnections,
		folder.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				attachResident(child)
			end
		end)
	)
	table.insert(
		residentsFolderConnections,
		folder.ChildRemoved:Connect(function(child)
			if child:IsA("Model") then
				detachResident(child)
			end
		end)
	)
end

local function rebindPlot(plotIndex: number?)
	if plotIndex == currentPlotIndex then
		return
	end
	currentPlotIndex = plotIndex
	disconnectResidentsFolder()
	clearAllTrackers()
	if not plotIndex then
		return
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return
	end
	local residentsFolder = plotModel:FindFirstChild("Residents")
	if residentsFolder then
		bindResidentsFolder(residentsFolder)
		return
	end
	local awaiting
	awaiting = plotModel.ChildAdded:Connect(function(child)
		if child.Name == "Residents" then
			awaiting:Disconnect()
			bindResidentsFolder(child)
		end
	end)
	table.insert(residentsFolderConnections, awaiting)
end

function ResidentStationBillboard.Init()
	rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)
	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)
	end)
end

return ResidentStationBillboard
