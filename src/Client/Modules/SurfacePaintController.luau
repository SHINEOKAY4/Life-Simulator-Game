--!strict
-- StarterPlayerScripts/Client/Modules/SurfacePaintController.luau

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")

local PlacementPackets = require(ReplicatedStorage.Network.PlacementPackets)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local BuildPaletteUI = require(script.Parent.Parent.UserInterface.BuildPaletteUI)

local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local VisualToolsFolder = AssetsFolder:WaitForChild("VisualTools")
local SelectionHighlightTemplate = VisualToolsFolder:WaitForChild("SelectionHighlight") :: Highlight

type PaintSuggestion = BuildPaletteUI.PaintSuggestion

local SurfacePaintController = {}

local ACTION_NAME = "SurfacePaintController.Paint"
local CANCEL_SOURCE = "SurfacePaint"
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value
local RAYCAST_DISTANCE = 512
local DEBUG_ATTRIBUTE = "SurfacePaintDebug"
local DRAG_THRESHOLD_CELLS = 1
local MAX_BATCH_KEYS = 128

type HoverInfo = {
	model: Model,
	placementKey: string,
	entry: { [string]: any },
	placementType: string,
	level: number,
	cellX: number?,
	cellZ: number?,
}

type DragState = {
	isMouseDown: boolean,
	isDragging: boolean,
	startCellX: number?,
	startCellZ: number?,
	currentCellX: number?,
	currentCellZ: number?,
	level: number?,
	placementType: string?,
	startPlacementKey: string?,
	startModel: Model?,
}

local isActive = false
local paletteHiddenDuringSession = false
local hoverInfo: HoverInfo? = nil
local hoverUpdateConnection: RBXScriptConnection? = nil
local suggestionConnection: RBXScriptConnection? = nil
local hoverHighlight: Highlight? = nil
local dragPreviewHighlights: { [string]: Highlight } = {}
local dragPreviewActiveKeys: { [string]: boolean } = {}
local lastUsedSurfaceId: string? = nil
local lastUsedPaintColor: Color3? = nil
local dragState: DragState = {
	isMouseDown = false,
	isDragging = false,
	placementType = nil,
}

local function isDebugEnabled(): boolean
	if Workspace:GetAttribute(DEBUG_ATTRIBUTE) == true then
		return true
	end
	local ok, result = pcall(function()
		return RunService:IsStudio()
	end)
	return ok and result == true
end

local function formatDebugPayload(data: any): string
	if data == nil then
		return "{}"
	end
	local ok, encoded = pcall(HttpService.JSONEncode, HttpService, data)
	if ok then
		return encoded
	end
	return tostring(data)
end

local function debugLog(message: string, data: any?)
	if not isDebugEnabled() then
		return
	end
	if data ~= nil then
		warn(("[SurfacePaint][Client] %s :: %s"):format(message, formatDebugPayload(data)))
	else
		warn("[SurfacePaint][Client] " .. message)
	end
end

local function serializeColor(color: Color3?): { [string]: number }?
	if typeof(color) ~= "Color3" then
		return nil
	end
	return {
		R = color.R,
		G = color.G,
		B = color.B,
	}
end

local function deserializeColor(record: any): Color3?
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

local function getPlotContainer(): Instance?
	return PlotStateStore.GetPlotContainer()
end

local function resolvePlacementModel(hitInstance: Instance?): Model?
	if not hitInstance then
		return nil
	end
	local container = getPlotContainer()
	if not container then
		return nil
	end
	local model = hitInstance:FindFirstAncestorOfClass("Model")
	while model and model.Parent ~= container do
		local parent = model.Parent
		if parent and parent:IsA("Model") then
			model = parent
		else
			model = nil
		end
	end
	if model and model.Parent == container then
		return model
	end
	return nil
end

local function raycastPlot(): RaycastResult?
	local container = getPlotContainer()
	if not container then
		return nil
	end
	local unitRay = Mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { container }
	params.IgnoreWater = true
	return Workspace:Raycast(unitRay.Origin, unitRay.Direction * RAYCAST_DISTANCE, params)
end

local function ensureHoverHighlight(): Highlight
	if hoverHighlight and hoverHighlight.Parent then
		return hoverHighlight
	end
	local highlight = SelectionHighlightTemplate:Clone()
	highlight.Name = "SurfacePaintHoverHighlight"
	highlight.Enabled = false
	highlight.FillTransparency = 1
	highlight.Parent = Workspace.CurrentCamera or Workspace
	hoverHighlight = highlight
	return highlight
end

local function setHoverHighlight(model: Model?)
	local highlight = ensureHoverHighlight()
	if model then
		highlight.Adornee = model
		highlight.Enabled = true
	else
		highlight.Adornee = nil
		highlight.Enabled = false
	end
end

local function clearHoverHighlight()
	if hoverHighlight then
		hoverHighlight.Adornee = nil
		hoverHighlight.Enabled = false
	end
end

local function destroyDragPreviewHighlight(key: string)
	local highlight = dragPreviewHighlights[key]
	if not highlight then
		return
	end
	highlight.Adornee = nil
	highlight.Enabled = false
	highlight:Destroy()
	dragPreviewHighlights[key] = nil
	dragPreviewActiveKeys[key] = nil
end

local function ensureDragPreviewHighlight(key: string): Highlight
	local highlight = dragPreviewHighlights[key]
	if highlight and highlight.Parent then
		return highlight
	end
	highlight = SelectionHighlightTemplate:Clone()
	highlight.Name = "SurfacePaintDragHighlight"
	highlight.FillTransparency = 0.6
	highlight.OutlineTransparency = 0
	highlight.FillColor = Color3.fromRGB(255, 255, 255)
	highlight.OutlineColor = Color3.fromRGB(108, 172, 255)
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.Enabled = false
	highlight.Parent = Workspace.CurrentCamera or Workspace
	dragPreviewHighlights[key] = highlight
	return highlight
end

local function clearDragPreview()
	for key in pairs(dragPreviewHighlights) do
		destroyDragPreviewHighlight(key)
	end
	dragPreviewActiveKeys = {}
end

local function applyDragPreviewTargets(keys: { string })
	local container = getPlotContainer()
	if not container then
		clearDragPreview()
		return
	end
	local newActive: { [string]: boolean } = {}
	for index, key in ipairs(keys) do
		if index > MAX_BATCH_KEYS then
			break
		end
		local model = container:FindFirstChild(key)
		if model and model:IsA("Model") then
			local highlight = ensureDragPreviewHighlight(key)
			highlight.Adornee = model
			highlight.Enabled = true
			newActive[key] = true
		end
	end
	for key in pairs(dragPreviewHighlights) do
		if not newActive[key] then
			destroyDragPreviewHighlight(key)
		end
	end
	dragPreviewActiveKeys = newActive
end

local function rememberLastUsed(surfaceId: string?, paintColor: Color3?)
	lastUsedSurfaceId = surfaceId
	lastUsedPaintColor = paintColor
end

local function extractSurfaceMetadata(entry: { [string]: any }?): (string?, Color3?)
	if typeof(entry) ~= "table" then
		return nil, nil
	end
	local surfaceIdValue = entry.SurfaceId
	local surfaceId = if typeof(surfaceIdValue) == "string" and surfaceIdValue ~= "" then surfaceIdValue else nil
	local paintColor = deserializeColor(entry.PaintColor)
	return surfaceId, paintColor
end

local function collectNeighborSuggestionRecords(info: HoverInfo): { PaintSuggestion }
	local footprint = PlotStateStore.GetPlacementFootprint(info.placementKey)
	if not footprint then
		return {}
	end
	local searchMinX = footprint.MinCellX - 1
	local searchMaxX = footprint.MaxCellX + 1
	local searchMinZ = footprint.MinCellZ - 1
	local searchMaxZ = footprint.MaxCellZ + 1
	local level = footprint.Level
	local placementType = info.placementType
	local tallies: { [string]: { SurfaceId: string?, PaintColor: Color3?, Count: number } } = {}

	PlotStateStore.IteratePlacements(function(key, record)
		if key == info.placementKey then
			return
		end
		local recordType = tostring(record.PlacementType or record.Type or "CellObject")
		if recordType ~= placementType then
			return
		end
		local recordLevel = record.Level or record.yLevel or PlotStateStore.GetDefaultLevel()
		if recordLevel ~= level then
			return
		end
		local otherFootprint = PlotStateStore.GetPlacementFootprint(key)
		if not otherFootprint then
			return
		end
		if otherFootprint.MinCellX > searchMaxX or otherFootprint.MaxCellX < searchMinX then
			return
		end
		if otherFootprint.MinCellZ > searchMaxZ or otherFootprint.MaxCellZ < searchMinZ then
			return
		end
		local surfaceId, paintColor = extractSurfaceMetadata(record.Metadata)
		if not surfaceId and not paintColor then
			return
		end
		local talliedKey = (surfaceId or "")
		if paintColor then
			talliedKey ..= string.format("|%.3f_%.3f_%.3f", paintColor.R, paintColor.G, paintColor.B)
		else
			talliedKey ..= "|"
		end
		local tally = tallies[talliedKey]
		if not tally then
			tally = {
				SurfaceId = surfaceId,
				PaintColor = paintColor,
				Count = 0,
			}
			tallies[talliedKey] = tally
		end
		tally.Count += 1
	end)

	local ordered: { { SurfaceId: string?, PaintColor: Color3?, Count: number } } = {}
	for _, tally in pairs(tallies) do
		ordered[#ordered + 1] = tally
	end
	table.sort(ordered, function(a, b)
		return a.Count > b.Count
	end)
	local records: { PaintSuggestion } = {}
	local limit = math.min(3, #ordered)
	for index = 1, limit do
		local entry = ordered[index]
		records[#records + 1] = {
			Id = "neighbor_" .. index,
			Label = if index == 1 then "Match Neighbor" else string.format("Neighbor #%d", index),
			SurfaceId = entry.SurfaceId,
			PaintColor = entry.PaintColor,
		}
	end
	return records
end

local function buildSuggestions(info: HoverInfo?): { PaintSuggestion }
	if not info then
		return {}
	end
	local suggestions: { PaintSuggestion } = {}
	local seen: { [string]: boolean } = {}
	local function addSuggestion(record: PaintSuggestion)
		if not record.SurfaceId and not record.PaintColor then
			return
		end
		local key = (record.SurfaceId or "")
		if record.PaintColor then
			key ..= string.format("|%.3f_%.3f_%.3f", record.PaintColor.R, record.PaintColor.G, record.PaintColor.B)
		else
			key ..= "|"
		end
		if seen[key] then
			return
		end
		seen[key] = true
		suggestions[#suggestions + 1] = record
	end

	local surfaceId, paintColor = extractSurfaceMetadata(info.entry and info.entry.Metadata)
	if surfaceId or paintColor then
		addSuggestion({
			Id = "current",
			Label = "Use Current Surface",
			SurfaceId = surfaceId,
			PaintColor = paintColor,
		})
	end
	local original = info.entry and info.entry.Metadata and info.entry.Metadata.OriginalWallMetadata
	if typeof(original) == "table" then
		local originalSurface, originalPaint = extractSurfaceMetadata(original)
		if originalSurface or originalPaint then
			addSuggestion({
				Id = "original",
				Label = "Original Material",
				SurfaceId = originalSurface,
				PaintColor = originalPaint,
			})
		end
	end
	if lastUsedSurfaceId or lastUsedPaintColor then
		addSuggestion({
			Id = "last",
			Label = "Last Used",
			SurfaceId = lastUsedSurfaceId,
			PaintColor = lastUsedPaintColor,
		})
	end
	for _, neighbor in ipairs(collectNeighborSuggestionRecords(info)) do
		addSuggestion(neighbor)
	end
	return suggestions
end

local function sendPaintRequests(targetKeys: { string }, overrideSurfaceId: string?, overrideColor: Color3?)
	if #targetKeys == 0 then
		return
	end
	local surfaceId = overrideSurfaceId or BuildPaletteUI.GetSelectedSurfaceId() or ""
	local colorOverride = overrideColor or BuildPaletteUI.GetSelectedColorOverride()
	local serializedColor = serializeColor(colorOverride)
	local success: boolean
	local message: string?
	if #targetKeys == 1 then
		success, message = PlacementPackets.PaintSurfaceRequest:Fire({
			PlacementKey = targetKeys[1],
			SurfaceId = surfaceId,
			PaintColor = serializedColor,
		})
	else
		success, message = PlacementPackets.PaintSurfaceBatchRequest:Fire({
			PlacementKeys = targetKeys,
			SurfaceId = surfaceId,
			PaintColor = serializedColor,
		})
	end
	if success then
		debugLog("Paint request succeeded", {
			keys = targetKeys,
			message = message,
		})
		rememberLastUsed(surfaceId ~= "" and surfaceId or nil, colorOverride)
	else
		warn("Surface paint failed: " .. (message or "unknown reason"))
		debugLog("Paint request failed", {
			keys = targetKeys,
			message = message,
		})
	end
end

local function collectPlacementsInArea(
	level: number,
	minCellX: number,
	minCellZ: number,
	maxCellX: number,
	maxCellZ: number,
	placementTypeFilter: string?
): { string }
	local results: { string } = {}
	local seen: { [string]: boolean } = {}
	PlotStateStore.IteratePlacements(function(key, record)
		local placementType = tostring(record.PlacementType or record.Type or "CellObject")
		if placementType ~= "Floor" and placementType ~= "Wall" then
			return
		end
		if placementTypeFilter and placementType ~= placementTypeFilter then
			return
		end
		local placementLevel = record.Level or record.yLevel or PlotStateStore.GetDefaultLevel()
		if placementLevel ~= level then
			return
		end
		local footprint = PlotStateStore.GetPlacementFootprint(key)
		if not footprint then
			return
		end
		if footprint.MinCellX > maxCellX or footprint.MaxCellX < minCellX then
			return
		end
		if footprint.MinCellZ > maxCellZ or footprint.MaxCellZ < minCellZ then
			return
		end
		if seen[key] then
			return
		end
		seen[key] = true
		results[#results + 1] = key
	end)
	return results
end

local function resetDragState()
	dragState = {
		isMouseDown = false,
		isDragging = false,
		placementType = nil,
	}
	clearDragPreview()
end

local function updateDragFromHover(info: HoverInfo?)
	if not dragState.isMouseDown then
		return
	end
	if info then
		dragState.currentCellX = info.cellX
		dragState.currentCellZ = info.cellZ
		if not dragState.level then
			dragState.level = info.level
		end
	end
	if dragState.startCellX and dragState.startCellZ and dragState.currentCellX and dragState.currentCellZ then
		local delta = math.abs((dragState.currentCellX :: number) - dragState.startCellX)
			+ math.abs((dragState.currentCellZ :: number) - dragState.startCellZ)
		if delta >= DRAG_THRESHOLD_CELLS then
			dragState.isDragging = true
		end
	end
	return true
end

local function buildTargetsForDragState(includeHoverFallback: boolean): { string }
	local targets: { string } = {}
	if
		dragState.isDragging
		and dragState.startCellX
		and dragState.startCellZ
		and dragState.currentCellX
		and dragState.currentCellZ
		and dragState.level
	then
		local minCellX = math.min(dragState.startCellX, dragState.currentCellX)
		local maxCellX = math.max(dragState.startCellX, dragState.currentCellX)
		local minCellZ = math.min(dragState.startCellZ, dragState.currentCellZ)
		local maxCellZ = math.max(dragState.startCellZ, dragState.currentCellZ)
		targets =
			collectPlacementsInArea(dragState.level, minCellX, minCellZ, maxCellX, maxCellZ, dragState.placementType)
	elseif dragState.startPlacementKey then
		targets = { dragState.startPlacementKey }
	elseif dragState.startModel and dragState.startModel.Name ~= "" then
		targets = { dragState.startModel.Name }
	elseif includeHoverFallback and hoverInfo then
		targets = { hoverInfo.placementKey }
	end
	return targets
end

local function refreshDragPreview()
	if not dragState.isMouseDown then
		if next(dragPreviewActiveKeys) ~= nil then
			clearDragPreview()
		end
		return
	end
	local targets = buildTargetsForDragState(true)
	if #targets == 0 then
		clearDragPreview()
		return
	end
	applyDragPreviewTargets(targets)
end

local function beginPaintAction()
	if dragState.isMouseDown then
		return
	end
	dragState.isMouseDown = true
	dragState.isDragging = false
	if hoverInfo then
		dragState.startCellX = hoverInfo.cellX
		dragState.startCellZ = hoverInfo.cellZ
		dragState.currentCellX = hoverInfo.cellX
		dragState.currentCellZ = hoverInfo.cellZ
		dragState.level = hoverInfo.level
		dragState.placementType = hoverInfo.placementType
		dragState.startPlacementKey = hoverInfo.placementKey
		dragState.startModel = hoverInfo.model
	else
		dragState.startCellX = nil
		dragState.startCellZ = nil
		dragState.startPlacementKey = nil
		dragState.startModel = nil
		dragState.level = PlotStateStore.GetActiveLevel()
		dragState.placementType = nil
	end
	refreshDragPreview()
end

local function finishPaintAction()
	if not dragState.isMouseDown then
		return
	end
	dragState.isMouseDown = false
	local targets = buildTargetsForDragState(false)
	resetDragState()
	if #targets == 0 then
		return
	end
	if #targets > MAX_BATCH_KEYS then
		warn(("Painting limited to first %d placements."):format(MAX_BATCH_KEYS))
		while #targets > MAX_BATCH_KEYS do
			table.remove(targets)
		end
	end
	sendPaintRequests(targets)
end

local function handlePaintAction(_: string, inputState: Enum.UserInputState): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		beginPaintAction()
		return Enum.ContextActionResult.Sink
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		finishPaintAction()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function bindInput()
	ContextActionService:BindActionAtPriority(
		ACTION_NAME,
		handlePaintAction,
		false,
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton1,
		Enum.UserInputType.Touch
	)
end

local function unbindInput()
	ContextActionService:UnbindAction(ACTION_NAME)
end

local function updateHoverInfo()
	if not isActive then
		return
	end
	local result = raycastPlot()
	local model = result and resolvePlacementModel(result.Instance)
	local info: HoverInfo? = nil
	if model then
		local placementKey = model.Name
		if placementKey ~= "" then
			local entry = PlotStateStore.GetPlacementEntry(placementKey)
			if entry then
				local placementType =
					tostring(entry.PlacementType or entry.Type or model:GetAttribute("PlacementType") or "CellObject")
				if placementType == "Floor" or placementType == "Wall" then
					local footprint = PlotStateStore.GetPlacementFootprint(placementKey)
					local levelValue = entry.Level
						or entry.yLevel
						or (footprint and footprint.Level)
						or PlotStateStore.GetDefaultLevel()
					local cellXValue = entry.cellX or (footprint and footprint.MinCellX)
					local cellZValue = entry.cellZ or (footprint and footprint.MinCellZ)
					info = {
						model = model,
						placementKey = placementKey,
						entry = entry,
						placementType = placementType,
						level = levelValue,
						cellX = cellXValue,
						cellZ = cellZValue,
					}
				end
			end
		end
	end
	local previousKey = hoverInfo and hoverInfo.placementKey or nil
	hoverInfo = info
	setHoverHighlight(info and info.model or nil)
	local dragUpdated = updateDragFromHover(info)
	if dragUpdated then
		refreshDragPreview()
	end
	local currentKey = info and info.placementKey or nil
	if previousKey ~= currentKey then
		local suggestions = buildSuggestions(info)
		BuildPaletteUI.SetSuggestions(suggestions)
	end
end

local function stopHoverUpdates()
	if hoverUpdateConnection then
		hoverUpdateConnection:Disconnect()
		hoverUpdateConnection = nil
	end
	BuildPaletteUI.SetSuggestions({})
	clearHoverHighlight()
	hoverInfo = nil
	resetDragState()
end

local function startHoverUpdates()
	if hoverUpdateConnection then
		return
	end
	hoverUpdateConnection = RunService.RenderStepped:Connect(updateHoverInfo)
	updateHoverInfo()
end

local function applySuggestionToHover(suggestion: PaintSuggestion)
	if not isActive then
		return
	end
	if not hoverInfo then
		return
	end
	sendPaintRequests({ hoverInfo.placementKey }, suggestion.SurfaceId, suggestion.PaintColor)
end

local function stopSession()
	if not isActive then
		return
	end
	isActive = false
	unbindInput()
	BuildPaletteUI.ReleaseCancelButton(CANCEL_SOURCE)
	BuildPaletteUI.SetSelectModeActive(false)
	if paletteHiddenDuringSession or not BuildPaletteUI.IsVisible() then
		BuildPaletteUI.Show()
	end
	paletteHiddenDuringSession = false
	stopHoverUpdates()
	debugLog("Stopped surface paint session", nil)
end

local function startSession()
	if isActive then
		return
	end
	if not PlotStateStore.IsReady() then
		warn("Plot data not ready for surface painting.")
		return
	end
	if not getPlotContainer() then
		warn("Surface painting unavailable until the plot finishes loading.")
		return
	end
	isActive = true
	bindInput()
	BuildPaletteUI.AcquireCancelButton(CANCEL_SOURCE, stopSession)
	BuildPaletteUI.SetSelectModeActive(true)
	paletteHiddenDuringSession = BuildPaletteUI.IsVisible()
	if paletteHiddenDuringSession then
		BuildPaletteUI.Hide()
	end
	startHoverUpdates()
	debugLog("Started surface paint session", {
		paletteWasVisible = paletteHiddenDuringSession,
		surfaceId = BuildPaletteUI.GetSelectedSurfaceId() or "",
		colorOverride = serializeColor(BuildPaletteUI.GetSelectedColorOverride()),
	})
end

function SurfacePaintController.Init()
	if not suggestionConnection then
		suggestionConnection = BuildPaletteUI.OnSuggestionSelected(function(suggestion)
			applySuggestionToHover(suggestion)
		end)
	end
	BuildPaletteUI.OnSelectActivated(function()
		debugLog("Select button activated", {
			isActive = isActive,
		})
		if isActive then
			stopSession()
		else
			startSession()
		end
	end)
end

function SurfacePaintController.IsActive(): boolean
	return isActive
end

function SurfacePaintController.Stop()
	stopSession()
end

return SurfacePaintController
