--!strict

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")

local CutawayViewController = {}

local CUTAWAY_TAG = "CutawayEligible"
local TRACKED_PLACEMENT_TYPES = {
	Wall = true,
	Roof = true,
	Floor = true,
	Ceiling = true,
}

local DEFAULT_DIM_TRANSPARENCY = 0.88
local WALL_DIM_TRANSPARENCY = 0.78
local BUILD_MODE_WALL_TRANSPARENCY = 0.45
local FLOOR_DIM_TRANSPARENCY = 0.96
local ROOF_DIM_TRANSPARENCY = 0.9
local CEILING_DIM_TRANSPARENCY = 0.92
local TRANSPARENCY_EPSILON = 0.01

type CutawayState = PlotStateStore.CutawayState
type PlacementRoomCoverageRecord = PlotStateStore.PlacementRoomCoverageRecord

type CutawayRequestOptions = {
	Priority: number?,
	TargetLevel: number?,
	HidePlacementTypes: { [string]: boolean }?,
}

type CameraInfo = {
	Level: number,
	Position: Vector3,
	CellX: number,
	CellZ: number,
	RoomId: number?,
	Forward: Vector3,
}

type TrackedPlacement = {
	Instance: Instance,
	PlacementType: string,
	Level: number,
	Parts: { BasePart },
	OriginalLTM: { [BasePart]: number },
	OriginalCanQuery: { [BasePart]: boolean }?,
	OriginalCanCollide: { [BasePart]: boolean }?,
	Hidden: boolean,
	HiddenTransparency: number?,
	LevelConnection: RBXScriptConnection?,
	DestroyingConnection: RBXScriptConnection?,
	Coverage: PlacementRoomCoverageRecord?,
}

local trackedPlacements: { [Instance]: TrackedPlacement } = {}
local pendingTypeListeners: { [Instance]: RBXScriptConnection } = {}
local containerConnections: { RBXScriptConnection } = {}
local currentContainer: Instance? = nil
local currentState: CutawayState = PlotStateStore.GetCutawayState()
local currentCameraInfo: CameraInfo? = nil
local currentCameraSignature: string? = nil
local initialized = false
local containerRetryThread: thread? = nil
local wallSegmentCaches: { [number]: { [string]: any } } = {}
local roomIdCaches: { [number]: { [string]: number | false } } = {}
local cameraWatcherConnection: RBXScriptConnection? = nil
local buildModeValue: BoolValue? = nil
local buildModeChangedConnection: RBXScriptConnection? = nil

local function isBuildModeActive(): boolean
	local value = buildModeValue
	if value and value:IsA("BoolValue") then
		return value.Value == true
	end
	return false
end

local function computeDimTransparency(entry: TrackedPlacement): number
	if entry.PlacementType == "Wall" then
		if isBuildModeActive() then
			return BUILD_MODE_WALL_TRANSPARENCY
		end
		return WALL_DIM_TRANSPARENCY
	elseif entry.PlacementType == "Floor" then
		return FLOOR_DIM_TRANSPARENCY
	elseif entry.PlacementType == "Roof" then
		return ROOF_DIM_TRANSPARENCY
	elseif entry.PlacementType == "Ceiling" then
		return CEILING_DIM_TRANSPARENCY
	end
	return DEFAULT_DIM_TRANSPARENCY
end

local function clearLevelCaches()
	wallSegmentCaches = {}
	roomIdCaches = {}
	for _, entry in pairs(trackedPlacements) do
		entry.Coverage = nil
	end
end

local function getWallSegmentMap(level: number): { [string]: any }
	local cache = wallSegmentCaches[level]
	if cache then
		return cache
	end
	local newCache: { [string]: any } = {}
	PlotStateStore.IterateWallSegments(level, function(segment: any)
		if segment and segment.PlacementKey then
			newCache[segment.PlacementKey] = segment
		end
		return nil
	end, false)
	wallSegmentCaches[level] = newCache
	return newCache
end

local function getWallSegmentForInstance(level: number, placementKey: string)
	local cache = getWallSegmentMap(level)
	return cache[placementKey]
end

local function makeRoomCacheKey(cellX: number, cellZ: number): string
	return ("%d:%d"):format(cellX, cellZ)
end

local function getRoomIdCached(level: number, cellX: number, cellZ: number): number?
	local levelCache = roomIdCaches[level]
	if not levelCache then
		levelCache = {}
		roomIdCaches[level] = levelCache
	end
	local key = makeRoomCacheKey(cellX, cellZ)
	local stored = levelCache[key]
	if stored == nil then
		local value = PlotStateStore.GetRoomIdAtCell(level, cellX, cellZ)
		levelCache[key] = if value == nil then false else value
		stored = levelCache[key]
	end
	if stored == false then
		return nil
	end
	return stored :: number
end

local function resolvePlacementCoverage(entry: TrackedPlacement): PlacementRoomCoverageRecord?
	if entry.Coverage == nil then
		entry.Coverage = PlotStateStore.GetPlacementRoomCoverage(entry.Instance.Name)
	end
	return entry.Coverage
end

local function getPlacementCenterWorldPosition(entry: TrackedPlacement): Vector3?
	local parts = entry.Parts
	local count = 0
	local accumulator = Vector3.zero
	for _, part in ipairs(parts) do
		if part.Parent then
			accumulator += part.Position
			count += 1
		end
	end
	if count == 0 then
		return nil
	end
	return accumulator / count
end

local function isPlacementFacingCamera(entry: TrackedPlacement, cameraInfo: CameraInfo): boolean
	local center = getPlacementCenterWorldPosition(entry)
	if not center then
		return true
	end
	local cameraForward = Vector3.new(cameraInfo.Forward.X, 0, cameraInfo.Forward.Z)
	local toPlacement = Vector3.new(center.X - cameraInfo.Position.X, 0, center.Z - cameraInfo.Position.Z)
	local forwardMagnitude = cameraForward.Magnitude
	local placementMagnitude = toPlacement.Magnitude
	if forwardMagnitude < 1e-3 or placementMagnitude < 1e-3 then
		return true
	end
	local dot = cameraForward.Unit:Dot(toPlacement.Unit)
	return dot >= 0.1
end

local function computeCameraInfo(level: number): CameraInfo?
	local camera = workspace.CurrentCamera
	if not camera then
		return nil
	end
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return nil
	end
	local position = camera.CFrame.Position
	local success, cellX, cellZ = grid:WorldPointToCell(position)
	if not success then
		cellX, cellZ = grid:WorldPointToClampedCell(position)
	end
	cellX = math.clamp(cellX, 1, grid.Columns)
	cellZ = math.clamp(cellZ, 1, grid.Rows)
	local roomId = PlotStateStore.GetRoomIdAtCell(level, cellX, cellZ)
	return {
		Level = level,
		Position = position,
		CellX = cellX,
		CellZ = cellZ,
		RoomId = roomId,
		Forward = camera.CFrame.LookVector,
	}
end

local function cameraSignature(info: CameraInfo?): string
	if not info then
		return "none"
	end
	local forward = info.Forward
	local fx = math.floor(forward.X * 100 + 0.5)
	local fy = math.floor(forward.Y * 100 + 0.5)
	local fz = math.floor(forward.Z * 100 + 0.5)
	return ("%d:%d:%d:%s:%d:%d:%d"):format(info.Level, info.CellX, info.CellZ, tostring(info.RoomId), fx, fy, fz)
end

local function getCellWorldPosition(grid: any, cell: { CellX: number, CellZ: number }?): Vector3?
	if not cell then
		return nil
	end
	local cellX = cell.CellX
	local cellZ = cell.CellZ
	if typeof(cellX) ~= "number" or typeof(cellZ) ~= "number" then
		return nil
	end
	if grid.IsCellInBounds and not grid:IsCellInBounds(cellX, cellZ) then
		return nil
	end
	return grid:CellToWorldCenter(cellX, cellZ)
end

local function prefersCellA(cameraInfo: CameraInfo, posA: Vector3?, posB: Vector3?): boolean
	if posA and posB then
		local dirA = posA - cameraInfo.Position
		local dirB = posB - cameraInfo.Position
		local magA = dirA.Magnitude
		local magB = dirB.Magnitude
		local dotA = if magA > 1e-3 then cameraInfo.Forward:Dot(dirA / magA) else -math.huge
		local dotB = if magB > 1e-3 then cameraInfo.Forward:Dot(dirB / magB) else -math.huge
		if math.abs(dotA - dotB) > 0.05 then
			return dotA >= dotB
		end
		if magA > 0 and magB > 0 then
			return magA <= magB
		end
	end
	if posA then
		return true
	end
	if posB then
		return false
	end
	return true
end

local function ensureCutawayValue(): BoolValue
	local folder = ActiveQueryFolder
	if not folder or not folder.Parent then
		folder = Instance.new("Folder")
		folder.Name = "ActiveQuery"
		folder.Parent = PlayerGui
		ActiveQueryFolder = folder
	end

	local boolValue = folder:FindFirstChild("CutawayVisible")
	if boolValue and boolValue:IsA("BoolValue") then
		return boolValue
	end

	boolValue = Instance.new("BoolValue")
	boolValue.Name = "CutawayVisible"
	boolValue.Value = false
	boolValue.Parent = folder
	return boolValue
end

local function hidePlacement(entry: TrackedPlacement)
	local target = computeDimTransparency(entry)
	if target < 0 then
		target = 0
	elseif target > 1 then
		target = 1
	end
	if
		entry.Hidden
		and entry.HiddenTransparency
		and math.abs(entry.HiddenTransparency - target) < TRANSPARENCY_EPSILON
	then
		return
	end

	local shouldDisableQuery = false
	local state = currentState
	if state.Visible then
		if entry.PlacementType == "Floor" or entry.PlacementType == "Roof" or entry.PlacementType == "Ceiling" then
			shouldDisableQuery = entry.Level >= state.TargetLevel
		end
	end

	if shouldDisableQuery and not entry.OriginalCanQuery then
		entry.OriginalCanQuery = {}
	end
	if shouldDisableQuery and not entry.OriginalCanCollide then
		entry.OriginalCanCollide = {}
	end

	for _, part in ipairs(entry.Parts) do
		if entry.OriginalLTM[part] == nil then
			entry.OriginalLTM[part] = part.LocalTransparencyModifier
		end
		part.LocalTransparencyModifier = target
		part.CastShadow = target < 0.9

		if shouldDisableQuery then
			local queryCache = entry.OriginalCanQuery
			if queryCache and queryCache[part] == nil then
				queryCache[part] = part.CanQuery
			end
			if part.CanQuery then
				part.CanQuery = false
			end

			local collideCache = entry.OriginalCanCollide
			if collideCache and collideCache[part] == nil then
				collideCache[part] = part.CanCollide
			end
			if part.CanCollide then
				part.CanCollide = false
			end
		end
	end
	entry.Hidden = true
	entry.HiddenTransparency = target
end

local function showPlacement(entry: TrackedPlacement)
	if not entry.Hidden then
		return
	end

	for part, previous in pairs(entry.OriginalLTM) do
		if part.Parent then
			part.LocalTransparencyModifier = previous
			part.CastShadow = true
		end
	end

	local queryCache = entry.OriginalCanQuery
	if queryCache then
		for part, previous in pairs(queryCache) do
			if part.Parent then
				part.CanQuery = previous
			end
		end
		table.clear(queryCache)
		entry.OriginalCanQuery = nil
	end

	local collideCache = entry.OriginalCanCollide
	if collideCache then
		for part, previous in pairs(collideCache) do
			if part.Parent then
				part.CanCollide = previous
			end
		end
		table.clear(collideCache)
		entry.OriginalCanCollide = nil
	end

	table.clear(entry.OriginalLTM)
	entry.Hidden = false
	entry.HiddenTransparency = nil
end

local function shouldHideWall(entry: TrackedPlacement, state: CutawayState): boolean
	if entry.Level < state.TargetLevel then
		return false
	end
	local segment = getWallSegmentForInstance(entry.Level, entry.Instance.Name)
	if not segment then
		return entry.Level >= state.TargetLevel
	end
	if segment.Orientation ~= "Cardinal" then
		return entry.Level >= state.TargetLevel
	end
	local cameraInfo = currentCameraInfo
	if not cameraInfo then
		return true
	end
	local grid = PlotStateStore.GetGrid()
	if not grid then
		return true
	end
	local adjacent = segment.AdjacentCells
	local cellA = adjacent and adjacent.CellA
	local cellB = adjacent and adjacent.CellB
	if not cellA or not cellB then
		return true
	end
	local roomA = if grid:IsCellInBounds(cellA.CellX, cellA.CellZ)
		then getRoomIdCached(entry.Level, cellA.CellX, cellA.CellZ)
		else nil
	local roomB = if grid:IsCellInBounds(cellB.CellX, cellB.CellZ)
		then getRoomIdCached(entry.Level, cellB.CellX, cellB.CellZ)
		else nil
	local posA = getCellWorldPosition(grid, cellA)
	local posB = getCellWorldPosition(grid, cellB)
	if not posA and not posB then
		return entry.Level >= state.TargetLevel
	end
	local cameraCloserToA = prefersCellA(cameraInfo, posA, posB)
	if posA and not posB then
		cameraCloserToA = true
	elseif posB and not posA then
		cameraCloserToA = false
	end
	local cameraSideRoom = if cameraCloserToA then roomA else roomB
	local oppositeRoom = if cameraCloserToA then roomB else roomA
	local oppositePos = if cameraCloserToA then posB else posA
	local cameraInsideRoom = cameraInfo.RoomId ~= nil

	if cameraInsideRoom and cameraSideRoom == cameraInfo.RoomId then
		if oppositeRoom == cameraInfo.RoomId then
			return false
		end
		if oppositePos then
			local direction = oppositePos - cameraInfo.Position
			if direction.Magnitude < 1e-3 then
				return true
			end
			local facingDot = cameraInfo.Forward:Dot(direction.Unit)
			if facingDot >= -0.2 then
				return true
			end
		else
			return true
		end
		return false
	end

	if cameraSideRoom == nil and oppositeRoom ~= nil then
		return true
	end

	if cameraSideRoom ~= oppositeRoom then
		return true
	end

	if cameraInsideRoom then
		return false
	end

	return entry.Level >= state.TargetLevel
end

local function shouldHideRoofOrCeiling(entry: TrackedPlacement, state: CutawayState): boolean
	if entry.Level < state.TargetLevel then
		return false
	end
	local cameraInfo = currentCameraInfo
	if not cameraInfo then
		return entry.Level >= state.TargetLevel
	end
	local coverage = resolvePlacementCoverage(entry)
	local cameraRoomId = cameraInfo.RoomId
	local cameraInsideRoom = cameraRoomId ~= nil
	local cameraMatchesRoom = false
	local roomIds = coverage and coverage.RoomIds
	local hasRoomData = roomIds ~= nil and next(roomIds) ~= nil
	if roomIds and cameraRoomId then
		cameraMatchesRoom = roomIds[cameraRoomId] == true
	end
	local shouldConsider = cameraMatchesRoom or not cameraInsideRoom or not hasRoomData
	if not shouldConsider then
		return false
	end
	if not isPlacementFacingCamera(entry, cameraInfo) then
		return false
	end
	return true
end

local function shouldHide(entry: TrackedPlacement, state: CutawayState): boolean
	if not state.Visible then
		return false
	end

	if entry.PlacementType == "Floor" then
		return entry.Level > state.TargetLevel
	end

	if not state.HidePlacementTypes[entry.PlacementType] then
		return false
	end

	if entry.PlacementType == "Wall" then
		return shouldHideWall(entry, state)
	end

	if entry.PlacementType == "Roof" or entry.PlacementType == "Ceiling" then
		return shouldHideRoofOrCeiling(entry, state)
	end

	return entry.Level >= state.TargetLevel
end

local function updatePlacementVisibility(entry: TrackedPlacement, state: CutawayState)
	if shouldHide(entry, state) then
		hidePlacement(entry)
	else
		showPlacement(entry)
	end
end

local function refreshAllPlacementVisibility()
	for _, entry in pairs(trackedPlacements) do
		updatePlacementVisibility(entry, currentState)
	end
end

local function onBuildModeValueChanged()
	refreshAllPlacementVisibility()
end

local function bindBuildModeValue(value: Instance?)
	if buildModeChangedConnection then
		buildModeChangedConnection:Disconnect()
		buildModeChangedConnection = nil
	end
	buildModeValue = nil
	if value and value:IsA("BoolValue") then
		buildModeValue = value
		buildModeChangedConnection = value:GetPropertyChangedSignal("Value"):Connect(onBuildModeValueChanged)
	end
end

local function initBuildModeTracking()
	if not ActiveQueryFolder then
		return
	end
	bindBuildModeValue(ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled"))

	ActiveQueryFolder.ChildAdded:Connect(function(child)
		if child.Name == "PlotBuilderEnabled" then
			bindBuildModeValue(child)
			onBuildModeValueChanged()
		end
	end)

	ActiveQueryFolder.ChildRemoved:Connect(function(child)
		if child == buildModeValue then
			bindBuildModeValue(nil)
			onBuildModeValueChanged()
		end
	end)

	onBuildModeValueChanged()
end

local function updateCameraTracking()
	if not currentState.Visible then
		if currentCameraInfo then
			currentCameraInfo = nil
			currentCameraSignature = nil
			refreshAllPlacementVisibility()
		end
		return
	end
	local info = computeCameraInfo(currentState.TargetLevel)
	local signature = cameraSignature(info)
	if signature ~= currentCameraSignature then
		currentCameraInfo = info
		currentCameraSignature = signature
		refreshAllPlacementVisibility()
	end
end

local function ensureCameraWatcher()
	if cameraWatcherConnection then
		return
	end
	cameraWatcherConnection = RunService.RenderStepped:Connect(updateCameraTracking)
end

local function applyState(state: CutawayState)
	currentState = state
	clearLevelCaches()
	currentCameraSignature = nil
	local cutawayValue = ensureCutawayValue()
	if cutawayValue.Value ~= state.Visible then
		cutawayValue.Value = state.Visible
	end

	for _, entry in pairs(trackedPlacements) do
		updatePlacementVisibility(entry, state)
	end

	updateCameraTracking()
end

local function cleanupEntry(entry: TrackedPlacement)
	showPlacement(entry)
	if entry.LevelConnection then
		entry.LevelConnection:Disconnect()
		entry.LevelConnection = nil
	end
	if entry.DestroyingConnection then
		entry.DestroyingConnection:Disconnect()
		entry.DestroyingConnection = nil
	end
end

local function stopPendingTypeListener(instance: Instance)
	local pending = pendingTypeListeners[instance]
	if pending then
		pending:Disconnect()
		pendingTypeListeners[instance] = nil
	end
end

local function unregisterPlacement(instance: Instance)
	stopPendingTypeListener(instance)
	local entry = trackedPlacements[instance]
	if not entry then
		return
	end

	cleanupEntry(entry)
	trackedPlacements[instance] = nil
	CollectionService:RemoveTag(instance, CUTAWAY_TAG)
	clearLevelCaches()
end

local function captureParts(instance: Instance): { BasePart }
	if instance:IsA("BasePart") then
		return { instance }
	end

	local parts = {}
	if instance:IsA("Model") then
		for _, descendant in ipairs(instance:GetDescendants()) do
			if descendant:IsA("BasePart") then
				table.insert(parts, descendant)
			end
		end
	end
	return parts
end

local function parseTypeAndLevelFromKey(key: string): (string?, number?)
	local ok, _, _, _, parsedType, parsedLevel = pcall(PlacementKey.ParseWithType, key)
	if ok then
		return parsedType, parsedLevel
	end
	return nil, nil
end

local function resolvePlacementMetadata(instance: Instance): (string?, number)
	local placementType: string? = nil
	local levelValue: number? = nil

	local typeAttr = instance:GetAttribute("PlacementType")
	if typeof(typeAttr) == "string" and typeAttr ~= "" then
		placementType = typeAttr
	end

	local levelAttr = instance:GetAttribute("Level")
	if typeof(levelAttr) == "number" then
		levelValue = levelAttr
	end

	local record = PlotStateStore.GetPlacementEntry(instance.Name)
	if record then
		if not levelValue and typeof(record.Level) == "number" then
			levelValue = record.Level
		end
	end

	if not placementType or not levelValue then
		local parsedType, parsedLevel = parseTypeAndLevelFromKey(instance.Name)
		if not placementType then
			placementType = parsedType
		end
		if not levelValue and typeof(parsedLevel) == "number" then
			levelValue = parsedLevel
		end
	end

	if not placementType then
		return nil, levelValue or PlotStateStore.GetDefaultLevel()
	end

	return placementType, levelValue or PlotStateStore.GetDefaultLevel()
end

local function registerPlacement(instance: Instance)
	if trackedPlacements[instance] then
		return
	end
	if not instance:IsA("Model") and not instance:IsA("BasePart") then
		return
	end

	local placementType, levelValue = resolvePlacementMetadata(instance)
	if not placementType then
		stopPendingTypeListener(instance)
		pendingTypeListeners[instance] = instance:GetAttributeChangedSignal("PlacementType"):Connect(function()
			stopPendingTypeListener(instance)
			task.defer(function()
				registerPlacement(instance)
			end)
		end)
		return
	end

	if not TRACKED_PLACEMENT_TYPES[placementType] then
		return
	end

	local entry: TrackedPlacement = {
		Instance = instance,
		PlacementType = placementType,
		Level = levelValue,
		Parts = captureParts(instance),
		OriginalLTM = {},
		OriginalCanQuery = nil,
		OriginalCanCollide = nil,
		Hidden = false,
		HiddenTransparency = nil,
		LevelConnection = nil,
		DestroyingConnection = nil,
		Coverage = nil,
	}

	entry.LevelConnection = instance:GetAttributeChangedSignal("Level"):Connect(function()
		local updated = instance:GetAttribute("Level")
		if typeof(updated) == "number" then
			entry.Level = updated
			entry.Coverage = nil
			updatePlacementVisibility(entry, currentState)
		end
	end)

	entry.DestroyingConnection = instance.Destroying:Connect(function()
		unregisterPlacement(instance)
	end)

	trackedPlacements[instance] = entry
	CollectionService:AddTag(instance, CUTAWAY_TAG)
	updatePlacementVisibility(entry, currentState)
	clearLevelCaches()
end

local function disconnectContainer()
	for _, connection in ipairs(containerConnections) do
		connection:Disconnect()
	end
	table.clear(containerConnections)
	currentContainer = nil
	clearLevelCaches()

	for instance, entry in pairs(trackedPlacements) do
		cleanupEntry(entry)
		CollectionService:RemoveTag(instance, CUTAWAY_TAG)
		trackedPlacements[instance] = nil
	end

	for instance, connection in pairs(pendingTypeListeners) do
		connection:Disconnect()
		pendingTypeListeners[instance] = nil
	end
end

local function bindContainer(container: Instance)
	if currentContainer == container then
		return
	end

	disconnectContainer()
	currentContainer = container
	containerConnections[#containerConnections + 1] = container.ChildAdded:Connect(registerPlacement)
	containerConnections[#containerConnections + 1] = container.ChildRemoved:Connect(unregisterPlacement)
	containerConnections[#containerConnections + 1] = container.DescendantAdded:Connect(registerPlacement)
	containerConnections[#containerConnections + 1] = container.DescendantRemoving:Connect(unregisterPlacement)
	containerConnections[#containerConnections + 1] = container:GetPropertyChangedSignal("Parent"):Connect(function()
		if container.Parent == nil then
			disconnectContainer()
		end
	end)

	for _, child in ipairs(container:GetDescendants()) do
		registerPlacement(child)
	end

	applyState(currentState)
end

local function tryBindContainer()
	local container = PlotStateStore.GetPlotContainer()
	if container then
		bindContainer(container)
		return
	end
	if containerRetryThread then
		return
	end
	containerRetryThread = task.spawn(function()
		while currentContainer == nil do
			task.wait(0.5)
			local candidate = PlotStateStore.GetPlotContainer()
			if candidate then
				bindContainer(candidate)
				break
			end
		end
		containerRetryThread = nil
	end)
end

function CutawayViewController.Init()
	if initialized then
		return
	end
	initialized = true

	ensureCutawayValue()
	initBuildModeTracking()
	currentState = PlotStateStore.GetCutawayState()
	applyState(currentState)

	PlotStateStore.OnCutawayChanged(function(state)
		applyState(state)
	end)

	ensureCameraWatcher()

	task.defer(tryBindContainer)
	Player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		task.defer(tryBindContainer)
	end)
end

function CutawayViewController.Request(source: string, options: CutawayRequestOptions?)
	PlotStateStore.RequestCutaway(source, options)
end

function CutawayViewController.Release(source: string)
	PlotStateStore.ReleaseCutaway(source)
end

function CutawayViewController.GetState(): CutawayState
	return PlotStateStore.GetCutawayState()
end

return CutawayViewController
