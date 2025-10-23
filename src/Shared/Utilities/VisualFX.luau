-- VisualFX.lua
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local VisualFX = {}

function VisualFX.Fade(uiElement, targetTransparency, duration)
	local start = uiElement.BackgroundTransparency
	local time = 0

	local conn
	conn = RunService.PreRender:Connect(function(dt)
		time += dt
		local alpha = math.clamp(time / duration, 0, 1)
		uiElement.BackgroundTransparency = start + (targetTransparency - start) * alpha

		if alpha >= 1 then
			uiElement.BackgroundTransparency = targetTransparency
			conn:Disconnect()
		end
	end)
end

function VisualFX.Pulse(uiElement, multiplier, duration, onComplete)
	local scale = uiElement:FindFirstChildWhichIsA("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "UIScale"
		scale.Scale = 1
		scale.Parent = uiElement
	end

	local original = scale.Scale
	local target = original * multiplier

	local out =
		TweenService:Create(scale, TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Scale = target,
		})

	local inside =
		TweenService:Create(scale, TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Scale = original,
		})

	local conn1, conn2
	conn1 = out.Completed:Connect(function()
		conn1:Disconnect()
		inside:Play()
		conn2 = inside.Completed:Connect(function()
			conn2:Disconnect()
			if typeof(onComplete) == "function" then
				onComplete()
			end
		end)
	end)

	out:Play()
end

function VisualFX.TweenSize(uiElement, tweenInfo, targetSize)
	local tween = TweenService:Create(
		uiElement,
		tweenInfo or TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = targetSize }
	)
	tween:Play()
	return tween
end

function VisualFX.Shake(uiElement, intensity, duration, frequency)
	local start = uiElement.Position
	local time = 0
	local interval = 1 / frequency
	local step = 0

	local conn
	conn = RunService.PreRender:Connect(function(dt)
		time += dt
		step += dt

		if time >= duration then
			uiElement.Position = start
			conn:Disconnect()
			return
		end

		if step >= interval then
			step -= interval
			local dx = math.random(-intensity, intensity)
			local dy = math.random(-intensity, intensity)
			uiElement.Position = start + UDim2.fromOffset(dx, dy)
		end
	end)
end

function VisualFX.SlideIn(uiElement, direction, duration)
	local origin = uiElement:GetAttribute("__OriginalPosition")
	if not origin then
		origin = uiElement.Position
		uiElement:SetAttribute("__OriginalPosition", origin)
	end

	local size = uiElement.Size
	local offset

	if direction == "Left" then
		offset = UDim2.new(-1, -size.X.Offset, 0, 0)
	elseif direction == "Right" then
		offset = UDim2.new(1, size.X.Offset, 0, 0)
	elseif direction == "Top" then
		offset = UDim2.new(0, 0, -1, -size.Y.Offset)
	elseif direction == "Bottom" then
		offset = UDim2.new(0, 0, 1, size.Y.Offset)
	end

	uiElement.Position = origin + offset

	local tween =
		TweenService:Create(uiElement, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = origin,
		})

	tween:Play()
end

function VisualFX.SlideOut(uiElement, direction, duration, callback)
	local start = uiElement.Position
	local size = uiElement.Size
	local offset

	if direction == "Left" then
		offset = UDim2.new(-1, -size.X.Offset, 0, 0)
	elseif direction == "Right" then
		offset = UDim2.new(1, size.X.Offset, 0, 0)
	elseif direction == "Top" then
		offset = UDim2.new(0, 0, -1, -size.Y.Offset)
	elseif direction == "Bottom" then
		offset = UDim2.new(0, 0, 1, size.Y.Offset)
	end

	local target = start + offset

	local tween =
		TweenService:Create(uiElement, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = target,
		})

	local conn
	conn = tween.Completed:Connect(function()
		if callback then
			callback()
		end
		conn:Disconnect()
	end)

	tween:Play()
end

function VisualFX.Flash(uiElement, targetTransparency, duration)
	local original = uiElement.BackgroundTransparency

	local out =
		TweenService:Create(uiElement, TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = targetTransparency,
		})

	local back =
		TweenService:Create(uiElement, TweenInfo.new(duration / 2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			BackgroundTransparency = original,
		})

	local conn
	conn = out.Completed:Connect(function()
		back:Play()
		conn:Disconnect()
	end)

	out:Play()
end

function VisualFX.Typewriter(label, fullText, duration)
	local total = #fullText
	local interval = duration / total
	local elapsed = 0
	local index = 0

	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		while elapsed >= interval and index < total do
			elapsed -= interval
			index += 1
			label.Text = string.sub(fullText, 1, index)
			if index == total then
				conn:Disconnect()
			end
		end
	end)
end

function VisualFX.BounceIn(uiElement, duration)
	local scale = Instance.new("UIScale")
	scale.Scale = 0
	scale.Parent = uiElement

	local tween =
		TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), {
			Scale = 1,
		})

	tween:Play()
end

function VisualFX.ScaleTo(uiElement, targetScale, duration)
	local scale = uiElement:FindFirstChildWhichIsA("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "UIScale"
		scale.Scale = 1
		scale.Parent = uiElement
	end

	local tween =
		TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), {
			Scale = targetScale,
		})

	tween:Play()
end

function VisualFX.Wiggle(uiElement, intensity, duration, frequency)
	local original = uiElement.Rotation
	local elapsed = 0

	local conn
	conn = RunService.PreRender:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration then
			uiElement.Rotation = original
			conn:Disconnect()
			return
		end

		local t = math.sin(elapsed * frequency * math.pi * 2)
		uiElement.Rotation = original + t * intensity
	end)
end

function VisualFX.GlowPulse(uiElement, min, max, duration)
	local stroke = uiElement:FindFirstChildWhichIsA("UIStroke")
	if not stroke then
		stroke = Instance.new("UIStroke")
		stroke.Thickness = min
		stroke.Transparency = 0
		stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		stroke.Parent = uiElement
	end

	local out =
		TweenService:Create(stroke, TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Thickness = max,
		})

	local back =
		TweenService:Create(stroke, TweenInfo.new(duration / 2, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Thickness = min,
		})

	local conn
	conn = out.Completed:Connect(function()
		back:Play()
		conn:Disconnect()
	end)

	out:Play()
end

function VisualFX.Collapse(uiElement, duration)
	local scale = uiElement:FindFirstChildWhichIsA("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 1
		scale.Parent = uiElement
	end

	local tween = TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		Scale = 0,
	})

	tween:Play()
end

function VisualFX.Expand(uiElement, duration)
	local scale = uiElement:FindFirstChildWhichIsA("UIScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = uiElement
	end

	local tween = TweenService:Create(scale, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Scale = 1,
	})

	tween:Play()
end

function VisualFX.ColorSweep(uiElement, fromColor, toColor, duration)
	uiElement.BackgroundColor3 = fromColor

	local tween =
		TweenService:Create(uiElement, TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			BackgroundColor3 = toColor,
		})

	tween:Play()
end

function VisualFX.TextWave(container, text, duration, amplitude, frequency)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextLabel") and child:GetAttribute("WaveChar") == true then
			child:Destroy()
		end
	end

	local fontSize = 18
	local spacing = fontSize * 0.6
	local total = #text
	local baseX = (container.AbsoluteSize.X - total * spacing) * 0.5

	local chars = {}
	local positions = {}

	for i = 1, total do
		local c = string.sub(text, i, i)
		local x = baseX + (i - 1) * spacing

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, fontSize, 1, 0)
		label.Position = UDim2.new(0, x, 0.5, 0)
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.BackgroundTransparency = 1
		label.Text = c
		label.TextSize = fontSize
		label.Font = Enum.Font.SourceSans
		label.TextColor3 = Color3.new(1, 1, 1)
		label:SetAttribute("WaveChar", true)
		label.Parent = container

		chars[i] = label
		positions[i] = x
	end

	local elapsed = 0
	local conn
	conn = RunService.PreRender:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration then
			conn:Disconnect()
			return
		end

		local wave = elapsed * frequency * math.pi * 2
		for i = 1, total do
			local y = math.sin(wave + i * 0.3) * amplitude
			chars[i].Position = UDim2.new(0, positions[i], 0.5, y)
		end
	end)
end

function VisualFX.TextColorWave(container, text, duration, baseColor, waveColor, frequency)
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextLabel") and child:GetAttribute("WaveChar") == true then
			child:Destroy()
		end
	end

	local fontSize = 18
	local spacing = fontSize * 0.6
	local total = #text
	local baseX = (container.AbsoluteSize.X - total * spacing) * 0.5

	local chars = {}

	for i = 1, total do
		local c = string.sub(text, i, i)
		local x = baseX + (i - 1) * spacing

		local label = Instance.new("TextLabel")
		label.Size = UDim2.new(0, fontSize, 1, 0)
		label.Position = UDim2.new(0, x, 0.5, 0)
		label.AnchorPoint = Vector2.new(0, 0.5)
		label.BackgroundTransparency = 1
		label.Text = c
		label.TextSize = fontSize
		label.Font = Enum.Font.SourceSans
		label.TextColor3 = baseColor
		label:SetAttribute("WaveChar", true)
		label.Parent = container

		chars[i] = label
	end

	local elapsed = 0
	local conn
	conn = RunService.PreRender:Connect(function(dt)
		elapsed += dt
		if elapsed >= duration then
			conn:Disconnect()
			return
		end

		local wave = elapsed * frequency * math.pi * 2
		for i = 1, total do
			local t = (math.sin(wave + i * 0.3) + 1) * 0.5
			local r = baseColor.R + (waveColor.R - baseColor.R) * t
			local g = baseColor.G + (waveColor.G - baseColor.G) * t
			local b = baseColor.B + (waveColor.B - baseColor.B) * t
			chars[i].TextColor3 = Color3.new(r, g, b)
		end
	end)
end

function VisualFX.Swing(uiElement, distance, duration)
	distance = distance or 6
	duration = duration or 0.18

	local origin = uiElement.Position
	local left = origin + UDim2.fromOffset(-distance, 0)
	local right = origin + UDim2.fromOffset(distance, 0)

	local tweenL =
		TweenService:Create(uiElement, TweenInfo.new(duration / 3, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
			Position = left,
		})

	local tweenR =
		TweenService:Create(uiElement, TweenInfo.new(duration / 3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), {
			Position = right,
		})

	local tweenBack =
		TweenService:Create(uiElement, TweenInfo.new(duration / 3, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
			Position = origin,
		})

	local conn1, conn2
	conn1 = tweenL.Completed:Connect(function()
		conn1:Disconnect()
		tweenR:Play()

		conn2 = tweenR.Completed:Connect(function()
			conn2:Disconnect()
			tweenBack:Play()
		end)
	end)

	tweenL:Play()
end

return VisualFX
