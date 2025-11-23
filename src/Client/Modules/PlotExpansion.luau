--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotExpansion.lua

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local SoundService = game:GetService("SoundService")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local Debounce = require(ReplicatedStorage.Shared.Utilities.Debounce)
local BuildConstants = require(ReplicatedStorage.Shared.Configurations.BuildConstants)
local Formatter = require(ReplicatedStorage.Shared.Utilities.Formatter)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlayerModule = require(Player.PlayerScripts:WaitForChild("PlayerModule")) :: any
local Controls = PlayerModule:GetControls()

local InputContextsFolder = PlayerGui:WaitForChild("InputContexts")
local PlotContext = InputContextsFolder:WaitForChild("PlotContext")
local ToggleExpansionAction = PlotContext.ToggleExpansion
local ToggleClickPurchaseAction = PlotContext.ToggleClickPurchase

local AssetsFolder = ReplicatedStorage:WaitForChild("Assets")
local VisualToolsFolder = AssetsFolder.VisualTools
local ChunkHighlight = VisualToolsFolder:WaitForChild("ChunkHighlight") :: Highlight
local PriceTag = VisualToolsFolder:WaitForChild("PriceTag") :: BillboardGui
local PriceLabel = PriceTag:FindFirstChild("Label") :: TextLabel

local ActiveQueryFolder = PlayerGui:FindFirstChild("ActiveQuery")
local PlotBuilderEnabled = ActiveQueryFolder:FindFirstChild("PlotBuilderEnabled")
local PlotExpansionEnabled = ActiveQueryFolder:FindFirstChild("PlotExpansionEnabled")
local ObjectSelectorEnabled = ActiveQueryFolder:FindFirstChild("ObjectSelectorEnabled")

local camera = Workspace.CurrentCamera :: Camera

local PlotExpansion = {}
local INPUT_DEBOUNCE_SECONDS = 1.6 -- Increased to match tween duration + buffer

local _originalCameraCFrame: CFrame? = nil
local _originalCameraType: Enum.CameraType? = nil
local _visualEffects: { Instance } = {}

local function runDebounced(actionName: string, callback: () -> ()): ()
	local key = string.format("PlotExpansion/%s", actionName)
	Debounce.RunIfAvailable(key, INPUT_DEBOUNCE_SECONDS, callback, Player.UserId)
end

local Connection: RBXScriptConnection? = nil
local _HoveredCover: BasePart? = nil

local function ClearEffects()
	_HoveredCover = nil
	ChunkHighlight.Adornee = nil
	PriceTag.Adornee = VisualToolsFolder
end

local function BuildParams(coversFolder: Folder): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { coversFolder }
	params.RespectCanCollide = false
	params.IgnoreWater = true
	return params
end

local function PlaySuccessSound()
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://127613720380706"
	sound.Volume = 1
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function PlayCelebrationEffect(targetPart: BasePart)
	local attachment = Instance.new("Attachment")
	attachment.Position = Vector3.new(0, 2, 0)
	attachment.Parent = targetPart

	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxassetid://1266170131" -- Sparkle texture
	emitter.Rate = 0
	emitter.Speed = NumberRange.new(15, 25)
	emitter.Lifetime = NumberRange.new(1, 2)
	emitter.SpreadAngle = Vector2.new(360, 360)
	emitter.Acceleration = Vector3.new(0, -15, 0)
	emitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 100)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(100, 255, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	})
	emitter.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(0.5, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	emitter.Parent = attachment

	emitter:Emit(80)

	task.delay(3, function()
		attachment:Destroy()
	end)
end

local function UpdateCoverVisual(cover: BasePart, isUnlocked: boolean)
	local selectionBox = cover:FindFirstChild("ExpansionVisual") :: SelectionBox
	if not selectionBox then
		return
	end

	if isUnlocked then
		-- Unlocked: Greenish tint, low opacity
		selectionBox.Color3 = Color3.fromRGB(100, 255, 100)
		selectionBox.SurfaceColor3 = Color3.fromRGB(100, 255, 100)

		TweenService:Create(selectionBox, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.5,
			SurfaceTransparency = 0.95,
		}):Play()
	else
		-- Locked: White/Grey tint
		selectionBox.Color3 = Color3.fromRGB(255, 255, 255)
		selectionBox.SurfaceColor3 = Color3.fromRGB(80, 200, 255)

		TweenService:Create(selectionBox, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 0.2,
			SurfaceTransparency = 0.9,
		}):Play()
	end
end

local function getExpansionCost(): number
	local snapshot = PlotStateStore.GetStateSnapshot()
	if not snapshot or not snapshot.ChunkUnlocked then
		return BuildConstants.ExpansionBaseCost or 400
	end

	local unlockedCount = 0
	for _, unlocked in pairs(snapshot.ChunkUnlocked) do
		if unlocked then
			unlockedCount += 1
		end
	end

	local baseCost = BuildConstants.ExpansionBaseCost or 400
	local increment = BuildConstants.ExpansionCostIncrement or 200
	return baseCost + math.max(0, unlockedCount - 1) * increment
end

function PlotExpansion.Init()
	PlotBuilderEnabled.Changed:Connect(function()
		if PlotBuilderEnabled.Value and PlotExpansionEnabled.Value then
			PlotExpansion.Hide()
		end
	end)

	ObjectSelectorEnabled.Changed:Connect(function()
		if ObjectSelectorEnabled.Value and PlotExpansionEnabled.Value then
			PlotExpansion.Hide()
		end
	end)

	ToggleExpansionAction.Pressed:Connect(function()
		runDebounced("Toggle", function()
			local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
			if not plotIndex then
				warn("Player does not own a plot.")
				return
			end

			if PlotFinder.IsWithinBounds(Player) then
				if PlotExpansionEnabled.Value then
					PlotExpansion.Hide()
				else
					PlotExpansion.Show()
				end
			end
		end)
	end)

	ToggleClickPurchaseAction.Pressed:Connect(function()
		runDebounced("Purchase", function()
			print("ToggleClickPurchase pressed")
			local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
			local plotModel = PlotFinder.FindPlot(plotIndex)
			local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder

			local params = BuildParams(coversFolder)
			local mouse = UserInputService:GetMouseLocation()
			local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
			local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

			if not result or not result.Instance or not result.Instance:IsA("BasePart") then
				return
			end

			local hitCover = result.Instance
			if hitCover == _HoveredCover then
				local chunkX = hitCover:GetAttribute("ChunkX") :: number
				local chunkZ = hitCover:GetAttribute("ChunkZ") :: number
				local success, message = PlotStateStore.RequestPurchase(chunkX, chunkZ)
				if success then
					PlaySuccessSound()
					PlayCelebrationEffect(hitCover)
					UpdateCoverVisual(hitCover, true)
					print("Toast notification UI implementation needed")
				end
				--#TODO: Toast notification for success/failure
				print("Purchase result:", success, message)
			end
		end)
	end)

	Player:GetAttributeChangedSignal("WithinPlot"):Connect(function()
		local IsWithinBounds = Player:GetAttribute("WithinPlot")
		if not IsWithinBounds then
			PlotExpansion.Hide()
		end
	end)
end

function PlotExpansion.Show()
	PlotExpansionEnabled.Value = true
	ToggleClickPurchaseAction.Enabled = true
	local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)
	local coversFolder = plotModel and plotModel:FindFirstChild("Covers") :: Folder
	local container = plotModel and plotModel:FindFirstChild("Container") :: Folder
	PriceTag.Enabled = true
	PriceTag.Parent = container

	-- Disable controls
	Controls:Disable()

	-- Camera Tween
	_originalCameraCFrame = camera.CFrame
	_originalCameraType = camera.CameraType
	camera.CameraType = Enum.CameraType.Scriptable

	local targetCFrame: CFrame? = nil
	local tweenStartTime = os.clock()

	if plotModel then
		local cf, size = plotModel:GetBoundingBox()
		local height = math.max(size.X, size.Z) * 0.48
		local targetPos = cf.Position + Vector3.new(-4, height, 0)

		-- Determine orientation based on Spawn part
		local spawnPart = plotModel:FindFirstChild("Spawn")
		local upVector = Vector3.new(0, 0, -1) -- Default North

		if spawnPart and spawnPart:IsA("BasePart") then
			local dir = (cf.Position - spawnPart.Position) * Vector3.new(1, 0, 1)
			if dir.Magnitude > 0.1 then
				upVector = dir.Unit
			end
		end

		-- Build base camera CFrame
		local baseCFrame = CFrame.lookAt(targetPos, cf.Position, upVector)

		-- Shift camera position upward in screen space (local Y-axis)
		local screenOffsetY = 8 -- Adjust this value to move camera up/down in 2D view
		targetCFrame = baseCFrame * CFrame.new(0, screenOffsetY, 0)

		if targetCFrame then
			local tween = TweenService:Create(
				camera,
				TweenInfo.new(1.5, Enum.EasingStyle.Exponential, Enum.EasingDirection.Out),
				{ CFrame = targetCFrame }
			)
			tween:Play()
		end

		-- Highlight all chunks (Reverted neon effect)
		if coversFolder then
			for _, cover in ipairs(coversFolder:GetChildren()) do
				if cover:IsA("BasePart") then
					local chunkX = cover:GetAttribute("ChunkX") :: number
					local chunkZ = cover:GetAttribute("ChunkZ") :: number
					local isUnlocked = PlotStateStore.IsChunkUnlocked(chunkX, chunkZ)

					local selectionBox = Instance.new("SelectionBox")
					selectionBox.Name = "ExpansionVisual"
					selectionBox.Adornee = cover
					selectionBox.LineThickness = 0.05
					selectionBox.Parent = cover

					if isUnlocked then
						-- Unlocked: Greenish tint, low opacity
						selectionBox.Color3 = Color3.fromRGB(100, 255, 100)
						selectionBox.SurfaceColor3 = Color3.fromRGB(100, 255, 100)
						selectionBox.Transparency = 1 -- Start invisible
						selectionBox.SurfaceTransparency = 1 -- Start invisible

						table.insert(_visualEffects, selectionBox)

						TweenService
							:Create(selectionBox, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								Transparency = 0.5,
								SurfaceTransparency = 0.95,
							})
							:Play()
					else
						-- Locked: White/Grey tint
						selectionBox.Color3 = Color3.fromRGB(255, 255, 255)
						selectionBox.SurfaceColor3 = Color3.fromRGB(80, 200, 255)
						selectionBox.Transparency = 1 -- Start invisible
						selectionBox.SurfaceTransparency = 1 -- Start invisible

						table.insert(_visualEffects, selectionBox)

						TweenService
							:Create(selectionBox, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
								Transparency = 0.2,
								SurfaceTransparency = 0.9,
							})
							:Play()
					end
				end
			end
		end
	end

	local params = BuildParams(coversFolder)
	PlotFinder.StartTracking(Player)

	Connection = RunService.PreRender:Connect(function(_deltaTime)
		-- Enforce Camera State
		if PlotExpansionEnabled.Value and targetCFrame then
			camera.CameraType = Enum.CameraType.Scriptable
			if os.clock() - tweenStartTime > 1.5 then
				camera.CFrame = targetCFrame
			end
		end

		local mouse = UserInputService:GetMouseLocation()
		local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
		local result = Workspace:Raycast(ray.Origin, ray.Direction * 1000, params)

		if not result or not result.Instance or not result.Instance:IsA("BasePart") then
			ClearEffects()
			return
		end

		local hitCover = result.Instance
		local chunkX = hitCover:GetAttribute("ChunkX") :: number
		local chunkZ = hitCover:GetAttribute("ChunkZ") :: number

		if hitCover == _HoveredCover then
			return
		end

		local success, message = PlotStateStore.CanPurchaseChunk(chunkX, chunkZ)

		-- Hover Effect
		if _HoveredCover ~= hitCover then
			_HoveredCover = hitCover
			ChunkHighlight.Adornee = hitCover
			PriceTag.Adornee = hitCover

			-- Reset highlight properties for tween
			ChunkHighlight.OutlineTransparency = 1
			ChunkHighlight.FillTransparency = 1

			local targetColor = if success then Color3.fromRGB(0, 255, 0) else Color3.fromRGB(255, 0, 0)
			local targetOutline = if success then Color3.fromRGB(0, 255, 0) else Color3.fromRGB(255, 0, 0)

			ChunkHighlight.FillColor = targetColor
			ChunkHighlight.OutlineColor = targetOutline

			-- Tween glow effect
			TweenService:Create(ChunkHighlight, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				OutlineTransparency = 0,
				FillTransparency = 0.5,
			}):Play()
		end

		local cost = getExpansionCost()
		local formattedCost = Formatter.formatNumber(cost)
		PriceLabel.Text = if not success then message else "$" .. formattedCost
	end)
end

function PlotExpansion.Hide()
	PlotExpansionEnabled.Value = false
	ToggleClickPurchaseAction.Enabled = false
	PriceTag.Parent = VisualToolsFolder
	PriceTag.Enabled = false
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end

	ClearEffects()

	-- Cleanup visual effects
	for _, effect in ipairs(_visualEffects) do
		effect:Destroy()
	end
	table.clear(_visualEffects)

	-- Enable controls
	Controls:Enable()

	-- Restore Camera
	if _originalCameraCFrame then
		local restoreCFrame = _originalCameraCFrame
		local restoreType = _originalCameraType

		_originalCameraCFrame = nil
		_originalCameraType = nil

		local tween = TweenService:Create(
			camera,
			TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = restoreCFrame }
		)
		tween:Play()
		tween.Completed:Connect(function()
			if not PlotExpansionEnabled.Value then
				camera.CameraType = restoreType or Enum.CameraType.Custom
			end
		end)
	end

	-- Leave cover transparency untouched; server-side unlock flow drives visibility
end

return PlotExpansion
