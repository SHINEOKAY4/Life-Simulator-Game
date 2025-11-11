--!strict
-- Attaches standard hover and click sounds to all GuiButtons.

local Players = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local BUTTON_SOUND_ID = "rbxassetid://103307955424380"
local CLICK_VOLUME = 0.6

local ButtonSoundController = {}

type ConnectionBucket = { [number]: RBXScriptConnection }

local trackedButtons: { [GuiButton]: ConnectionBucket } = {}
local playerGui: PlayerGui

local function playSound(volume: number)
	local sound = Instance.new("Sound")
	sound.Name = "UIButtonSound"
	sound.SoundId = BUTTON_SOUND_ID
	sound.Volume = volume
	sound.RollOffMode = Enum.RollOffMode.Linear
	sound.Parent = SoundService
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
end

local function teardown(button: GuiButton)
	local bucket = trackedButtons[button]
	if not bucket then
		return
	end
	trackedButtons[button] = nil
	for _, connection in pairs(bucket) do
		connection:Disconnect()
	end
end

local function attach(button: GuiButton)
	if trackedButtons[button] then
		return
	end

	local bucket: ConnectionBucket = {}

	bucket[#bucket + 1] = button.Activated:Connect(function()
		playSound(CLICK_VOLUME)
	end)

	bucket[#bucket + 1] = button.Destroying:Connect(function()
		teardown(button)
	end)

	trackedButtons[button] = bucket
end

local function scanDescendants(container: Instance)
	for _, descendant in ipairs(container:GetDescendants()) do
		if descendant:IsA("GuiButton") then
			attach(descendant)
		end
	end
end

function ButtonSoundController.Init()
	local localPlayer = Players.LocalPlayer
	playerGui = localPlayer:WaitForChild("PlayerGui") :: PlayerGui

	scanDescendants(playerGui)

	playerGui.DescendantAdded:Connect(function(instance)
		if instance:IsA("GuiButton") then
			attach(instance)
		end
	end)

	playerGui.DescendantRemoving:Connect(function(instance)
		if instance:IsA("GuiButton") then
			teardown(instance)
		end
	end)
end

return ButtonSoundController
