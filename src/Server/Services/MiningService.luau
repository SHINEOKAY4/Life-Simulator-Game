--!strict
-- ServerScriptService/Server/Services/MiningService.luau
-- Manages shared rock nodes, mining requests, yields, and respawn timers.

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local ServicesFolder = ServerScriptService.Server.Services
local UtilitiesFolder = ServerScriptService.Server.Utilities

local PlayerSession = require(ServicesFolder.PlayerSession)
local CurrencyService = require(ServicesFolder.CurrencyService)
local MiningPackets = require(ReplicatedStorage.Network.MiningPackets)
local MiningConfig = require(ReplicatedStorage.Shared.Definitions.MiningConfig)
local WorldUpdate = require(UtilitiesFolder.WorldUpdate)

local RockStateAttributes = MiningConfig.RockStateAttributes
local RockStates = MiningConfig.RockStateEnum

local RockStorageFolder = (function()
	local existing = ReplicatedStorage:FindFirstChild("MiningRockStorage")
	if existing and existing:IsA("Folder") then
		return existing
	end
	local folder = Instance.new("Folder")
	folder.Name = "MiningRockStorage"
	folder.Parent = ReplicatedStorage
	return folder
end)()

export type RockSpec = MiningConfig.RockSpec

export type RockRuntime = {
	Guid: string,
	Instance: Instance,
	Spec: RockSpec,
	State: string,
	RespawnAt: number,
	BusyUserId: number?,
	BusyToken: number,
	HomeParent: Instance?,
	OriginalTransform: CFrame,
}

local MiningService = {}

local registeredRocks: { [string]: RockRuntime } = {}
local rocksByInstance: { [Instance]: RockRuntime } = {}
local regrowQueue: { [string]: true } = {}

local MINING_WORLDUPDATE_NAME = "MiningService.Regrow"

local function nowServer(): number
	return Workspace:GetServerTimeNow()
end

local WorldFolder = Workspace:WaitForChild("World")
local ForestFolder = WorldFolder:WaitForChild("Forest")
local RockFolder = ForestFolder:WaitForChild("Rocks") :: Folder

local function resolveRockSpec(instance: Instance): RockSpec?
	local attrType = instance:GetAttribute(RockStateAttributes.TypeId)
	if typeof(attrType) == "string" and attrType ~= "" then
		local byAttr = MiningConfig.RockTypes[attrType]
		if byAttr then
			return byAttr
		end
	end

	local nameLookup = MiningConfig.RockTypes[instance.Name]
	if nameLookup then
		return nameLookup
	end

	for _, spec in pairs(MiningConfig.RockTypes) do
		if spec.ModelName and spec.ModelName == instance.Name then
			return spec
		end
	end

	return nil
end

local function computeInstancePosition(instance: Instance): Vector3
	if instance:IsA("BasePart") then
		return instance.Position
	end
	if instance:IsA("Model") then
		local model = instance :: Model
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
	end
	return Vector3.zero
end

local function getCurrentTransform(instance: Instance): CFrame
	if instance:IsA("BasePart") then
		return instance.CFrame
	end
	if instance:IsA("Model") then
		local model = instance :: Model
		local ok, pivot = pcall(model.GetPivot, model)
		if ok then
			return pivot
		end
	end
	return CFrame.identity
end

local function applyTransform(instance: Instance, target: CFrame)
	if instance:IsA("BasePart") then
		(instance :: BasePart).CFrame = target
		return
	end
	if instance:IsA("Model") then
		local model = instance :: Model
		pcall(function()
			model:PivotTo(target)
		end)
	end
end

local function setInstanceAttributes(runtime: RockRuntime)
	runtime.Instance:SetAttribute(RockStateAttributes.Guid, runtime.Guid)
	runtime.Instance:SetAttribute(RockStateAttributes.TypeId, runtime.Spec.Id)
	runtime.Instance:SetAttribute(RockStateAttributes.State, runtime.State)
	runtime.Instance:SetAttribute(RockStateAttributes.BusyUserId, runtime.BusyUserId or 0)
	runtime.Instance:SetAttribute(RockStateAttributes.RespawnAt, runtime.RespawnAt)
end

local function broadcastState(runtime: RockRuntime)
	local position = computeInstancePosition(runtime.Instance)
	local payload = {
		Guid = runtime.Guid,
		TypeId = runtime.Spec.Id,
		State = runtime.State,
		RespawnAt = runtime.RespawnAt,
		Position = position,
		BusyUserId = runtime.BusyUserId or 0,
	}
	for _, player in ipairs(Players:GetPlayers()) do
		MiningPackets.RockStateChanged:FireClient(player, payload)
	end
end

local function transitionToState(runtime: RockRuntime, nextState: string, respawnAt: number?, busyUserId: number?)
	runtime.State = nextState
	runtime.RespawnAt = respawnAt or 0
	runtime.BusyUserId = busyUserId
	if nextState ~= RockStates.Busy then
		runtime.BusyToken += 1
	end
	if nextState == RockStates.Ready then
		if runtime.HomeParent and runtime.Instance.Parent ~= runtime.HomeParent then
			runtime.Instance.Parent = runtime.HomeParent
		end
		applyTransform(runtime.Instance, runtime.OriginalTransform)
	elseif nextState == RockStates.Regrowing then
		task.delay(0.5, function()
			if registeredRocks[runtime.Guid] ~= runtime then
				return
			end
			if runtime.State ~= RockStates.Regrowing then
				return
			end
			runtime.Instance.Parent = RockStorageFolder
		end)
	end
	setInstanceAttributes(runtime)
	broadcastState(runtime)
	if nextState == RockStates.Regrowing and respawnAt and respawnAt > 0 then
		regrowQueue[runtime.Guid] = true
	else
		regrowQueue[runtime.Guid] = nil
	end
end

local function grantRockYield(player: Player, runtime: RockRuntime): (boolean, string?, number)
	local spec = runtime.Spec
	local yieldSpec = spec.Yield
	local itemDefId = yieldSpec.ItemDefId
	local quantity = math.max(1, yieldSpec.Quantity or 1)

	local inventoryState = PlayerSession.GetDataAwait(player, "InventoryState")
	if not inventoryState then
		return false, "InventoryUnavailable", 0
	end

	local category = MiningConfig.DefaultBagCategory
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

	MiningPackets.RockYieldNotice:FireClient(player, {
		Guid = runtime.Guid,
		ItemDefId = itemDefId,
		Quantity = quantity,
	})

	return true, nil, quantity
end

local function scheduleRegrow(runtime: RockRuntime)
	if runtime.Spec.RespawnSeconds and runtime.Spec.RespawnSeconds <= 0 then
		transitionToState(runtime, RockStates.Ready, 0, nil)
		return
	end

	local respawnSeconds = math.max(1, runtime.Spec.RespawnSeconds or 20)
	transitionToState(runtime, RockStates.Regrowing, nowServer() + respawnSeconds, nil)
	task.delay(respawnSeconds, function()
		local current = registeredRocks[runtime.Guid]
		if current ~= runtime then
			return
		end
		if runtime.State ~= RockStates.Regrowing then
			return
		end
		transitionToState(runtime, RockStates.Ready, 0, nil)
	end)
end

local function finalizeMine(runtime: RockRuntime, player: Player, token: number)
	if registeredRocks[runtime.Guid] ~= runtime then
		return
	end
	if runtime.State ~= RockStates.Busy then
		return
	end
	if runtime.BusyToken ~= token then
		return
	end
	if runtime.BusyUserId ~= player.UserId then
		return
	end

	local ok, message = grantRockYield(player, runtime)
	if not ok then
		transitionToState(runtime, RockStates.Ready, 0, nil)
		warn("MiningService: failed to grant yield", message)
		return
	end
	scheduleRegrow(runtime)
end

local function beginMine(player: Player, runtime: RockRuntime): (boolean, string, number)
	if runtime.State ~= RockStates.Ready then
		return false, "Rock not ready", 0
	end

	runtime.BusyToken += 1
	local token = runtime.BusyToken
	transitionToState(runtime, RockStates.Busy, 0, player.UserId)

	local duration = math.max(1, runtime.Spec.MineDurationSeconds or 4)
	task.delay(duration, function()
		finalizeMine(runtime, player, token)
	end)

	return true, "", duration
end

local function serializeRuntime(runtime: RockRuntime)
	return {
		Guid = runtime.Guid,
		TypeId = runtime.Spec.Id,
		State = runtime.State,
		RespawnAt = runtime.RespawnAt,
		Position = computeInstancePosition(runtime.Instance),
		BusyUserId = runtime.BusyUserId or 0,
	}
end

local function handleRockMineRequest(player: Player, rockGuid: string?)
	if typeof(rockGuid) ~= "string" or rockGuid == "" then
		return false, "Invalid rock id", 0
	end

	local runtime = registeredRocks[rockGuid]
	if not runtime then
		return false, "Rock unavailable", 0
	end

	if runtime.State == RockStates.Busy and runtime.BusyUserId ~= player.UserId then
		return false, "Rock already in use", 0
	end

	if runtime.State == RockStates.Regrowing then
		return false, "Rock is regrowing", 0
	end

	local success, message, duration = beginMine(player, runtime)
	return success, message, duration
end

local function handleMineSnapshot(_player: Player)
	local snapshot = {}
	for _, runtime in pairs(registeredRocks) do
		snapshot[#snapshot + 1] = serializeRuntime(runtime)
	end
	return {
		Timestamp = nowServer(),
		Rocks = snapshot,
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

local function handleSellOre(player: Player, itemDefId: string?, quantityRaw: number?)
	if typeof(itemDefId) ~= "string" or itemDefId == "" then
		return false, "Invalid item", 0
	end
	local quantity = sanitizeQuantity(quantityRaw)
	if not quantity then
		return false, "Invalid quantity", 0
	end

	local priceSpec = MiningConfig.SellPrices[itemDefId]
	if not priceSpec then
		return false, "Item cannot be sold", 0
	end

	local inventoryState = PlayerSession.GetDataAwait(player, "InventoryState")
	if not inventoryState then
		return false, "Inventory unavailable", 0
	end

	local category = MiningConfig.DefaultBagCategory
	local bagAny = inventoryState[category]
	if typeof(bagAny) ~= "table" then
		return false, "No ore found", 0
	end
	local bag = bagAny :: { [string]: number }

	local current = bag[itemDefId]
	if typeof(current) ~= "number" or current < quantity then
		return false, "Not enough ore", 0
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
		Source = "Mining",
	})

	return true, "", total
end

local function registerRock(instance: Instance)
	if rocksByInstance[instance] then
		return
	end

	local spec = resolveRockSpec(instance)
	if not spec then
		warn("MiningService: missing rock spec for", instance:GetFullName())
		return
	end

	local guidAttr = instance:GetAttribute(RockStateAttributes.Guid)
	local guid = if typeof(guidAttr) == "string" and guidAttr ~= "" then guidAttr else HttpService:GenerateGUID(false)

	local runtime: RockRuntime = {
		Guid = guid,
		Instance = instance,
		Spec = spec,
		State = RockStates.Ready,
		RespawnAt = 0,
		BusyUserId = nil,
		BusyToken = 0,
		HomeParent = instance.Parent,
		OriginalTransform = getCurrentTransform(instance),
	}

	registeredRocks[guid] = runtime
	rocksByInstance[instance] = runtime

	setInstanceAttributes(runtime)
	broadcastState(runtime)

	instance.Destroying:Connect(function()
		registeredRocks[guid] = nil
		rocksByInstance[instance] = nil
		regrowQueue[guid] = nil
	end)

	instance:GetAttributeChangedSignal(RockStateAttributes.TypeId):Connect(function()
		local updatedSpec = resolveRockSpec(instance)
		if updatedSpec then
			runtime.Spec = updatedSpec
			setInstanceAttributes(runtime)
		end
	end)
end

local function bindRockFolder(folder: Instance)
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("Model") or child:IsA("BasePart") then
			registerRock(child)
		end
	end
	folder.ChildAdded:Connect(function(child)
		if child:IsA("Model") or child:IsA("BasePart") then
			registerRock(child)
		end
	end)
	folder.ChildRemoved:Connect(function(child)
		if child:IsA("Model") or child:IsA("BasePart") then
			if child.Parent == RockStorageFolder then
				return
			end
			local runtime = rocksByInstance[child]
			if runtime then
				registeredRocks[runtime.Guid] = nil
				rocksByInstance[child] = nil
				regrowQueue[runtime.Guid] = nil
			end
		end
	end)
end

function MiningService.Init()
	bindRockFolder(RockFolder)

	MiningPackets.RockMineRequest.OnServerInvoke = handleRockMineRequest
	MiningPackets.RequestMineSnapshot.OnServerInvoke = handleMineSnapshot
	MiningPackets.SellOreRequest.OnServerInvoke = handleSellOre

	WorldUpdate.Subscribe(MINING_WORLDUPDATE_NAME, 1.2, function()
		local now = nowServer()
		for guid in pairs(regrowQueue) do
			local runtime = registeredRocks[guid]
			if
				runtime
				and runtime.State == RockStates.Regrowing
				and runtime.RespawnAt > 0
				and now >= runtime.RespawnAt
			then
				transitionToState(runtime, RockStates.Ready, 0, nil)
			end
		end
	end)
end

return MiningService
