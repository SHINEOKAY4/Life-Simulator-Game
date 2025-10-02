--!strict
-- ReplicatedStorage/Shared/Utilities/PlotFinder.lua
-- Finds and manages plot models tagged with "Plot".

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

BuildOrderedPlotList()

return PlotFinder
