--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundtrackController = require(ReplicatedStorage.Packages.Soundtrack)
local BillingPackets = require(ReplicatedStorage.Network.BillingPackets)

local LOCAL_PLAYER = Players.LocalPlayer or Players.PlayerAdded:Wait()

local SOUND_IDS = {
	Ambient = "rbxassetid://526738965",
	BillingDue = "rbxassetid://8060079174",
	ButtonClick = "rbxassetid://88442833509532",
	BillToggle = "rbxassetid://135041843438612",
	BillPaid = "rbxassetid://5613553529",
	PlacementSuccess = "rbxassetid://9119999441",
	Notification = "rbxassetid://9119999441",
}

local BILLING_SFX_OPTIONS = {
	Volume = 0.85,
}

local NOTIFICATION_SFX_OPTIONS = {
	Volume = 0.55,
}

local BUTTON_SFX_OPTIONS = {
	Volume = 0.6,
}

local BILL_TOGGLE_SFX_OPTIONS = {
	Volume = 0.65,
}

local BILL_PAID_SFX_OPTIONS = {
	Volume = 0.75,
}

local DEFAULT_AMBIENT_VOLUME = 0.45

local SoundtrackManager = {}

local controller: any = nil
local connections: { any } = {}
local billingDueActive = false
local lastOutstanding: number? = nil
local lastTimeRemaining: number? = nil
local lastElectricCost: number? = nil

local function disconnectAll()
	for _, connection in connections do
		if connection then
			connection:Disconnect()
		end
	end
	connections = {}
end

local function evaluateBillingState(outstandingTotal: number?, timeRemaining: number?, electricCost: number?): boolean
	local outstanding = if typeof(outstandingTotal) == "number" then outstandingTotal else 0
	local hasOutstanding = outstanding > 0

	if not hasOutstanding then
		return false
	end

	local electric = if typeof(electricCost) == "number" then electricCost else 0
	if electric <= 0 then
		return false
	end

	local attributeDue = LOCAL_PLAYER:GetAttribute("BillingGraceActive") == true
	if LOCAL_PLAYER:GetAttribute("BillingOverdueActive") == true then
		attributeDue = true
	end

	local remoteDue = hasOutstanding and typeof(timeRemaining) == "number" and timeRemaining <= 0

	return attributeDue or remoteDue
end

local function applyBillingState(outstandingTotal: number?, timeRemaining: number?, electricCost: number?)
	lastOutstanding = outstandingTotal
	lastTimeRemaining = timeRemaining
	lastElectricCost = electricCost

	if not controller then
		return
	end

	local isDue = evaluateBillingState(outstandingTotal, timeRemaining, electricCost)
	if isDue and not billingDueActive then
		controller:PlaySFX(SOUND_IDS.BillingDue, BILLING_SFX_OPTIONS)
	end
	billingDueActive = isDue
end

local function onBillingAttributeChanged()
	applyBillingState(lastOutstanding, lastTimeRemaining, lastElectricCost)
end

local function ensureController()
	if controller then
		return
	end

	controller = SoundtrackController.new()
	controller:SetMasterVolume(1)
	controller:SetMusicVolume(0.6)
	controller:SetSFXVolume(0.8)
	controller:SetAmbientVolume(DEFAULT_AMBIENT_VOLUME)

	controller:PlayAmbientSound(SOUND_IDS.Ambient, {
		Loop = true,
	})
end

local function playSfx(soundId: string?, options: { Volume: number?, PlaybackSpeed: number? }?)
	if typeof(soundId) ~= "string" or soundId == "" then
		return
	end

	if not controller then
		SoundtrackManager.Init()
	end

	if not controller then
		return
	end

	if typeof(options) == "table" then
		controller:PlaySFX(soundId, options)
	else
		controller:PlaySFX(soundId)
	end
end

function SoundtrackManager.Init()
	if controller then
		return
	end

	ensureController()

	connections = {
		LOCAL_PLAYER:GetAttributeChangedSignal("BillingGraceActive"):Connect(onBillingAttributeChanged),
		LOCAL_PLAYER:GetAttributeChangedSignal("BillingOverdueActive"):Connect(onBillingAttributeChanged),
		BillingPackets.BillingBreakdownUpdate.OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then
				return
			end
			applyBillingState(payload.OutstandingTotal, payload.TimeRemaining, payload.Electric)
		end),
	}

	local payload = BillingPackets.RequestBillingInfo:Fire()
	if typeof(payload) == "table" then
		applyBillingState(payload.OutstandingTotal, payload.TimeRemaining, payload.Electric)
	else
		applyBillingState(nil, nil, nil)
	end
end

function SoundtrackManager.Destroy()
	if not controller then
		return
	end
	disconnectAll()
	controller:Cleanup()
	controller = nil
	billingDueActive = false
	lastOutstanding = nil
	lastTimeRemaining = nil
end

function SoundtrackManager.PlayButtonClick()
	playSfx(SOUND_IDS.ButtonClick, BUTTON_SFX_OPTIONS)
end

function SoundtrackManager.PlayNotificationSound(
	soundId: string?,
	options: { Volume: number?, PlaybackSpeed: number? }?
)
	if soundId == "" then
		return
	end
	local resolvedId = soundId
	if resolvedId == nil or resolvedId == "" then
		resolvedId = SOUND_IDS.Notification
	end
	local resolvedOptions = options
	if resolvedId == SOUND_IDS.Notification then
		resolvedOptions = options or NOTIFICATION_SFX_OPTIONS
	end
	playSfx(resolvedId, resolvedOptions)
end

function SoundtrackManager.PlayBillToggle()
	playSfx(SOUND_IDS.BillToggle, BILL_TOGGLE_SFX_OPTIONS)
end

function SoundtrackManager.PlayBillPaid()
	playSfx(SOUND_IDS.BillPaid, BILL_PAID_SFX_OPTIONS)
end

function SoundtrackManager.PlayPlacementSuccess()
	playSfx(SOUND_IDS.BillPaid, BILL_PAID_SFX_OPTIONS)
end

SoundtrackManager.NotificationSoundId = SOUND_IDS.Notification

return SoundtrackManager
