--!strict
-- ReplicatedStorage/Shared/Utilities/PlotFinder.luau
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

BuildOrderedPlotList()

return PlotFinder
