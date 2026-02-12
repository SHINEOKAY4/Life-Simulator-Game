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
local WireBeams = {} -- [connectionKey] = { {Beam, Attachment0, Attachment1}, ... }

local function getFloorY(level: number?): number
	local surface = PlotStateStore.GetSurface()
	if not surface then
		return 0
	end
	local baseHeight = surface.Position.Y + surface.Size.Y / 2
	local lvl = level or PlotStateStore.GetActiveLevel()
	return baseHeight + (lvl * PlotStateStore.GetFloorHeightStuds()) + 0.2 -- +0.2 offset to sit on top of floor
end

function UtilityVisuals.GetWirePath(p1: Vector3, p2: Vector3, floorY: number): { Vector3 }
	local points = {}

	-- Start
	table.insert(points, p1)

	local p1Ground = Vector3.new(p1.X, floorY, p1.Z)
	local p2Ground = Vector3.new(p2.X, floorY, p2.Z)

	-- Drop to floor if needed
	if math.abs(p1.Y - floorY) > 0.5 then
		table.insert(points, p1Ground)
	end

	-- Corner (Manhattan)
	-- Try to route along X then Z, or Z then X?
	-- Simple X then Z for now
	local corner = Vector3.new(p2Ground.X, floorY, p1Ground.Z)

	-- Only add corner if it creates a distinct segment
	local last = points[#points]
	if (corner - last).Magnitude > 0.1 and (corner - p2Ground).Magnitude > 0.1 then
		table.insert(points, corner)
	end

	-- Move to under target
	if (p2Ground - points[#points]).Magnitude > 0.1 then
		table.insert(points, p2Ground)
	end

	-- Rise to target if needed
	if math.abs(p2.Y - floorY) > 0.5 then
		table.insert(points, p2)
	else
		-- If we are already at floor level, ensure the last point connects to p2
		if (p2 - points[#points]).Magnitude > 0.1 then
			table.insert(points, p2)
		end
	end

	-- Filter close points
	local filtered = { points[1] }
	for i = 2, #points do
		if (points[i] - filtered[#filtered]).Magnitude > 0.1 then
			table.insert(filtered, points[i])
		end
	end

	return filtered
end

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

local function drawWire(keyA: string, keyB: string)
	-- Enforce deterministic order so the path (L-shape vs Gamma-shape) is consistent
	local key1, key2 = keyA, keyB
	if key1 > key2 then
		key1, key2 = key2, key1
	end

	local wKey = key1 .. "_" .. key2
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

	-- Determine floor Y
	local level = entry1.Level or 0
	local floorY = getFloorY(level)

	local path = UtilityVisuals.GetWirePath(pos1, pos2, floorY)
	local segments = {}
	local terrain = Workspace.Terrain

	-- Determine color based on type
	local isWater = spec1 and (spec1.WaterSource or spec1.WaterConductor)
	local color = if isWater then Color3.fromRGB(0, 150, 255) else Color3.fromRGB(255, 170, 0)

	for i = 1, #path - 1 do
		local pA = path[i]
		local pB = path[i + 1]

		local att0 = Instance.new("Attachment")
		att0.WorldPosition = pA
		att0.Parent = terrain

		local att1 = Instance.new("Attachment")
		att1.WorldPosition = pB
		att1.Parent = terrain

		local beam = Instance.new("Beam")
		beam.Attachment0 = att0
		beam.Attachment1 = att1
		beam.Color = ColorSequence.new(color)
		beam.FaceCamera = true
		beam.Width0 = 0.15
		beam.Width1 = 0.15
		beam.Transparency = NumberSequence.new(0)
		beam.Texture = "rbxassetid://956427044"
		beam.TextureMode = Enum.TextureMode.Stretch
		beam.TextureSpeed = 0
		beam.CurveSize0 = 0
		beam.CurveSize1 = 0
		beam.Parent = terrain

		table.insert(segments, { Beam = beam, Attachment0 = att0, Attachment1 = att1 })
	end

	WireBeams[wKey] = segments
end

local forceShowWires = false
local forceShowSources: { [string]: boolean } = {}

local function isAnyConflictingUIActive(): boolean
	local PlayerGui = Players.LocalPlayer:FindFirstChild("PlayerGui")
	if not PlayerGui then
		return false
	end

	local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
	if ActiveQueryFolder then
		local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
		if PlotBuilderEnabled and PlotBuilderEnabled:IsA("BoolValue") and PlotBuilderEnabled.Value then
			return true
		end

		local ResidentUIEnabled = ActiveQueryFolder:FindFirstChild("ResidentUIEnabled")
		if ResidentUIEnabled and ResidentUIEnabled:IsA("BoolValue") and ResidentUIEnabled.Value then
			return true
		end

		local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
		if PlotExpansionEnabled and PlotExpansionEnabled:IsA("BoolValue") and PlotExpansionEnabled.Value then
			return true
		end
	end

	local ReviewsUI = PlayerGui:FindFirstChild("ReviewsUI")
	if ReviewsUI and ReviewsUI:IsA("ScreenGui") and ReviewsUI.Enabled then
		return true
	end

	return false
end

local function shouldShowWires()
	if isAnyConflictingUIActive() then
		return false
	end

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

local function getConnectedNetwork(startKey: string): { [string]: boolean }
	local visited = {}
	local queue = { startKey }
	visited[startKey] = true

	local head = 1
	while head <= #queue do
		local currentKey = queue[head]
		head += 1

		local entry = PlotStateStore.GetPlacementEntry(currentKey)
		if entry and entry.Metadata and entry.Metadata.Connections then
			for _, neighborKey in ipairs(entry.Metadata.Connections) do
				if not visited[neighborKey] then
					visited[neighborKey] = true
					table.insert(queue, neighborKey)
				end
			end
		end
	end

	return visited
end

local function updateWires()
	local state = PlotStateStore.GetStateSnapshot()
	if not state or not state.PlacedItems then
		return
	end

	local show = shouldShowWires()
	local activeWireKeys = {}

	if show then
		local _, selectedKey = SelectionController.GetSelection()
		local visibleKeys = nil

		-- If we are not forcing show (dragging), and we have a selection, filter by network
		if not forceShowWires and selectedKey then
			visibleKeys = getConnectedNetwork(selectedKey)
		end

		for key, entry in pairs(state.PlacedItems) do
			-- Optimization: Skip if key is not in visible network (if filtering is active)
			if visibleKeys and not visibleKeys[key] then
				continue
			end

			local metadata = entry.Metadata or {}
			if metadata.Connections then
				for _, otherKey in ipairs(metadata.Connections) do
					-- Double check visibility for the other end too (should be in network if key is)
					if visibleKeys and not visibleKeys[otherKey] then
						continue
					end

					local wKey = getWireKey(key, otherKey)
					activeWireKeys[wKey] = true
					drawWire(key, otherKey)
				end
			end
		end
	end

	-- Cleanup removed wires
	for wKey, segments in pairs(WireBeams) do
		if not activeWireKeys[wKey] then
			for _, data in ipairs(segments) do
				if data.Beam then
					data.Beam:Destroy()
				end
				if data.Attachment0 then
					data.Attachment0:Destroy()
				end
				if data.Attachment1 then
					data.Attachment1:Destroy()
				end
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
				for _, otherKey in ipairs(selectedEntry.Metadata.Connections) do
					local otherEntry = PlotStateStore.GetPlacementEntry(otherKey)
					if otherEntry then
						local otherSpec = ItemFinder.FindItemById(otherEntry.id)
						if otherSpec then
							local isSource = otherSpec.PowerSource or otherSpec.WaterSource
							if not isSource then
								current += 1
							end
						end
					end
				end
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

		local tags = spec.Tags
		local isLight = typeof(tags) == "table" and table.find(tags, "Light") ~= nil
		if isLight then
			-- Lights are not part of wiring/utility mode.
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

				-- Add a subtle stroke to make icons pop
				local stroke = Instance.new("UIStroke")
				stroke.Thickness = 2
				stroke.Transparency = 0.5
				stroke.Color = Color3.new(0, 0, 0)
				stroke.Parent = lbl

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
				local connectionCount = 0
				if metadata.Connections then
					connectionCount = #metadata.Connections
				end

				if needsPower then
					if isPowered then
						-- Powered (Good)
						if spec.PowerConductor and not spec.PowerSource then
							-- Outlet/Conductor: Less intrusive dot
							lbl.Text = "•"
							lbl.TextColor3 = Color3.fromRGB(100, 255, 100) -- Bright Green
							lbl.TextTransparency = 0.2
						else
							-- Source or Consumer: Bolt
							lbl.Text = "⚡"
							lbl.TextColor3 = Color3.fromRGB(255, 220, 0) -- Yellow
							lbl.TextTransparency = 0
						end
					else
						-- Not Powered (Bad)
						if spec.RequiresPower and not spec.PowerSource and not spec.PowerConductor then
							-- Consumer (e.g. Lamp)
							if connectionCount == 0 then
								-- Unplugged
								lbl.Text = "🔌" -- Plug
								lbl.TextColor3 = Color3.fromRGB(255, 80, 80) -- Redish
							else
								-- Plugged but dead grid
								lbl.Text = "⚠️" -- Warning
								lbl.TextColor3 = Color3.fromRGB(255, 150, 0) -- Orange
							end
						elseif spec.PowerSource then
							-- Generator Off/Empty
							lbl.Text = "🛑" -- Stop
							lbl.TextColor3 = Color3.fromRGB(255, 50, 50)
						else
							-- Conductor (Outlet) Unpowered
							lbl.Text = "•" -- Dot
							lbl.TextColor3 = Color3.fromRGB(255, 50, 50) -- Red
						end
					end
				elseif needsWater then
					if isWatered then
						if spec.WaterConductor and not spec.WaterSource then
							-- Pipe: Dot
							lbl.Text = "•"
							lbl.TextColor3 = Color3.fromRGB(100, 200, 255)
							lbl.TextTransparency = 0.2
						else
							-- Source or Consumer: Droplet
							lbl.Text = "💧"
							lbl.TextColor3 = Color3.fromRGB(0, 150, 255)
							lbl.TextTransparency = 0
						end
					else
						if spec.RequiresWater and not spec.WaterSource and not spec.WaterConductor then
							if connectionCount == 0 then
								-- Unplumbed
								lbl.Text = "🚱" -- Non-potable / No water
								lbl.TextColor3 = Color3.fromRGB(255, 80, 80)
							else
								-- Plumbed but dry
								lbl.Text = "🪣" -- Bucket / Dry
								lbl.TextColor3 = Color3.fromRGB(255, 150, 0)
							end
						else
							-- Dry Pipe/Source
							lbl.Text = "💧"
							lbl.TextColor3 = Color3.fromRGB(150, 150, 150) -- Greyed out
						end
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

	PlotStateStore.OnActiveLevelChanged(function()
		-- Level changed
	end)
end

function UtilityVisuals.SetForceShow(val: boolean, sourceId: string?)
	local key = sourceId or "__default"
	if val then
		forceShowSources[key] = true
	else
		forceShowSources[key] = nil
	end

	local shouldForce = next(forceShowSources) ~= nil
	if forceShowWires ~= shouldForce then
		forceShowWires = shouldForce
		updateVisuals()
		updateWires()
	elseif shouldForce then
		-- Already forcing visibility but refresh to reflect new placements/icons quickly.
		updateVisuals()
		updateWires()
	end
	-- When no sources remain and state unchanged, no refresh needed.
end

return UtilityVisuals
