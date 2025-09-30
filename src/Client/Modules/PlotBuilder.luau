--!strict
-- ReplicatedStorage/Client/Modules/PlotBuilder.lua

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local PlotGridOverlay = require(script.Parent.PlotGridOverlay)
local ObjectPreview = require(script.Parent.ObjectPreview)
local Packets = require(ReplicatedStorage.Network.PlacementPackets)

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local BuildContext = PlayerGui:WaitForChild("BuildContext")

local PlotBuilder = {}
local Connection: RBXScriptConnection? = nil
local IsActive = false

function PlotBuilder.Init()
	BuildContext.ToggleBuildMode.Pressed:Connect(function()
		local plotIndex = Player:GetAttribute("OwnedPlotIndex") :: number
		if not plotIndex then
			warn("Player does not own a plot.")
			return
		end
		if PlotFinder.IsWithinBounds(Player) then
			if IsActive then
				PlotBuilder.Hide()
			else
				PlotBuilder.Show()
			end
		end
	end)

	BuildContext.PlacePreview.Pressed:Connect(function()
		PlotBuilder.PlaceSelectedPreview()
	end)
end

function PlotBuilder.Show()
	IsActive = true
	--#TODO: SHOW BUILD UI
	PlotGridOverlay.Show()
	PlotBuilder.PreviewSelected("WoodenChair") -- Demo
	Connection = RunService.Heartbeat:Connect(function()
		if not PlotFinder.IsWithinBounds(Player) then
			PlotBuilder.Hide()
		end
	end)
end

function PlotBuilder.Hide()
	IsActive = false
	--#TODO: HIDE BUILD UI
	PlotGridOverlay.Hide()
	PlotBuilder.RemovePreview()
	if Connection then
		Connection:Disconnect()
		Connection = nil
	end
end

function PlotBuilder.PreviewSelected(itemId: string)
	ObjectPreview.RenderPreview(itemId)
	BuildContext.PlacePreview.Enabled = true
end

function PlotBuilder.RemovePreview()
	ObjectPreview.ClearPreview()
	BuildContext.PlacePreview.Enabled = false
end

function PlotBuilder.PlaceSelectedPreview()
	-- Packets.PlaceRequest:Fire(itemId, cellX, cellZ, facing):Response(boolean, string long) -- shape of payload

	local pose = ObjectPreview.GetCurrentPose()
	if not pose then
		warn("No preview pose available.")
		return
	end

	local success, message = Packets.PlaceRequest:Fire({
		ItemId = pose.ItemId,
		CellX = pose.CellX,
		CellZ = pose.CellZ,
		Facing = pose.Facing,
	})

	if not success then
		warn("Placement failed: " .. message)
	end

	-- Optional: keep previewing for batch placement; or call RemovePreview()
end

--#TODO: More functions for rotating, selecting already placed items, deleting placed items, etc.
return PlotBuilder
