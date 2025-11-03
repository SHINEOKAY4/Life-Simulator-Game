--!strict
-- ServerScriptService/Server/Services/WoodcuttingService.luau
-- Manages shared forest trees, chop requests, yields, and regrowth timers.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ServicesFolder = ServerScriptService.Server.Services
local UtilitiesFolder = ServerScriptService.Server.Utilities

local PlayerSession = require(ServicesFolder.PlayerSession)
local CurrencyService = require(ServicesFolder.CurrencyService)
local WoodcuttingPackets = require(ReplicatedStorage.Network.WoodcuttingPackets)
local WoodcuttingConfig = require(ReplicatedStorage.Shared.Definitions.WoodcuttingConfig)
local WorldUpdate = require(UtilitiesFolder.WorldUpdate)

local TreeStateAttributes = WoodcuttingConfig.TreeStateAttributes
local TreeStates = WoodcuttingConfig.TreeStateEnum
local TREE_FALL_DURATION = WoodcuttingConfig.TreeFallDuration or 1.2

local TreeStorageFolder = (function()
	local existing = ReplicatedStorage:FindFirstChild("WoodcuttingTreeStorage")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "WoodcuttingTreeStorage"
	folder.Parent = ReplicatedStorage
	return folder
end)()

export type TreeSpec = WoodcuttingConfig.TreeSpec

export type TreeRuntime = {
	Guid: string,
	Model: Model,
	Spec: TreeSpec,
	State: string,
	RespawnAt: number,
	BusyUserId: number?,
	BusyToken: number,
	HomeParent: Instance?,
	OriginalPivot: CFrame,
}

local WoodcuttingService = {}

local registeredTrees: { [string]: TreeRuntime } = {}
local treesByModel: { [Model]: TreeRuntime } = {}
local regrowQueue: { [string]: true } = {}

local WOODCUTTING_WORLDUPDATE_NAME = "WoodcuttingService.Regrow"

local function nowServer(): number
	return Workspace:GetServerTimeNow()
end

local WorldFolder = Workspace:WaitForChild("World")
local ForestFolder = WorldFolder:WaitForChild("Forest")
local TreeFolder = ForestFolder:WaitForChild("Trees") :: Folder

local function resolveTreeSpec(model: Model): TreeSpec?
	local attrType = model:GetAttribute(TreeStateAttributes.TypeId)
	if typeof(attrType) == "string" and attrType ~= "" then
		local byAttr = WoodcuttingConfig.TreeTypes[attrType]
		if byAttr then
			return byAttr
		end
	end
	local nameLookup = WoodcuttingConfig.TreeTypes[model.Name]
	if nameLookup then
		return nameLookup
	end
	for _, spec in pairs(WoodcuttingConfig.TreeTypes) do
		if spec.ModelName and spec.ModelName == model.Name then
			return spec
		end
	end
	return nil
end

local function computeModelPosition(model: Model): Vector3
	local primary = model.PrimaryPart
	if primary and primary:IsA("BasePart") then
		return primary.Position
	end
	local okPivot, pivot = pcall(model.GetPivot, model)
	if okPivot then
		return pivot.Position
	end
	local okBounds, boundsCFrame = pcall(function(): CFrame
		local cframe = model:GetBoundingBox()
		return cframe
	end)
	if okBounds then
		return (boundsCFrame :: CFrame).Position
	end
	return Vector3.zero
end

local function setModelAttributes(runtime: TreeRuntime)
	runtime.Model:SetAttribute(TreeStateAttributes.Guid, runtime.Guid)
	runtime.Model:SetAttribute(TreeStateAttributes.TypeId, runtime.Spec.Id)
	runtime.Model:SetAttribute(TreeStateAttributes.State, runtime.State)
	runtime.Model:SetAttribute(TreeStateAttributes.BusyUserId, runtime.BusyUserId or 0)
	runtime.Model:SetAttribute(TreeStateAttributes.RespawnAt, runtime.RespawnAt)
end

local function broadcastState(runtime: TreeRuntime)
	local position = computeModelPosition(runtime.Model)
	local payload = {
		Guid = runtime.Guid,
		TypeId = runtime.Spec.Id,
		State = runtime.State,
		RespawnAt = runtime.RespawnAt,
		Position = position,
		BusyUserId = runtime.BusyUserId or 0,
	}
	for _, player in ipairs(Players:GetPlayers()) do
		WoodcuttingPackets.TreeStateChanged:FireClient(player, payload)
	end
end

local function transitionToState(runtime: TreeRuntime, nextState: string, respawnAt: number?, busyUserId: number?)
	runtime.State = nextState
	runtime.RespawnAt = respawnAt or 0
	runtime.BusyUserId = busyUserId
	if nextState ~= TreeStates.Busy then
		runtime.BusyToken += 1
	end
	if nextState == TreeStates.Ready then
		if runtime.HomeParent and runtime.Model.Parent ~= runtime.HomeParent then
			runtime.Model.Parent = runtime.HomeParent
		end
		pcall(function()
			runtime.Model:PivotTo(runtime.OriginalPivot)
		end)
	elseif nextState == TreeStates.Regrowing then
		task.delay(TREE_FALL_DURATION, function()
			if registeredTrees[runtime.Guid] ~= runtime then
				return
			end
			if runtime.State ~= TreeStates.Regrowing then
				return
			end
			runtime.Model.Parent = TreeStorageFolder
		end)
	end
	setModelAttributes(runtime)
	broadcastState(runtime)
	if nextState == TreeStates.Regrowing and respawnAt and respawnAt > 0 then
		regrowQueue[runtime.Guid] = true
	else
		regrowQueue[runtime.Guid] = nil
	end
end

local function grantTreeYield(player: Player, runtime: TreeRuntime): (boolean, string?, number)
	local spec = runtime.Spec
	local yieldSpec = spec.Yield
	local itemDefId = yieldSpec.ItemDefId
	local quantity = math.max(1, yieldSpec.Quantity or 1)

	local inventoryState = PlayerSession.GetDataAwait(player, "InventoryState")
	if not inventoryState then
		return false, "InventoryUnavailable", 0
	end

	local category = WoodcuttingConfig.DefaultBagCategory
	local categorySnapshot = inventoryState[category]
	if typeof(categorySnapshot) ~= "table" then
		categorySnapshot = {}
		inventoryState[category] = categorySnapshot
	end
	local bag = categorySnapshot :: { [string]: number }

	local currentAmount = bag[itemDefId]
	if typeof(currentAmount) ~= "number" then
		currentAmount = 0
	end
	bag[itemDefId] = currentAmount + quantity

	WoodcuttingPackets.TreeYieldNotice:FireClient(player, {
		Guid = runtime.Guid,
		ItemDefId = itemDefId,
		Quantity = quantity,
	})

	return true, nil, quantity
end

local function scheduleRegrow(runtime: TreeRuntime)
	if runtime.Spec.RespawnSeconds and runtime.Spec.RespawnSeconds <= 0 then
		transitionToState(runtime, TreeStates.Ready, 0, nil)
		return
	end

	local respawnSeconds = math.max(1, runtime.Spec.RespawnSeconds or 15)
	transitionToState(runtime, TreeStates.Regrowing, nowServer() + respawnSeconds, nil)
	task.delay(respawnSeconds, function()
		local current = registeredTrees[runtime.Guid]
		if current ~= runtime then
			return
		end
		if runtime.State ~= TreeStates.Regrowing then
			return
		end
		transitionToState(runtime, TreeStates.Ready, 0, nil)
	end)
end

local function finalizeChop(runtime: TreeRuntime, player: Player, token: number)
	if registeredTrees[runtime.Guid] ~= runtime then
		return
	end
	if runtime.State ~= TreeStates.Busy then
		return
	end
	if runtime.BusyToken ~= token then
		return
	end
	if runtime.BusyUserId ~= player.UserId then
		return
	end

	local ok, message = grantTreeYield(player, runtime)
	if not ok then
		transitionToState(runtime, TreeStates.Ready, 0, nil)
		warn("WoodcuttingService: failed to grant yield", message)
		return
	end
	scheduleRegrow(runtime)
end

local function beginChop(player: Player, runtime: TreeRuntime): (boolean, string, number)
	if runtime.State ~= TreeStates.Ready then
		return false, "Tree not ready", 0
	end

	runtime.BusyToken += 1
	local token = runtime.BusyToken
	transitionToState(runtime, TreeStates.Busy, 0, player.UserId)

	local duration = math.max(1, runtime.Spec.ChopDurationSeconds or 3)
	task.delay(duration, function()
		finalizeChop(runtime, player, token)
	end)

	return true, "", duration
end

local function serializeRuntime(runtime: TreeRuntime)
	return {
		Guid = runtime.Guid,
		TypeId = runtime.Spec.Id,
		State = runtime.State,
		RespawnAt = runtime.RespawnAt,
		Position = computeModelPosition(runtime.Model),
		BusyUserId = runtime.BusyUserId or 0,
	}
end

local function handleTreeChopRequest(player: Player, treeGuid: string?)
	if typeof(treeGuid) ~= "string" or treeGuid == "" then
		return false, "Invalid tree id", 0
	end

	local runtime = registeredTrees[treeGuid]
	if not runtime then
		return false, "Tree unavailable", 0
	end

	if runtime.State == TreeStates.Busy and runtime.BusyUserId ~= player.UserId then
		return false, "Tree already in use", 0
	end

	if runtime.State == TreeStates.Regrowing then
		return false, "Tree is regrowing", 0
	end

	local success, message, duration = beginChop(player, runtime)
	return success, message, duration
end

local function handleForestSnapshot(_player: Player)
	local snapshot = {}
	for _, runtime in pairs(registeredTrees) do
		snapshot[#snapshot + 1] = serializeRuntime(runtime)
	end
	return {
		Timestamp = nowServer(),
		Trees = snapshot,
	}
end

local function sanitizeQuantity(quantity: any): number?
	if typeof(quantity) ~= "number" then
		return nil
	end
	if quantity <= 0 then
		return nil
	end
	if quantity ~= quantity or quantity == math.huge or quantity == -math.huge then
		return nil
	end
	return math.floor(quantity + 0.5)
end

local function handleSellLogs(player: Player, itemDefId: string?, quantityRaw: number?)
	if typeof(itemDefId) ~= "string" or itemDefId == "" then
		return false, "Invalid item", 0
	end
	local quantity = sanitizeQuantity(quantityRaw)
	if not quantity then
		return false, "Invalid quantity", 0
	end

	local priceSpec = WoodcuttingConfig.SellPrices[itemDefId]
	if not priceSpec then
		return false, "Item cannot be sold", 0
	end

	local inventoryState = PlayerSession.GetDataAwait(player, "InventoryState")
	if not inventoryState then
		return false, "Inventory unavailable", 0
	end

	local category = WoodcuttingConfig.DefaultBagCategory
	local bagAny = inventoryState[category]
	if typeof(bagAny) ~= "table" then
		return false, "No logs found", 0
	end
	local bag = bagAny :: { [string]: number }

	local current = bag[itemDefId]
	if typeof(current) ~= "number" or current < quantity then
		return false, "Not enough logs", 0
	end

	bag[itemDefId] = current - quantity
	if bag[itemDefId] <= 0 then
		bag[itemDefId] = nil
	end

	local currencyState = PlayerSession.GetDataAwait(player, "CurrencyState")
	if not currencyState then
		return false, "Currency unavailable", 0
	end

	local total = priceSpec.UnitPrice * quantity
	CurrencyService.Add(player, "Cash", total, currencyState, {
		Source = "Woodcutting",
	})

	return true, "", total
end

local function registerTree(model: Model)
	if treesByModel[model] then
		return
	end

	local spec = resolveTreeSpec(model)
	if not spec then
		warn("WoodcuttingService: missing tree spec for", model:GetFullName())
		return
	end

	local guidAttr = model:GetAttribute(TreeStateAttributes.Guid)
	local guid = if typeof(guidAttr) == "string" and guidAttr ~= "" then guidAttr else HttpService:GenerateGUID(false)

	local runtime: TreeRuntime = {
		Guid = guid,
		Model = model,
		Spec = spec,
		State = TreeStates.Ready,
		RespawnAt = 0,
		BusyUserId = nil,
		BusyToken = 0,
		HomeParent = model.Parent,
		OriginalPivot = model:GetPivot(),
	}

	registeredTrees[guid] = runtime
	treesByModel[model] = runtime

	setModelAttributes(runtime)
	broadcastState(runtime)

	model.Destroying:Connect(function()
		registeredTrees[guid] = nil
		treesByModel[model] = nil
		regrowQueue[guid] = nil
	end)

	model:GetAttributeChangedSignal(TreeStateAttributes.TypeId):Connect(function()
		local updatedSpec = resolveTreeSpec(model)
		if updatedSpec then
			runtime.Spec = updatedSpec
		end
	end)
end

local function scanTreeFolder(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") then
			registerTree(child)
		end
	end
end

local function bindTreeFolder(folder: Instance)
	scanTreeFolder(folder)

	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") then
			registerTree(child)
		end
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") then
			local runtime = treesByModel[child]
			if runtime then
				if child.Parent == TreeStorageFolder then
					return
				end
				registeredTrees[runtime.Guid] = nil
				treesByModel[child] = nil
				regrowQueue[runtime.Guid] = nil
			end
		end
	end)
end

function WoodcuttingService.Init()
	WoodcuttingPackets.TreeChopRequest.OnServerInvoke = handleTreeChopRequest
	WoodcuttingPackets.RequestForestSnapshot.OnServerInvoke = handleForestSnapshot
	WoodcuttingPackets.SellLogsRequest.OnServerInvoke = handleSellLogs

	bindTreeFolder(TreeFolder)

	WorldUpdate.Subscribe(WOODCUTTING_WORLDUPDATE_NAME, 1, function()
		local now = nowServer()
		for guid in pairs(regrowQueue) do
			local runtime = registeredTrees[guid]
			if runtime and runtime.State == TreeStates.Regrowing and runtime.RespawnAt <= now then
				transitionToState(runtime, TreeStates.Ready, 0, nil)
			end
		end
	end)
end

return WoodcuttingService
