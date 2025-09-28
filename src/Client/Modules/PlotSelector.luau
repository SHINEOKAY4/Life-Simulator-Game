--!strict
-- StarterPlayer/StarterPlayerScripts/Client/Modules/PlotSelector.luau

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local PlotSelectorGui = PlayerGui:WaitForChild("PlotSelectorGui")
local MainFrame = PlotSelectorGui:WaitForChild("Main")
local PlotSelectorContext = PlotSelectorGui:WaitForChild("PlotSelectorContext")

local Camera = workspace.CurrentCamera

local PlotSelector = {}
local Connections: { RBXScriptConnection } = {}
local ActiveCameraTween: Tween? = nil
local CurrentIndex = 1

local function MoveCamera()
	local currentPlot = PlotFinder.FindPlot(CurrentIndex)
	local cameraPosition = currentPlot:WaitForChild("CameraPosition") :: Part
	local cameraFocus = currentPlot:WaitForChild("CameraFocus") :: Part

	Camera.CameraType = Enum.CameraType.Scriptable
	Camera.CameraSubject = cameraPosition

	local studsPerSecond = 20 -- Adjust for camera speed
	local distance = (cameraPosition.Position - Camera.CFrame.Position).Magnitude
	local duration = math.clamp(distance / studsPerSecond, 0.2, 2.0) -- Tween duration is based on distance to ensure consistent speed

	local targetCFrame = CFrame.lookAt(cameraPosition.Position, cameraFocus.Position)

	if ActiveCameraTween then
		ActiveCameraTween:Cancel()
		ActiveCameraTween = nil
	end

	local tweenInfo = TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	local tween = TweenService:Create(Camera, tweenInfo, { CFrame = targetCFrame })

	ActiveCameraTween = tween

	tween:Play()

	tween.Completed:Once(function()
		if ActiveCameraTween == tween then
			ActiveCameraTween = nil
		end
	end)
end

local function SetPlayerMovement(enabled: boolean)
	local character = Player.Character
	if not character then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end

	if enabled then
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
	else
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
	end
end

function PlotSelector.Init()
	SetPlayerMovement(false)
	MoveCamera()
	MainFrame.Visible = true
	--#TODO: Throttle or debounce input to prevent multiple rapid inputs
	table.insert(
		Connections,
		PlotSelectorContext.MoveNextAction.Pressed:Connect(function()
			PlotSelector.Next()
		end)
	)

	table.insert(
		Connections,
		PlotSelectorContext.MovePreviousAction.Pressed:Connect(function()
			PlotSelector.Previous()
		end)
	)

	table.insert(
		Connections,
		PlotSelectorContext.SelectAction.Pressed:Connect(function()
			PlotSelector.Select()
		end)
	)
end

function PlotSelector.Next()
	CurrentIndex = CurrentIndex + 1

	if CurrentIndex > PlotFinder.GetTotalPlots() then
		CurrentIndex = 1
	end
	MoveCamera()
end

function PlotSelector.Previous()
	CurrentIndex = CurrentIndex - 1
	if CurrentIndex < 1 then
		CurrentIndex = PlotFinder.GetTotalPlots()
	end
	MoveCamera()
end

function PlotSelector.Select()
	local currentPlot = PlotFinder.FindPlot(CurrentIndex)

	local success, message = Packets.ClaimRequest:Fire(CurrentIndex)

	if not success then
		--#TODO: Toast notification for failure
		warn("Failed to claim plot: " .. message)
		return
	end

	local character = Player.Character or Player.CharacterAdded:Wait()
	local spawnLocation = currentPlot:WaitForChild("Spawn") :: Part

	Camera.CameraType = Enum.CameraType.Custom
	Camera.CameraSubject = character:WaitForChild("Humanoid")
	MainFrame.Visible = false
	PlotSelectorContext.Enabled = false

	character:PivotTo(spawnLocation.CFrame)

	for _, connection in ipairs(Connections) do
		connection:Disconnect()
	end

	SetPlayerMovement(true)
	--#TODO: Toast notification for success
	print("Successfully claimed plot: " .. message)
end

return PlotSelector
