--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SoundtrackController = require(ReplicatedStorage.Packages.Soundtrack)

local LOCAL_PLAYER = Players.LocalPlayer or Players.PlayerAdded:Wait()

local SOUND_IDS = {
	Ambient = "rbxassetid://526738965",
	Music1 = "rbxassetid://97135398416629",
	Music2 = "rbxassetid://1842205471",
	ButtonClick = "rbxassetid://88442833509532",
	PlacementSuccess = "rbxassetid://9119999441",
	Notification = "rbxassetid://9119999441",
	ChoreCompleted = "rbxassetid://8486683243",
}

local NOTIFICATION_SFX_OPTIONS = {
	Volume = 0.55,
}

local BUTTON_SFX_OPTIONS = {
	Volume = 0.6,
}

local DEFAULT_AMBIENT_VOLUME = 0.45
local MUSIC_PLAYLIST_NAME = "LifeSim_MainPlaylist"
local MUSIC_TRACKS = {
	SOUND_IDS.Music1,
	SOUND_IDS.Music2,
}

local SoundtrackManager = {}

local controller: any = nil
local connections: { any } = {}
local musicPlaylistStarted = false

local function copyPlaylistTracks()
	local tracks = {}
	for _, soundId in ipairs(MUSIC_TRACKS) do
		table.insert(tracks, soundId)
	end
	return tracks
end

local function startMusicPlaylist()
	if not controller or musicPlaylistStarted then
		return
	end

	controller:CreatePlaylist(MUSIC_PLAYLIST_NAME, copyPlaylistTracks(), {
		Shuffle = true,
		Repeat = true,
		CrossFade = true,
	})
	controller:PlayPlaylist(MUSIC_PLAYLIST_NAME)
	musicPlaylistStarted = true
end

local function disconnectAll()
	for _, connection in connections do
		if connection then
			connection:Disconnect()
		end
	end
	connections = {}
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

	startMusicPlaylist()
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
	startMusicPlaylist()
end

function SoundtrackManager.Destroy()
	if not controller then
		return
	end
	disconnectAll()
	controller:Cleanup()
	controller = nil
	musicPlaylistStarted = false
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

function SoundtrackManager.PlayPlacementSuccess()
	playSfx(SOUND_IDS.PlacementSuccess, { Volume = 0.7 })
end

function SoundtrackManager.PlayChoreCompleted()
	playSfx(SOUND_IDS.ChoreCompleted, { Volume = 0.7 })
end

SoundtrackManager.NotificationSoundId = SOUND_IDS.Notification

return SoundtrackManager
