--!strict
-- StarterPlayerScripts/Client/Modules/PowerSwitchController.lua

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local PowerSwitchController = {}

local function updatePrompt(model: Model, key: string)
	local prompt = model:FindFirstChild("PowerSwitchPrompt") :: ProximityPrompt
	if not prompt then
		return
	end

	local entry = PlotStateStore.GetPlacementEntry(key)
	if not entry then
		return
	end

	local metadata = entry.Metadata or {}
	local isPowered = metadata.IsPowered == true
	local isOn = true
	if metadata.IsOn ~= nil then
		isOn = metadata.IsOn
	end

	if not isPowered then
		prompt.ActionText = "No Power"
		-- We keep it enabled so the user sees the "No Power" status,
		-- but we'll block the interaction in the Triggered handler.
		prompt.Enabled = true
	elseif isOn then
		prompt.ActionText = "Turn Off"
		prompt.Enabled = true
	else
		prompt.ActionText = "Turn On"
		prompt.Enabled = true
	end
end

local function setupPrompt(model: Model, key: string)
	if model:FindFirstChild("PowerSwitchPrompt") then
		return
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "PowerSwitchPrompt"
	prompt.ActionText = "Turn Off"
	prompt.ObjectText = "Power Switch"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = model

	prompt.Triggered:Connect(function()
		local entry = PlotStateStore.GetPlacementEntry(key)
		if not entry then
			return
		end

		local metadata = entry.Metadata or {}

		-- Prevent toggling if there is no power
		if metadata.IsPowered ~= true then
			return
		end

		local currentIsOn = true
		if metadata.IsOn ~= nil then
			currentIsOn = metadata.IsOn
		end

		local newIsOn = not currentIsOn

		Packets.TogglePowerRequest:Fire({
			Key = key,
			IsOn = newIsOn,
		})
	end)

	updatePrompt(model, key)
end

local function onPlacementAdded(key: string, entry: any)
	local spec = ItemFinder.FindItemById(entry.id)
	if not spec then
		return
	end

	local tags = spec.Tags
	local isLight = typeof(tags) == "table" and table.find(tags, "Light") ~= nil

	-- Check if it's a non-light consumer
	if spec.RequiresPower and not isLight then
		-- Find the model
		local model = PlotStateStore.ResolvePlacementInstance(key)
		if model and model:IsA("Model") then
			setupPrompt(model, key)
		end
	end
end

function PowerSwitchController.Init()
	-- Listen for placement changes (metadata updates)
	PlotStateStore.OnPlacementMetadataChanged(function()
		PlotStateStore.IteratePlacements(function(key, _)
			local model = PlotStateStore.ResolvePlacementInstance(key)
			if model and model:IsA("Model") then
				updatePrompt(model, key)
			end
			return true
		end)
	end)

	-- Listen for new models in the plot container
	local function watchContainer(container: Instance)
		container.ChildAdded:Connect(function(child)
			if child:IsA("Model") then
				local key = child.Name
				local entry = PlotStateStore.GetPlacementEntry(key)
				if entry then
					onPlacementAdded(key, entry)
				end
			end
		end)

		for _, child in ipairs(container:GetChildren()) do
			if child:IsA("Model") then
				local key = child.Name
				local entry = PlotStateStore.GetPlacementEntry(key)
				if entry then
					onPlacementAdded(key, entry)
				end
			end
		end
	end

	task.spawn(function()
		while not PlotStateStore.GetPlotContainer() do
			task.wait(1)
		end
		local container = PlotStateStore.GetPlotContainer()
		if container then
			watchContainer(container)
		end
	end)
end

return PowerSwitchController
