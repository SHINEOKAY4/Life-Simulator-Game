--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Packets = require(ReplicatedStorage.Network.PlacementPackets)
local RateLimiter = require(ReplicatedStorage.Shared.Utilities.RateLimiter)

local Build = require(script.Actions.Build)
local DestroyAction = require(script.Actions.DestroyAction)
local Move = require(script.Actions.Move)
local PlaceFloorArea = require(script.Actions.PlaceFloorArea)
local PlaceRoofArea = require(script.Actions.PlaceRoofArea)
local PlaceWallStrip = require(script.Actions.PlaceWallStrip)
local PlaceSurfaceMount = require(script.Actions.PlaceSurfaceMount)
local DestroySurfaceMount = require(script.Actions.DestroySurfaceMount)
local Rotate = require(script.Actions.Rotate)
local PaintSurface = require(script.Actions.PaintSurface)
local ConnectUtility = require(script.Actions.ConnectUtility)
local DisconnectUtility = require(script.Actions.DisconnectUtility)

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
BuildService.PlaceRoofArea = PlaceRoofArea
BuildService.PlaceWallStrip = PlaceWallStrip
BuildService.Build = Build
BuildService.Destroy = DestroyAction
BuildService.Move = Move
BuildService.Rotate = Rotate
BuildService.PlaceSurfaceMount = PlaceSurfaceMount
BuildService.DestroySurfaceMount = DestroySurfaceMount
BuildService.PaintSurface = PaintSurface.PaintSurface
BuildService.PaintSurfaceBatch = PaintSurface.PaintSurfaceBatch
BuildService.ConnectUtility = ConnectUtility
BuildService.DisconnectUtility = DisconnectUtility

function BuildService.Init()
	Packets.PlaceRequest.OnServerInvoke = withRateLimit(BuildService.Build)
	Packets.PlaceFloorAreaRequest.OnServerInvoke = withRateLimit(BuildService.PlaceFloorArea)
	Packets.PlaceRoofAreaRequest.OnServerInvoke = withRateLimit(BuildService.PlaceRoofArea)
	Packets.PlaceWallStripRequest.OnServerInvoke = withRateLimit(BuildService.PlaceWallStrip)
	Packets.PlaceSurfaceMountRequest.OnServerInvoke = withRateLimit(BuildService.PlaceSurfaceMount)
	Packets.DestroySurfaceMountRequest.OnServerInvoke = withRateLimit(BuildService.DestroySurfaceMount)
	Packets.PaintSurfaceRequest.OnServerInvoke = withRateLimit(BuildService.PaintSurface)
	Packets.PaintSurfaceBatchRequest.OnServerInvoke = withRateLimit(BuildService.PaintSurfaceBatch)
	Packets.DestroyRequest.OnServerInvoke = withRateLimit(BuildService.Destroy)
	Packets.MoveRequest.OnServerInvoke = withRateLimit(BuildService.Move)
	Packets.RotateRequest.OnServerInvoke = withRateLimit(BuildService.Rotate)
	Packets.ConnectUtilityRequest.OnServerInvoke = withRateLimit(BuildService.ConnectUtility)
	Packets.DisconnectUtilityRequest.OnServerInvoke = withRateLimit(BuildService.DisconnectUtility)
end

return BuildService
