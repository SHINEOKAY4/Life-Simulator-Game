--!strict
-- StarterPlayerScripts/Client/Modules/ObjectAction.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local ObjectPreview = require(script.Parent.ObjectPreview)
local PlotBuilder = require(script.Parent.PlotBuilder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementHelpers = require(ReplicatedStorage.Shared.Utilities.PlacementHelpers)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ObjectPreviewEnabled = ActiveQueryFolder.ObjectPreviewEnabled :: BoolValue
local RadialBillboardButtonEnabled = ActiveQueryFolder.RadialBillboardButtonEnabled :: BoolValue

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local ObjectActionContext = InputContextsFolder:WaitForChild("ObjectActionContext")

local ObjectAction = {}
local INPUT_DEBOUNCE_SECONDS = 0.25
local CurrentSelectedObject: Model? = nil
local SelectedObjectOriginalParent: Instance? = nil
local DetachedPreviewObject: Model? = nil
local DetachedPreviewOriginalParent: Instance? = nil
local TemporaryRestoredWall: Model? = nil

local function destroyTemporaryWall()
	if TemporaryRestoredWall then
		if TemporaryRestoredWall:GetAttribute("TemporaryDoorWallRestore") then
			TemporaryRestoredWall:Destroy()
		else
			TemporaryRestoredWall.Parent = nil
		end
		TemporaryRestoredWall = nil
	end
end

local function clearDetachedPreviewState()
	CurrentSelectedObject = nil
	SelectedObjectOriginalParent = nil
	DetachedPreviewObject = nil
	DetachedPreviewOriginalParent = nil
	destroyTemporaryWall()
end

local function captureDetachedPreview(object: Model?, originalParent: Instance?)
	if not object then
		return
	end
	CurrentSelectedObject = object
	SelectedObjectOriginalParent = originalParent
	DetachedPreviewObject = object
	DetachedPreviewOriginalParent = originalParent
end

local function restoreDetachedPreview(): boolean
	local object = CurrentSelectedObject or DetachedPreviewObject
	if not object then
		return false
	end

	local originalParent = SelectedObjectOriginalParent or DetachedPreviewOriginalParent
	if not originalParent or originalParent.Parent == nil then
		return false
	end

	object.Parent = originalParent --#TODO: Bug (The Parent property of 2:15:South:Wall is locked, current parent: NULL, new parent Container )

	-- Currently harmless but unsightly, ideally should be fixed properly
	clearDetachedPreviewState()
	return true
end

type Facing = ObjectPreview.Facing
type PreviewPose = ObjectPreview.PreviewPose

local function sanitizeFacing(value: any): Facing
	if value == "North" or value == "East" or value == "South" or value == "West" then
		return value
	end
	return "North"
end

local function getObjectItemId(object: Model): string?
	local attr = object:GetAttribute("ItemId")
	if typeof(attr) == "string" and attr ~= "" then
		return attr
	end
	local fallback = object.Name
	if typeof(fallback) == "string" and fallback ~= "" then
		return fallback
	end
	return nil
end

local function spawnTemporaryWallFill(object: Model, parent: Instance)
	destroyTemporaryWall()

	local previousWallIdAttr = object:GetAttribute("PreviousWallId")
	if typeof(previousWallIdAttr) ~= "string" or previousWallIdAttr == "" then
		return
	end

	local cellX = tonumber(object:GetAttribute("CellX"))
	local cellZ = tonumber(object:GetAttribute("CellZ"))
	if not cellX or not cellZ then
		return
	end

	local facingAttr = object:GetAttribute("Facing")
	local facing: Facing = sanitizeFacing(facingAttr)

	local grid = PlotStateStore.GetGrid()
	if not grid then
		return
	end

	local wallModel = ItemFinder.CloneModel(previousWallIdAttr)
	if not wallModel then
		return
	end

	local base = grid:CellToWorldEdgeCenterCFrame(cellX, cellZ, facing)
	local lift = PlacementHelpers.GetLiftFromPivotToBottom(wallModel)
	wallModel:PivotTo(base * CFrame.new(0, lift, 0))

	wallModel:SetAttribute("ItemId", previousWallIdAttr)
	wallModel:SetAttribute("CellX", cellX)
	wallModel:SetAttribute("CellZ", cellZ)
	wallModel:SetAttribute("Facing", facing)
	wallModel:SetAttribute("TemporaryDoorWallRestore", true)

	for _, descendant in wallModel:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanTouch = false
			descendant.CanQuery = true
		end
	end

	wallModel.Parent = parent
	TemporaryRestoredWall = wallModel
end

local function PlaceSelectedPreview(object: Model)
	local pose = ObjectPreview.GetCurrentPose() :: PreviewPose?
	if not pose then
		warn("No valid pose for placing object.")
		return
	end
	if pose.Kind == "SurfaceMounted" then
		warn("Move is not supported for surface-mounted items yet.")
		ObjectPreview.ClearPreview()
		if not restoreDetachedPreview() then
			clearDetachedPreviewState()
		end
		return
	end

	-- Fire move request to server here
	local fromCellX = tonumber(object:GetAttribute("CellX")) :: number
	local fromCellZ = tonumber(object:GetAttribute("CellZ")) :: number

	local fromFacingAttr = object:GetAttribute("Facing")
	local fromFacing = if typeof(fromFacingAttr) == "string" and fromFacingAttr ~= ""
		then fromFacingAttr :: string
		else "North"

	local itemId = getObjectItemId(object)
	if not itemId then
		warn("Cannot move object without item id")
		return
	end

	local toFacing = pose.Facing
	if pose.Kind == "Floor" then
		toFacing = "North"
	end

	local fromLevelAttr = tonumber(object:GetAttribute("Level"))
	local fromLevelRaw = fromLevelAttr or PlotStateStore.GetActiveLevel() or 0
	local fromLevel = math.floor(math.clamp(fromLevelRaw, 0, 255) + 0.5)
	local poseLevelValue = pose.Level
	local toLevelRaw = if typeof(poseLevelValue) == "number" then poseLevelValue else fromLevel
	local toLevel = math.floor(math.clamp(toLevelRaw, 0, 255) + 0.5)

	local payload = {
		ItemId = itemId,
		FromCellX = fromCellX,
		FromCellZ = fromCellZ,
		FromFacing = fromFacing,
		FromLevel = fromLevel,
		ToCellX = pose.CellX,
		ToCellZ = pose.CellZ,
		ToFacing = toFacing,
		ToLevel = toLevel,
	}

	local isNoOpMove = fromCellX == pose.CellX
		and fromCellZ == pose.CellZ
		and fromFacing == toFacing
		and fromLevel == toLevel
	if isNoOpMove then
		ObjectActionContext.ClickMoveRequest.Enabled = false
		ObjectPreview.ClearPreview()
		if not restoreDetachedPreview() then
			clearDetachedPreviewState()
		end
		return
	end

	local success, result = Packets.MoveRequest:Fire(payload)
	if not success then
		warn("Move request failed:", result)
		local restored = restoreDetachedPreview()
		if not restored then
			clearDetachedPreviewState()
		end
		ObjectActionContext.ClickMoveRequest.Enabled = false
		ObjectPreview.ClearPreview()
		return
	end

	ObjectActionContext.ClickMoveRequest.Enabled = false
	ObjectPreview.ClearPreview()
	if isNoOpMove then
		if not restoreDetachedPreview() then
			clearDetachedPreviewState()
		end
	else
		clearDetachedPreviewState()
	end
end

function ObjectAction.Init()
	ObjectPreviewEnabled.Changed:Connect(function()
		-- if object previewing is cancelled while in the middle of a move action, cancel the move action and reparent the object back to its original parent
		if not ObjectPreviewEnabled.Value and ObjectActionContext.ClickMoveRequest.Enabled then
			ObjectActionContext.ClickMoveRequest.Enabled = false

			if not restoreDetachedPreview() then
				warn("No current selected object to reparent.")
				clearDetachedPreviewState()
			end
		end
	end)

	ObjectActionContext.ClickMoveRequest.Pressed:Connect(function()
		Debounce.RunIfAvailable("ObjectAction/ClickMove", INPUT_DEBOUNCE_SECONDS, function()
			local object = CurrentSelectedObject or DetachedPreviewObject
			if not object then
				warn("No object selected for move action.")
				return
			end

			if RadialBillboardButtonEnabled.Value then
				return
			end
			PlaceSelectedPreview(object)
		end, Player.UserId)
	end)
end

function ObjectAction.Move(object: Model, newPosition: Vector3)
	print("Moving object:", object:GetFullName(), "to new position:", newPosition)
	-- Implement movement logic here
	-- Visual and mechanic goals: The original object gets parented to nil to sell the illusion of movement
	-- The objectpreview of that object is now shown visually following the cursor to sell the illusion of movement
	-- When the player clicks a position during object previewing, to place must send a move request to the server with the new position
	-- the objectpreview is hidden and the visuals are taken care of by the server world placer
	local itemId = getObjectItemId(object)
	if not itemId then
		warn("Cannot move object without item id")
		return
	end

	local spec = ItemFinder.FindItemById(itemId)
	local originalParent = object.Parent
	if spec and originalParent then
		local placementType = spec.PlacementType or spec.Type or "CellObject"
		if placementType == "Wall" and spec.RequiresExistingWall == true then
			spawnTemporaryWallFill(object, originalParent)
		end
	end
	captureDetachedPreview(object, originalParent)
	object.Parent = nil
	local facingAttr = object:GetAttribute("Facing")
	local initialFacing: Facing = if typeof(facingAttr) == "string" and facingAttr ~= ""
		then facingAttr :: Facing
		else "North"
	ObjectPreview.RenderPreview(itemId, initialFacing)

	local cellXAttr = tonumber(object:GetAttribute("CellX"))
	local cellZAttr = tonumber(object:GetAttribute("CellZ"))
	local widthAttr = tonumber(object:GetAttribute("WidthCells"))
	local depthAttr = tonumber(object:GetAttribute("DepthCells"))
	local levelAttr = tonumber(object:GetAttribute("Level"))
	local fromLevelValue = if levelAttr ~= nil then levelAttr else PlotStateStore.GetActiveLevel()
	local fromLevel = math.floor(math.clamp(fromLevelValue, 0, 255) + 0.5)
	if cellXAttr ~= nil and cellZAttr ~= nil then
		ObjectPreview.SetMoveOrigin({
			ItemId = itemId,
			CellX = cellXAttr,
			CellZ = cellZAttr,
			Facing = initialFacing,
			WidthCells = widthAttr,
			DepthCells = depthAttr,
			Level = fromLevel,
		})
	else
		ObjectPreview.SetMoveOrigin(nil)
	end
	ObjectActionContext.ClickMoveRequest.Enabled = true
end

function ObjectAction.Rotate(object: Model, rotation: Vector3)
	print("Rotating object:", object:GetFullName(), "to new rotation:", rotation)
	local itemId = getObjectItemId(object)
	if not itemId then
		warn("Unknown item id for rotation")
		return
	end
	local spec = ItemFinder.FindItemById(itemId)
	if not spec then
		warn("Unknown item id for rotation:", itemId)
		return
	end

	local placementType = spec.PlacementType or spec.Type or "CellObject"
	if placementType == "Floor" then
		warn("Floors cannot be rotated.")
		return
	end

	local currentFacingAttr = object:GetAttribute("Facing")
	local currentFacing: Facing = sanitizeFacing(currentFacingAttr)
	local levelAttr = tonumber(object:GetAttribute("Level"))
	local rotateLevelValue = if levelAttr ~= nil then levelAttr else PlotStateStore.GetActiveLevel()
	local rotateLevel = math.floor(math.clamp(rotateLevelValue, 0, 255) + 0.5)

	local allowedFacing = spec.Facing :: { Facing }?
	local nextFacing: Facing
	if allowedFacing and #allowedFacing > 0 then
		local index = table.find(allowedFacing, currentFacing) or 0
		nextFacing = allowedFacing[(index % #allowedFacing) + 1]
	else
		local cycle: { Facing } = { "North", "East", "South", "West" }
		local index = table.find(cycle, currentFacing) or 0
		nextFacing = cycle[(index % #cycle) + 1]
	end

	if nextFacing == currentFacing then
		nextFacing = currentFacing
	end

	local cellXAttr = tonumber(object:GetAttribute("CellX"))
	local cellZAttr = tonumber(object:GetAttribute("CellZ"))
	if not cellXAttr or not cellZAttr then
		warn("Cannot rotate object without cell coordinates")
		return
	end

	local normalizedFacing = PlacementKey.NormalizeFacing(currentFacing :: any)
	local fromKey =
		PlacementKey.ForPlacementType(cellXAttr, cellZAttr, normalizedFacing :: any, placementType, rotateLevel)

	local success, message = Packets.RotateRequest:Fire({
		ItemId = itemId,
		FromKey = fromKey,
		ToFacing = nextFacing,
	})

	if not success then
		warn("Rotate request failed:", message)
		return
	end

	object:SetAttribute("Facing", nextFacing)
end

function ObjectAction.Delete(object: Model)
	print("Deleting object:", object:GetFullName())
	-- Implement deletion logic here
	local itemId = getObjectItemId(object)
	if not itemId then
		warn("Cannot delete object without item id")
		return
	end

	local placementTypeAttr = object:GetAttribute("PlacementType")
	if placementTypeAttr == "SurfaceMounted" then
		local mountKeyAttr = object:GetAttribute("MountKey")
		if typeof(mountKeyAttr) ~= "string" or mountKeyAttr == "" then
			warn("Cannot delete surface mount without mount key")
			return
		end
		local success, message = Packets.DestroySurfaceMountRequest:Fire({
			MountKey = mountKeyAttr,
		})
		if not success then
			warn("Surface mount deletion failed:", message)
		end
		return
	end

	local cellXValue = tonumber(object:GetAttribute("CellX"))
	local cellZValue = tonumber(object:GetAttribute("CellZ"))
	if not cellXValue or not cellZValue then
		warn("Cannot delete object without cell coordinates")
		return
	end

	local facingAttr = object:GetAttribute("Facing")
	local facing = if typeof(facingAttr) == "string" and facingAttr ~= "" then facingAttr else "North"

	local levelAttr = object:GetAttribute("Level")
	local levelNumber = if typeof(levelAttr) == "number" then levelAttr else PlotStateStore.GetActiveLevel()
	if typeof(levelNumber) ~= "number" then
		levelNumber = 0
	end
	levelNumber = math.clamp(levelNumber, 0, 255)

	local success, message = Packets.DestroyRequest:Fire({
		ItemId = itemId,
		CellX = cellXValue,
		CellZ = cellZValue,
		Facing = facing,
		Level = levelNumber,
	})
	if not success then
		warn("Deletion failed:", message)
	end
end

-- #TODO: Bug fix the copy and close mechanic (while on the copy preview, clicking the close action does not stop object selection mode)
function ObjectAction.Copy(object: Model)
	print("Copying object:", object:GetFullName())
	-- Implement copy logic here
	local itemId = getObjectItemId(object)
	if not itemId then
		warn("Cannot copy object without item id")
		return
	end
	local facing = object:GetAttribute("Facing") :: string
	PlotBuilder.PreviewSelected(itemId, facing)
end

function ObjectAction.Close()
	ObjectPreview.ClearPreview()
	if restoreDetachedPreview() then
		return
	end

	if CurrentSelectedObject then
		CurrentSelectedObject:Destroy()
	end
	clearDetachedPreviewState()
end
return ObjectAction
