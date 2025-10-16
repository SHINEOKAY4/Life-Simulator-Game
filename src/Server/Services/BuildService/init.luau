--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local RateLimiter = require(ReplicatedStorage.Shared.Utilities.RateLimiter)

local Build = require(script.Actions.Build)
local DestroyAction = require(script.Actions.DestroyAction)
local Move = require(script.Actions.Move)
local PlaceFloorArea = require(script.Actions.PlaceFloorArea)
local PlaceWallStrip = require(script.Actions.PlaceWallStrip)
local Rotate = require(script.Actions.Rotate)

local BuildService = {}

local Limiter = RateLimiter.new()
local PlaceBucket = Limiter:Bucket("place", { ratePerSecond = 4, burst = 6 })

local function withRateLimit(handler: (Player, any) -> (boolean, string))
	return function(player: Player, payload: any): (boolean, string)
		if not PlaceBucket:Allow(player, 1) then
			local waitSeconds = PlaceBucket:SecondsUntilNextToken(player)
			return false, ("Too fast. Try again in %.2fs"):format(waitSeconds)
		end

		return handler(player, payload)
	end
end

BuildService.PlaceFloorArea = PlaceFloorArea
BuildService.PlaceWallStrip = PlaceWallStrip
BuildService.Build = Build
BuildService.Destroy = DestroyAction
BuildService.Move = Move
BuildService.Rotate = Rotate

function BuildService.Init()
	Packets.PlaceRequest.OnServerInvoke = withRateLimit(BuildService.Build)
	Packets.PlaceFloorAreaRequest.OnServerInvoke = withRateLimit(BuildService.PlaceFloorArea)
	Packets.PlaceWallStripRequest.OnServerInvoke = withRateLimit(BuildService.PlaceWallStrip)
	Packets.DestroyRequest.OnServerInvoke = withRateLimit(BuildService.Destroy)
	Packets.MoveRequest.OnServerInvoke = withRateLimit(BuildService.Move)
	Packets.RotateRequest.OnServerInvoke = withRateLimit(BuildService.Rotate)
end

return BuildService
