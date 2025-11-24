--!strict
-- Client/ClientStores/CutawayStateManager.luau
-- Isolated cutaway request priority resolution and state management

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)

export type CutawayRequestOptions = {
	Priority: number?,
	TargetLevel: number?,
	HidePlacementTypes: { [string]: boolean }?,
}

export type CutawayRequest = {
	Source: string,
	Priority: number,
	TargetLevel: number?,
	HidePlacementTypes: { [string]: boolean }?,
}

export type CutawayState = {
	Visible: boolean,
	Source: string?,
	TargetLevel: number,
	HidePlacementTypes: { [string]: boolean },
}

local CutawayStateManager = {}

local DEFAULT_CUTAWAY_HIDE_TYPES = {
	Wall = true,
	Roof = true,
	Ceiling = true,
}

local function cloneBooleanMap(source: { [string]: boolean }?): { [string]: boolean }
	local result = {}
	if not source then
		return result
	end
	for key, value in pairs(source) do
		if value == true then
			result[key] = true
		end
	end
	return result
end

local function booleanMapsEqual(left: { [string]: boolean }?, right: { [string]: boolean }?): boolean
	if left == right then
		return true
	end
	if not left then
		if not right then
			return true
		end
		for _, value in pairs(right) do
			if value == true then
				return false
			end
		end
		return true
	end
	if not right then
		for _, value in pairs(left) do
			if value == true then
				return false
			end
		end
		return true
	end
	for key, value in pairs(left) do
		if (right[key] or false) ~= (value == true) then
			return false
		end
	end
	for key, value in pairs(right) do
		if (left[key] or false) ~= (value == true) then
			return false
		end
	end
	return true
end

function CutawayStateManager.new(defaultLevel: number, maxLevel: number, getActiveLevel: () -> number)
	local self = {}

	local cutawayRequests: { [string]: CutawayRequest } = {}
	local activeCutawayState: CutawayState = {
		Visible = false,
		Source = nil,
		TargetLevel = defaultLevel,
		HidePlacementTypes = cloneBooleanMap(DEFAULT_CUTAWAY_HIDE_TYPES),
	}

	local cutawayChanged = GoodSignal.new()

	local function clampLevel(level: number?): number?
		if typeof(level) ~= "number" then
			return nil
		end
		local candidate = math.floor((level :: number) + 0.5)
		return math.clamp(candidate, defaultLevel, maxLevel)
	end

	local function normalizeCutawayOptions(source: string, options: CutawayRequestOptions?): CutawayRequest
		local resolved: any = options or {}
		local resolvedLevel: number? = clampLevel(resolved.TargetLevel)

		local hideMap = cloneBooleanMap(DEFAULT_CUTAWAY_HIDE_TYPES)
		if typeof(resolved.HidePlacementTypes) == "table" then
			for placementType, shouldHide in pairs(resolved.HidePlacementTypes :: any) do
				if shouldHide == true then
					hideMap[placementType] = true
				else
					hideMap[placementType] = nil
				end
			end
		end

		local priorityValue = 0
		if typeof(resolved.Priority) == "number" then
			priorityValue = resolved.Priority :: number
		end

		return {
			Source = source,
			Priority = priorityValue,
			TargetLevel = resolvedLevel,
			HidePlacementTypes = hideMap,
		}
	end

	local function recomputeCutawayState()
		local winningSource: string? = nil
		local winningRequest: CutawayRequest? = nil
		local winningPriority = -math.huge
		for source, request in pairs(cutawayRequests) do
			if request and request.Priority >= winningPriority then
				winningPriority = request.Priority
				winningSource = source
				winningRequest = request
			end
		end

		local newVisible = winningRequest ~= nil
		local resolvedLevel = getActiveLevel()
		local resolvedHideTypes = if winningRequest
			then cloneBooleanMap(winningRequest.HidePlacementTypes)
			else cloneBooleanMap(DEFAULT_CUTAWAY_HIDE_TYPES)
		if winningRequest and winningRequest.TargetLevel then
			resolvedLevel = winningRequest.TargetLevel
		end

		local stateChanged = newVisible ~= activeCutawayState.Visible
			or resolvedLevel ~= activeCutawayState.TargetLevel
			or winningSource ~= activeCutawayState.Source
			or not booleanMapsEqual(resolvedHideTypes, activeCutawayState.HidePlacementTypes)

		if stateChanged then
			activeCutawayState.Visible = newVisible
			activeCutawayState.Source = winningSource
			activeCutawayState.TargetLevel = resolvedLevel
			activeCutawayState.HidePlacementTypes = resolvedHideTypes
			cutawayChanged:Fire(self.GetState())
		end
	end

	function self.RequestCutaway(source: string, options: CutawayRequestOptions?)
		if typeof(source) ~= "string" or source == "" then
			warn("Cutaway request requires a non-empty source identifier")
			return
		end
		cutawayRequests[source] = normalizeCutawayOptions(source, options)
		recomputeCutawayState()
	end

	function self.ReleaseCutaway(source: string)
		if typeof(source) ~= "string" or source == "" then
			return
		end
		if cutawayRequests[source] == nil then
			return
		end
		cutawayRequests[source] = nil
		recomputeCutawayState()
	end

	function self.ClearAllRequests()
		if next(cutawayRequests) == nil then
			return
		end
		for source in pairs(cutawayRequests) do
			cutawayRequests[source] = nil
		end
		recomputeCutawayState()
	end

	function self.GetState(): CutawayState
		return {
			Visible = activeCutawayState.Visible,
			Source = activeCutawayState.Source,
			TargetLevel = activeCutawayState.TargetLevel,
			HidePlacementTypes = cloneBooleanMap(activeCutawayState.HidePlacementTypes),
		}
	end

	function self.OnCutawayChanged(handler: (CutawayState) -> ()): RBXScriptConnection
		return cutawayChanged:Connect(handler)
	end

	function self.RefreshState()
		recomputeCutawayState()
	end

	return self
end

return CutawayStateManager
