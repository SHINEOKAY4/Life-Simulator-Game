--!strict
-- Client/Modules/ChoreController.luau
-- Handles visual representation and interaction for chores (messes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ChorePackets = require(ReplicatedStorage.Network.ChorePackets)
-- Chore prompts use the default ProximityPrompt UI (radial hold) for clarity.
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local SoundtrackManager = require(script.Parent.SoundtrackManager)
local ResidentsFolderFinder = require(ReplicatedStorage.Shared.Utilities.ResidentsFolderFinder)
local RepairVFX = require(script.Parent.RepairVFX)
local RepairConfig = require(ReplicatedStorage.Shared.Configurations.RepairConfig)

local ChoreController = {}

type ChoreVisual = {
	Type: string,
	Instance: Instance?,
	Prompt: ProximityPrompt?,
	Cleanup: (() -> ())?,
	Metadata: { [string]: any }?,
}

local ActiveChores: { [string]: ChoreVisual } = {}
local LocalPlayer = Players.LocalPlayer or Players.PlayerAdded:Wait()
local rng = Random.new()

local TRASH_HOLD_DURATION = 1.25
local MAX_RESIDENT_RESOLVE_ATTEMPTS = 5

local function playTrashPickupFeedback(visual: Instance)
	local function fadeHighlight(model: Instance)
		local highlight = model:FindFirstChild("TrashHighlight")
		if highlight and highlight:IsA("Highlight") then
			TweenService:Create(highlight, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				FillTransparency = 1,
				OutlineTransparency = 1,
			}):Play()
		end
	end

	if visual:IsA("BasePart") then
		fadeHighlight(visual)
		local tween = TweenService:Create(visual, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
			Transparency = 1,
			Size = visual.Size * 0.6,
		})
		tween:Play()
		task.delay(0.22, function()
			visual:Destroy()
		end)
		return
	end

	if visual:IsA("Model") then
		fadeHighlight(visual)
		-- Fade all renderables and slightly shrink via pivot scale if possible
		for _, child in ipairs(visual:GetDescendants()) do
			if child:IsA("BasePart") then
				child.CanCollide = false
				TweenService:Create(child, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
				}):Play()
			elseif child:IsA("Decal") or child:IsA("Texture") then
				TweenService:Create(child, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
					Transparency = 1,
				}):Play()
			end
		end
		-- Best-effort small pop (models often have anchored parts)
		pcall(function()
			local pivot = visual:GetPivot()
			visual:PivotTo(pivot * CFrame.new(0, 0.1, 0))
		end)
		task.delay(0.22, function()
			visual:Destroy()
		end)
	end
end

local function findTenantModel(tenantName: string): Model?
	return ResidentsFolderFinder.FindResident(LocalPlayer, tenantName)
end

local function getPlotContainer(): Instance?
	if not LocalPlayer then
		return nil
	end
	local plotIndex = LocalPlayer:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end
	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end
	return plotModel:FindFirstChild("Container")
end

local function getPlacementModel(placementKey: string?): Model?
	if typeof(placementKey) ~= "string" or placementKey == "" then
		return nil
	end
	local container = getPlotContainer()
	if not container then
		return nil
	end
	local instance = container:FindFirstChild(placementKey)
	if instance and instance:IsA("Model") then
		return instance
	end
	return nil
end

local function resolveTenantPosition(tenantName: string): Vector3?
	local model = findTenantModel(tenantName)
	if not model then
		return nil
	end
	local primary = model.PrimaryPart or model:FindFirstChild("HumanoidRootPart")
	local baseCFrame: CFrame? = nil
	if primary and primary:IsA("BasePart") then
		baseCFrame = primary.CFrame
	else
		local pivot = model:GetPivot()
		if typeof(pivot) == "CFrame" then
			baseCFrame = pivot
		end
	end
	if not baseCFrame then
		return nil
	end
	local backOffset = baseCFrame.LookVector * -2
	local jitter = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	return baseCFrame.Position + backOffset + jitter
end

local function createTrashVisual(position: Vector3): Instance
	-- Try to find the TrashBag model
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local gameEffects = assets and assets:FindFirstChild("GameEffects")
	local trashBagTemplate = gameEffects and gameEffects:FindFirstChild("TrashBag")

	if trashBagTemplate then
		local model = trashBagTemplate:Clone()

		if model:IsA("Model") then
			model:PivotTo(CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
		elseif model:IsA("BasePart") then
			model.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)
			model.Anchored = true
			model.CanCollide = false
		end

		-- Add subtle highlight
		local highlight = Instance.new("Highlight")
		highlight.Name = "TrashHighlight"
		highlight.Adornee = model
		highlight.FillColor = Color3.fromRGB(255, 255, 255)
		highlight.FillTransparency = 0.95 -- Very subtle fill
		highlight.OutlineColor = Color3.fromRGB(255, 255, 255)
		highlight.OutlineTransparency = 0.8 -- Subtle outline
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = model

		return model
	end

	-- Fallback to simple part

	local defaultPart = Instance.new("Part")
	defaultPart.Size = Vector3.new(1.5, 0.5, 1.5)
	defaultPart.Anchored = true
	defaultPart.CanCollide = false
	defaultPart.CanQuery = false
	defaultPart.CanTouch = false
	defaultPart.Material = Enum.Material.SmoothPlastic
	defaultPart.Color = Color3.fromRGB(90, 90, 90)
	defaultPart.Position = position
	defaultPart.Name = "Trash"
	return defaultPart
end

local function spawnTrashForPayload(
	payload: {
		ChoreId: string,
		Type: string,
		TenantName: string,
		PlotIndex: number,
		Metadata: { [string]: any }?,
	},
	attempt: number
)
	if ActiveChores[payload.ChoreId] then
		return
	end

	local metadata = payload.Metadata
	local worldPosition: Vector3? = nil
	if metadata then
		local candidate = metadata.WorldPosition
		if typeof(candidate) == "Vector3" then
			worldPosition = candidate
		end
	end

	local position = worldPosition or resolveTenantPosition(payload.TenantName)
	if not position then
		if attempt < MAX_RESIDENT_RESOLVE_ATTEMPTS then
			task.delay(0.75, function()
				spawnTrashForPayload(payload, attempt + 1)
			end)
		else
			warn("[ChoreController] Unable to resolve tenant position for", payload.TenantName)
		end
		return
	end

	local visual = createTrashVisual(position)
	if payload.Type ~= "Trash" then
		if visual:IsA("BasePart") then
			visual.Color = Color3.fromRGB(255, 0, 0)
		elseif visual:IsA("Model") then
			for _, child in ipairs(visual:GetDescendants()) do
				if child:IsA("BasePart") then
					child.Color = Color3.fromRGB(255, 0, 0)
				end
			end
		end
	end

	visual.Parent = Workspace

	-- Add Prompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	if payload.Type == "Trash" then
		prompt.ActionText = "Pick Up"
		prompt.ObjectText = "Garbage"
		prompt.HoldDuration = TRASH_HOLD_DURATION
	else
		prompt.ActionText = "Clean Up"
		prompt.ObjectText = "Mess"
		prompt.HoldDuration = 0.5
	end
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	-- Make the default prompt smaller while keeping radial hold behavior.
	local scale = Instance.new("UIScale")
	scale.Scale = 0.78
	scale.Parent = prompt
	prompt.Parent = visual

	prompt.Triggered:Connect(function()
		if payload.Type == "Trash" then
			prompt.Enabled = false
			local success, msg = ChorePackets.CompleteChore:Fire(payload.ChoreId)
			if success then
				-- Replace old success feedback for trash with a cleaner pickup effect.
				playTrashPickupFeedback(visual)
			else
				prompt.Enabled = true
				warn("Failed to complete chore:", msg)
			end
			return
		end

		prompt.Enabled = false

		-- Optimistic visual feedback for non-trash chores
		if visual:IsA("BasePart") then
			local tween = TweenService:Create(visual, TweenInfo.new(0.2), {
				Transparency = 1,
				Size = Vector3.new(0, 0, 0),
			})
			tween:Play()
		elseif visual:IsA("Model") then
			for _, child in ipairs(visual:GetDescendants()) do
				if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
					local tween = TweenService:Create(child, TweenInfo.new(0.2), { Transparency = 1 })
					tween:Play()
				end
			end
		end

		local success, msg = ChorePackets.CompleteChore:Fire(payload.ChoreId)

		if success then
			SoundtrackManager.PlayChoreCompleted()
		end

		if not success then
			-- Revert if failed
			prompt.Enabled = true
			if visual:IsA("BasePart") then
				visual.Transparency = 0
				visual.Size = Vector3.new(1.5, 0.5, 1.5)
			elseif visual:IsA("Model") then
				for _, child in ipairs(visual:GetDescendants()) do
					if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
						local transparentChild = child :: any
						transparentChild.Transparency = 0
					end
				end
			end
			warn("Failed to complete chore:", msg)
		end
	end)

	ActiveChores[payload.ChoreId] = {
		Type = payload.Type,
		Instance = visual,
		Prompt = prompt,
		Metadata = metadata,
	}
	return visual
end

local function spawnRepairChore(
	payload: {
		ChoreId: string,
		Type: string,
		Metadata: { [string]: any }?,
	},
	attempt: number
)
	if ActiveChores[payload.ChoreId] then
		return
	end

	local metadata: { [string]: any } = payload.Metadata or {}
	local placementKeyValue = metadata.PlacementKey
	if typeof(placementKeyValue) ~= "string" or placementKeyValue == "" then
		if attempt < MAX_RESIDENT_RESOLVE_ATTEMPTS then
			task.delay(0.75, function()
				spawnRepairChore(payload, attempt + 1)
			end)
		else
			warn("[ChoreController] Missing placement key for repair chore")
		end
		return
	end

	local model = getPlacementModel(placementKeyValue)
	if not model then
		if attempt < MAX_RESIDENT_RESOLVE_ATTEMPTS then
			task.delay(0.75, function()
				spawnRepairChore(payload, attempt + 1)
			end)
		else
			warn("[ChoreController] Unable to resolve broken object for", placementKeyValue)
		end
		return
	end

	local severitySource = if typeof(metadata.Severity) == "number" then metadata.Severity else 0.5
	local severity = math.clamp(severitySource, 0.1, 1)
	local worldPosition = if typeof(metadata.WorldPosition) == "Vector3" then metadata.WorldPosition else nil
	local cleanupEffects = RepairVFX.Attach(model, {
		Severity = severity,
		WorldPosition = worldPosition,
		VisualSeed = metadata.VisualSeed,
	})

	local promptParent: BasePart? = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local anchor: Part? = nil
	if not promptParent and worldPosition then
		local anchorPart = Instance.new("Part")
		anchorPart.Anchored = true
		anchorPart.CanCollide = false
		anchorPart.CanQuery = false
		anchorPart.Transparency = 1
		anchorPart.Size = Vector3.new(0.2, 0.2, 0.2)
		anchorPart.Position = worldPosition
		anchorPart.Parent = Workspace
		promptParent = anchorPart
		anchor = anchorPart
	end

	if not promptParent then
		cleanupEffects()
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Repair"
	local itemName = if typeof(metadata.ItemName) == "string" and metadata.ItemName ~= ""
		then metadata.ItemName
		else "Broken Item"
	prompt.ObjectText = itemName
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	local holdDuration = if typeof(metadata.PromptHoldSeconds) == "number"
		then metadata.PromptHoldSeconds
		else RepairConfig.DefaultProfile.PromptHoldSeconds
	prompt.HoldDuration = holdDuration
	prompt.MaxActivationDistance = 8 + severity * 2
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Enabled = true
	prompt.Parent = promptParent

	prompt.Triggered:Connect(function()
		prompt.Enabled = false
		local success, msg = ChorePackets.CompleteChore:Fire(payload.ChoreId)
		if success then
			SoundtrackManager.PlayChoreCompleted()
			RepairVFX.PlayRepairComplete(model, worldPosition)
		else
			prompt.Enabled = true
			warn("Failed to repair:", msg)
		end
	end)

	ActiveChores[payload.ChoreId] = {
		Type = payload.Type,
		Instance = model,
		Prompt = prompt,
		Cleanup = function()
			cleanupEffects()
			if anchor then
				anchor:Destroy()
			end
		end,
		Metadata = metadata,
	}
end

local function onChoreSpawned(payload: {
	ChoreId: string,
	Type: string,
	TenantName: string,
	PlotIndex: number,
	Metadata: { [string]: any }?,
})
	if payload.Type == "Repair" then
		spawnRepairChore(payload, 1)
	else
		spawnTrashForPayload(payload, 1)
	end
end

local function onChoreRemoved(payload: { ChoreId: string, Reason: string })
	local record = ActiveChores[payload.ChoreId]
	if not record then
		return
	end

	ActiveChores[payload.ChoreId] = nil

	if record.Cleanup then
		record.Cleanup()
	end

	if record.Prompt then
		record.Prompt:Destroy()
	end

	local visual = record.Instance
	local skipAnimation = payload.Reason == "PickedUp"
	if visual and record.Type ~= "Repair" then
		if skipAnimation then
			visual:Destroy()
			return
		end

		if visual:IsA("BasePart") then
			local tween = TweenService:Create(visual, TweenInfo.new(0.3), { Transparency = 1 })
			tween:Play()
			task.delay(0.3, function()
				if visual.Parent then
					visual:Destroy()
				end
			end)
		elseif visual:IsA("Model") then
			for _, child in ipairs(visual:GetDescendants()) do
				if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
					local tween = TweenService:Create(child, TweenInfo.new(0.3), { Transparency = 1 })
					tween:Play()
				end
			end
			task.delay(0.3, function()
				if visual.Parent then
					visual:Destroy()
				end
			end)
		else
			visual:Destroy()
		end
	end
end

function ChoreController.GetNearbyChores(position: Vector3, radius: number): { { Type: string, Position: Vector3 } }
	local found = {}
	for _, entry in pairs(ActiveChores) do
		local visual = entry.Instance
		local chorePos: Vector3? = nil
		if visual then
			if visual:IsA("Model") then
				local primary = visual.PrimaryPart
				if primary then
					chorePos = primary.Position
				else
					local ok, pivot = pcall(function()
						return visual:GetPivot()
					end)
					if ok and typeof(pivot) == "CFrame" then
						chorePos = pivot.Position
					end
				end
			elseif visual:IsA("BasePart") then
				chorePos = visual.Position
			end
		end
		if not chorePos and entry.Metadata then
			local worldPosition = entry.Metadata.WorldPosition
			if typeof(worldPosition) == "Vector3" then
				chorePos = worldPosition
			end
		end
		if chorePos and (chorePos - position).Magnitude <= radius then
			table.insert(found, { Type = entry.Type or "Trash", Position = chorePos })
		end
	end
	return found
end

function ChoreController.Init()
	ChorePackets.ChoreSpawned.OnClientEvent:Connect(onChoreSpawned)
	ChorePackets.ChoreRemoved.OnClientEvent:Connect(onChoreRemoved)

	-- Legacy trash carry/deposit flow removed. We keep RunService required because other chore visuals use it.
end

return ChoreController
