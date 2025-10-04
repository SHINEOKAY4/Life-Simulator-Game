--!strict
-- StarterPlayerScripts/Client/Modules/ObjectAction.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local ObjectPreview = require(script.Parent.ObjectPreview)
local PlotBuilder = require(script.Parent.PlotBuilder)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local PlacementKey = require(ReplicatedStorage.Shared.Utilities.PlacementKey)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local ObjectPreviewEnabled = ActiveQueryFolder:FindFirstChild("ObjectPreviewEnabled")
local RadialBillboardButtonEnabled = ActiveQueryFolder:WaitForChild("RadialBillboardButtonEnabled") :: BoolValue

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local ObjectActionContext = InputContextsFolder:WaitForChild("ObjectActionContext")

local ObjectAction = {}
local CurrentSelectedObject: Model? = nil
local SelectedObjectOriginalParent: Instance? = nil
local DetachedPreviewObject: Model? = nil
local DetachedPreviewOriginalParent: Instance? = nil

local function clearDetachedPreviewState()
	CurrentSelectedObject = nil
	SelectedObjectOriginalParent = nil
	DetachedPreviewObject = nil
	DetachedPreviewOriginalParent = nil
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

	object.Parent = originalParent
	clearDetachedPreviewState()
	return true
end

type Facing = "North" | "East" | "South" | "West"
type PreviewKind = "CellObject" | "Floor" | "Wall" | "Roof"
type PreviewPose = {
	ItemId: string,
	CellX: number,
	CellZ: number,
	Facing: Facing,
	Kind: PreviewKind,
}

local function sanitizeFacing(value: any): Facing
	if value == "North" or value == "East" or value == "South" or value == "West" then
		return value
	end
	return "North"
end

local function PlaceSelectedPreview(object: Model)
	local pose = ObjectPreview.GetCurrentPose() :: PreviewPose?
	if not pose then
		warn("No valid pose for placing object.")
		return
	end

	-- Fire move request to server here
	local fromCellX = tonumber(object:GetAttribute("CellX")) :: number
	local fromCellZ = tonumber(object:GetAttribute("CellZ")) :: number

	local fromFacingAttr = object:GetAttribute("Facing")
	local fromFacing = if typeof(fromFacingAttr) == "string" and fromFacingAttr ~= ""
		then fromFacingAttr :: string
		else "North"

	local toFacing = pose.Facing
	if pose.Kind == "Floor" then
		toFacing = "North"
	end

	local payload = {
		ItemId = object.Name,
		FromCellX = fromCellX,
		FromCellZ = fromCellZ,
		FromFacing = fromFacing,
		ToCellX = pose.CellX,
		ToCellZ = pose.CellZ,
		ToFacing = toFacing,
	}

	local success, result = Packets.MoveRequest:Fire(payload)
	if not success then
		warn("Move request failed:", result)
		-- Do not reparent for now, let the player try again/ better game experience
		-- Toast or UI feedback could be added here
		-- And visual effect to indicate failure
		return
	end

	ObjectActionContext.ClickMoveRequest.Enabled = false
	ObjectPreview.ClearPreview()
	clearDetachedPreviewState()
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
		local object = CurrentSelectedObject or DetachedPreviewObject
		if not object then
			warn("No object selected for move action.")
			return
		end

		if RadialBillboardButtonEnabled.Value then
			return
		end
		PlaceSelectedPreview(object)
	end)
end

function ObjectAction.Move(object: Model, newPosition: Vector3)
	print("Moving object:", object:GetFullName(), "to new position:", newPosition)
	-- Implement movement logic here
	-- Visual and mechanic goals: The original object gets parented to nil to sell the illusion of movement
	-- The objectpreview of that object is now shown visually following the cursor to sell the illusion of movement
	-- When the player clicks a position during object previewing, to place must send a move request to the server with the new position
	-- the objectpreview is hidden and the visuals are taken care of by the server world placer
	local originalParent = object.Parent
	captureDetachedPreview(object, originalParent)
	object.Parent = nil
	local facingAttr = object:GetAttribute("Facing")
	local initialFacing: Facing = if typeof(facingAttr) == "string" and facingAttr ~= ""
		then facingAttr :: Facing
		else "North"
	ObjectPreview.RenderPreview(object.Name, initialFacing)

	local cellXAttr = tonumber(object:GetAttribute("CellX"))
	local cellZAttr = tonumber(object:GetAttribute("CellZ"))
	if cellXAttr ~= nil and cellZAttr ~= nil then
		ObjectPreview.SetMoveOrigin({
			ItemId = object.Name,
			CellX = cellXAttr,
			CellZ = cellZAttr,
			Facing = initialFacing,
		})
	else
		ObjectPreview.SetMoveOrigin(nil)
	end
	ObjectActionContext.ClickMoveRequest.Enabled = true
end

function ObjectAction.Rotate(object: Model, rotation: Vector3)
	print("Rotating object:", object:GetFullName(), "to new rotation:", rotation)
	local itemId = object.Name
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

	local normalizedFacing: Facing = PlacementKey.NormalizeFacing(currentFacing)
	local fromKey = PlacementKey.ForPlacementType(cellXAttr, cellZAttr, normalizedFacing, placementType)

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
	local itemData = {
		ItemId = object.Name,
		CellX = tonumber(object:GetAttribute("CellX")) :: number,
		CellZ = tonumber(object:GetAttribute("CellZ")) :: number,
		Facing = object:GetAttribute("Facing") :: string,
	}
	Packets.DestroyRequest:Fire(itemData)
end

function ObjectAction.Copy(object: Model)
	print("Copying object:", object:GetFullName())
	-- Implement copy logic here
	local facing = object:GetAttribute("Facing") :: string
	PlotBuilder.PreviewSelected(object.Name, facing)
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
