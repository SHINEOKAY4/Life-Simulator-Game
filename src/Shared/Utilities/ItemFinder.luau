--!strict
-- ReplicatedStorage/Shared/Utilities/ItemFinder.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StartupDiagnostics = require(ReplicatedStorage.Shared.Utilities.StartupDiagnostics)
local StartupLog = StartupDiagnostics.new("ItemFinder")

local CatalogFolder = ReplicatedStorage.Shared.Definitions:FindFirstChild("Catalog")
assert(CatalogFolder and CatalogFolder:IsA("Folder"), "Replicated catalog folder not found")

local REQUIRED_CHILD_TIMEOUT_SECONDS = 15

local function requireChildOfClass(parent: Instance, childName: string, className: string): Instance
	return StartupLog:ResolveDependency(("%s.%s"):format(parent:GetFullName(), childName), function()
		local child = parent:FindFirstChild(childName)
		if child and child:IsA(className) then
			return child
		end

		local waited = parent:WaitForChild(childName, REQUIRED_CHILD_TIMEOUT_SECONDS)
		assert(
			waited and waited:IsA(className),
			("[ItemFinder] Missing required %s '%s' under %s after %ds")
				:format(className, childName, parent:GetFullName(), REQUIRED_CHILD_TIMEOUT_SECONDS)
		)

		return waited
	end)
end

local AssetsFolder = requireChildOfClass(ReplicatedStorage, "Assets", "Folder")
	:: Folder

local CatalogModelsFolder = requireChildOfClass(AssetsFolder, "Catalog", "Folder")
	:: Folder

local function loadCatalogModule(name: string): { [string]: any }
	local moduleScript = CatalogFolder:FindFirstChild(name)
	assert(moduleScript, ("Missing catalog module: %s"):format(name))

	local ok, result = pcall(require, moduleScript)
	if not ok then
		warn(("[ItemFinder] Failed to require catalog module %s: %s"):format(name, tostring(result)))
		return {}
	end

	if typeof(result) ~= "table" then
		return {}
	end

	return result
end

local CatalogModules: { [string]: { [string]: any } } = {
	Build = loadCatalogModule("Build"),
	Furnitures = loadCatalogModule("Furniture"),
	Appliances = loadCatalogModule("Appliances"),
	Decorations = loadCatalogModule("Decorations"),
	Electronics = loadCatalogModule("Electronics"),
	Utilities = loadCatalogModule("Utilities"),
	Outdoor = loadCatalogModule("Outdoor"),
	Rooms = loadCatalogModule("Rooms"),
}

local CATEGORY_SEQUENCE: { string } = {
	"Build",
	"Furnitures",
	"Appliances",
	"Decorations",
	"Electronics",
	"Utilities",
	"Outdoor",
	"Rooms",
}

local CategorySortOrder: { [string]: number } = {}
for index, categoryName in ipairs(CATEGORY_SEQUENCE) do
	CategorySortOrder[categoryName] = index
end

type ItemSpec = { [string]: any }

local ItemFinder = {}
local ItemsById: { [string]: ItemSpec } = {}
local TagSetsById: { [string]: { [string]: boolean } } = {}
local CategoryItems: { [string]: { [string]: ItemSpec } } = {}
local ItemPathsById: { [string]: { string } } = {}
local ItemModelPathsById: { [string]: { string } } = {}
local CategoryEntryCache: { [string]: { ItemEntry } } = {}
type SearchEntryInternal = ItemEntry & {
	Category: string,
	SearchBlob: string,
	SortNameLower: string,
}
local SearchEntries: { SearchEntryInternal } = {}
local TokenIndex: { [string]: { SearchEntryInternal } } = {}
local EMPTY_CATEGORY: { [string]: ItemSpec } = table.freeze({} :: { [string]: ItemSpec })
local EMPTY_PATH: { string } = table.freeze({})

type ItemEntry = {
	Id: string,
	Spec: ItemSpec,
	Path: { string },
}
type SearchResultEntry = {
	Id: string,
	Spec: ItemSpec,
	Path: { string },
	Category: string,
}

local function resolveDisplayName(spec: ItemSpec, fallbackId: string): string
	local candidate = spec.Name
	if typeof(candidate) == "string" and candidate ~= "" then
		return candidate
	end

	return fallbackId
end

local function sanitizeComponent(value: any): string?
	if typeof(value) ~= "string" then
		return nil
	end

	local trimmed = value:gsub("^%s+", ""):gsub("%s+$", "")
	if trimmed == "" then
		return nil
	end

	return string.lower(trimmed)
end

local function registerToken(token: string, entry: SearchEntryInternal)
	local bucket = TokenIndex[token]
	if not bucket then
		bucket = {}
		TokenIndex[token] = bucket
	end

	bucket[#bucket + 1] = entry
end

local nextCategoryOrder = #CATEGORY_SEQUENCE

local function getCategoryOrder(categoryName: string): number
	local order = CategorySortOrder[categoryName]
	if order then
		return order
	end

	nextCategoryOrder += 1
	CategorySortOrder[categoryName] = nextCategoryOrder
	return nextCategoryOrder
end

local function makeItemEntry(itemId: string, spec: ItemSpec): ItemEntry
	local entry: ItemEntry = {
		Id = itemId,
		Spec = spec,
		Path = ItemPathsById[itemId] or EMPTY_PATH,
	}

	return table.freeze(entry)
end

local function entryNameLess(left: ItemEntry, right: ItemEntry): boolean
	local leftName = resolveDisplayName(left.Spec, left.Id)
	local rightName = resolveDisplayName(right.Spec, right.Id)
	if leftName == rightName then
		return left.Id < right.Id
	end

	return leftName < rightName
end

local function isItemSpec(candidate: any): boolean
	if typeof(candidate) ~= "table" then
		return false
	end

	local placementType = candidate.PlacementType
	local modelPath = candidate.ModelPath
	return typeof(placementType) == "string" or typeof(modelPath) == "table"
end

local function registerSpec(categoryName: string, itemId: string, spec: ItemSpec, path: { string })
	assert(itemId ~= "", "Item id cannot be empty")
	assert(ItemsById[itemId] == nil, ("Duplicate item id detected: %s"):format(itemId))

	ItemsById[itemId] = spec

	local storedPath = EMPTY_PATH
	if #path > 0 then
		storedPath = table.freeze(table.clone(path))
	end
	ItemPathsById[itemId] = storedPath

	local resolvedModelName: string? = nil
	local explicitModelPath = spec.ModelPath
	if typeof(explicitModelPath) == "table" then
		for index = #explicitModelPath, 1, -1 do
			local segment = explicitModelPath[index]
			if typeof(segment) == "string" and segment ~= "" then
				resolvedModelName = segment
				break
			end
		end
	elseif typeof(explicitModelPath) == "string" and explicitModelPath ~= "" then
		resolvedModelName = explicitModelPath
	end

	local overrideModelName = spec.ModelName
	if typeof(overrideModelName) == "string" and overrideModelName ~= "" then
		resolvedModelName = overrideModelName
	end

	local modelSegments = table.create(#path + 2)
	modelSegments[#modelSegments + 1] = categoryName
	-- Compose the ReplicatedStorage.Assets.Catalog path from the catalog hierarchy; only the
	-- final segment is overrideable so definitions do not have to repeat intermediate folders.
	for i = 1, #path do
		local segment = path[i]
		if typeof(segment) == "string" and segment ~= "" then
			modelSegments[#modelSegments + 1] = segment
		end
	end
	modelSegments[#modelSegments + 1] = resolvedModelName or itemId
	ItemModelPathsById[itemId] = table.freeze(modelSegments)

	local bucket = CategoryItems[categoryName]
	if not bucket then
		bucket = {}
		CategoryItems[categoryName] = bucket
	end
	bucket[itemId] = spec

	local tags = spec.Tags
	if typeof(tags) == "table" then
		local tagSet: { [string]: boolean } = {}
		for _, tag in ipairs(tags) do
			tagSet[tag] = true
		end
		if next(tagSet) then
			TagSetsById[itemId] = tagSet
		end
	end

	local displayName = resolveDisplayName(spec, itemId)
	local sortNameLower = string.lower(displayName)

	local components = table.create(16)
	local function pushComponent(value: any)
		local sanitized = sanitizeComponent(value)
		if sanitized then
			components[#components + 1] = sanitized
		end
	end

	pushComponent(categoryName)
	pushComponent(itemId)
	pushComponent(displayName)

	for _, segment in ipairs(storedPath) do
		pushComponent(segment)
	end

	pushComponent(spec.PlacementType)
	pushComponent(spec.StationType)

	if typeof(tags) == "table" then
		for _, tag in ipairs(tags) do
			pushComponent(tag)
		end
	end

	local searchBlob = table.concat(components, "\n")

	local entry: SearchEntryInternal = {
		Id = itemId,
		Spec = spec,
		Path = storedPath,
		Category = categoryName,
		SearchBlob = searchBlob,
		SortNameLower = sortNameLower,
	}

	SearchEntries[#SearchEntries + 1] = entry

	local tokenSet: { [string]: boolean } = {}
	local function collectTokens(value: any)
		if typeof(value) ~= "string" then
			return
		end

		for token in string.gmatch(value, "[%w]+") do
			if token ~= "" then
				tokenSet[string.lower(token)] = true
			end
		end
	end

	collectTokens(displayName)
	collectTokens(itemId)
	collectTokens(categoryName)

	if typeof(tags) == "table" then
		for _, tag in ipairs(tags) do
			collectTokens(tag)
		end
	end

	for _, segment in ipairs(storedPath) do
		collectTokens(segment)
	end

	collectTokens(spec.PlacementType)
	collectTokens(spec.StationType)

	for token in pairs(tokenSet) do
		registerToken(token, entry)
	end
end

local function ingest(categoryName: string, rootTable: { [string]: any })
	local function traverse(container: { [string]: any }, path: { string })
		for key, value in container do
			if typeof(value) == "table" then
				if isItemSpec(value) then
					registerSpec(categoryName, key, value, path)
				else
					local nextPath = table.clone(path)
					table.insert(nextPath, key)
					traverse(value, nextPath)
				end
			end
		end
	end

	traverse(rootTable, {})
	ItemFinder[categoryName] = CategoryItems[categoryName] or EMPTY_CATEGORY
end

local function finalizeCategoryEntries()
	local function assignCategory(categoryName: string)
		local bucket = CategoryItems[categoryName]
		if not bucket then
			CategoryEntryCache[categoryName] = table.freeze({} :: { ItemEntry })
			return
		end

		local count = 0
		for _ in bucket do
			count += 1
		end

		local entries = table.create(count)
		for itemId, spec in bucket do
			entries[#entries + 1] = makeItemEntry(itemId, spec)
		end

		table.sort(entries, entryNameLess)
		CategoryEntryCache[categoryName] = table.freeze(entries)
	end

	for _, categoryName in ipairs(CATEGORY_SEQUENCE) do
		assignCategory(categoryName)
	end

	for categoryName in CategoryItems do
		if CategoryEntryCache[categoryName] == nil then
			assignCategory(categoryName)
		end
	end
end

local function finalizeSearchEntries()
	for _, entry in ipairs(SearchEntries) do
		getCategoryOrder(entry.Category)
	end

	table.sort(SearchEntries, function(left, right)
		if left.SortNameLower == right.SortNameLower then
			local leftOrder = getCategoryOrder(left.Category)
			local rightOrder = getCategoryOrder(right.Category)
			if leftOrder == rightOrder then
				return left.Id < right.Id
			end
			return leftOrder < rightOrder
		end

		return left.SortNameLower < right.SortNameLower
	end)

	SearchEntries = table.freeze(SearchEntries)
	for _, bucket in TokenIndex do
		table.freeze(bucket)
	end
end

for categoryName, moduleTable in CatalogModules do
	ingest(categoryName, moduleTable)
end

finalizeCategoryEntries()
finalizeSearchEntries()

function ItemFinder.FindItemById(itemId: string)
	return ItemsById[itemId]
end

function ItemFinder.GetCategory(category: string)
	local bucket = CategoryItems[category]
	if not bucket then
		return EMPTY_CATEGORY
	end

	return table.clone(bucket)
end

function ItemFinder.GetItemPath(itemId: string): { string }
	return ItemPathsById[itemId] or EMPTY_PATH
end

function ItemFinder.GetCategoryEntries(category: string): { ItemEntry }
	local cached = CategoryEntryCache[category]
	if not cached then
		return {}
	end

	return table.clone(cached)
end

local function cloneSearchResults(entries: { SearchEntryInternal }): { SearchResultEntry }
	local results = table.create(#entries)
	for index = 1, #entries do
		local source = entries[index]
		results[index] = {
			Id = source.Id,
			Spec = source.Spec,
			Path = source.Path,
			Category = source.Category,
		}
	end

	return results
end

local function extractQueryTokens(query: string): { string }
	local tokens = {} :: { string }
	local seen: { [string]: boolean } = {}

	for token in string.gmatch(query, "[%w]+") do
		local lowered = string.lower(token)
		if lowered ~= "" and not seen[lowered] then
			seen[lowered] = true
			tokens[#tokens + 1] = lowered
		end
	end

	return tokens
end

function ItemFinder.SearchCatalog(normalizedQuery: string): { SearchResultEntry }
	if normalizedQuery == "" then
		return cloneSearchResults(SearchEntries)
	end

	local tokens = extractQueryTokens(normalizedQuery)
	local candidateMap: { [string]: SearchEntryInternal }? = nil

	for _, token in ipairs(tokens) do
		local bucket = TokenIndex[token]
		if not bucket then
			candidateMap = {}
			break
		end

		if not candidateMap then
			local newMap: { [string]: SearchEntryInternal } = {}
			for _, entry in ipairs(bucket) do
				newMap[entry.Id] = entry
			end
			candidateMap = newMap
		else
			local current = candidateMap :: { [string]: SearchEntryInternal }
			local nextMap: { [string]: SearchEntryInternal } = {}
			for _, entry in ipairs(bucket) do
				local existing = current[entry.Id]
				if existing then
					nextMap[entry.Id] = existing
				end
			end
			candidateMap = nextMap
			if next(candidateMap) == nil then
				break
			end
		end
	end

	local scanList: { SearchEntryInternal }
	if candidateMap then
		local count = 0
		for _ in pairs(candidateMap) do
			count += 1
		end
		scanList = table.create(count)
		for _, entry in pairs(candidateMap) do
			scanList[#scanList + 1] = entry
		end
	else
		scanList = SearchEntries
	end

	local matches = table.create(#scanList)
	for _, entry in ipairs(scanList) do
		if string.find(entry.SearchBlob, normalizedQuery, 1, true) then
			matches[#matches + 1] = entry
		end
	end

	if #matches == 0 then
		return {}
	end

	table.sort(matches, function(left, right)
		if left.SortNameLower == right.SortNameLower then
			local leftOrder = getCategoryOrder(left.Category)
			local rightOrder = getCategoryOrder(right.Category)
			if leftOrder == rightOrder then
				return left.Id < right.Id
			end
			return leftOrder < rightOrder
		end

		return left.SortNameLower < right.SortNameLower
	end)

	return cloneSearchResults(matches)
end

function ItemFinder.Exists(itemId: string): boolean
	return ItemsById[itemId] ~= nil
end

function ItemFinder.HasTag(itemId: string, tag: string): boolean
	local tagSet = TagSetsById[itemId]
	return tagSet ~= nil and tagSet[tag] == true
end

function ItemFinder.AnyTag(itemId: string, tags: { string }): boolean
	local tagSet = TagSetsById[itemId]
	if not tagSet then
		return false
	end

	for i = 1, #tags do
		if tagSet[tags[i]] then
			return true
		end
	end

	return false
end

function ItemFinder.ResolveItemModel(itemId: string): Model
	local spec = ItemsById[itemId]
	assert(spec, ("Unknown item id: %s"):format(itemId))

	local modelPath = ItemModelPathsById[itemId]
	assert(modelPath, ("Model path not registered for item %s"):format(itemId))

	local node: Instance = CatalogModelsFolder
	local found = true
	for index = 1, #modelPath do
		local segment = modelPath[index]
		if typeof(segment) ~= "string" or segment == "" then
			found = false
			break
		end
		local nextNode = node:FindFirstChild(segment)
		if not nextNode then
			found = false
			break
		end
		node = nextNode
	end

	if found and node:IsA("Model") then
		return node :: Model
	end

	-- Fallback model generation
	local width = spec.WidthCells or spec.Width or 1
	local depth = spec.DepthCells or spec.Depth or 1
	local height = 4 -- Default height

	local model = Instance.new("Model")
	model.Name = itemId

	local part = Instance.new("Part")
	part.Name = "PrimaryPart"
	part.Size = Vector3.new(width * 4, height, depth * 4)
	part.Anchored = true
	part.CanCollide = false
	part.Transparency = 0.5
	part.Color = Color3.fromRGB(255, 0, 255) -- Magenta
	part.Material = Enum.Material.Neon
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = model
	model.PrimaryPart = part

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(4, 1)
	bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true
	bb.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0
	label.TextScaled = true
	label.Text = spec.Name or itemId
	label.Parent = bb

	return model
end

function ItemFinder.CloneModel(itemId: string): Model
	return ItemFinder.ResolveItemModel(itemId):Clone()
end

return ItemFinder
