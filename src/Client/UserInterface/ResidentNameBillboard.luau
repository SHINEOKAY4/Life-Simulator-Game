--!strict
-- StarterPlayerScripts/Client/UserInterface/ResidentNameBillboard.luau
-- Renders resident nameplates with live resident activity subtitles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BillboardText = require(script.Parent:WaitForChild("BillboardText"))
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)
local ClientFolder = script.Parent.Parent
local ClientStoresFolder = ClientFolder:WaitForChild("ClientStores")
local ResidentsStore = require(ClientStoresFolder:WaitForChild("ResidentsStore"))

type BillboardTextHandle = BillboardText.BillboardTextHandle

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local DISABLE_BILLBOARD_ATTR = "DisableResidentBillboard"

export type NameplateEntry = {
	Model: Model,
	Handle: BillboardTextHandle,
	Connections: { RBXScriptConnection },
	ResidentName: string,
	Traits: { string }?,
}

local ResidentNameBillboard = {}

local currentPlotIndex: number? = nil
local nameplatesByModel: { [Model]: NameplateEntry } = {}
local nameplatesByResident: { [string]: NameplateEntry } = {}
local residentsFolderConnections: { RBXScriptConnection } = {}

local function disconnectAll(connections: { RBXScriptConnection })
	for _, connection in ipairs(connections) do
		if connection.Connected then
			connection:Disconnect()
		end
	end
	table.clear(connections)
end

local function escapeRichText(text: string): string
	local sanitized = text
	sanitized = sanitized:gsub("&", "&amp;")
	sanitized = sanitized:gsub("<", "&lt;")
	sanitized = sanitized:gsub(">", "&gt;")
	return sanitized
end

local function getBoostString(traits: { string }?): string?
	if not traits then
		return nil
	end
	local parts = {}
	for _, traitId in ipairs(traits) do
		local traitDef = TenantTraits.GetTrait(traitId)
		if traitDef and traitDef.Effects then
			if traitDef.Effects.TipMultiplier then
				local pct = (traitDef.Effects.TipMultiplier - 1) * 100
				if pct > 0 then
					table.insert(parts, string.format("+%d%% Tips", pct))
				elseif pct < 0 then
					table.insert(parts, string.format("%d%% Tips", pct))
				end
			end
			if traitDef.Effects.RentMultiplier then
				local pct = (traitDef.Effects.RentMultiplier - 1) * 100
				if pct > 0 then
					table.insert(parts, string.format("+%d%% Rent", pct))
				elseif pct < 0 then
					table.insert(parts, string.format("%d%% Rent", pct))
				end
			end
		end
	end
	if #parts == 0 then
		return nil
	end
	return table.concat(parts, ", ")
end

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

local function applyBillboard(entry: NameplateEntry)
	local model = entry.Model
	if not model or not model:IsDescendantOf(workspace) then
		entry.Handle.instance.Enabled = false
		return
	end

	local adornee = getAdornee(model)
	if adornee and entry.Handle.instance.Adornee ~= adornee then
		entry.Handle.instance.Adornee = adornee
	end

	local residentName = entry.ResidentName

	local titleLine = string.format("<b>%s</b>", escapeRichText(residentName))

	local lines = { titleLine }

	local boostText = getBoostString(entry.Traits)
	if boostText then
		lines[#lines + 1] = string.format('<font size="10" color="#FFD700">%s</font>', escapeRichText(boostText))
	end

	entry.Handle:setText(table.concat(lines, "\n"))
	entry.Handle.instance.Enabled = true
end

local function detachResident(model: Model)
	local entry = nameplatesByModel[model]
	if not entry then
		return
	end

	nameplatesByModel[model] = nil
	nameplatesByResident[entry.ResidentName] = nil
	disconnectAll(entry.Connections)
	entry.Handle:destroy()
end

local function updateResidentNameplate(residentName: string, traits: { string }?)
	local entry = nameplatesByResident[residentName]
	if not entry then
		return
	end
	if traits then
		entry.Traits = traits
	end
	applyBillboard(entry)
end

local function attachResident(model: Model)
	if nameplatesByModel[model] then
		return
	end
	if not model:IsA("Model") then
		return
	end
	if not model:FindFirstChildOfClass("Humanoid") then
		return
	end
	if model:GetAttribute(DISABLE_BILLBOARD_ATTR) then
		return
	end

	local residentName = model.Name
	if type(residentName) ~= "string" or residentName == "" then
		return
	end

	local handle = BillboardText.new({
		adornee = getAdornee(model),
		parent = PlayerGui,
		text = "",
		textColor = Color3.new(1, 1, 1),
		backgroundTransparency = 1,
		size = UDim2.fromScale(1.5, 0.6),
		studsOffsetWorldSpace = Vector3.new(0, 1.5, 0),
		alwaysOnTop = false,
		maxDistance = 40,
		textSize = 12,
		richText = true,
		font = Enum.Font.GothamBold,
		outline = true,
		outlineColor = Color3.new(0, 0, 0),
		outlineTransparency = 0.45,
		clipsDescendants = false,
	})
	local billboard = handle.instance
	billboard.Enabled = true

	local residentData = ResidentsStore.GetResident(LocalPlayer.UserId, residentName)

	local entry: NameplateEntry = {
		Model = model,
		Handle = handle,
		Connections = {},
		ResidentName = residentName,
		Traits = residentData and residentData.Traits,
	}

	nameplatesByModel[model] = entry
	nameplatesByResident[residentName] = entry

	local function bind(connection: RBXScriptConnection)
		table.insert(entry.Connections, connection)
	end

	bind(model.Destroying:Connect(function()
		detachResident(model)
	end))

	bind(model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			detachResident(model)
		end
	end))

	bind(model.ChildAdded:Connect(function()
		if billboard.Adornee then
			return
		end
		local adornee = getAdornee(model)
		if adornee then
			billboard.Adornee = adornee
		end
	end))

	applyBillboard(entry)
end

local function clearAllNameplates()
	for model in pairs(nameplatesByModel) do
		detachResident(model)
	end
end

local function detachAllConnections()
	disconnectAll(residentsFolderConnections)
	residentsFolderConnections = {}
end

local function bindResidentsFolder(folder: Instance?)
	detachAllConnections()
	if not folder then
		clearAllNameplates()
		return
	end

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			attachResident(child)
		end
	end

	local function bind(connection: RBXScriptConnection)
		table.insert(residentsFolderConnections, connection)
	end

	bind(folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			attachResident(child)
		end
	end))

	bind(folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			detachResident(child)
		end
	end))
end

local function rebindPlot(plotIndex: number?)
	if plotIndex == currentPlotIndex then
		return
	end
	currentPlotIndex = plotIndex
	clearAllNameplates()
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

	local awaiting: RBXScriptConnection
	awaiting = plotModel.ChildAdded:Connect(function(child)
		if child.Name == "Residents" then
			awaiting:Disconnect()
			bindResidentsFolder(child)
		end
	end)
	table.insert(residentsFolderConnections, awaiting)
end

function ResidentNameBillboard.Init()
	rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)
	LocalPlayer:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
		rebindPlot(LocalPlayer:GetAttribute("OwnedPlotIndex") :: number?)
	end)

	ResidentsStore.ResidentAdded:Connect(function(userId: number, residentData: any)
		if userId ~= LocalPlayer.UserId then
			return
		end
		if type(residentData.Name) ~= "string" then
			return
		end
		updateResidentNameplate(residentData.Name, residentData.Traits)
	end)

	ResidentsStore.ResidentsUpdated:Connect(function(userId: number, residentData: any)
		if userId ~= LocalPlayer.UserId then
			return
		end
		if type(residentData.Name) ~= "string" then
			return
		end
		updateResidentNameplate(residentData.Name, residentData.Traits)
	end)

	ResidentsStore.ResidentRemoved:Connect(function(userId: number, residentName: string)
		if userId ~= LocalPlayer.UserId then
			return
		end
		local entry = nameplatesByResident[residentName]
		if entry then
			detachResident(entry.Model)
		end
	end)
end

return ResidentNameBillboard
