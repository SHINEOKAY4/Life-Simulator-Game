--!strict
-- StarterPlayerScripts/Client/UserInterface/ResidentNameBillboard.luau
-- Renders resident nameplates with live resident activity subtitles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BillboardText = require(script.Parent:WaitForChild("BillboardText"))
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local TenantTraits = require(ReplicatedStorage.Shared.Definitions.TenantTraits)
local TenantDefinitions = require(ReplicatedStorage.Shared.Definitions.TenantDefinitions)
local ClientFolder = script.Parent.Parent
local ClientStoresFolder = ClientFolder:WaitForChild("ClientStores")
local TenantStore = require(ClientStoresFolder:WaitForChild("TenantStore"))

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
	TierId: string?,
	TenantId: string?,
}

local ResidentNameBillboard = {}

local function toHex(color: Color3): string
	return string.format("#%02X%02X%02X", color.R * 255, color.G * 255, color.B * 255)
end

local currentPlotIndex: number? = nil
local nameplatesByModel: { [Model]: NameplateEntry } = {}
local nameplatesByResident: { [string]: NameplateEntry } = {}
local nameplatesByTenantId: { [string]: NameplateEntry } = {}
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

	local titleLine = string.format('<font size="16"><b>%s</b></font>', escapeRichText(residentName))

	local lines = { titleLine }

	if entry.TierId then
		local tierDef = TenantDefinitions.GetDefinition(entry.TierId)
		if tierDef then
			lines[#lines + 1] = string.format(
				'<font size="12" color="%s">%s</font>',
				toHex(tierDef.DisplayColor),
				escapeRichText(entry.TierId)
			)
		end
	end

	local boostText = getBoostString(entry.Traits)
	if boostText then
		lines[#lines + 1] = string.format('<font size="10" color="#FFD700">%s</font>', escapeRichText(boostText))
	end

	entry.Handle:setText(table.concat(lines, "\n"))
	entry.Handle.instance.Enabled = true
end

local function syncTenantData(entry: NameplateEntry)
	local tenantId = entry.TenantId
	if not tenantId or tenantId == "" then
		entry.TierId = nil
		entry.Traits = nil
		applyBillboard(entry)
		return
	end

	local tenant = TenantStore.GetTenant(LocalPlayer.UserId, tenantId)
	if tenant then
		entry.TierId = tenant.TierId
		entry.Traits = tenant.Traits
	else
		entry.TierId = nil
		entry.Traits = nil
	end
	applyBillboard(entry)
end

local function updateEntryTenantBinding(entry: NameplateEntry, newTenantId: string?)
	local currentId = entry.TenantId
	if currentId and nameplatesByTenantId[currentId] == entry then
		nameplatesByTenantId[currentId] = nil
	end

	if newTenantId and newTenantId ~= "" then
		entry.TenantId = newTenantId
		nameplatesByTenantId[newTenantId] = entry
	else
		entry.TenantId = nil
	end

	syncTenantData(entry)
end

local function resolveTenantIdAttribute(model: Model): string?
	local rawValue = model:GetAttribute("TenantId")
	if type(rawValue) == "string" and rawValue ~= "" then
		return rawValue
	end
	return nil
end

local function resolveResidentDisplayName(model: Model): string?
	local attr = model:GetAttribute("ResidentName")
	if type(attr) == "string" and attr ~= "" then
		return attr
	end
	local fallback = model.Name
	if type(fallback) == "string" and fallback ~= "" then
		return fallback
	end
	return nil
end

local function detachResident(model: Model)
	local entry = nameplatesByModel[model]
	if not entry then
		return
	end

	if entry.TenantId and nameplatesByTenantId[entry.TenantId] == entry then
		nameplatesByTenantId[entry.TenantId] = nil
	end

	nameplatesByModel[model] = nil
	nameplatesByResident[entry.ResidentName] = nil
	disconnectAll(entry.Connections)
	entry.Handle:destroy()
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

	local residentName = resolveResidentDisplayName(model)
	if not residentName then
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
		clipsDescendants = false,
	})
	local billboard = handle.instance
	billboard.Enabled = true

	local entry: NameplateEntry = {
		Model = model,
		Handle = handle,
		Connections = {},
		ResidentName = residentName,
		Traits = nil,
		TierId = nil,
		TenantId = nil,
	}

	nameplatesByModel[model] = entry
	nameplatesByResident[residentName] = entry

	updateEntryTenantBinding(entry, resolveTenantIdAttribute(model))

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

	bind(model:GetAttributeChangedSignal("TenantId"):Connect(function()
		updateEntryTenantBinding(entry, resolveTenantIdAttribute(model))
	end))

	local function refreshResidentName()
		local nextName = resolveResidentDisplayName(model)
		if not nextName or nextName == entry.ResidentName then
			return
		end
		nameplatesByResident[entry.ResidentName] = nil
		entry.ResidentName = nextName
		nameplatesByResident[nextName] = entry
		applyBillboard(entry)
	end

	bind(model:GetAttributeChangedSignal("ResidentName"):Connect(refreshResidentName))
	bind(model:GetPropertyChangedSignal("Name"):Connect(function()
		if model:GetAttribute("ResidentName") then
			return
		end
		refreshResidentName()
	end))
end

local function clearAllNameplates()
	for model in pairs(nameplatesByModel) do
		detachResident(model)
	end
	table.clear(nameplatesByTenantId)
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

	-- Listen to TenantStore updates to refresh billboards
	TenantStore.TenantAdded:Connect(function(userId: number, tenantData: any)
		if userId ~= LocalPlayer.UserId then
			return
		end
		local tenantId = tenantData and tenantData.TenantId
		if type(tenantId) ~= "string" then
			return
		end
		local entry = nameplatesByTenantId[tenantId]
		if entry then
			syncTenantData(entry)
		end
	end)

	TenantStore.TenantsUpdated:Connect(function(userId: number, tenantData: any)
		if userId ~= LocalPlayer.UserId then
			return
		end
		local tenantId = tenantData and tenantData.TenantId
		if type(tenantId) ~= "string" then
			return
		end
		local entry = nameplatesByTenantId[tenantId]
		if entry then
			syncTenantData(entry)
		end
	end)

	TenantStore.TenantRemoved:Connect(function(userId: number, _tenantId: string)
		if userId ~= LocalPlayer.UserId then
			return
		end
		local entry = nameplatesByTenantId[_tenantId]
		if entry then
			entry.TierId = nil
			entry.Traits = nil
			nameplatesByTenantId[_tenantId] = nil
			applyBillboard(entry)
		end
	end)
end

return ResidentNameBillboard
