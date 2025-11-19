--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local TipsPackets = require(ReplicatedStorage.Network.TipsPackets)

local TipsController = {}

local MAGNET_RADIUS = 15
local MAX_IDLE_TIME = 5
local FLY_SPEED = 40 -- studs per second

local activeTips = {}

local function createCashVisual(amount: number, position: Vector3): Part
	local part = Instance.new("Part")
	part.Name = "CashDrop"
	part.Size = Vector3.new(1, 0.2, 0.5)
	part.Color = Color3.fromRGB(85, 170, 0)
	part.Material = Enum.Material.Plastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Position = position + Vector3.new(0, 2, 0) -- Start slightly above

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.new(0, 100, 0, 50)
	billboard.StudsOffset = Vector3.new(0, 2, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = part

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "+$" .. tostring(amount)
	label.TextColor3 = Color3.fromRGB(85, 255, 85)
	label.TextStrokeTransparency = 0
	label.Font = Enum.Font.FredokaOne
	label.TextSize = 24
	label.Parent = billboard

	part.Parent = workspace.CurrentCamera

	-- Drop animation (simple tween down)
	local dropTween = TweenService:Create(part, TweenInfo.new(0.5, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out), {
		Position = position + Vector3.new(0, 0.5, 0),
	})
	dropTween:Play()

	return part
end

local function flyToPlayer(part: Part, player: Player, onComplete: () -> ())
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root then
		part:Destroy()
		onComplete()
		return
	end

	local connection
	local startTime = os.clock()

	connection = RunService.Heartbeat:Connect(function(dt)
		if not part.Parent then
			connection:Disconnect()
			return
		end

		local targetRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if not targetRoot then
			part:Destroy()
			connection:Disconnect()
			onComplete()
			return
		end

		local currentPos = part.Position
		local targetPos = targetRoot.Position
		local direction = (targetPos - currentPos)
		local distance = direction.Magnitude

		if distance < 2 then
			part:Destroy()
			connection:Disconnect()
			onComplete()
			return
		end

		local speed = FLY_SPEED + (os.clock() - startTime) * 10 -- Accelerate
		local moveDist = speed * dt

		if moveDist >= distance then
			part.Position = targetPos
		else
			part.Position = currentPos + direction.Unit * moveDist
		end
	end)
end

function TipsController.Start()
	TipsPackets.TipDropped.OnClientEvent:Connect(function(packet)
		local player = Players.LocalPlayer
		if not player then
			return
		end

		local visual = createCashVisual(packet.Amount, packet.SourcePosition)
		local spawnTime = os.clock()
		local flying = false

		local connection
		connection = RunService.Heartbeat:Connect(function()
			if not visual.Parent then
				connection:Disconnect()
				return
			end

			if flying then
				connection:Disconnect()
				return
			end

			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")

			local shouldFly = false
			if os.clock() - spawnTime > MAX_IDLE_TIME then
				shouldFly = true
			elseif root then
				local dist = (root.Position - visual.Position).Magnitude
				if dist < MAGNET_RADIUS then
					shouldFly = true
				end
			end

			if shouldFly then
				flying = true
				flyToPlayer(visual, player, function()
					-- Play sound or effect here
				end)
			end
		end)
	end)
end

return TipsController
