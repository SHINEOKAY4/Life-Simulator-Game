--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local NeedEffects = require(ServerScriptService.Server.Utilities.NeedEffects)
local ResidentChat = require(ServerScriptService.Server.Utilities.ResidentChat)
local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
local ResidentMovement = require(ServerScriptService.Server.Utilities.ResidentMovement)
local StationManager = require(ServerScriptService.Server.Services.ResidentAutonomyService.StationManager)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)

local handlerRoot = script.Parent
local BehaviorConfig = require(handlerRoot:WaitForChild("BehaviorConfig"))
local Types = require(handlerRoot:WaitForChild("Types"))

export type Behavior = Types.Behavior
export type HandlerContext = Types.HandlerContext
export type HandlerAssignment = Types.HandlerAssignment

type Assignment = Types.HandlerAssignment

local ACTION_CHANNEL = "Action"

local DINING_STATION_PREFERENCES: { { StationType: string, RequiredTag: string? } } = {
	{ StationType = "MealStation" },
	{ StationType = "SocialStation", RequiredTag = "Table" },
	{ StationType = "FunStation", RequiredTag = "Table" },
	{ StationType = "RestStation", RequiredTag = "Seating" },
}

local function itemHasTag(itemSpec: { [string]: any }?, tag: string): boolean
	if not itemSpec then
		return false
	end
	local tags = itemSpec.Tags
	if typeof(tags) ~= "table" then
		return false
	end
	for _, value in ipairs(tags) do
		if typeof(value) == "string" and value == tag then
			return true
		end
	end
	return false
end

local Pipeline = {}
Pipeline.__index = Pipeline

export type DiningReservation = {
	StationType: string,
	UniqueId: string,
	StationRecord: StationManager.StationRecord,
	ItemSpec: { [string]: any }?,
	Model: Model,
}

export type MovementOptions = {
	ApproachDistance: number?,
	MoveTimeoutSeconds: number?,
	UseSeat: boolean?,
	RestPoseMode: string?,
	RestPoseEligible: boolean?,
	AllowRestPose: boolean?,
	StationRecord: StationManager.StationRecord?,
	ItemSpec: { [string]: any }?,
	OccupantIndex: number?,
	OccupantCount: number?,
	IsDining: boolean?,
}

function Pipeline.new(context: HandlerContext, assignment: HandlerAssignment)
	local self = setmetatable(
		{
			context = context,
			assignment = assignment :: Assignment,
			actionLabel = BehaviorConfig.getStationLabel(assignment.StationType),
			stationName = BehaviorConfig.resolveStationDisplayName(assignment, assignment.StationType),
			primaryRecord = assignment.StationRecord,
			cleanupTasks = {},
			restPoseApplied = false,
			restPoseMode = nil,
			restPoseModel = nil,
			primarySeat = nil,
			primaryArrival = nil,
			diningSeat = nil,
			diningArrival = nil,
			diningReservation = nil,
			primaryReleased = false,
			primaryOccupantIndex = nil,
			primaryOccupantCount = nil,
			persistentBubbleShown = false,
		} :: any,
		Pipeline
	)
	self:defer(function()
		self:clearRestPose()
		self:leavePrimarySeat()
		self:leaveDiningSeat()
		self:releaseDiningReservation()
		self:releasePrimaryReservation()
		self:clearPersistentBubble()
	end)
	self.primaryOccupantIndex, self.primaryOccupantCount =
		self:_computeOccupantMetadata(assignment.StationRecord, assignment.ItemSpec)
	return self
end

function Pipeline:defer(callback: () -> ())
	self.cleanupTasks[#self.cleanupTasks + 1] = callback
end

function Pipeline:clearPersistentBubble()
	if self.persistentBubbleShown then
		ResidentChat.ClearPersistentAction(self.assignment.ResidentState)
		self.persistentBubbleShown = false
	end
end

function Pipeline:_computeOccupantMetadata(
	record: StationManager.StationRecord?,
	itemSpec: { [string]: any }?
): (number?, number?)
	local occupantIndex: number? = nil
	local occupantCount: number? = nil
	if record then
		local residents = record.Residents
		if typeof(residents) == "table" then
			occupantCount = #residents
			local found = table.find(residents, self.assignment.ResidentName)
			if found then
				occupantIndex = found
			end
		end
	end
	if itemSpec then
		local maxOccupancy = itemSpec.maxOccupancy
		if typeof(maxOccupancy) == "number" and maxOccupancy > 0 then
			if not occupantCount or occupantCount < maxOccupancy then
				occupantCount = maxOccupancy
			end
		end
	end
	return occupantIndex, occupantCount
end

function Pipeline:setActionLabel(label: string?)
	if label and label ~= "" then
		self.actionLabel = label
	else
		self.actionLabel = BehaviorConfig.getStationLabel(self.assignment.StationType)
	end
end

function Pipeline:getActionLabel(): string
	return self.actionLabel
end

function Pipeline:getStationName(): string?
	return self.stationName
end

function Pipeline:trace(message: string, payload: { [string]: any }?)
	ResidentDebug.Trace(ACTION_CHANNEL, message, payload or {
		Resident = self.assignment.ResidentName,
		StationType = self.assignment.StationType,
		StationId = self.assignment.StationId,
	})
end

function Pipeline:showInterrupt(reason: string, metadata: { [string]: any }?)
	local payload = (metadata or {}) :: { [string]: any }
	payload.StationType = payload.StationType or self.assignment.StationType
	payload.StationId = payload.StationId or self.assignment.StationId
	payload.StationName = payload.StationName or self.stationName
	payload.NeedName = payload.NeedName or self.assignment.NeedName
	payload.ActionName = payload.ActionName or self.actionLabel
	payload.Player = payload.Player or self.assignment.Player
	ResidentChat.ShowInterrupt(self.assignment.ResidentState, reason, payload)
end

function Pipeline:releasePrimaryReservation()
	if self.primaryReleased then
		return
	end
	self.primaryReleased = true
	local record = self.assignment.StationRecord
	if record then
		StationManager.releaseStationOccupancy(record, self.assignment.ResidentName)
	end
end

local function reserveAuxStation(stationRecord: StationManager.StationRecord, residentName: string)
	if not table.find(stationRecord.Residents, residentName) then
		table.insert(stationRecord.Residents, residentName)
	end
	stationRecord.Occupied = true
end

local function releaseAuxStation(stationRecord: StationManager.StationRecord?, residentName: string)
	if not stationRecord then
		return
	end
	StationManager.releaseStationOccupancy(stationRecord, residentName)
end

local function selectDiningStation(player: Player?, residentName: string): DiningReservation?
	if not player then
		return nil
	end
	for _, preference in ipairs(DINING_STATION_PREFERENCES) do
		local stationType = preference.StationType
		local requiredTag = preference.RequiredTag
		local filter
		if requiredTag then
			filter = function(
				_id: string,
				_station: StationManager.StationRecord,
				itemSpec: { [string]: any }?,
				_model: Model?
			)
				return itemHasTag(itemSpec, requiredTag)
			end
		end
		local uniqueId, stationRecordRaw, itemSpec, modelRaw =
			StationManager.findAvailableStation(player, stationType, residentName, nil, filter)
		if uniqueId and stationRecordRaw and modelRaw then
			local stationRecord: StationManager.StationRecord = stationRecordRaw
			local model: Model = modelRaw
			local reservation: DiningReservation = {
				StationType = stationType,
				UniqueId = uniqueId,
				StationRecord = stationRecord,
				ItemSpec = itemSpec,
				Model = model,
			}
			return reservation
		end
	end
	return nil
end

function Pipeline:ensureDiningReservation(): DiningReservation?
	if self.diningReservation then
		return self.diningReservation
	end
	local reservationOptional = selectDiningStation(self.assignment.Player, self.assignment.ResidentName)
	if not reservationOptional then
		return nil
	end
	local reservation: DiningReservation = reservationOptional
	reserveAuxStation(reservation.StationRecord, self.assignment.ResidentName)
	self.diningReservation = reservation
	self:defer(function()
		releaseAuxStation(reservation.StationRecord, self.assignment.ResidentName)
	end)
	return reservation
end

function Pipeline:releaseDiningReservation()
	local reservation = self.diningReservation
	if not reservation then
		return
	end
	releaseAuxStation(reservation.StationRecord, self.assignment.ResidentName)
	self.diningReservation = nil :: any
	self.diningArrival = nil
	self.diningSeat = nil
end

function Pipeline:leavePrimarySeat()
	if self.primarySeat then
		ResidentMovement.LeaveSeat(self.assignment.ResidentState, self.primarySeat)
		self.primarySeat = nil
	end
end

function Pipeline:leaveDiningSeat()
	if self.diningSeat then
		ResidentMovement.LeaveSeat(self.assignment.ResidentState, self.diningSeat)
		self.diningSeat = nil
	end
end

function Pipeline:clearRestPose()
	if self.restPoseApplied then
		ResidentMovement.ClearRestPose(self.assignment.ResidentState)
		self.restPoseApplied = false
		self.restPoseMode = nil
		self.restPoseModel = nil
	end
end

function Pipeline:moveToModel(model: Model?, options: MovementOptions): (boolean, any?)
	if not model then
		return false, nil
	end
	local occupantIndex = options.OccupantIndex
	local occupantCount = options.OccupantCount
	if not occupantIndex or not occupantCount then
		occupantIndex, occupantCount = self:_computeOccupantMetadata(options.StationRecord, options.ItemSpec)
	end
	local arrived, arrival = ResidentMovement.GoToStation(self.assignment.ResidentState, model, {
		CancelToken = self.context.CancelToken,
		ApproachDistance = options.ApproachDistance,
		TimeoutSeconds = options.MoveTimeoutSeconds,
		EnsureSeat = options.UseSeat,
		OccupantIndex = occupantIndex,
		OccupantCount = occupantCount,
		ResidentName = self.assignment.ResidentName,
	})
	if not arrived then
		return false, arrival
	end
	if arrival then
		ResidentMovement.FaceStation(self.assignment.ResidentState, arrival.EntryCFrame)
		if options.RestPoseMode and options.AllowRestPose ~= false then
			if options.RestPoseEligible ~= false then
				if
					ResidentMovement.ApplyRestPose(self.assignment.ResidentState, {
						Mode = options.RestPoseMode,
						StationModel = model,
						EntryCFrame = arrival.EntryCFrame,
						EntryAttachment = arrival.EntryAttachment,
					})
				then
					self.restPoseApplied = true
					self.restPoseMode = options.RestPoseMode
					self.restPoseModel = model
				end
			end
		end
		if options.UseSeat and arrival.Seat then
			ResidentMovement.SeatResident(self.assignment.ResidentState, arrival.Seat, self.context.CancelToken)
			if options.IsDining then
				self.diningSeat = arrival.Seat
			else
				self.primarySeat = arrival.Seat
			end
		end
	end
	return true, arrival
end

function Pipeline:moveToPrimary(behavior: Behavior, opts: MovementOptions?): (boolean, any?)
	local options = table.clone(opts or {}) :: MovementOptions
	options.ApproachDistance = options.ApproachDistance or behavior.ApproachDistance
	options.MoveTimeoutSeconds = options.MoveTimeoutSeconds or behavior.MoveTimeoutSeconds
	options.UseSeat = if options.UseSeat ~= nil then options.UseSeat else behavior.UseSeat
	options.StationRecord = options.StationRecord or self.assignment.StationRecord
	options.ItemSpec = options.ItemSpec or self.assignment.ItemSpec
	local success, arrival = self:moveToModel(self.assignment.StationModel, options)
	if success then
		self.primaryArrival = arrival
	end
	return success, arrival
end

function Pipeline:moveToDining(
	reservation: DiningReservation,
	behavior: Behavior,
	opts: MovementOptions?
): (boolean, any?)
	local options = table.clone(opts or {}) :: MovementOptions
	options.ApproachDistance = options.ApproachDistance or behavior.ApproachDistance
	options.MoveTimeoutSeconds = options.MoveTimeoutSeconds or behavior.MoveTimeoutSeconds
	options.UseSeat = if options.UseSeat ~= nil then options.UseSeat else behavior.UseSeat
	options.StationRecord = reservation.StationRecord
	options.ItemSpec = reservation.ItemSpec
	options.IsDining = true
	local success, arrival = self:moveToModel(reservation.Model, options)
	if success then
		self.diningArrival = arrival
	end
	return success, arrival
end

function Pipeline:runNeedEffects(behavior: Behavior, metadata: { [string]: any }): (boolean, string?, any?)
	-- Handle persistent action bubble
	if not self.persistentBubbleShown then
		local emoji = behavior.ActionEmoji
		if emoji and emoji ~= "" then
			ResidentChat.ShowPersistentAction(self.assignment.ResidentState, emoji)
			self.persistentBubbleShown = true
		end
	end

	if not behavior.ChatIntervalSeconds then
		local initialLine = ResidentChat.SelectChatText(self.assignment.ResidentState, behavior.ChatPhrases, nil)
		if initialLine then
			ResidentChat.ShowAction(self.assignment.ResidentState, initialLine)
		end
	end

	self:trace("Running effects", {
		Resident = self.assignment.ResidentName,
		StationType = metadata.StationType or self.assignment.StationType,
		Behavior = behavior,
	})

	local runOk, runResult, runReason = pcall(function()
		return NeedEffects.Run(self.assignment.ResidentState, self.context.CancelToken, behavior, metadata)
	end)
	if not runOk then
		return false, nil, runResult
	end
	if runResult == true then
		return true, nil, nil
	end
	local abortReason = runReason
	if not abortReason or abortReason == "" then
		local token = self.context.CancelToken
		if token and token.Cancelled then
			abortReason = token.Reason or "Cancelled"
		else
			abortReason = "Interrupted"
		end
	end
	return false, abortReason, nil
end

function Pipeline:formatAbortError(reason: string?): string
	return NeedEffects.FormatAbortError(reason)
end

function Pipeline:parseAbortReason(message: string?): string?
	return NeedEffects.ParseAbortReason(message)
end

function Pipeline:getNeedBounds()
	return NeedConfig.Needs
end

function Pipeline:cleanup()
	local tasks = self.cleanupTasks
	self.cleanupTasks = {}
	for index = #tasks, 1, -1 do
		tasks[index]()
	end
end

return Pipeline
