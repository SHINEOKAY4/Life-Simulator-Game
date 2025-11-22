--!strict
-- StarterPlayerScripts/Client/Modules/TenantHelpController.luau
-- Spawns proximity prompts on tenants when they request help and routes responses to the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TenantHelpPackets = require(ReplicatedStorage.Network.TenantHelpPackets)
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local MinimalPromptUI = require(script.Parent.MinimalPromptUI)

local LocalPlayer = Players.LocalPlayer

type HelpRecord = {
	RequestId: string,
	TenantId: string,
	TenantName: string,
	Need: string,
	ExpiresAt: number,
	RewardXP: number,
	RewardCash: number,
	Prompt: ProximityPrompt?,
	Connections: { RBXScriptConnection },
	Retries: number,
}

local TenantHelpController = {}
local ActiveRequests: { [string]: HelpRecord } = {}

local PROMPT_NAME = "TenantHelpPrompt"
local PROMPT_OFFSET = Vector3.new(0, 2.5, 0)
local MAX_RETRIES = 4

local function cleanupPrompt(record: HelpRecord)
	if record.Connections then
		for _, connection in ipairs(record.Connections) do
			if connection.Connected then
				connection:Disconnect()
			end
		end
		record.Connections = {}
	end

	if record.Prompt then
		MinimalPromptUI.Detach(record.Prompt)
		record.Prompt:Destroy()
		record.Prompt = nil
	end
end

local function teardown(record: HelpRecord, _reason: string)
	cleanupPrompt(record)
	ActiveRequests[record.RequestId] = nil
end

local function findTenantModel(tenantId: string): Model?
	local plotIndex = LocalPlayer:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end

	local residentsFolder = plotModel:FindFirstChild("Residents")
	if not residentsFolder then
		return nil
	end

	for _, child in ipairs(residentsFolder:GetChildren()) do
		if child:IsA("Model") and child:GetAttribute("TenantId") == tenantId then
			return child
		end
	end

	return nil
end

local function attachPrompt(record: HelpRecord)
	cleanupPrompt(record)

	local model = findTenantModel(record.TenantId)
	if not model then
		record.Retries += 1
		if record.Retries <= MAX_RETRIES then
			task.delay(1.5, function()
				if ActiveRequests[record.RequestId] == record then
					attachPrompt(record)
				end
			end)
		end
		return
	end

	local parent: Instance?
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		local attachment = root:FindFirstChild(PROMPT_NAME)
		if attachment and attachment:IsA("Attachment") then
			parent = attachment
		else
			local created = Instance.new("Attachment")
			created.Name = PROMPT_NAME
			created.Parent = root
			parent = created
		end
	end
	if not parent then
		parent = model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart") or model
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = "Help"
	prompt.ObjectText = record.Need
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.RequiresLineOfSight = false
	prompt.MaxActivationDistance = 14
	prompt.Style = Enum.ProximityPromptStyle.Custom
	prompt.HoldDuration = 0
	prompt:SetAttribute("MinimalPromptOffset", PROMPT_OFFSET)
	prompt.Parent = parent

	record.Prompt = prompt
	record.Connections = record.Connections or {}
	MinimalPromptUI.Attach(prompt)

	record.Connections[#record.Connections + 1] = prompt.Triggered:Connect(function(player: Player)
		if player ~= LocalPlayer then
			return
		end
		if ActiveRequests[record.RequestId] ~= record then
			return
		end
		prompt.Enabled = false
		local ok, success, message = pcall(function()
			return TenantHelpPackets.HelpInteraction:Fire(record.RequestId)
		end)
		if not ok then
			warn("[TenantHelpController] HelpInteraction failed:", success)
			prompt.Enabled = true
			return
		end
		if not success then
			warn("[TenantHelpController] HelpInteraction rejected:", message or "Request already resolved.")
			prompt.Enabled = true
		end
	end)
end

local function onHelpSpawn(payload: any)
	if typeof(payload) ~= "table" then
		return
	end

	local record: HelpRecord = {
		RequestId = payload.RequestId,
		TenantId = payload.TenantId,
		TenantName = payload.TenantName or "Tenant",
		Need = payload.Need or "Needs a hand",
		ExpiresAt = payload.ExpiresAt or 0,
		RewardXP = payload.RewardXP or 0,
		RewardCash = payload.RewardCash or 0,
		Prompt = nil,
		Connections = {},
		Retries = 0,
	}

	ActiveRequests[record.RequestId] = record

	attachPrompt(record)
end

local function onHelpRemoved(payload: any)
	if typeof(payload) ~= "table" then
		return
	end
	local requestId = payload.RequestId
	local reason = payload.Reason or "Expired"
	if typeof(requestId) ~= "string" or requestId == "" then
		return
	end

	local record = ActiveRequests[requestId]
	if not record then
		return
	end
	teardown(record, reason)
end

function TenantHelpController.Init()
	TenantHelpPackets.HelpRequestSpawn.OnClientEvent:Connect(onHelpSpawn)
	TenantHelpPackets.HelpRequestRemoved.OnClientEvent:Connect(onHelpRemoved)
end

return TenantHelpController
