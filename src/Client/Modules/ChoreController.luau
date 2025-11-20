--!strict
-- Client/Modules/ChoreController.luau
-- Handles visual representation and interaction for chores (messes).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ChorePackets = require(ReplicatedStorage.Network.ChorePackets)
local MinimalPromptUI = require(script.Parent.MinimalPromptUI)

local ChoreController = {}

local ActiveChores: { [string]: Model | Part } = {}
local LocalPlayer = Players.LocalPlayer

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

local function onChoreSpawned(payload: {
	ChoreId: string,
	Type: string,
	Position: Vector3,
	PlotIndex: number,
	TargetId: string,
})
	if ActiveChores[payload.ChoreId] then
		return
	end

	local visual: Model | BasePart

	if payload.Type == "Trash" then
		visual = createTrashVisual(payload.Position)
	else
		-- Fallback
		visual = createTrashVisual(payload.Position)
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

	visual.Parent = workspace

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

	ActiveChores[payload.ChoreId] = visual
end

local function onChoreRemoved(payload: { ChoreId: string, Reason: string })
	local visual = ActiveChores[payload.ChoreId]
	if visual then
		if visual:IsA("BasePart") then
			-- Fade out effect
			local tween = TweenService:Create(visual, TweenInfo.new(0.3), { Transparency = 1 })
			tween:Play()
			task.delay(0.3, function()
				visual:Destroy()
			end)
		elseif visual:IsA("Model") then
			for _, child in ipairs(visual:GetDescendants()) do
				if child:IsA("BasePart") or child:IsA("Decal") or child:IsA("Texture") then
					local tween = TweenService:Create(child, TweenInfo.new(0.3), { Transparency = 1 })
					tween:Play()
				end
			end
			task.delay(0.3, function()
				visual:Destroy()
			end)
		else
			visual:Destroy()
		end
		ActiveChores[payload.ChoreId] = nil
	end
end

function ChoreController.Init()
	ChorePackets.ChoreSpawned.OnClientEvent:Connect(onChoreSpawned)
	ChorePackets.ChoreRemoved.OnClientEvent:Connect(onChoreRemoved)
end

return ChoreController
