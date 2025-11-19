--!strict
-- StarterPlayerScripts/Client/UserInterface/ResidentNameBillboard.luau
-- Renders resident nameplates with live resident activity subtitles.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BillboardText = require(script.Parent:WaitForChild("BillboardText"))
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ClientFolder = script.Parent.Parent
local ClientStoresFolder = ClientFolder:WaitForChild("ClientStores")
local ResidentsStore = require(ClientStoresFolder:WaitForChild("ResidentsStore"))

local SUBTITLE_COLOR = Color3.fromRGB(218, 223, 235)

type BillboardTextHandle = BillboardText.BillboardTextHandle

local LocalPlayer = Players.LocalPlayer
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local DISABLE_BILLBOARD_ATTR = "DisableResidentBillboard"

export type NameplateEntry = {
	Model: Model,
	Handle: BillboardTextHandle,
	Connections: { RBXScriptConnection },
	ResidentName: string,
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

local function trim(text: string): string
	local trimmed = text:gsub("^%s+", "")
	return trimmed:gsub("%s+$", "")
end

local function canonicalizeLabel(raw: string): string
	local lowered = raw:lower()
	lowered = lowered:gsub("[:/_%-%s]+", " ")
	lowered = lowered:gsub("%s+", " ")
	lowered = lowered:gsub("^%s+", "")
	lowered = lowered:gsub("%s+$", "")
	return lowered
end

local ACTION_LABEL_OVERRIDES: { [string]: string } = {
	["rest"] = "Resting",
	["take nap"] = "Napping",
	["nap"] = "Napping",
	["sleep"] = "Sleeping",
	["sleep in"] = "Sleeping",
	["cook"] = "Cooking",
	["cook meal"] = "Cooking Meal",
	["prep meal"] = "Preparing Meal",
	["wash up"] = "Washing Up",
	["wash"] = "Washing Up",
	["clean"] = "Cleaning",
	["grab snack"] = "Grabbing Snack",
	["eat snack"] = "Eating Snack",
	["eat meal"] = "Eating Meal",
	["have fun"] = "Having Fun",
	["fun"] = "Having Fun",
	["chat"] = "Chatting",
	["socialize"] = "Socializing",
	["directsocial"] = "Socializing",
	["hang out"] = "Hanging Out",
	["check mail"] = "Checking Mail",
	["pay bills"] = "Paying Bills",
	["roam"] = "Roaming",
	["auto roam"] = "Roaming",
	["look around"] = "Looking Around",
	["need urgent hunger"] = "Seeking Food",
	["need urgent hygiene"] = "Freshening Up",
	["need urgent social"] = "Socializing",
	["need urgent fun"] = "Finding Fun",
	["forced energycollapse"] = "Collapsed",
	["energy collapse"] = "Collapsed",
}

local STATION_TYPE_OVERRIDES: { [string]: string } = {
	RestStation = "Resting",
	CookStation = "Cooking",
	SocialStation = "Socializing",
	HygieneStation = "Freshening Up",
	FunStation = "Relaxing",
}

local COLLAPSE_LABEL = "Collapsed"
local DEFAULT_IDLE_LABEL = "Idle"

local function humanizeIdentifier(raw: string): string
	local spaced = raw:gsub("(%l)(%u)", "%1 %2")
	spaced = spaced:gsub("[_%-%s]+", " ")
	return trim(spaced)
end

local function lookupActionOverride(raw: string): string?
	local canonical = canonicalizeLabel(raw)
	if canonical == "" then
		return nil
	end
	local override = ACTION_LABEL_OVERRIDES[canonical]
	if override then
		return override
	end
	local fragments = {}
	for fragment in canonical:gmatch("%S+") do
		fragments[#fragments + 1] = fragment
	end
	for index = #fragments, 1, -1 do
		local fragment = fragments[index]
		local fragmentOverride = ACTION_LABEL_OVERRIDES[fragment]
		if fragmentOverride then
			return fragmentOverride
		end
	end
	return nil
end

local function formatActionPhrase(raw: string): string?
	if raw == "" then
		return nil
	end
	local trimmed = trim(raw)
	if trimmed == "" then
		return nil
	end
	local override = lookupActionOverride(trimmed)
	if override then
		return override
	end
	local segments = {}
	for segment in trimmed:gmatch("[^:]+") do
		local cleaned = trim(segment)
		if cleaned ~= "" then
			local segOverride = lookupActionOverride(cleaned)
			if segOverride then
				return segOverride
			end
			table.insert(segments, cleaned)
		end
	end
	local candidate: string? = nil
	if #segments > 0 then
		for index = #segments, 1, -1 do
			local part = segments[index]
			part = part:gsub("^ManualOverride[%-%s]*", "")
			part = part:gsub("^Auto[%-%s]*", "")
			part = part:gsub("^Forced[%-%s]*", "")
			part = part:gsub("^Need[%-%s]*", "")
			part = trim(part)
			if part ~= "" then
				local partOverride = lookupActionOverride(part)
				if partOverride then
					return partOverride
				end
				candidate = part
				break
			end
		end
	end
	if not candidate or candidate == "" then
		candidate = trimmed
	end
	if not candidate or candidate == "" then
		return nil
	end
	local resolvedCandidate = candidate
	resolvedCandidate = resolvedCandidate:gsub("^ManualOverride[%-%s]*", "")
	resolvedCandidate = resolvedCandidate:gsub("^Auto[%-%s]*", "")
	resolvedCandidate = resolvedCandidate:gsub("^Forced[%-%s]*", "")
	resolvedCandidate = resolvedCandidate:gsub("^Need[%-%s]*", "")
	resolvedCandidate = humanizeIdentifier(resolvedCandidate)
	if resolvedCandidate == "" then
		return nil
	end
	local candidateOverride = lookupActionOverride(resolvedCandidate)
	if candidateOverride then
		return candidateOverride
	end
	local words = {}
	for word in resolvedCandidate:gmatch("%S+") do
		words[#words + 1] = word:sub(1, 1):upper() .. word:sub(2):lower()
	end
	if #words == 0 then
		return nil
	end
	return table.concat(words, " ")
end

local function resolveActionSubtitle(model: Model): string
	if model:GetAttribute("EnergyCollapseActive") == true then
		return COLLAPSE_LABEL
	end
	if model:GetAttribute("StationActivityActive") == true then
		local actionAttr = model:GetAttribute("StationActivityAction")
		if typeof(actionAttr) == "string" and actionAttr ~= "" then
			local formatted = formatActionPhrase(actionAttr)
			if formatted then
				return formatted
			end
		end
		local stationType = model:GetAttribute("StationActivityType")
		if typeof(stationType) == "string" and stationType ~= "" then
			local stationOverride = STATION_TYPE_OVERRIDES[stationType]
			if stationOverride then
				return stationOverride
			end
			local formattedStation = formatActionPhrase(stationType)
			if formattedStation then
				return formattedStation
			end
		end
	end
	local currentAction = model:GetAttribute("CurrentActionName")
	if typeof(currentAction) == "string" and currentAction ~= "" then
		local formattedAction = formatActionPhrase(currentAction)
		if formattedAction then
			return formattedAction
		end
	end
	return DEFAULT_IDLE_LABEL
end

local function color3ToHex(color: Color3): string
	local r = math.clamp(color.R, 0, 1)
	local g = math.clamp(color.G, 0, 1)
	local b = math.clamp(color.B, 0, 1)
	return string.format(
		"#%02X%02X%02X",
		math.floor(r * 255 + 0.5),
		math.floor(g * 255 + 0.5),
		math.floor(b * 255 + 0.5)
	)
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
	local subtitleText = resolveActionSubtitle(model)
	if subtitleText and subtitleText ~= "" then
		lines[#lines + 1] = string.format(
			'<font size="18" color="%s">%s</font>',
			color3ToHex(SUBTITLE_COLOR),
			escapeRichText(subtitleText)
		)
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

local function updateResidentNameplate(residentName: string)
	local entry = nameplatesByResident[residentName]
	if not entry then
		return
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
		size = UDim2.fromScale(2, 1),
		studsOffsetWorldSpace = Vector3.new(0, 2, 0),
		alwaysOnTop = false,
		maxDistance = 40,
		textSize = 22,
		richText = true,
		font = Enum.Font.GothamBold,
		outline = true,
		outlineColor = Color3.new(0, 0, 0),
		outlineTransparency = 0.45,
		clipsDescendants = false,
	})
	local billboard = handle.instance
	billboard.Enabled = true

	local entry: NameplateEntry = {
		Model = model,
		Handle = handle,
		Connections = {},
		ResidentName = residentName,
	}

	nameplatesByModel[model] = entry
	nameplatesByResident[residentName] = entry

	local function bind(connection: RBXScriptConnection)
		table.insert(entry.Connections, connection)
	end

	bind(model:GetAttributeChangedSignal("StationActivityActive"):Connect(function()
		applyBillboard(entry)
	end))

	bind(model:GetAttributeChangedSignal("StationActivityAction"):Connect(function()
		applyBillboard(entry)
	end))

	bind(model:GetAttributeChangedSignal("StationActivityType"):Connect(function()
		applyBillboard(entry)
	end))

	bind(model:GetAttributeChangedSignal("EnergyCollapseActive"):Connect(function()
		applyBillboard(entry)
	end))

	bind(model:GetAttributeChangedSignal("CurrentActionName"):Connect(function()
		applyBillboard(entry)
	end))

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
		updateResidentNameplate(residentData.Name)
	end)

	ResidentsStore.ResidentsUpdated:Connect(function(userId: number, residentData: any)
		if userId ~= LocalPlayer.UserId then
			return
		end
		if type(residentData.Name) ~= "string" then
			return
		end
		updateResidentNameplate(residentData.Name)
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
