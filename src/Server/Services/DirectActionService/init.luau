--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local GoodSignal = require(ReplicatedStorage.Packages.GoodSignal)
local ResidentsPackets = require(ReplicatedStorage.Network.ResidentsPackets)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local ResidentService = require(ServerScriptService.Server.Services.ResidentService)

local ManualOverrideCoordinator = require(script.ManualOverrideCoordinator)
local StationResolver = require(script.StationResolver)
local Types = require(script.Types)

local NEED_EFFECTS_ABORT_PREFIX = "NeedEffectsAborted|"
local MANUAL_MOVE_TIMEOUT_SECONDS = 25

local DirectActionService = {}
DirectActionService.OverrideStarted = GoodSignal.new()
DirectActionService.OverrideCompleted = GoodSignal.new()
DirectActionService.OverrideFailed = GoodSignal.new()

local OverrideHandlers: {
	[string]: (
		context: { Resident: any, CancelToken: { Cancelled: boolean, Reason: string? } },
		Types.StationAssignment
	) -> (),
} =
	{}

local function parseAbortReason(message: string?): string?
	if typeof(message) ~= "string" then
		return nil
	end
	if message:sub(1, #NEED_EFFECTS_ABORT_PREFIX) ~= NEED_EFFECTS_ABORT_PREFIX then
		return nil
	end
	local raw = message:sub(#NEED_EFFECTS_ABORT_PREFIX + 1)
	if raw == "" then
		return "Unknown"
	end
	return raw
end

local function formatFailureMessage(message: string?): string?
	if not message then
		return nil
	end
	local abortReason = parseAbortReason(message)
	if not abortReason then
		return message
	end
	if abortReason == "Cancelled" then
		return "Action cancelled."
	end
	if abortReason:sub(1, 11) == "NeedUrgent:" then
		local needName = abortReason:sub(12)
		if needName == "MultipleNeeds" or needName == "" then
			return "Interrupted by urgent needs."
		end
		return string.format("Interrupted by %s need.", needName)
	end
	return string.format("Interrupted: %s", abortReason)
end

local function resolveHandler(stationType: string)
	return OverrideHandlers[stationType]
		or function(context, _assignment)
			if context.CancelToken.Cancelled then
				return
			end
		end
end

local function finalizeAssignment(assignment: Types.StationAssignment, succeeded: boolean, message: string?)
	ManualOverrideCoordinator.releaseStation(assignment)
	assignment.ResidentState:ClearManualOverrideState()
	assignment.ResidentState:EnableAutomation()

	local deliveredMessage = message
	if not succeeded then
		local friendly = formatFailureMessage(message)
		if friendly then
			deliveredMessage = friendly
		end
	end

	if succeeded then
		DirectActionService.OverrideCompleted:Fire(assignment, deliveredMessage)
		return
	end

	DirectActionService.OverrideFailed:Fire(assignment, deliveredMessage)
end

local function isFiniteNumber(value: number): boolean
	return value == value and value > -math.huge and value < math.huge
end

local function isFiniteVector3(value: Vector3): boolean
	return isFiniteNumber(value.X) and isFiniteNumber(value.Y) and isFiniteNumber(value.Z)
end

function DirectActionService.GetHandler(stationType: string)
	return OverrideHandlers[stationType]
end

function DirectActionService.HasHandler(stationType: string): boolean
	return OverrideHandlers[stationType] ~= nil
end

function DirectActionService.RegisterHandler(
	stationType: string,
	handler: (
		context: { Resident: any, CancelToken: { Cancelled: boolean, Reason: string? } },
		Types.StationAssignment
	) -> ()
)
	OverrideHandlers[stationType] = handler
end

function DirectActionService.AssignStationToResident(player: Player, residentName: string, uniqueId: string)
	if type(residentName) ~= "string" or residentName == "" then
		return false, "Invalid resident name"
	end
	if type(uniqueId) ~= "string" or uniqueId == "" then
		return false, "Invalid station id"
	end

	local assignment, resolveError = StationResolver.Resolve(player, residentName, uniqueId)
	if not assignment then
		return false, resolveError or "Unable to resolve station"
	end

	local prepared, reason = ManualOverrideCoordinator.prepareResident(assignment.ResidentState, 3)
	if not prepared then
		return false, reason or "Unable to prepare resident for override"
	end

	ManualOverrideCoordinator.clearExistingOverride(player, assignment.ResidentState, assignment.ResidentName)
	ManualOverrideCoordinator.reserveStation(assignment)

	assignment.ResidentState:SetManualOverrideState({
		StationType = assignment.StationType,
		StationId = assignment.StationId,
		ItemId = assignment.ItemId,
	})

	DirectActionService.OverrideStarted:Fire(assignment)

	local handler = resolveHandler(assignment.StationType)
	local actionName = string.format("ManualOverride:%s", assignment.StationType)

	ManualOverrideCoordinator.enqueueOverrideAction(assignment, actionName, handler, function(succeeded, message)
		finalizeAssignment(assignment, succeeded, message)
	end)

	return true, "Manual override queued"
end

function DirectActionService.MoveResidentToWorldPosition(player: Player, residentName: string, targetPosition: Vector3)
	if type(residentName) ~= "string" or residentName == "" then
		return false, "Invalid resident name"
	end

	if typeof(targetPosition) ~= "Vector3" or not isFiniteVector3(targetPosition) then
		return false, "Invalid target position"
	end

	local residentState = ResidentService.GetResident(player, residentName)
	if not residentState then
		return false, "Resident not found"
	end
	if residentState.IsOnShift then
		return false, "Resident is currently working"
	end

	local prepared, reason = ManualOverrideCoordinator.prepareResident(residentState, 3)
	if not prepared then
		return false, reason or "Resident is busy"
	end

	ManualOverrideCoordinator.clearExistingOverride(player, residentState, residentName)

	residentState:SetManualOverrideState({ Mode = "ManualMove", TargetPosition = targetPosition })

	residentState:EnqueueAction("ManualOverride:Move", function(context)
		local releaseCollapse = residentState._EnergyCollapseRelease
		if typeof(releaseCollapse) == "function" then
			releaseCollapse()
		end
		ResidentMovement.ClearRestPose(residentState)
		local result = ResidentMovement.GoToWorldPosition(residentState, targetPosition, {
			CancelToken = context.CancelToken,
			TimeoutSeconds = MANUAL_MOVE_TIMEOUT_SECONDS,
			DebugName = "ManualMove",
		})

		residentState:ClearManualOverrideState()
		residentState:EnableAutomation()

		if result then
			return
		end

		if context.CancelToken.Cancelled then
			error(context.CancelToken.Reason or "Movement cancelled")
		end

		error("Resident could not reach the destination")
	end)

	return true, "Movement queued"
end

function DirectActionService.Init()
	ResidentsPackets.RequestAssignStation.OnServerInvoke = function(
		player: Player,
		residentName: string,
		uniqueId: string
	)
		local success, message = DirectActionService.AssignStationToResident(player, residentName, uniqueId)
		return success, message
	end

	ResidentsPackets.RequestResidentMove.OnServerInvoke = function(
		player: Player,
		residentName: string,
		targetPosition: Vector3
	)
		return DirectActionService.MoveResidentToWorldPosition(player, residentName, targetPosition)
	end
end

return DirectActionService
