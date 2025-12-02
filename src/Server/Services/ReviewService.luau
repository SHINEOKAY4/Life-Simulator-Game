--!strict
-- Server/Services/ReviewService.luau
-- Handles tenant review generation and replication.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")
local HttpService = game:GetService("HttpService")

local TenantConfig = require(ReplicatedStorage.Shared.Configurations.TenantConfig)
local ReviewPackets = require(ReplicatedStorage.Network.ReviewPackets)
local PlayerSession = require(ServerScriptService.Server.Services.PlayerSession)
local PlotService = require(ServerScriptService.Server.Services.PlotService)
local ChoreService = require(ServerScriptService.Server.Services.ChoreService)
local WeatherService = require(ServerScriptService.Server.Services.WeatherService)

local ReviewService = {}

local MAX_STORED_REVIEWS = 50
local tempConfig = TenantConfig.Temperature

local function getAverageRoomTemperature(player: Player): number
	local plotState = PlotService.GetState(player)
	if not plotState then
		return WeatherService.GetCurrentTemperature()
	end

	local totalTemp = 0
	local roomCount = 0
	for level = 0, plotState.MaxFloorLevel do
		for _, room in ipairs(plotState:GetRoomsForLevel(level)) do
			-- Only consider enclosed rooms for temperature averaging
			if room.IsEnclosed and room.CellCount > 0 then
				totalTemp += room.CurrentTemperature
				roomCount += 1
			end
		end
	end

	if roomCount == 0 then
		return WeatherService.GetCurrentTemperature()
	end

	return totalTemp / roomCount
end

local function buildReview(player: Player, lease: { [string]: any }, reason: string)
	local rating = math.random(3, 5)
	if typeof(lease.MissedPayments) == "number" and lease.MissedPayments > 0 then
		rating = math.max(1, rating - 1)
	end

	local trashCount = ChoreService.GetTrashCount(player)
	if trashCount > 0 then
		local penalty = math.max(1, math.floor(trashCount / 2))
		rating = math.max(1, rating - penalty)
	end

	local avgTemp = getAverageRoomTemperature(player)
	local tempPenalty = 0
	local tempComment: string? = nil

	if avgTemp < tempConfig.IdealMin then
		if avgTemp < tempConfig.FreezingThreshold then
			tempPenalty = 2
			tempComment = "It's absolutely freezing in here! Turn on the heat!"
		else
			tempPenalty = 1
			tempComment = "A bit too cold for my taste."
		end
	elseif avgTemp > tempConfig.IdealMax then
		if avgTemp > tempConfig.OverheatThreshold then
			tempPenalty = 2
			tempComment = "It's like a sauna in here! Unbearable heat."
		else
			tempPenalty = 1
			tempComment = "It's too hot inside. Do you have AC?"
		end
	end

	rating = math.clamp(rating - tempPenalty, 1, 5)
	if reason == "Evicted" then
		rating = 1
	end

	local comments = {
		[5] = {
			"Loved living here! Everything was perfect.",
			"Amazing place, highly recommend!",
			"Best landlord ever.",
			"So cozy and nice.",
		},
		[4] = { "Great place, would recommend.", "Nice and cozy.", "Good value for money.", "Pretty solid stay." },
		[3] = { "It was okay. Nothing special.", "Decent place to stay.", "Could be better.", "Average experience." },
		[2] = { "Had some issues, but it was cheap.", "Not the best experience.", "Needs improvement.", "Meh." },
		[1] = {
			"Terrible experience. Do not rent here.",
			"Avoid at all costs.",
			"Worst place ever.",
			"I was kicked out!",
		},
	}

	local commentPool = comments[rating] or comments[3]
	if tempComment and rating <= 3 then
		commentPool = { tempComment }
	elseif trashCount > 0 and rating <= 3 then
		commentPool = {
			"The place was a dump! Trash everywhere.",
			"Disgusting. Garbage all over the floor.",
			"I can't believe I lived in such filth.",
			"Smelled terrible. Clean up your property!",
		}
	end

	local comment = commentPool[math.random(1, #commentPool)]
	return {
		Id = HttpService:GenerateGUID(false),
		TenantName = lease.TenantName or "Unknown Tenant",
		Rating = rating,
		Comment = comment,
		Timestamp = Workspace:GetServerTimeNow(),
		Traits = lease.Traits or {},
	}
end

function ReviewService.RecordTenantReview(player: Player, lease: { [string]: any }, reason: string)
	local review = buildReview(player, lease, reason)
	local reviewState = PlayerSession.GetData(player, "ReviewState")
	if reviewState and reviewState.Reviews then
		table.insert(reviewState.Reviews, 1, review)
		if #reviewState.Reviews > MAX_STORED_REVIEWS then
			table.remove(reviewState.Reviews)
		end

		ReviewPackets.NewReview:FireClient(player, {
			Review = review,
		})
	end
end

function ReviewService.GetReviews(player: Player)
	local reviewState = PlayerSession.GetData(player, "ReviewState")
	if not reviewState or not reviewState.Reviews then
		return {}
	end
	return reviewState.Reviews
end

function ReviewService.Init()
	ReviewPackets.GetReviewsRequest.OnServerInvoke = function(player: Player)
		return ReviewService.GetReviews(player)
	end
end

return ReviewService
