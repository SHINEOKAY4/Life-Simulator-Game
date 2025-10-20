--!strict
-- ReplicatedStorage/Shared/Utilities/PlotFinder.lua
-- Finds and manages plot models tagged with "Plot".

local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local PlotFinder = {}
local OrderedPlots: { Model } = {}
local Plots = CollectionService:GetTagged("Plot")
local TotalPlots = #Plots

--[=[
	@private
	Initializes the module by fetching all parts tagged with "Plot" and
	ordering them in a table according to their "IndexOrder" attribute.
]=]
local function BuildOrderedPlotList()
	for _, plotModel in ipairs(Plots) do
		local plotIndexNumber = plotModel:GetAttribute("IndexOrder")
		OrderedPlots[plotIndexNumber] = plotModel
	end
end

--[=[
	Gets the list of all plot models.

	@return {Model} An array-like table where the key is the plot's 'IndexOrder' attribute
	and the value is the corresponding plot Model.
]=]
function PlotFinder.GetOrderedPlots()
	return OrderedPlots
end

--[=[
	Finds a specific plot model by its index.

	@param index number The 'IndexOrder' attribute of the plot to find.
	@return Model The plot Model corresponding to the given index, or nil if not found.
]=]
function PlotFinder.FindPlot(index: number): Model
	return OrderedPlots[index]
end

--[=[
	Gets the total number of plot models.

	@return number The total count of plots tagged with "Plot".
]=]
function PlotFinder.GetTotalPlots(): number
	return TotalPlots
end

--[=[
	Checks if a player's character is within the bounds of their owned plot.

	@param player The player to check.
	@return boolean True if the player is within the bounds of their owned plot, false otherwise.
]=]
function PlotFinder.IsWithinBounds(player: Player): boolean
	local character = player.Character
	if not character then
		return false
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart
	if not humanoidRootPart then
		return false
	end

	local plotIndex = player:GetAttribute("OwnedPlotIndex") :: number
	local plotModel = PlotFinder.FindPlot(plotIndex)

	if not plotModel then
		return false
	end

	local surface = plotModel:FindFirstChild("Surface") :: BasePart
	if not surface then
		return false
	end

	local verticalTolerance = 24 -- studs around the top face

	local localPoint: Vector3 = surface.CFrame:PointToObjectSpace(humanoidRootPart.Position)
	local halfSize: Vector3 = surface.Size * 0.5

	-- Optionally add offset to go beyond the surface edges
	local offset = 0
	local withinX = math.abs(localPoint.X) <= halfSize.X + offset
	local withinZ = math.abs(localPoint.Z) <= halfSize.Z + offset

	local topY = halfSize.Y
	local withinVertical = math.abs(localPoint.Y - topY) <= verticalTolerance

	return withinX and withinZ and withinVertical
end

------------------------------------------------------------------

if RunService:IsClient() then
	local Connection = nil :: RBXScriptConnection?
	local TrackingEnabled = false

	local function StopTracking(player: Player)
		if Connection then
			Connection:Disconnect()
			Connection = nil
		end
		TrackingEnabled = false
		if player and player:GetAttribute("WithinPlot") then
			player:SetAttribute("WithinPlot", false)
		end
	end

	--[=[
		@within PlotFinder
		@private
		Starts tracking whether the given player is within their plot bounds.
		This function sets up a heartbeat connection to periodically check
		the player's position and update the "WithinPlot" BoolValue in ReplicatedStorage.Shared.Booleans.
	
		@param player Player The player to track.
	]=]
	PlotFinder.StartTracking = function(player: Player)
		if TrackingEnabled or not player then
			return
		end

		TrackingEnabled = true
		local accumulatedTime = 0
		local lastWithinState = false

		Connection = RunService.Heartbeat:Connect(function(deltaTime)
			accumulatedTime += deltaTime

			if accumulatedTime >= 0.5 then
				accumulatedTime = 0

				local isWithin = PlotFinder.IsWithinBounds(player)
				if isWithin then
					if not lastWithinState then
						lastWithinState = true
						player:SetAttribute("WithinPlot", true)
					end
				else
					lastWithinState = false
					StopTracking(player)
				end
			end
		end)
	end
end

BuildOrderedPlotList()

return PlotFinder
