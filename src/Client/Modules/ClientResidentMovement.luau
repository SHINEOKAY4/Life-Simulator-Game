--!strict
-- Client/Modules/ClientResidentMovement.luau
-- Pathfinding and interaction helpers for steering residents toward station objects.

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")

local DEFAULT_TIMEOUT = 25
local ARRIVAL_TOLERANCE = 2
local WAYPOINT_TIMEOUT = 6
local WALK_SPEED = 8
local RUN_SPEED = 16
local RUN_DISTANCE_THRESHOLD = 40

export type CancelToken = { Cancelled: boolean, Reason: string? }

type MoveOptions = {
	CancelToken: CancelToken?,
	ApproachDistance: number?,
	TimeoutSeconds: number?,
	EnsureSeat: boolean?,
	OccupantIndex: number?,
	OccupantCount: number?,
	ResidentName: string?,
	DebugName: string?,
}

type StationArrival = {
	EntryCFrame: CFrame,
	Seat: Seat?,
	EntryAttachment: Attachment?,
}

local ClientResidentMovement = {}

local restPoseState = setmetatable({}, { __mode = "k" })

type RestPoseRecord = {
	AutoRotate: boolean,
	PlatformStand: boolean,
	WalkSpeed: number?,
	JumpPower: number?,
	JumpHeight: number?,
	UseJumpPower: boolean?,
	RootAnchored: boolean,
	StandCFrame: CFrame?,
	RootCFrame: CFrame?,
}

type RestPoseOptions = {
	Mode: string?,
	EntryCFrame: CFrame,
	EntryAttachment: Attachment?,
	StationModel: Model?,
}

local function getNumberAttribute(source: Instance?, attributeName: string): number?
	if not source then
		return nil
	end
	local value = source:GetAttribute(attributeName)
	if typeof(value) == "number" then
		return value
	end
	return nil
end

local function getVectorAttribute(source: Instance?, attributeName: string): Vector3?
	if not source then
		return nil
	end
	local value = source:GetAttribute(attributeName)
	if typeof(value) == "Vector3" then
		return value
	end
	return nil
end

local PATH_VARIANTS = {
	{
		AgentHeight = 4,
		AgentRadius = 2,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
		Costs = {
			Walls = math.huge,
		},
	},
	{
		AgentHeight = 4,
		AgentRadius = 1.4,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 3,
		Costs = {
			Walls = math.huge,
		},
	},
}

local function getHumanoid(model: Model?): Humanoid?
	if not model then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

local function getHumanoidRootPart(model: Model?): BasePart?
	if not model then
		return nil
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		return root
	end
	if model.PrimaryPart then
		return model.PrimaryPart
	end
	return nil
end

local function stopHumanoid(humanoid: Humanoid)
	humanoid:Move(Vector3.zero)
end

local function shouldRunToTarget(origin: Vector3, destination: Vector3): boolean
	local distance = (origin - destination).Magnitude
	if distance < RUN_DISTANCE_THRESHOLD then
		return false
	end
	return true
end

local function pickTravelSpeed(origin: Vector3, destination: Vector3): number
	if shouldRunToTarget(origin, destination) then
		return RUN_SPEED
	end
	return WALK_SPEED
end

local function computePathWithVariants(origin: Vector3, destination: Vector3): (Path?, { [number]: { [string]: any } })
	local attemptsMeta = table.create(#PATH_VARIANTS)
	local metaIndex = 0

	for _, params in ipairs(PATH_VARIANTS) do
		local path = PathfindingService:CreatePath(params)
		local ok, computeError = pcall(path.ComputeAsync, path, origin, destination)
		local statusName = if ok then path.Status.Name else "ComputeError"
		local waypointsCount = 0
		if ok and path.Status == Enum.PathStatus.Success then
			local waypoints = path:GetWaypoints()
			waypointsCount = #waypoints
		end
		metaIndex += 1
		attemptsMeta[metaIndex] = {
			AgentHeight = params.AgentHeight,
			AgentRadius = params.AgentRadius,
			WaypointSpacing = params.WaypointSpacing,
			AgentCanJump = params.AgentCanJump,
			AgentCanClimb = params.AgentCanClimb,
			Status = statusName,
			Error = if ok then nil else computeError,
			Waypoints = waypointsCount,
		}
		if ok and path.Status == Enum.PathStatus.Success then
			return path, attemptsMeta
		end
	end
	return nil, attemptsMeta
end

local function waitForMoveFinished(
	humanoid: Humanoid,
	targetPos: Vector3,
	token: CancelToken?,
	timeoutSeconds: number?
): boolean
	local root = humanoid.RootPart
	if root and (root.Position - targetPos).Magnitude <= ARRIVAL_TOLERANCE then
		return true
	end
	local finished = false
	local reached = false
	local function withinTolerance(): boolean
		local currentRoot = humanoid.RootPart
		if not currentRoot then
			return false
		end
		return (currentRoot.Position - targetPos).Magnitude <= ARRIVAL_TOLERANCE
	end
	local connection: RBXScriptConnection? = nil
	connection = humanoid.MoveToFinished:Connect(function(reach)
		finished = true
		reached = reach
	end)
	humanoid:MoveTo(targetPos)
	local startTime = os.clock()
	while not finished do
		if withinTolerance() then
			reached = true
			finished = true
			break
		end
		if token and token.Cancelled then
			break
		end
		if timeoutSeconds and timeoutSeconds > 0 then
			if os.clock() - startTime > timeoutSeconds then
				break
			end
		end
		RunService.Heartbeat:Wait()
	end
	if connection then
		connection:Disconnect()
	end
	if not reached and withinTolerance() then
		reached = true
		finished = true
	end
	return finished and reached
end

local function followWaypoints(humanoid: Humanoid, token: CancelToken?, waypoints: { PathWaypoint }): boolean
	for _, waypoint in ipairs(waypoints) do
		if token and token.Cancelled then
			return false
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		local ok = waitForMoveFinished(humanoid, waypoint.Position, token, WAYPOINT_TIMEOUT)
		if not ok then
			return false
		end
	end
	return true
end

local function moveToTarget(
	model: Model,
	targetPosition: Vector3,
	cancelToken: CancelToken?,
	timeoutSeconds: number?
): boolean
	local humanoid = getHumanoid(model)
	local root = getHumanoidRootPart(model)
	if not humanoid or not root then
		return false
	end
	ClientResidentMovement.LeaveSeat(model, nil)

	local originalSpeed = humanoid.WalkSpeed
	local desiredSpeed = pickTravelSpeed(root.Position, targetPosition)
	if typeof(humanoid.WalkSpeed) == "number" and desiredSpeed ~= humanoid.WalkSpeed then
		humanoid.WalkSpeed = desiredSpeed
	end

	local path, _attemptsMeta = computePathWithVariants(root.Position, targetPosition)
	local reached = false
	if path then
		local waypoints = path:GetWaypoints()
		reached = followWaypoints(humanoid, cancelToken, waypoints)
	else
		local timeoutBudget = timeoutSeconds and math.max(timeoutSeconds, 1) or DEFAULT_TIMEOUT
		reached = waitForMoveFinished(humanoid, targetPosition, cancelToken, timeoutBudget)
	end
	stopHumanoid(humanoid)
	if humanoid.Parent and typeof(originalSpeed) == "number" and humanoid.WalkSpeed ~= originalSpeed then
		humanoid.WalkSpeed = originalSpeed
	end

	return reached
end

local ENTRY_ATTACHMENT_PATTERNS = {
	"^InteractionPoint(%d*)$",
	"^ResidentInteraction(%d*)$",
	"^ResidentEntry(%d*)$",
}

local FRONT_AXIS_MAP = {
	["-Z"] = Vector3.new(0, 0, -1),
	["+Z"] = Vector3.new(0, 0, 1),
	["+X"] = Vector3.new(1, 0, 0),
	["-X"] = Vector3.new(-1, 0, 0),
	["+Y"] = Vector3.new(0, 1, 0),
	["-Y"] = Vector3.new(0, -1, 0),
}

type EntryAttachmentInfo = {
	Attachment: Attachment,
	Index: number?,
	Order: number,
}

type SeatInfo = {
	Seat: Seat,
	Index: number?,
	Order: number,
}

local function parseAttachmentIndex(attachment: Attachment): number?
	local attr = attachment:GetAttribute("ResidentEntryIndex")
	if typeof(attr) == "number" then
		local rounded = math.floor(attr + 0.5)
		if rounded >= 1 then
			return rounded
		end
	end
	for _, pattern in ipairs(ENTRY_ATTACHMENT_PATTERNS) do
		local digits = string.match(attachment.Name, pattern)
		if digits ~= nil then
			if #digits == 0 then
				return nil
			end
			local indexValue = tonumber(digits)
			if indexValue and indexValue >= 1 then
				return indexValue
			end
		end
	end
	return nil
end

local function isResidentEntryAttachment(attachment: Attachment): boolean
	if attachment:GetAttribute("ResidentEntry") == true then
		return true
	end
	if attachment:GetAttribute("ResidentEntryIndex") ~= nil then
		return true
	end
	for _, pattern in ipairs(ENTRY_ATTACHMENT_PATTERNS) do
		if string.match(attachment.Name, pattern) ~= nil then
			return true
		end
	end
	return false
end

local function collectResidentEntryAttachments(model: Model): { EntryAttachmentInfo }
	local list: { EntryAttachmentInfo } = {}
	local order = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Attachment") and isResidentEntryAttachment(descendant) then
			order += 1
			local index = parseAttachmentIndex(descendant)
			list[#list + 1] = {
				Attachment = descendant,
				Index = index,
				Order = order,
			}
		end
	end
	table.sort(list, function(a, b)
		local aIndex = a.Index
		local bIndex = b.Index
		if aIndex and bIndex then
			if aIndex == bIndex then
				return a.Order < b.Order
			end
			return aIndex < bIndex
		elseif aIndex then
			return true
		elseif bIndex then
			return false
		end
		return a.Order < b.Order
	end)
	return list
end

local SEAT_INDEX_PATTERNS = {
	"^Seat(%d+)$",
	"^Seat_(%d+)$",
	"^ResidentSeat(%d+)$",
	"^Chair(%d+)$",
}

local function parseSeatIndex(seat: Seat): number?
	local attr = seat:GetAttribute("ResidentSeatIndex")
	if typeof(attr) == "number" then
		local rounded = math.floor(attr + 0.5)
		if rounded >= 1 then
			return rounded
		end
	end
	local sharedAttr = seat:GetAttribute("ResidentEntryIndex")
	if typeof(sharedAttr) == "number" then
		local rounded = math.floor(sharedAttr + 0.5)
		if rounded >= 1 then
			return rounded
		end
	end
	for _, pattern in ipairs(SEAT_INDEX_PATTERNS) do
		local digits = string.match(seat.Name, pattern)
		if digits ~= nil and #digits > 0 then
			local indexValue = tonumber(digits)
			if indexValue and indexValue >= 1 then
				return indexValue
			end
		end
	end
	return nil
end

local function collectStationSeats(model: Model): { SeatInfo }
	local list: { SeatInfo } = {}
	local order = 0
	for _, descendant in ipairs(model:GetDescendants()) do
		if descendant:IsA("Seat") then
			order += 1
			list[#list + 1] = {
				Seat = descendant,
				Index = parseSeatIndex(descendant),
				Order = order,
			}
		end
	end
	table.sort(list, function(a, b)
		local aIndex = a.Index
		local bIndex = b.Index
		if aIndex and bIndex then
			if aIndex == bIndex then
				return a.Order < b.Order
			end
			return aIndex < bIndex
		elseif aIndex then
			return true
		elseif bIndex then
			return false
		end
		return a.Order < b.Order
	end)
	return list
end

local function isSeatAvailableToResident(seat: Seat, residentName: string?): boolean
	local occupant = seat.Occupant
	if not occupant then
		return true
	end
	local model = occupant.Parent
	if model == nil then
		return true
	end
	if residentName and model:IsA("Model") and model.Name == residentName then
		return true
	end
	return false
end

local function selectSeatForOccupant(
	seats: { SeatInfo },
	occupantIndex: number?,
	occupantCount: number?,
	residentName: string?
): SeatInfo?
	if #seats == 0 then
		return nil
	end
	local slotIndex = nil
	if typeof(occupantIndex) == "number" and occupantIndex >= 1 then
		slotIndex = math.floor(occupantIndex)
	end
	local totalSlots = if typeof(occupantCount) == "number" and occupantCount >= 1
		then math.floor(occupantCount)
		else nil
	if slotIndex then
		local fallback: SeatInfo? = nil
		for _, info in ipairs(seats) do
			if info.Index == slotIndex then
				if isSeatAvailableToResident(info.Seat, residentName) then
					return info
				end
				fallback = fallback or info
			end
		end
		if totalSlots and totalSlots <= #seats then
			local wrapIndex = ((slotIndex - 1) % totalSlots) + 1
			local candidate = seats[wrapIndex]
			if candidate then
				if isSeatAvailableToResident(candidate.Seat, residentName) then
					return candidate
				end
				fallback = fallback or candidate
			end
		end
		if fallback then
			return fallback
		end
		local wrapped = ((slotIndex - 1) % #seats) + 1
		return seats[wrapped]
	end
	for _, info in ipairs(seats) do
		if isSeatAvailableToResident(info.Seat, residentName) then
			return info
		end
	end
	return seats[1]
end

local AXIS_SPECIFIER_CACHE = {} :: { [string]: string? }

local function normalizeAxisSpecifier(value: string): string?
	local cached = AXIS_SPECIFIER_CACHE[value]
	if cached ~= nil then
		return cached
	end

	local trimmed = value:gsub("%s+", ""):upper()
	trimmed = trimmed:gsub("PLUS", "+"):gsub("POSITIVE", "+"):gsub("MINUS", "-"):gsub("NEGATIVE", "-")

	if trimmed == "X" or trimmed == "Y" or trimmed == "Z" then
		trimmed = "+" .. trimmed
	elseif trimmed == "FRONT" then
		trimmed = "-Z"
	elseif trimmed == "BACK" then
		trimmed = "+Z"
	elseif trimmed == "LEFT" then
		trimmed = "-X"
	elseif trimmed == "RIGHT" then
		trimmed = "+X"
	end

	local result = FRONT_AXIS_MAP[trimmed] and trimmed or nil
	AXIS_SPECIFIER_CACHE[value] = result
	return result
end

local function resolveFrontVector(stationModel: Model, bboxCFrame: CFrame): (Vector3, Vector3)
	local localFront = Vector3.new(0, 0, -1)
	local axisAttr = stationModel:GetAttribute("ResidentFrontAxis")
	if typeof(axisAttr) == "string" then
		local normalizedKey = normalizeAxisSpecifier(axisAttr)
		if normalizedKey then
			local mapped = FRONT_AXIS_MAP[normalizedKey]
			if mapped then
				localFront = mapped.Unit
			end
		end
	end
	local vectorAttr = stationModel:GetAttribute("ResidentFrontVector")
	if typeof(vectorAttr) == "Vector3" and vectorAttr.Magnitude > 0 then
		localFront = vectorAttr.Unit
	end
	local worldFront = bboxCFrame:VectorToWorldSpace(localFront)
	if worldFront.Magnitude > 0 then
		worldFront = worldFront.Unit
	else
		worldFront = bboxCFrame.LookVector
	end
	return localFront, worldFront
end

local function pickAttachmentForSlot(
	attachments: { EntryAttachmentInfo },
	preferredIndex: number?,
	fallbackIndex: number?
): Attachment?
	if #attachments == 0 then
		return nil
	end
	local function findByIndex(searched: number?): Attachment?
		if not searched then
			return nil
		end
		for _, info in ipairs(attachments) do
			if info.Index == searched then
				return info.Attachment
			end
		end
		return nil
	end
	local attachment = findByIndex(preferredIndex)
	if attachment then
		return attachment
	end
	attachment = findByIndex(fallbackIndex)
	if attachment then
		return attachment
	end
	for _, info in ipairs(attachments) do
		if info.Index == 1 then
			return info.Attachment
		end
	end
	return attachments[1].Attachment
end

local function computeEntryInfo(
	stationModel: Model,
	approachDistance: number?,
	moveOpts: MoveOptions?
): (CFrame, Attachment?, Seat?)
	local occupantIndex = moveOpts and moveOpts.OccupantIndex or nil
	local occupantCount = moveOpts and moveOpts.OccupantCount or nil
	local residentName = moveOpts and moveOpts.ResidentName or nil

	local attachments = collectResidentEntryAttachments(stationModel)
	local seats = collectStationSeats(stationModel)
	local seatInfo = if #seats > 0
		then selectSeatForOccupant(seats, occupantIndex, occupantCount, residentName)
		else nil

	local desiredAttachment = nil :: Attachment?
	if #attachments > 0 then
		local preferredIndex = if seatInfo and seatInfo.Index then seatInfo.Index else occupantIndex
		desiredAttachment = pickAttachmentForSlot(attachments, preferredIndex, occupantIndex)
	end

	if seatInfo then
		local seat = seatInfo.Seat
		local seatAttachment = desiredAttachment
		if seatAttachment then
			local attachmentOffsetAttr = seatAttachment:GetAttribute("ResidentEntryOffset")
			local stationOffsetAttr = stationModel:GetAttribute("ResidentEntryOffset")
			local offsetMagnitude = nil
			if typeof(attachmentOffsetAttr) == "number" then
				offsetMagnitude = attachmentOffsetAttr
			elseif typeof(stationOffsetAttr) == "number" then
				offsetMagnitude = stationOffsetAttr
			end
			if offsetMagnitude and offsetMagnitude ~= 0 then
				return seatAttachment.WorldCFrame * CFrame.new(0, 0, -offsetMagnitude), seatAttachment, seat
			end
			return seatAttachment.WorldCFrame, seatAttachment, seat
		end
		local approach = if approachDistance then math.max(approachDistance, 0) else 3
		local seatCFrame = seat.CFrame
		local seatLook = seatCFrame.LookVector
		if seatLook.Magnitude == 0 then
			seatLook = Vector3.new(0, 0, -1)
		else
			seatLook = seatLook.Unit
		end
		local seatUp = seatCFrame.UpVector
		if seatUp.Magnitude == 0 then
			seatUp = Vector3.new(0, 1, 0)
		else
			seatUp = seatUp.Unit
		end
		local seatDepth = seat.Size.Z
		local offsetDistance = approach + seatDepth * 0.5
		local entryPosition = seatCFrame.Position - seatLook * offsetDistance
		local seatBottom = seatCFrame.Position - seatUp * (seat.Size.Y * 0.5)
		entryPosition = Vector3.new(entryPosition.X, seatBottom.Y, entryPosition.Z)
		local entryCFrame = CFrame.new(entryPosition, seatCFrame.Position)
		return entryCFrame, nil, seat
	end

	if desiredAttachment then
		local attachmentOffsetAttr = desiredAttachment:GetAttribute("ResidentEntryOffset")
		local stationOffsetAttr = stationModel:GetAttribute("ResidentEntryOffset")
		local offsetMagnitude = nil
		if typeof(attachmentOffsetAttr) == "number" then
			offsetMagnitude = attachmentOffsetAttr
		elseif typeof(stationOffsetAttr) == "number" then
			offsetMagnitude = stationOffsetAttr
		end
		if offsetMagnitude and offsetMagnitude ~= 0 then
			return desiredAttachment.WorldCFrame * CFrame.new(0, 0, -offsetMagnitude), desiredAttachment, nil
		end
		return desiredAttachment.WorldCFrame, desiredAttachment, nil
	end

	local bboxCFrame, bboxSize = stationModel:GetBoundingBox()
	local localFront, worldFront = resolveFrontVector(stationModel, bboxCFrame)
	local approach = if approachDistance then math.max(approachDistance, 0) else 3
	local halfSize = bboxSize * 0.5
	local frontExtent = math.abs(localFront.X) * halfSize.X
		+ math.abs(localFront.Y) * halfSize.Y
		+ math.abs(localFront.Z) * halfSize.Z
	local entryOffset = frontExtent + approach
	local entryPosition = bboxCFrame.Position - worldFront * entryOffset
	local heightAttr = stationModel:GetAttribute("ResidentEntryHeight")
	if typeof(heightAttr) == "number" and heightAttr ~= 0 then
		entryPosition += Vector3.new(0, heightAttr, 0)
	end
	return CFrame.new(entryPosition, bboxCFrame.Position), nil, nil
end

local function findSeat(model: Model): Seat?
	return model:FindFirstChildWhichIsA("Seat", true)
end

local AUTO_SEAT_NAME = "ResidentAutoSeat"
local AUTO_SEAT_SIZE = Vector3.new(2, 1, 2)

local function getAutoSeatName(occupantIndex: number?): string
	if typeof(occupantIndex) == "number" and occupantIndex >= 1 then
		return string.format("%s%d", AUTO_SEAT_NAME, math.floor(occupantIndex))
	end
	return AUTO_SEAT_NAME
end

local function computeSeatCFrame(entryCFrame: CFrame, entryAttachment: Attachment?): CFrame
	if entryAttachment then
		local attachmentSeatOffset = entryAttachment:GetAttribute("ResidentSeatOffset")
		if typeof(attachmentSeatOffset) == "number" and attachmentSeatOffset ~= 0 then
			return entryAttachment.WorldCFrame * CFrame.new(0, -AUTO_SEAT_SIZE.Y * 0.5, -attachmentSeatOffset)
		end
		return entryAttachment.WorldCFrame * CFrame.new(0, -AUTO_SEAT_SIZE.Y * 0.5, 0)
	end
	return entryCFrame * CFrame.new(0, AUTO_SEAT_SIZE.Y * 0.5, 0)
end

local function ensureAutoSeat(
	stationModel: Model,
	entryCFrame: CFrame,
	entryAttachment: Attachment?,
	occupantIndex: number?
): Seat
	local autoSeatName = getAutoSeatName(occupantIndex)
	local seatInstance = stationModel:FindFirstChild(autoSeatName)
	local autoSeat: Seat
	if seatInstance and seatInstance:IsA("Seat") then
		autoSeat = seatInstance
	else
		autoSeat = Instance.new("Seat")
		autoSeat.Name = autoSeatName
		autoSeat.Size = AUTO_SEAT_SIZE
		autoSeat.Transparency = 1
		autoSeat.Anchored = true
		autoSeat.CanCollide = false
		autoSeat.CanTouch = false
		autoSeat.CanQuery = false
		autoSeat.TopSurface = Enum.SurfaceType.Smooth
		autoSeat.BottomSurface = Enum.SurfaceType.Smooth
		autoSeat.Parent = stationModel
	end
	autoSeat.Disabled = false
	autoSeat.CFrame = computeSeatCFrame(entryCFrame, entryAttachment)
	return autoSeat
end

local function ensureSeatForOccupant(
	seat: Seat?,
	stationModel: Model,
	entryCFrame: CFrame,
	entryAttachment: Attachment?,
	occupantIndex: number?
): Seat?
	if seat then
		seat.Disabled = false
		return seat
	end
	return ensureAutoSeat(stationModel, entryCFrame, entryAttachment, occupantIndex)
end

function ClientResidentMovement.ApplyRestPose(model: Model, options: RestPoseOptions): boolean
	local humanoid = getHumanoid(model)
	if not humanoid then
		return false
	end
	local root = getHumanoidRootPart(model)
	if not root then
		return false
	end
	local baseCFrame = options.EntryCFrame
	local entryAttachment = options.EntryAttachment
	if entryAttachment then
		baseCFrame = entryAttachment.WorldCFrame
	end
	if not baseCFrame then
		return false
	end
	local record = restPoseState[model]
	if not record then
		record = {
			AutoRotate = humanoid.AutoRotate,
			PlatformStand = humanoid.PlatformStand,
			WalkSpeed = if typeof(humanoid.WalkSpeed) == "number" then humanoid.WalkSpeed else nil,
			JumpPower = if typeof(humanoid.JumpPower) == "number" then humanoid.JumpPower else nil,
			JumpHeight = if typeof(humanoid.JumpHeight) == "number" then humanoid.JumpHeight else nil,
			UseJumpPower = humanoid.UseJumpPower,
			RootAnchored = root.Anchored,
			StandCFrame = baseCFrame,
			RootCFrame = root.CFrame,
		}
		restPoseState[model] = record
	else
		record.StandCFrame = baseCFrame
		record.RootCFrame = root.CFrame
	end
	local stationModel = options.StationModel
	local pitch = getNumberAttribute(entryAttachment, "ResidentRestPitch")
	if pitch == nil then
		pitch = getNumberAttribute(stationModel, "ResidentRestPitch")
	end
	local yaw = getNumberAttribute(entryAttachment, "ResidentRestYaw")
	if yaw == nil then
		yaw = getNumberAttribute(stationModel, "ResidentRestYaw")
	end
	local roll = getNumberAttribute(entryAttachment, "ResidentRestRoll")
	if roll == nil then
		roll = getNumberAttribute(stationModel, "ResidentRestRoll")
	end
	local heightOffset = getNumberAttribute(entryAttachment, "ResidentRestHeight")
	if heightOffset == nil then
		heightOffset = getNumberAttribute(stationModel, "ResidentRestHeight")
	end
	local restOffset = getVectorAttribute(entryAttachment, "ResidentRestOffset")
	if restOffset == nil then
		restOffset = getVectorAttribute(stationModel, "ResidentRestOffset")
	end
	local mode = options.Mode
	local baseLook = baseCFrame.LookVector
	local baseUp = baseCFrame.UpVector
	if mode == "Ground" then
		local flattenedLook = Vector3.new(baseLook.X, 0, baseLook.Z)
		if flattenedLook.Magnitude > 0 then
			baseLook = flattenedLook.Unit
		else
			baseLook = Vector3.new(0, 0, -1)
		end
		baseUp = Vector3.new(0, 1, 0)
	else
		if baseLook.Magnitude == 0 then
			baseLook = Vector3.new(0, 0, -1)
		end
		if baseUp.Magnitude == 0 then
			baseUp = Vector3.new(0, 1, 0)
		end
	end
	local defaultPitch = -90
	if mode == "Ground" or mode == "Sleep" or mode == "DaySleep" then
		defaultPitch = 90
	end
	local pitchValue: number = if pitch ~= nil then pitch else defaultPitch
	local yawValue: number = if yaw ~= nil then yaw else 0
	local rollValue: number = if roll ~= nil then roll else 0
	local heightOffsetValue: number = if heightOffset ~= nil then heightOffset else 0
	local restOffsetValue: Vector3 = if restOffset ~= nil then restOffset else Vector3.new()
	local baseRotation = CFrame.lookAt(Vector3.new(), baseLook, baseUp)
	local rotationAdjust = CFrame.Angles(math.rad(pitchValue), math.rad(yawValue), math.rad(rollValue))
	local finalRotation = baseRotation * rotationAdjust
	local baseHeight = root.Size.Y * 0.5
	local verticalOffset = baseHeight + heightOffsetValue
	local basePosition = baseCFrame.Position + baseCFrame.UpVector * verticalOffset
	local finalPosition = basePosition + finalRotation:VectorToWorldSpace(restOffsetValue)
	if mode == "Ground" then
		-- Snap collapse poses to nearby floor so residents do not float mid-air
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local parentModel = root.Parent
		if parentModel then
			rayParams.FilterDescendantsInstances = { parentModel }
		end
		local rayOrigin = Vector3.new(finalPosition.X, finalPosition.Y + 8, finalPosition.Z)
		local rayDirection = Vector3.new(0, -80, 0)
		local hit = workspace:Raycast(rayOrigin, rayDirection, rayParams)
		if hit then
			local verticalHalf = 0.5
				* (
					math.abs(finalRotation.RightVector.Y) * root.Size.X
					+ math.abs(finalRotation.UpVector.Y) * root.Size.Y
					+ math.abs(finalRotation.LookVector.Y) * root.Size.Z
				)
			local bottomY = finalPosition.Y - verticalHalf
			finalPosition += Vector3.new(0, hit.Position.Y - bottomY, 0)
		end
	end
	local finalCFrame = CFrame.new(finalPosition) * finalRotation
	root.AssemblyLinearVelocity = Vector3.new()
	root.AssemblyAngularVelocity = Vector3.new()
	root.CFrame = finalCFrame
	root.Anchored = true
	humanoid:Move(Vector3.zero)
	humanoid.Sit = false
	humanoid.Jump = false
	humanoid.AutoRotate = false
	humanoid.PlatformStand = true
	humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	if typeof(humanoid.WalkSpeed) == "number" then
		humanoid.WalkSpeed = 0
	end
	if humanoid.UseJumpPower then
		if typeof(humanoid.JumpPower) == "number" then
			humanoid.JumpPower = 0
		end
	else
		if typeof(humanoid.JumpHeight) == "number" then
			humanoid.JumpHeight = 0
		end
	end
	return true
end

function ClientResidentMovement.ClearRestPose(model: Model): boolean
	local record = restPoseState[model]
	if not record then
		return false
	end
	local humanoid = getHumanoid(model)
	local root = getHumanoidRootPart(model)
	if humanoid and root then
		root.AssemblyLinearVelocity = Vector3.new()
		root.AssemblyAngularVelocity = Vector3.new()
		local standCFrame = record.StandCFrame
		if standCFrame then
			local hipHeight = if typeof(humanoid.HipHeight) == "number" then humanoid.HipHeight else 2
			local verticalStandOffset = hipHeight + root.Size.Y * 0.5
			local standPosition = standCFrame.Position
			standPosition += standCFrame.LookVector * -0.75
			standPosition += standCFrame.UpVector * verticalStandOffset
			local lookTarget = standPosition + standCFrame.LookVector
			root.CFrame = CFrame.new(standPosition, lookTarget)
		end
		root.Anchored = record.RootAnchored
	end
	restPoseState[model] = nil
	if humanoid then
		humanoid.AutoRotate = record.AutoRotate
		humanoid.PlatformStand = record.PlatformStand
		humanoid.Sit = false
		humanoid.Jump = false
		humanoid:Move(Vector3.zero)
		if record.WalkSpeed ~= nil then
			humanoid.WalkSpeed = record.WalkSpeed
		end
		local useJumpPower = record.UseJumpPower
		if useJumpPower then
			if record.JumpPower ~= nil then
				humanoid.JumpPower = record.JumpPower
			end
		else
			if record.JumpHeight ~= nil then
				humanoid.JumpHeight = record.JumpHeight
			end
		end
		if record.PlatformStand then
			humanoid:ChangeState(Enum.HumanoidStateType.Physics)
		else
			humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
	end
	return true
end

function ClientResidentMovement.GoToStation(
	model: Model,
	stationModel: Model,
	opts: MoveOptions?
): (boolean, StationArrival?)
	if not stationModel then
		return false, nil
	end
	local approachDistance = if opts and opts.ApproachDistance then math.max(opts.ApproachDistance, 0.5) else 3
	local entryCFrame, entryAttachment, selectedSeat = computeEntryInfo(stationModel, approachDistance, opts)
	local goalPosition = entryCFrame.Position
	local ensureSeatFlag = opts and opts.EnsureSeat == true
	local seatForArrival = selectedSeat
	local occupantIndex = opts and opts.OccupantIndex or nil
	if ensureSeatFlag then
		seatForArrival = ensureSeatForOccupant(selectedSeat, stationModel, entryCFrame, entryAttachment, occupantIndex)
	end
	local timeout = if opts and opts.TimeoutSeconds then math.max(opts.TimeoutSeconds, 1) else DEFAULT_TIMEOUT

	local cancelToken = opts and opts.CancelToken or nil
	local reached = moveToTarget(model, goalPosition, cancelToken, timeout)

	if reached then
		local seat = seatForArrival or findSeat(stationModel)
		return true, { EntryCFrame = entryCFrame, Seat = seat, EntryAttachment = entryAttachment }
	end
	return false, nil
end

function ClientResidentMovement.GoToWorldPosition(model: Model, targetPosition: Vector3, opts: MoveOptions?): boolean
	local cancelToken = opts and opts.CancelToken or nil
	local timeout = if opts and opts.TimeoutSeconds then math.max(opts.TimeoutSeconds, 1) else DEFAULT_TIMEOUT
	local reached = moveToTarget(model, targetPosition, cancelToken, timeout)
	return reached
end

function ClientResidentMovement.FaceStation(model: Model, entryCFrame: CFrame)
	local root = getHumanoidRootPart(model)
	if not root then
		return
	end
	local position = root.Position
	local forward = entryCFrame.LookVector
	local orientation = CFrame.new(position, position + forward)
	root.CFrame = orientation
end

function ClientResidentMovement.SeatResident(model: Model, seat: Seat, token: CancelToken?): boolean
	local humanoid = getHumanoid(model)
	if not humanoid then
		return false
	end

	local function waitForSeatAvailability(timeout: number)
		local deadline = os.clock() + timeout
		while true do
			local occupant = seat.Occupant
			if not occupant or occupant == humanoid then
				return
			end
			if occupant.Parent == nil then
				local weld = seat:FindFirstChild("SeatWeld")
				if weld then
					weld:Destroy()
				end
				return
			end
			if os.clock() >= deadline then
				return
			end
			RunService.Heartbeat:Wait()
		end
	end
	local function attemptSeat(timeout: number): boolean
		seat:Sit(humanoid)
		local start = os.clock()
		while humanoid.SeatPart ~= seat do
			if token and token.Cancelled then
				return false
			end
			if os.clock() - start > timeout then
				break
			end
			RunService.Heartbeat:Wait()
		end
		return humanoid.SeatPart == seat
	end

	waitForSeatAvailability(1.5)
	local occupantAfterWait = seat.Occupant
	if occupantAfterWait and occupantAfterWait ~= humanoid then
		return false
	end
	local success = attemptSeat(3)
	if not success and (not token or not token.Cancelled) then
		waitForSeatAvailability(0.5)
		success = attemptSeat(1.5)
	end

	return success
end

function ClientResidentMovement.LeaveSeat(model: Model, seat: Seat?)
	local humanoid = getHumanoid(model)
	if not humanoid then
		return
	end
	local root = getHumanoidRootPart(model)
	local currentSeat = seat
	if not currentSeat then
		local seatPart = humanoid.SeatPart
		if seatPart and seatPart:IsA("Seat") then
			currentSeat = seatPart
		end
	end
	if not currentSeat or humanoid.SeatPart ~= currentSeat then
		return
	end

	local disabledSeatedState = false
	do
		local ok, seatedEnabled = pcall(humanoid.GetStateEnabled, humanoid, Enum.HumanoidStateType.Seated)
		if ok and seatedEnabled == true then
			humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)
			disabledSeatedState = true
		end
	end
	humanoid.Sit = false
	humanoid.Jump = false
	local jumpDelay = 0.2
	-- Only force a jump if the resident is still seated after a brief release window
	local maxReleaseDuration = 1.5
	local jumpTriggered = false
	local start = os.clock()
	while humanoid.SeatPart == currentSeat and os.clock() - start < maxReleaseDuration do
		if not jumpTriggered and os.clock() - start >= jumpDelay then
			local shouldJump = true
			if root then
				local seatPosition = currentSeat.CFrame.Position
				local distanceToSeat = (root.Position - seatPosition).Magnitude
				if distanceToSeat > 6 then
					shouldJump = false
				end
			end
			if shouldJump then
				humanoid.Jump = true
				jumpTriggered = true
			end
		end
		RunService.Heartbeat:Wait()
	end
	if humanoid.SeatPart == currentSeat then
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		humanoid.Sit = false
		local weld: Instance? = currentSeat:FindFirstChild("SeatWeld")
		if weld then
			weld:Destroy()
		end
		currentSeat.Disabled = true
		task.delay(0.1, function()
			if currentSeat.Parent then
				currentSeat.Disabled = false
			end
		end)
		if root then
			root.AssemblyLinearVelocity = Vector3.new()
			root.AssemblyAngularVelocity = Vector3.new()
			root.CFrame = root.CFrame * CFrame.new(0, 2, 0)
		end
		local releaseStart = os.clock()
		while humanoid.SeatPart == currentSeat and os.clock() - releaseStart < 0.5 do
			RunService.Heartbeat:Wait()
		end
	end
	if disabledSeatedState then
		humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
	end
end

return ClientResidentMovement
