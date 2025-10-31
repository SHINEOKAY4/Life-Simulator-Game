local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ServicesFolder = ServerScriptService.Server.Services

local PlotService = require(ServicesFolder.PlotService)
local KitchenService = require(ServicesFolder.KitchenService)
local FoodPackets = require(ReplicatedStorage.Network.FoodPackets)
local FoodSourcesModule = require(ReplicatedStorage.Shared.Definitions.FoodSources)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

export type FoodSourceSpec = FoodSourcesModule.FoodSourceSpec
export type FoodSourceYield = FoodSourcesModule.FoodSourceYield
type IngredientGrantEntry = KitchenService.IngredientGrantEntry

type FoodSourceCooldownRecord = {
	ChargesRemaining: number?,
	RestockReadyUnix: number?,
}

local FoodSourceService = {}

local FoodSources = FoodSourcesModule.Sources

type SourceRuntime = {
	Player: Player,
	Model: Model,
	Spec: FoodSourceSpec,
	Guid: string,
	PersistenceKey: string,
	ChargesRemaining: number,
	RestockToken: number,
	Busy: boolean,
	Connections: { RBXScriptConnection },
	TargetContainerId: string?,
	TargetStationType: string?,
	TargetItemId: string?,
	TargetCapacity: number?,
}

local SourcesByGuid: { [string]: SourceRuntime } = {}
local SourcesByModel: { [Model]: SourceRuntime } = {}
local PlayerBindings: {
	[number]: {
		Folder: Instance?,
		Connections: { RBXScriptConnection },
	},
} = {}

local function sanitizePositiveInteger(value: any): number
	if typeof(value) ~= "number" or value ~= value then
		return 0
	end
	local rounded = math.floor(value + 0.5)
	if rounded < 0 then
		return 0
	end
	return rounded
end

local function resolveQuantity(entry: FoodSourceYield): number
	local directQuantity = sanitizePositiveInteger(entry.Quantity)
	if directQuantity > 0 then
		return directQuantity
	end
	local minQuantity = sanitizePositiveInteger(entry.MinQuantity)
	local maxQuantity = sanitizePositiveInteger(entry.MaxQuantity)
	if minQuantity <= 0 and maxQuantity <= 0 then
		return 1
	end
	if minQuantity <= 0 then
		minQuantity = 1
	end
	if maxQuantity < minQuantity then
		maxQuantity = minQuantity
	end
	return math.random(minQuantity, maxQuantity)
end

local function buildGuaranteedYields(spec: FoodSourceSpec): { IngredientGrantEntry }
	local yields: { IngredientGrantEntry } = {}
	for _, entry in ipairs(spec.Yields) do
		if typeof(entry.IngredientId) == "string" and entry.IngredientId ~= "" then
			local quantity = resolveQuantity(entry)
			if quantity > 0 then
				yields[#yields + 1] = {
					IngredientId = entry.IngredientId,
					Quantity = quantity,
				}
			end
		end
	end
	return yields
end

local function buildWeightedYield(spec: FoodSourceSpec): { IngredientGrantEntry }
	local weightedEntries = {}
	local totalWeight = 0
	for _, entry in ipairs(spec.Yields) do
		if typeof(entry.IngredientId) == "string" and entry.IngredientId ~= "" then
			local weight = sanitizePositiveInteger(entry.Weight)
			if weight <= 0 then
				weight = 1
			end
			totalWeight += weight
			weightedEntries[#weightedEntries + 1] = {
				Definition = entry,
				Weight = weight,
			}
		end
	end
	if totalWeight <= 0 then
		return {}
	end
	local roll = math.random(totalWeight)
	local cumulative = 0
	for _, weighted in ipairs(weightedEntries) do
		cumulative += weighted.Weight
		if roll <= cumulative then
			local quantity = resolveQuantity(weighted.Definition)
			if quantity <= 0 then
				return {}
			end
			return {
				{
					IngredientId = weighted.Definition.IngredientId,
					Quantity = quantity,
				},
			}
		end
	end
	return {}
end

local function selectYields(spec: FoodSourceSpec): { IngredientGrantEntry }
	if #spec.Yields == 0 then
		return {}
	end
	local mode = spec.YieldMode or "Guaranteed"
	if mode == "Weighted" then
		return buildWeightedYield(spec)
	end
	-- Scatter is treated the same as guaranteed for now.
	return buildGuaranteedYields(spec)
end

local function getPlotSave(player: Player): any?
	local plotState = PlotService.GetState(player)
	if not plotState then
		return nil
	end
	local save = plotState.Save
	if not save then
		return nil
	end
	if not save.InteractableCooldowns then
		save.InteractableCooldowns = {}
	end
	return save
end

local function getCooldownMap(player: Player): { [string]: FoodSourceCooldownRecord }?
	local save = getPlotSave(player)
	if not save then
		return nil
	end
	return save.InteractableCooldowns
end

local function loadCooldownRecord(player: Player, key: string): FoodSourceCooldownRecord?
	local map = getCooldownMap(player)
	if not map then
		return nil
	end
	return map[key]
end

local function writeCooldownRecord(runtime: SourceRuntime, charges: number, readyUnix: number?)
	local map = getCooldownMap(runtime.Player)
	if not map then
		return
	end
	local key = runtime.PersistenceKey
	if key == "" then
		return
	end
	local record = map[key]
	if not record then
		record = {}
		map[key] = record
	end
	record.ChargesRemaining = math.max(0, sanitizePositiveInteger(charges))
	if typeof(readyUnix) == "number" and readyUnix > 0 then
		record.RestockReadyUnix = readyUnix
	else
		record.RestockReadyUnix = nil
	end
end

local function removeCooldownRecord(runtime: SourceRuntime)
	local map = getCooldownMap(runtime.Player)
	if not map then
		return
	end
	map[runtime.PersistenceKey] = nil
end

local function computeRelativePath(model: Instance, root: Instance?): string
	local components = {}
	local current: Instance? = model
	while current and current ~= root do
		table.insert(components, 1, current.Name)
		current = current.Parent
	end
	if root and current == root then
		return table.concat(components, "/")
	end
	local ok, full = pcall(model.GetFullName, model)
	if ok then
		return full
	end
	return table.concat(components, "/")
end

local function computePersistenceKey(player: Player, model: Model): string
	local cached = model:GetAttribute("FoodSourcePersistenceKey")
	if typeof(cached) == "string" and cached ~= "" then
		return cached
	end
	local plotIndexAttr = player:GetAttribute("OwnedPlotIndex")
	local plotIndex = if typeof(plotIndexAttr) == "number" then plotIndexAttr else -1
	local plotModel = nil
	if typeof(plotIndexAttr) == "number" then
		plotModel = PlotFinder.FindPlot(plotIndexAttr)
	end
	local path = computeRelativePath(model, plotModel)
	local key = string.format("%d:%s", plotIndex, path)
	model:SetAttribute("FoodSourcePersistenceKey", key)
	return key
end

local function resolveTargetForModel(model: Model, spec: FoodSourceSpec): (string?, string?, string?, number?)
	local targetSpec = spec.TargetStorage
	local containerId: string? = nil
	local containerAttr = model:GetAttribute("HarvestContainerId")
	if typeof(containerAttr) == "string" and containerAttr ~= "" then
		containerId = containerAttr
	elseif targetSpec and typeof(targetSpec.ContainerId) == "string" and targetSpec.ContainerId ~= "" then
		containerId = targetSpec.ContainerId
	end

	local stationType: string? = nil
	local stationAttr = model:GetAttribute("HarvestStationType")
	if typeof(stationAttr) == "string" and stationAttr ~= "" then
		stationType = stationAttr
	elseif targetSpec and typeof(targetSpec.StationType) == "string" and targetSpec.StationType ~= "" then
		stationType = targetSpec.StationType
	end

	local itemId: string? = nil
	local itemAttr = model:GetAttribute("HarvestItemId")
	if typeof(itemAttr) == "string" and itemAttr ~= "" then
		itemId = itemAttr
	elseif targetSpec and typeof(targetSpec.ItemId) == "string" and targetSpec.ItemId ~= "" then
		itemId = targetSpec.ItemId
	end

	local capacityValue: number? = nil
	local capacityAttr = model:GetAttribute("HarvestCapacity")
	if typeof(capacityAttr) == "number" then
		capacityValue = sanitizePositiveInteger(capacityAttr)
	elseif targetSpec and typeof(targetSpec.Capacity) == "number" then
		capacityValue = sanitizePositiveInteger(targetSpec.Capacity)
	end

	return containerId, stationType, itemId, capacityValue
end

local function completeRestock(runtime: SourceRuntime)
	local defaultCharges = sanitizePositiveInteger(runtime.Spec.Charges)
	if defaultCharges <= 0 then
		defaultCharges = 1
	end
	runtime.ChargesRemaining = defaultCharges
	runtime.Model:SetAttribute("ChargesRemaining", runtime.ChargesRemaining)
	runtime.Model:SetAttribute("HarvestReady", true)
	runtime.Model:SetAttribute("HarvestRestockAt", 0)
	writeCooldownRecord(runtime, runtime.ChargesRemaining, nil)
end

local function beginRestock(runtime: SourceRuntime, overrideSeconds: number?, overrideReadyUnix: number?)
	runtime.RestockToken += 1
	local token = runtime.RestockToken
	local nowServer = Workspace:GetServerTimeNow()
	local nowUnix = os.time()

	local remainingSeconds: number
	local targetUnix: number

	if typeof(overrideReadyUnix) == "number" then
		remainingSeconds = math.max(0, overrideReadyUnix - nowUnix)
		targetUnix = overrideReadyUnix
	elseif typeof(overrideSeconds) == "number" then
		remainingSeconds = math.max(0, sanitizePositiveInteger(overrideSeconds))
		targetUnix = nowUnix + remainingSeconds
	else
		local specSeconds = sanitizePositiveInteger(runtime.Spec.RestockSeconds)
		remainingSeconds = math.max(0, specSeconds)
		targetUnix = nowUnix + remainingSeconds
	end

	runtime.Model:SetAttribute("HarvestReady", false)
	runtime.Model:SetAttribute("HarvestRestockAt", nowServer + remainingSeconds)
	writeCooldownRecord(runtime, runtime.ChargesRemaining, targetUnix)

	if remainingSeconds <= 0 then
		completeRestock(runtime)
		return
	end

	task.delay(remainingSeconds, function()
		if SourcesByGuid[runtime.Guid] ~= runtime then
			return
		end
		if runtime.RestockToken ~= token then
			return
		end
		completeRestock(runtime)
	end)
end

local function hydrateRuntimeFromSave(runtime: SourceRuntime)
	local record = loadCooldownRecord(runtime.Player, runtime.PersistenceKey)
	if not record then
		writeCooldownRecord(runtime, runtime.ChargesRemaining, nil)
		return
	end

	local charges = sanitizePositiveInteger(record.ChargesRemaining)
	local readyUnix = record.RestockReadyUnix

	if charges <= 0 then
		runtime.ChargesRemaining = 0
		runtime.Model:SetAttribute("ChargesRemaining", 0)
		if typeof(readyUnix) == "number" and readyUnix > 0 then
			beginRestock(runtime, nil, readyUnix)
		else
			completeRestock(runtime)
		end
		return
	end

	runtime.ChargesRemaining = charges
	runtime.Model:SetAttribute("ChargesRemaining", charges)
	runtime.Model:SetAttribute("HarvestReady", true)
	runtime.Model:SetAttribute("HarvestRestockAt", 0)
	writeCooldownRecord(runtime, charges, nil)
end

local function cleanupRuntime(model: Model, forgetState: boolean?)
	local runtime = SourcesByModel[model]
	if not runtime then
		return
	end
	SourcesByModel[model] = nil
	if SourcesByGuid[runtime.Guid] == runtime then
		SourcesByGuid[runtime.Guid] = nil
	end
	for _, connection in ipairs(runtime.Connections) do
		connection:Disconnect()
	end
	runtime.Connections = {}

	if forgetState then
		removeCooldownRecord(runtime)
	end
	if model.Parent then
		model:SetAttribute("HarvestReady", false)
		model:SetAttribute("HarvestRestockAt", 0)
		model:SetAttribute("ChargesRemaining", 0)
		model:SetAttribute("FoodSourceGuid", nil)
	end
end

local function registerRuntime(player: Player, model: Model, spec: FoodSourceSpec)
	cleanupRuntime(model)

	local guid = HttpService:GenerateGUID(false)
	local defaultCharges = sanitizePositiveInteger(spec.Charges)
	if defaultCharges <= 0 then
		defaultCharges = 1
	end

	model:SetAttribute("FoodSourceId", spec.Id)
	model:SetAttribute("FoodSourceGuid", guid)
	model:SetAttribute("ChargesRemaining", defaultCharges)
	model:SetAttribute("HarvestReady", true)
	model:SetAttribute("HarvestRestockAt", 0)

	local targetContainerId, targetStationType, targetItemId, targetCapacity = resolveTargetForModel(model, spec)

	if targetContainerId then
		model:SetAttribute("HarvestContainerId", targetContainerId)
	else
		model:SetAttribute("HarvestContainerId", nil)
	end
	if targetStationType then
		model:SetAttribute("HarvestStationType", targetStationType)
	end
	if targetItemId then
		model:SetAttribute("HarvestItemId", targetItemId)
	end
	if targetCapacity then
		model:SetAttribute("HarvestCapacity", targetCapacity)
	end

	local persistenceKey = computePersistenceKey(player, model)

	local runtime: SourceRuntime = {
		Player = player,
		Model = model,
		Spec = spec,
		Guid = guid,
		PersistenceKey = persistenceKey,
		ChargesRemaining = defaultCharges,
		RestockToken = 0,
		Busy = false,
		Connections = {},
		TargetContainerId = targetContainerId,
		TargetStationType = targetStationType,
		TargetItemId = targetItemId,
		TargetCapacity = targetCapacity,
	}

	runtime.Connections[#runtime.Connections + 1] = model.Destroying:Connect(function()
		cleanupRuntime(model, true)
	end)

	runtime.Connections[#runtime.Connections + 1] = model.AncestryChanged:Connect(function(_, parent)
		if parent == nil then
			cleanupRuntime(model, true)
		end
	end)

	runtime.Connections[#runtime.Connections + 1] = model:GetAttributeChangedSignal("FoodSourceId"):Connect(function()
		local newId = model:GetAttribute("FoodSourceId")
		local newSpec
		if typeof(newId) == "string" and newId ~= "" then
			newSpec = FoodSources[newId]
		end
		if newSpec then
			runtime.Spec = newSpec
		else
			cleanupRuntime(model, true)
		end
	end)

	runtime.Connections[#runtime.Connections + 1] = model:GetAttributeChangedSignal("FoodSourceGuid"):Connect(function()
		local newGuid = model:GetAttribute("FoodSourceGuid")
		if typeof(newGuid) ~= "string" or newGuid == "" then
			return
		end
		SourcesByGuid[runtime.Guid] = nil
		runtime.Guid = newGuid
		SourcesByGuid[newGuid] = runtime
	end)

	SourcesByModel[model] = runtime
	SourcesByGuid[guid] = runtime

	hydrateRuntimeFromSave(runtime)
end

local function harvest(player: Player, sourceHandle: any): (boolean, string)
	if typeof(sourceHandle) ~= "string" or sourceHandle == "" then
		return false, "InvalidSource"
	end

	local guid = sourceHandle :: string
	local runtime = SourcesByGuid[guid]
	if not runtime then
		return false, "SourceUnavailable"
	end
	if runtime.Player ~= player then
		return false, "NotYourPlot"
	end
	if runtime.Busy then
		return false, "HarvestBusy"
	end
	if runtime.ChargesRemaining <= 0 then
		return false, "Restocking"
	end

	runtime.Busy = true
	runtime.Model:SetAttribute("HarvestReady", false)

	local yields = selectYields(runtime.Spec)
	if #yields == 0 then
		runtime.Busy = false
		if runtime.ChargesRemaining > 0 then
			runtime.Model:SetAttribute("HarvestReady", true)
		end
		return false, "NoYield"
	end

	local success, reason = KitchenService.ApplyIngredientGrant(player, yields, {
		SourceId = runtime.Spec.Id,
		SourceName = runtime.Spec.Name,
		TargetContainerId = runtime.TargetContainerId,
		TargetStationType = runtime.TargetStationType,
		TargetItemId = runtime.TargetItemId,
		TargetCapacity = runtime.TargetCapacity,
	})
	if not success then
		runtime.Busy = false
		if runtime.ChargesRemaining > 0 then
			runtime.Model:SetAttribute("HarvestReady", true)
		end
		return false, reason or "GrantFailed"
	end

	runtime.ChargesRemaining -= 1
	runtime.Model:SetAttribute("ChargesRemaining", runtime.ChargesRemaining)
	if runtime.ChargesRemaining <= 0 then
		beginRestock(runtime, nil, nil)
	else
		runtime.Model:SetAttribute("HarvestReady", true)
		runtime.Model:SetAttribute("HarvestRestockAt", 0)
		writeCooldownRecord(runtime, runtime.ChargesRemaining, nil)
	end

	runtime.Busy = false
	return true, ""
end

local function bindFolder(player: Player, folder: Instance)
	local userId = player.UserId
	local binding = PlayerBindings[userId]
	if binding then
		for _, connection in ipairs(binding.Connections) do
			connection:Disconnect()
		end
	else
		binding = {
			Folder = folder,
			Connections = {},
		}
		PlayerBindings[userId] = binding
	end
	binding.Folder = folder

	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			local spec = nil
			local idAttr = child:GetAttribute("FoodSourceId")
			if typeof(idAttr) == "string" and idAttr ~= "" then
				spec = FoodSources[idAttr]
			end
			if not spec then
				spec = FoodSources[child.Name]
			end
			if spec then
				registerRuntime(player, child, spec)
			end
		end
	end

	binding.Connections[#binding.Connections + 1] = folder.ChildAdded:Connect(function(child)
		if not child:IsA("Model") then
			return
		end
		local spec = nil
		local idAttr = child:GetAttribute("FoodSourceId")
		if typeof(idAttr) == "string" and idAttr ~= "" then
			spec = FoodSources[idAttr]
		end
		if not spec then
			spec = FoodSources[child.Name]
		end
		if not spec then
			return
		end
		registerRuntime(player, child, spec)
	end)

	binding.Connections[#binding.Connections + 1] = folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			cleanupRuntime(child, true)
		end
	end)
end

local function unbindPlayer(player: Player)
	local userId = player.UserId
	local binding = PlayerBindings[userId]
	if binding then
		for _, connection in ipairs(binding.Connections) do
			connection:Disconnect()
		end
		PlayerBindings[userId] = nil
	end

	local toCleanup: { Model } = {}
	for model, runtime in pairs(SourcesByModel) do
		if runtime.Player == player then
			toCleanup[#toCleanup + 1] = model
		end
	end
	for _, model in ipairs(toCleanup) do
		cleanupRuntime(model)
	end
end

local function tryBindPlot(player: Player)
	local plotIndexAttr = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndexAttr) ~= "number" then
		return
	end
	local plotModel = PlotFinder.FindPlot(plotIndexAttr)
	if not plotModel then
		return
	end
	local interactables = plotModel:FindFirstChild("Interactables")
	if interactables then
		bindFolder(player, interactables)
		return
	end

	local childAddedConn: RBXScriptConnection?
	childAddedConn = plotModel.ChildAdded:Connect(function(child)
		if child.Name == "Interactables" then
			if childAddedConn then
				childAddedConn:Disconnect()
				childAddedConn = nil
			end
			bindFolder(player, child)
		end
	end)
end

function FoodSourceService.Init()
	FoodPackets.HarvestFoodSourceRequest.OnServerInvoke = function(player: Player, sourceGuid: string?)
		return harvest(player, sourceGuid)
	end

	PlotService.PlotClaimed:Connect(function(player: Player)
		tryBindPlot(player)
	end)

	PlotService.PlotUnclaimed:Connect(function(player: Player)
		unbindPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		unbindPlayer(player)
	end)

	Players.PlayerAdded:Connect(function(player: Player)
		player:GetAttributeChangedSignal("OwnedPlotIndex"):Connect(function()
			tryBindPlot(player)
		end)
	end)

	for _, player in ipairs(Players:GetPlayers()) do
		tryBindPlot(player)
	end
end

return FoodSourceService
