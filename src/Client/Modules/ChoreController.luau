--!strict
-- Client/Modules/ChoreController.luau
-- Handles visual representation and interaction for chores (messes).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ChorePackets = require(ReplicatedStorage.Network.ChorePackets)
local MinimalPromptUI = require(script.Parent.MinimalPromptUI)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
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
local MAX_RESIDENT_RESOLVE_ATTEMPTS = 5

local function getResidentsFolder(): Folder?
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
	local residentsFolder = plotModel:FindFirstChild("Residents")
	if residentsFolder and residentsFolder:IsA("Folder") then
		return residentsFolder
	end
	return nil
end

local function findTenantModel(tenantName: string): Model?
	local folder = getResidentsFolder()
	if not folder then
		return nil
	end
	local instance = folder:FindFirstChild(tenantName)
	if instance and instance:IsA("Model") then
		return instance
	end
	return nil
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

local function createTrashVisual(position: Vector3): Model | BasePart
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
	local part = Instance.new("Part")
	part.Name = "TrashMess"
	part.Size = Vector3.new(1.5, 0.5, 1.5)
	part.Position = position
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Fabric
	part.Color = Color3.fromRGB(100, 100, 100)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth

	-- Add some random rotation for variety
	part.CFrame = CFrame.new(position) * CFrame.Angles(0, math.random() * math.pi * 2, 0)

	-- Add a highlight or decal to make it look like trash
	local decal = Instance.new("Decal")
	decal.Texture = "rbxassetid://6035236356" -- Generic trash texture or similar (placeholder)
	decal.Face = Enum.NormalId.Top
	decal.Parent = part

	return part
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
	local position = metadata and metadata.WorldPosition or resolveTenantPosition(payload.TenantName)
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

	local visual: Model | BasePart
	if payload.Type == "Trash" then
		visual = createTrashVisual(position)
	else
		visual = createTrashVisual(position)
		if visual:IsA("BasePart") then
			visual.Color = Color3.fromRGB(255, 0, 0)
		else
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
	prompt.ActionText = "Clean Up"
	prompt.ObjectText = "Mess"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = visual

	MinimalPromptUI.Attach(prompt)

	prompt.Triggered:Connect(function()
		prompt.Enabled = false

		-- Optimistic visual feedback
		if visual:IsA("BasePart") then
			local tween =
				TweenService:Create(visual, TweenInfo.new(0.2), { Transparency = 1, Size = Vector3.new(0, 0, 0) })
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

		if not success then
			-- Revert if failed
			prompt.Enabled = true
			if visual:IsA("BasePart") then
				visual.Transparency = 0
				visual.Size = Vector3.new(1.5, 0.5, 1.5)
			elseif visual:IsA("Model") then
				for _, child in ipairs(visual:GetDescendants()) do
					if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
						child.Transparency = 0
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

	local metadata = payload.Metadata or {}
	local model = getPlacementModel(metadata.PlacementKey)
	if not model then
		if attempt < MAX_RESIDENT_RESOLVE_ATTEMPTS then
			task.delay(0.75, function()
				spawnRepairChore(payload, attempt + 1)
			end)
		else
			warn("[ChoreController] Unable to resolve broken object for", metadata.PlacementKey)
		end
		return
	end

	local severity = math.clamp((metadata.Severity or 0.5), 0.1, 1)
	local cleanupEffects = RepairVFX.Attach(model, {
		Severity = severity,
		WorldPosition = metadata.WorldPosition,
		VisualSeed = metadata.VisualSeed,
	})

	local promptParent: BasePart? = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart")
	local anchor: Part? = nil
	if not promptParent and metadata.WorldPosition then
		anchor = Instance.new("Part")
		anchor.Anchored = true
		anchor.CanCollide = false
		anchor.CanQuery = false
		anchor.Transparency = 1
		anchor.Size = Vector3.new(0.2, 0.2, 0.2)
		anchor.Position = metadata.WorldPosition
		anchor.Parent = Workspace
		promptParent = anchor
	end

	if not promptParent then
		cleanupEffects()
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Repair"
	prompt.ObjectText = metadata.ItemName or "Broken Item"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.HoldDuration = metadata.PromptHoldSeconds or RepairConfig.DefaultProfile.PromptHoldSeconds
	prompt.MaxActivationDistance = 8 + severity * 2
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.Parent = promptParent

	MinimalPromptUI.Attach(prompt)

	prompt.Triggered:Connect(function()
		prompt.Enabled = false
		local success, msg = ChorePackets.CompleteChore:Fire(payload.ChoreId)
		if success then
			RepairVFX.PlayRepairComplete(model, metadata.WorldPosition)
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
	if visual and record.Type ~= "Repair" then
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
end

return ChoreController
