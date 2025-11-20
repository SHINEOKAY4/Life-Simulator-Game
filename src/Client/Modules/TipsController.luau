--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local TipsPackets = require(ReplicatedStorage.Network.TipsPackets)
local SoundtrackManager = require(script.Parent.SoundtrackManager)

local TipsController = {}

local MAGNET_RADIUS = 8 -- Almost touching
local MAX_IDLE_TIME = 30 -- Give plenty of time before auto-collect
local FLY_SPEED = 40 -- studs per second

local function createCashVisual(amount: number, position: Vector3, reason: string): (Part, Trail)
	local part = Instance.new("Part")
	part.Name = "CashDrop"
	part.Size = Vector3.new(1.2, 0.1, 0.6) -- Thinner, bill-shaped
	part.Color = Color3.fromRGB(85, 170, 0)
	part.Material = Enum.Material.Plastic
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.Position = position
	part.Transparency = 0

	-- Add a subtle glow/highlight
	local highlight = Instance.new("Highlight")
	highlight.FillTransparency = 1
	highlight.OutlineTransparency = 0.5
	highlight.OutlineColor = Color3.fromRGB(150, 255, 150)
	highlight.Parent = part

	local billboard = Instance.new("BillboardGui")
	billboard.Size = UDim2.fromOffset(100, 50)
	billboard.StudsOffset = Vector3.new(0, 1.5, 0)
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

	if reason and reason ~= "Tip" then
		local reasonLabel = Instance.new("TextLabel")
		reasonLabel.Size = UDim2.fromScale(1, 0.5)
		reasonLabel.Position = UDim2.fromScale(0, 1)
		reasonLabel.BackgroundTransparency = 1
		reasonLabel.Text = reason
		reasonLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
		reasonLabel.TextStrokeTransparency = 0.5
		reasonLabel.Font = Enum.Font.FredokaOne
		reasonLabel.TextSize = 14
		reasonLabel.Parent = billboard
	end

	-- Trail for flying effect later
	local attachment0 = Instance.new("Attachment")
	attachment0.Position = Vector3.new(0, 0, 0.3)
	attachment0.Parent = part

	local attachment1 = Instance.new("Attachment")
	attachment1.Position = Vector3.new(0, 0, -0.3)
	attachment1.Parent = part

	local trail = Instance.new("Trail")
	trail.Attachment0 = attachment0
	trail.Attachment1 = attachment1
	trail.Lifetime = 0.3
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Color = ColorSequence.new(Color3.fromRGB(85, 255, 85))
	trail.Enabled = false -- Enable when flying
	trail.Parent = part

	part.Parent = workspace.CurrentCamera

	-- Raycast to find ground
	local rayOrigin = position + Vector3.new(0, 5, 0)
	local rayDirection = Vector3.new(0, -50, 0)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterDescendantsInstances = { part, Players.LocalPlayer.Character }
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude

	local rayResult = Workspace:Raycast(rayOrigin, rayDirection, raycastParams)
	local groundY = position.Y
	if rayResult then
		groundY = rayResult.Position.Y + 0.1 -- Slightly above ground
	end

	-- Pop up and drop animation
	local randomOffset = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5) * 2
	local targetPos = Vector3.new(position.X, groundY, position.Z) + randomOffset

	-- Quadratic Bezier for arc
	local t = 0
	local duration = 0.6
	local startPos = position
	local controlPos = (startPos + targetPos) / 2 + Vector3.new(0, 4, 0) -- Control point high up

	local dropConnection
	local startTime = os.clock()

	dropConnection = RunService.Heartbeat:Connect(function()
		if not part.Parent then
			if dropConnection then
				dropConnection:Disconnect()
			end
			return
		end

		local elapsed = os.clock() - startTime
		t = math.clamp(elapsed / duration, 0, 1)

		-- Bezier formula: (1-t)^2 * P0 + 2(1-t)t * P1 + t^2 * P2
		local p0 = startPos
		local p1 = controlPos
		local p2 = targetPos

		local pos = (1 - t) ^ 2 * p0 + 2 * (1 - t) * t * p1 + t ^ 2 * p2
		part.Position = pos

		-- Spin while dropping
		part.CFrame = CFrame.new(pos) * CFrame.Angles(0, elapsed * 5, 0) * CFrame.Angles(math.sin(elapsed * 10), 0, 0)

		if t >= 1 then
			dropConnection:Disconnect()
			-- Landed
			part.Position = targetPos
			part.CFrame = CFrame.new(targetPos) * CFrame.Angles(0, math.random() * 6.28, 0)
		end
	end)

	return part, trail
end

local function flyToPlayer(part: Part, trail: Trail, player: Player, onComplete: () -> ())
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")

	if not root then
		part:Destroy()
		onComplete()
		return
	end

	trail.Enabled = true

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
		local targetPos = (targetRoot :: BasePart).Position
		local direction = (targetPos - currentPos)
		local distance = direction.Magnitude

		if distance < 2 then
			part:Destroy()
			connection:Disconnect()
			onComplete()
			return
		end

		local speed = FLY_SPEED + (os.clock() - startTime) * 20 -- Accelerate faster
		local moveDist = speed * dt

		if moveDist >= distance then
			part.Position = targetPos
		else
			part.Position = currentPos + direction.Unit * moveDist
		end

		-- Spin fast while flying
		part.CFrame = CFrame.new(part.Position) * CFrame.Angles(0, (os.clock() * 15) % 6.28, 0)
	end)
end

function TipsController.Start()
	TipsPackets.TipDropped.OnClientEvent:Connect(function(packet)
		local player = Players.LocalPlayer
		if not player then
			return
		end

		local visual, trail = createCashVisual(packet.Amount, packet.SourcePosition, packet.Reason)
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

			if os.clock() - spawnTime > MAX_IDLE_TIME then
				connection:Disconnect()
				-- Fade out and destroy
				local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
				local tween = TweenService:Create(visual, tweenInfo, { Transparency = 1 })
				tween:Play()
				local billboard = visual:FindFirstChildOfClass("BillboardGui")
				if billboard then
					local label = billboard:FindFirstChildOfClass("TextLabel")
					if label then
						TweenService:Create(label, tweenInfo, { TextTransparency = 1, TextStrokeTransparency = 1 })
							:Play()
					end
				end
				task.delay(0.5, function()
					visual:Destroy()
				end)
				return
			end

			local shouldFly = false
			if root then
				local dist = (root.Position - visual.Position).Magnitude
				if dist < MAGNET_RADIUS then
					shouldFly = true
				end
			end

			if shouldFly then
				flying = true
				flyToPlayer(visual, trail, player, function()
					SoundtrackManager.PlayBillPaid()
					TipsPackets.ClaimTip:Fire({ TipId = packet.TipId })
					-- Optional: Add particle burst here if desired
				end)
			end
		end)
	end)
end

return TipsController
