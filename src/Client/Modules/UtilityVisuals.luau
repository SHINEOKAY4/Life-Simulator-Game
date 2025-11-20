--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/UtilityVisuals.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)
local SelectionController = require(script.Parent.SelectionController)

local UtilityVisuals = {}
local Icons = {} -- [key] = BillboardGui
local RadiusVisual: BasePart? = nil
local SelectionHighlight: Highlight? = nil
local ConnectionCountVisual: BillboardGui? = nil
local WireBeams = {} -- [connectionKey] = {Beam, Attachment0, Attachment1}

local POWER_ICON = "⚡"
local POWER_OFF_ICON = "🔌" -- Plug icon for unpowered state
local WATER_ICON = "💧"

local function getWireAttachmentPosition(instance: Instance, spec: any): Vector3
	if instance:IsA("Model") then
		local att = instance:FindFirstChild("WireAttachment", true)
		if att and att:IsA("Attachment") then
			return att.WorldPosition
		end
		local cf, size = instance:GetBoundingBox()
		if spec and spec.PlacementType == "Wall" then
			return cf.Position -- Center for wall items
		end
		return cf.Position - Vector3.new(0, size.Y / 2, 0) -- Bottom for floor items
	elseif instance:IsA("BasePart") then
		if spec and spec.PlacementType == "Wall" then
			return instance.Position
		end
		return instance.Position - Vector3.new(0, instance.Size.Y / 2, 0)
	end
	return Vector3.zero
end

local function getWireKey(key1: string, key2: string)
	if key1 < key2 then
		return key1 .. "_" .. key2
	else
		return key2 .. "_" .. key1
	end
end

local function drawWire(key1: string, key2: string)
	local wKey = getWireKey(key1, key2)
	if WireBeams[wKey] then
		return
	end

	local inst1 = PlotStateStore.ResolvePlacementInstance(key1)
	local inst2 = PlotStateStore.ResolvePlacementInstance(key2)
	local entry1 = PlotStateStore.GetPlacementEntry(key1)
	local entry2 = PlotStateStore.GetPlacementEntry(key2)

	if not inst1 or not inst2 or not entry1 or not entry2 then
		return
	end

	local spec1 = ItemFinder.FindItemById(entry1.id)
	local spec2 = ItemFinder.FindItemById(entry2.id)

	local pos1 = getWireAttachmentPosition(inst1, spec1)
	local pos2 = getWireAttachmentPosition(inst2, spec2)

	if pos1 == Vector3.zero or pos2 == Vector3.zero then
		return
	end

	local terrain = Workspace.Terrain
	local att0 = Instance.new("Attachment")
	att0.WorldPosition = pos1
	att0.Parent = terrain

	local att1 = Instance.new("Attachment")
	att1.WorldPosition = pos2
	att1.Parent = terrain

	local beam = Instance.new("Beam")
	beam.Attachment0 = att0
	beam.Attachment1 = att1

	-- Determine color based on type
	local isWater = spec1 and (spec1.WaterSource or spec1.WaterConductor)
	if isWater then
		beam.Color = ColorSequence.new(Color3.fromRGB(0, 150, 255)) -- Blue for water
	else
		beam.Color = ColorSequence.new(Color3.fromRGB(255, 170, 0)) -- Bright Orange/Gold for power
	end

	beam.FaceCamera = true
	beam.Width0 = 0.2
	beam.Width1 = 0.2
	beam.Transparency = NumberSequence.new(0)
	beam.Parent = terrain

	WireBeams[wKey] = { Beam = beam, Attachment0 = att0, Attachment1 = att1 }
end

local forceShowWires = false

local function shouldShowWires()
	if forceShowWires then
		return true
	end

	local _, key = SelectionController.GetSelection()
	if not key then
		return false
	end

	local entry = PlotStateStore.GetPlacementEntry(key)
	if not entry then
		return false
	end

	local spec = ItemFinder.FindItemById(entry.id)
	if not spec then
		return false
	end

	return spec.PowerSource
		or spec.PowerConductor
		or spec.RequiresPower
		or spec.RequiresWater
		or spec.WaterSource
		or spec.WaterConductor
end

local function updateWires()
	local state = PlotStateStore.GetStateSnapshot()
	if not state or not state.PlacedItems then
		return
	end

	local show = shouldShowWires()
	local activeWireKeys = {}

	if show then
		for key, entry in pairs(state.PlacedItems) do
			local metadata = entry.Metadata or {}
			if metadata.Connections then
				for _, otherKey in ipairs(metadata.Connections) do
					local wKey = getWireKey(key, otherKey)
					activeWireKeys[wKey] = true
					drawWire(key, otherKey)
				end
			end
		end
	end

	-- Cleanup removed wires
	for wKey, data in pairs(WireBeams) do
		if not activeWireKeys[wKey] then
			if data.Beam then
				data.Beam:Destroy()
			end
			if data.Attachment0 then
				data.Attachment0:Destroy()
			end
			if data.Attachment1 then
				data.Attachment1:Destroy()
			end
			WireBeams[wKey] = nil
		end
	end
end

local function updateSelectionVisuals()
	local adornee, key = SelectionController.GetSelection()

	-- Handle Highlight
	if adornee and key then
		local entry = PlotStateStore.GetPlacementEntry(key)
		if entry then
			local spec = ItemFinder.FindItemById(entry.id)
			if
				spec
				and (
					spec.PowerSource
					or spec.PowerConductor
					or spec.RequiresPower
					or spec.RequiresWater
					or spec.WaterSource
					or spec.WaterConductor
				)
			then
				if not SelectionHighlight then
					local hl = Instance.new("Highlight")
					hl.FillColor = Color3.fromRGB(0, 255, 0)
					hl.FillTransparency = 0.5
					hl.OutlineColor = Color3.fromRGB(255, 255, 255)
					hl.Parent = Players.LocalPlayer.PlayerGui -- Or CoreGui if possible, but PlayerGui is safe
					SelectionHighlight = hl
				end
				local hl = SelectionHighlight :: Highlight
				hl.Adornee = adornee
			else
				if SelectionHighlight then
					SelectionHighlight.Adornee = nil
				end
			end
		else
			if SelectionHighlight then
				SelectionHighlight.Adornee = nil
			end
		end
	else
		if SelectionHighlight then
			SelectionHighlight.Adornee = nil
		end
	end

	-- Handle Radius Visual
	if adornee and key then
		local entry = PlotStateStore.GetPlacementEntry(key)
		local spec = entry and ItemFinder.FindItemById(entry.id)
		local radius = spec and spec.PowerRadius

		if radius then
			if not RadiusVisual then
				local part = Instance.new("Part")
				part.Name = "RadiusVisual"
				part.Shape = Enum.PartType.Cylinder
				part.Anchored = true
				part.CanCollide = false
				part.CastShadow = false
				part.Material = Enum.Material.Neon
				part.Transparency = 0.85
				part.Color = Color3.fromRGB(100, 255, 255)
				part.TopSurface = Enum.SurfaceType.Smooth
				part.BottomSurface = Enum.SurfaceType.Smooth
				RadiusVisual = part
			end

			local visual = RadiusVisual :: BasePart
			local position: Vector3
			if adornee:IsA("Model") then
				position = adornee:GetPivot().Position
			elseif adornee:IsA("BasePart") then
				position = adornee.Position
			else
				position = Vector3.zero
			end

			visual.Size = Vector3.new(0.2, radius * 2, radius * 2)
			visual.CFrame = CFrame.new(position) * CFrame.Angles(0, 0, math.rad(90))
			visual.Parent = Workspace.CurrentCamera
		else
			if RadiusVisual then
				RadiusVisual.Parent = nil
			end
		end
	else
		if RadiusVisual then
			RadiusVisual.Parent = nil
		end
	end

	-- Handle Connection Count Visual
	if not adornee or not key then
		if ConnectionCountVisual then
			ConnectionCountVisual.Enabled = false
		end
	else
		-- Reuse entry/spec from Radius logic if available, or fetch
		local selectedEntry = PlotStateStore.GetPlacementEntry(key)
		local selectedSpec = selectedEntry and ItemFinder.FindItemById(selectedEntry.id)

		if selectedSpec and selectedSpec.MaxConnections then
			if not ConnectionCountVisual then
				local bb = Instance.new("BillboardGui")
				bb.Name = "ConnectionCountVisual"
				bb.Size = UDim2.fromOffset(120, 26)
				bb.StudsOffset = Vector3.new(0, 4.5, 0)
				bb.AlwaysOnTop = true
				bb.Parent = Players.LocalPlayer.PlayerGui

				local frame = Instance.new("Frame")
				frame.Size = UDim2.fromScale(1, 1)
				frame.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
				frame.BackgroundTransparency = 0.3
				frame.BorderSizePixel = 0
				frame.Parent = bb

				local uiCorner = Instance.new("UICorner")
				uiCorner.CornerRadius = UDim.new(0, 6)
				uiCorner.Parent = frame

				local txt = Instance.new("TextLabel")
				txt.Size = UDim2.fromScale(1, 1)
				txt.BackgroundTransparency = 1
				txt.TextColor3 = Color3.fromRGB(255, 255, 255)
				txt.Font = Enum.Font.GothamBold
				txt.TextSize = 14
				txt.Parent = frame

				ConnectionCountVisual = bb
			end

			local bb = ConnectionCountVisual :: BillboardGui
			bb.Adornee = adornee
			bb.Enabled = true

			local current = 0
			if selectedEntry and selectedEntry.Metadata and selectedEntry.Metadata.Connections then
				current = #selectedEntry.Metadata.Connections
			end

			local frame = bb:FindFirstChild("Frame")
			if frame then
				local lbl = frame:FindFirstChild("TextLabel") :: TextLabel
				if lbl then
					lbl.Text = string.format("Connections: %d / %d", current, selectedSpec.MaxConnections)

					if current >= selectedSpec.MaxConnections then
						lbl.TextColor3 = Color3.fromRGB(255, 80, 80)
					else
						lbl.TextColor3 = Color3.fromRGB(255, 255, 255)
					end
				end
			end
		else
			if ConnectionCountVisual then
				ConnectionCountVisual.Enabled = false
			end
		end
	end
end

local function updateVisuals()
	local state = PlotStateStore.GetStateSnapshot()
	if not state or not state.PlacedItems then
		return
	end

	local showAll = shouldShowWires()
	local activeKeys = {}

	for key, entry in pairs(state.PlacedItems) do
		activeKeys[key] = true
		local spec = ItemFinder.FindItemById(entry.id)
		if not spec then
			continue
		end

		local needsPower = spec.RequiresPower or spec.PowerConductor or spec.PowerSource
		local needsWater = spec.RequiresWater or spec.WaterSource or spec.WaterConductor

		if not needsPower and not needsWater then
			continue
		end

		local metadata = entry.Metadata or {}
		local isPowered = metadata.IsPowered == true or spec.PowerSource == true
		local isWatered = metadata.IsWatered == true or spec.WaterSource == true

		-- Show icon if we are in "utility mode" (something selected) OR if there is a problem (unpowered/unwatered)
		-- Actually, user asked for "when i click a generator", implying they want to see the network status.
		-- Let's stick to: Show if shouldShowWires() is true.
		local showIcon = showAll

		if showIcon then
			local icon = Icons[key]
			if not icon then
				icon = Instance.new("BillboardGui")
				icon.Size = UDim2.fromOffset(32, 32) -- Larger for visibility
				icon.AlwaysOnTop = true
				icon.StudsOffset = Vector3.new(0, 3, 0) -- Higher offset
				icon.MaxDistance = 80 -- Visible from further away

				local lbl = Instance.new("TextLabel")
				lbl.Size = UDim2.fromScale(1, 1)
				lbl.BackgroundTransparency = 1
				lbl.TextScaled = true
				lbl.Font = Enum.Font.GothamBold
				lbl.Parent = icon

				local instance = PlotStateStore.ResolvePlacementInstance(key)
				if instance and instance:IsA("Model") and instance.PrimaryPart then
					icon.Adornee = instance.PrimaryPart
				elseif instance and instance:IsA("BasePart") then
					icon.Adornee = instance
				else
					icon:Destroy()
					continue
				end

				icon.Parent = Players.LocalPlayer.PlayerGui
				Icons[key] = icon
			end

			local lbl = icon:FindFirstChildOfClass("TextLabel")
			if lbl then
				if needsPower then
					if isPowered then
						lbl.Text = POWER_ICON
						lbl.TextColor3 = Color3.fromRGB(255, 220, 0) -- Yellow for powered
						lbl.TextTransparency = 0 -- Fully visible when powered
					else
						-- Unpowered state (Consumer OR Conductor)
						lbl.Text = POWER_OFF_ICON
						lbl.TextColor3 = Color3.fromRGB(255, 50, 50)
						lbl.TextTransparency = 0
					end
				elseif needsWater then
					lbl.Text = WATER_ICON
					if isWatered then
						lbl.TextColor3 = Color3.fromRGB(0, 150, 255) -- Blue for watered
						lbl.TextTransparency = 0.2
					else
						lbl.TextColor3 = Color3.fromRGB(255, 50, 50) -- Red for unwatered
						lbl.TextTransparency = 0
					end
				end
			end
		else
			if Icons[key] then
				Icons[key]:Destroy()
				Icons[key] = nil
			end
		end
	end

	-- Cleanup removed items
	for key, icon in pairs(Icons) do
		if not activeKeys[key] then
			icon:Destroy()
			Icons[key] = nil
		end
	end
end

function UtilityVisuals.Init()
	PlotStateStore.OnPlacementMetadataChanged(function()
		updateVisuals()
		updateWires()
		updateSelectionVisuals()
	end)
	PlotStateStore.OnRoomSnapshotChanged(function()
		updateVisuals()
		updateSelectionVisuals()
		updateWires()
	end)

	-- Listen for selection changes to show radius
	SelectionController.OnSelectionChanged(function()
		updateSelectionVisuals()
		updateWires()
		updateVisuals()
	end)
end

function UtilityVisuals.SetForceShow(val: boolean)
	forceShowWires = val
	updateWires()
end

return UtilityVisuals
