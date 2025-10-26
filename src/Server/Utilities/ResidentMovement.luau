--!strict
-- ResidentMovement.lua
-- Pathfinding and interaction helpers for steering residents toward station objects.

local PathfindingService = game:GetService("PathfindingService")
local RunService = game:GetService("RunService")
local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

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
	DebugName: string?,
}

type StationArrival = {
	EntryCFrame: CFrame,
	Seat: Seat?,
	EntryAttachment: Attachment?,
}

local ResidentMovement = {}
local ResidentDebug = require(ServerScriptService.Server.Utilities.ResidentDebug)
local NeedConfig = require(ReplicatedStorage.Shared.Configurations.NeedConfig)

local MOVEMENT_CHANNEL = "Movement"
local restPoseState = setmetatable({}, { __mode = "k" })

type RestPoseRecord = {
	AutoRotate: boolean,
	PlatformStand: boolean,
	WalkSpeed: number?,
	JumpPower: number?,
	JumpHeight: number?,
	UseJumpPower: boolean?,
	RootAnchored: boolean,
	RootOwner: Player?,
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

local function getResidentName(residentState: any): string
	local save = residentState and residentState.Save
	local name = if save
			and typeof(save) == "table"
			and typeof(save.Name) == "string"
		then save.Name
		else "UnknownResident"
	return name
end

local PATH_VARIANTS = {
	{
		AgentHeight = 4,
		AgentRadius = 1,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 4,
	},
	{
		AgentHeight = 4,
		AgentRadius = 0.8,
		AgentCanJump = true,
		AgentCanClimb = false,
		WaypointSpacing = 3,
	},
}

local function getHumanoid(residentState: any): Humanoid?
	local model = residentState and residentState.Model
	if not model then
		return nil
	end
	return model:FindFirstChildOfClass("Humanoid")
end

local function getHumanoidRootPart(residentState: any): BasePart?
	local model = residentState and residentState.Model
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

local function getNeedValue(residentState: any, needName: string): number
	if residentState and typeof(residentState.GetNeed) == "function" then
		local value = residentState:GetNeed(needName)
		if typeof(value) == "number" then
			return value
		end
	end
	local config = NeedConfig.Needs[needName]
	if config then
		return config.Max
	end
	return 100
end

local CACHED_HUNGER_DEF = NeedConfig.Needs.Hunger
local CACHED_ENERGY_DEF = NeedConfig.Needs.Energy

local function shouldRunToTarget(residentState: any, origin: Vector3, destination: Vector3): boolean
	local distance = (origin - destination).Magnitude
	if distance < RUN_DISTANCE_THRESHOLD then
		return false
	end

	if CACHED_HUNGER_DEF then
		local hunger = getNeedValue(residentState, "Hunger")
		if hunger <= CACHED_HUNGER_DEF.Critical then
			return false
		end
	end

	if CACHED_ENERGY_DEF then
		local energy = getNeedValue(residentState, "Energy")
		if energy <= CACHED_ENERGY_DEF.Critical or energy <= CACHED_ENERGY_DEF.Low then
			return false
		end
	end

	return true
end

local function pickTravelSpeed(residentState: any, origin: Vector3, destination: Vector3): number
	if shouldRunToTarget(residentState, origin, destination) then
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

local function followWaypoints(
	humanoid: Humanoid,
	token: CancelToken?,
	waypoints: { PathWaypoint },
	residentName: string
): boolean
	for index, waypoint in ipairs(waypoints) do
		if token and token.Cancelled then
			ResidentDebug.Trace(MOVEMENT_CHANNEL, string.format("Waypoint cancelled for %s", residentName), {
				WaypointIndex = index,
			})
			return false
		end
		if waypoint.Action == Enum.PathWaypointAction.Jump then
			humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		local ok = waitForMoveFinished(humanoid, waypoint.Position, token, WAYPOINT_TIMEOUT)
		if not ok then
			ResidentDebug.Trace(MOVEMENT_CHANNEL, string.format("Waypoint failed for %s", residentName), {
				WaypointIndex = index,
				WaypointPosition = waypoint.Position,
			})
			return false
		end
	end
	return true
end

local function moveToTarget(
	residentState: any,
	targetPosition: Vector3,
	cancelToken: CancelToken?,
	timeoutSeconds: number?,
	debugLabel: string?
): (boolean, { [string]: any }?)
	local humanoid = getHumanoid(residentState)
	local root = getHumanoidRootPart(residentState)
	if not humanoid or not root then
		return false, nil
	end
	ResidentMovement.LeaveSeat(residentState, nil)
	local residentName = getResidentName(residentState)
	local originalSpeed = humanoid.WalkSpeed
	local desiredSpeed = pickTravelSpeed(residentState, root.Position, targetPosition)
	if typeof(humanoid.WalkSpeed) == "number" and desiredSpeed ~= humanoid.WalkSpeed then
		humanoid.WalkSpeed = desiredSpeed
	end
	local label = debugLabel or "Target"
	local startClock = os.clock()
	if residentState.SetDestination then
		residentState:SetDestination(targetPosition)
	end
	local path, attemptsMeta = computePathWithVariants(root.Position, targetPosition)
	local computeError = nil
	local pathStatus = "NoPath"
	local reached = false
	if path then
		pathStatus = path.Status.Name
		local waypoints = path:GetWaypoints()
		reached = followWaypoints(humanoid, cancelToken, waypoints, residentName)
	else
		if #attemptsMeta > 0 then
			local lastAttempt = attemptsMeta[#attemptsMeta]
			computeError = lastAttempt.Error
		end
		local timeoutBudget = timeoutSeconds and math.max(timeoutSeconds, 1) or DEFAULT_TIMEOUT
		reached = waitForMoveFinished(humanoid, targetPosition, cancelToken, timeoutBudget)
	end
	stopHumanoid(humanoid)
	if humanoid.Parent and typeof(originalSpeed) == "number" and humanoid.WalkSpeed ~= originalSpeed then
		humanoid.WalkSpeed = originalSpeed
	end
	if residentState.SetDestination then
		residentState:SetDestination(nil)
	end
	if reached and residentState.DestinationCompleted then
		residentState.DestinationCompleted:Fire(targetPosition)
	end
	return reached,
		{
			Duration = os.clock() - startClock,
			Attempts = attemptsMeta,
			PathStatus = pathStatus,
			ComputeError = computeError,
			GoalPosition = targetPosition,
			Label = label,
		}
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

local function selectEntryAttachment(
	attachments: { EntryAttachmentInfo },
	occupantIndex: number?,
	occupantCount: number?
): Attachment?
	if #attachments == 0 then
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
		for _, info in ipairs(attachments) do
			if info.Index == slotIndex then
				return info.Attachment
			end
		end
		if totalSlots and totalSlots <= #attachments then
			local wrapIndex = ((slotIndex - 1) % totalSlots) + 1
			local candidate = attachments[wrapIndex]
			if candidate then
				return candidate.Attachment
			end
		end
		local wrapped = ((slotIndex - 1) % #attachments) + 1
		return attachments[wrapped].Attachment
	end
	for _, info in ipairs(attachments) do
		if info.Index == 1 then
			return info.Attachment
		end
	end
	return attachments[1].Attachment
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

local function computeEntryInfo(
	stationModel: Model,
	approachDistance: number?,
	moveOpts: MoveOptions?
): (CFrame, Attachment?)
	local attachments = collectResidentEntryAttachments(stationModel)
	local occupantIndex = moveOpts and moveOpts.OccupantIndex or nil
	local occupantCount = moveOpts and moveOpts.OccupantCount or nil
	local attachment = selectEntryAttachment(attachments, occupantIndex, occupantCount)
	if attachment then
		local attachmentOffsetAttr = attachment:GetAttribute("ResidentEntryOffset")
		local stationOffsetAttr = stationModel:GetAttribute("ResidentEntryOffset")
		local offsetMagnitude = nil
		if typeof(attachmentOffsetAttr) == "number" then
			offsetMagnitude = attachmentOffsetAttr
		elseif typeof(stationOffsetAttr) == "number" then
			offsetMagnitude = stationOffsetAttr
		end
		if offsetMagnitude and offsetMagnitude ~= 0 then
			return attachment.WorldCFrame * CFrame.new(0, 0, -offsetMagnitude), attachment
		end
		return attachment.WorldCFrame, attachment
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
	return CFrame.new(entryPosition, bboxCFrame.Position), nil
end

local function findSeat(model: Model): Seat?
	return model:FindFirstChildWhichIsA("Seat", true)
end

local AUTO_SEAT_NAME = "ResidentAutoSeat"
local AUTO_SEAT_SIZE = Vector3.new(2, 1, 2)

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

local function ensureSeat(stationModel: Model, entryCFrame: CFrame, entryAttachment: Attachment?): Seat?
	local existing = findSeat(stationModel)
	if existing then
		existing.Disabled = false
		return existing
	end
	local seatInstance = stationModel:FindFirstChild(AUTO_SEAT_NAME)
	local autoSeat: Seat
	if seatInstance and seatInstance:IsA("Seat") then
		autoSeat = seatInstance
	else
		autoSeat = Instance.new("Seat")
		autoSeat.Name = AUTO_SEAT_NAME
		autoSeat.Size = AUTO_SEAT_SIZE
		autoSeat.Transparency = 1
		autoSeat.Anchored = true
		autoSeat.CanCollide = false
		autoSeat.CanTouch = false
		autoSeat.CanQuery = false
		autoSeat.TopSurface = Enum.SurfaceType.Smooth
		autoSeat.BottomSurface = Enum.SurfaceType.Smooth
		autoSeat.Parent = stationModel
		ResidentDebug.Trace(MOVEMENT_CHANNEL, "Created auto seat", {
			StationModel = stationModel:GetFullName(),
		})
	end
	autoSeat.Disabled = false
	autoSeat.CFrame = computeSeatCFrame(entryCFrame, entryAttachment)
	return autoSeat
end

function ResidentMovement.ApplyRestPose(residentState: any, options: RestPoseOptions): boolean
	local humanoid = getHumanoid(residentState)
	if not humanoid then
		return false
	end
	local root = getHumanoidRootPart(residentState)
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
	local record = restPoseState[residentState]
	if not record then
		local networkOwner: Player? = root:GetNetworkOwner()
		record = {
			AutoRotate = humanoid.AutoRotate,
			PlatformStand = humanoid.PlatformStand,
			WalkSpeed = if typeof(humanoid.WalkSpeed) == "number" then humanoid.WalkSpeed else nil,
			JumpPower = if typeof(humanoid.JumpPower) == "number" then humanoid.JumpPower else nil,
			JumpHeight = if typeof(humanoid.JumpHeight) == "number" then humanoid.JumpHeight else nil,
			UseJumpPower = humanoid.UseJumpPower,
			RootAnchored = root.Anchored,
			RootOwner = networkOwner,
			StandCFrame = baseCFrame,
			RootCFrame = root.CFrame,
		}
		restPoseState[residentState] = record
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
	root:SetNetworkOwner(nil)
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

function ResidentMovement.ClearRestPose(residentState: any): boolean
	local record = restPoseState[residentState]
	if not record then
		return false
	end
	local humanoid = getHumanoid(residentState)
	local root = getHumanoidRootPart(residentState)
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
		if record.RootOwner then
			root:SetNetworkOwner(record.RootOwner :: Player)
		else
			root:SetNetworkOwner(nil)
		end
	end
	restPoseState[residentState] = nil
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

function ResidentMovement.GoToStation(
	residentState: any,
	stationModel: Model,
	opts: MoveOptions?
): (boolean, StationArrival?)
	if not stationModel then
		return false, nil
	end
	local residentName = getResidentName(residentState)
	local approachDistance = if opts and opts.ApproachDistance then math.max(opts.ApproachDistance, 0.5) else 3
	local entryCFrame, entryAttachment = computeEntryInfo(stationModel, approachDistance, opts)
	local goalPosition = entryCFrame.Position
	local ensureSeatFlag = opts and opts.EnsureSeat == true
	local ensureSeatResult: Seat? = nil
	if ensureSeatFlag then
		ensureSeatResult = ensureSeat(stationModel, entryCFrame, entryAttachment)
	end
	local timeout = if opts and opts.TimeoutSeconds then math.max(opts.TimeoutSeconds, 1) else DEFAULT_TIMEOUT
	ResidentDebug.Trace(
		MOVEMENT_CHANNEL,
		string.format("GoToStation start: %s -> %s", residentName, stationModel.Name),
		{
			Resident = residentName,
			StationModel = stationModel:GetFullName(),
			GoalPosition = goalPosition,
			ApproachDistance = approachDistance,
		}
	)
	local cancelToken = opts and opts.CancelToken or nil
	local reached, moveMeta = moveToTarget(residentState, goalPosition, cancelToken, timeout, stationModel.Name)
	if moveMeta == nil then
		moveMeta = {
			GoalPosition = goalPosition,
			Label = stationModel.Name,
		}
	end
	local metadata = moveMeta :: { [string]: any }
	metadata.Resident = residentName
	metadata.StationModel = stationModel:GetFullName()
	metadata.ApproachDistance = approachDistance
	metadata.EnsureSeat = ensureSeatFlag
	if ensureSeatFlag and ensureSeatResult then
		metadata.EnsuredSeat = ensureSeatResult.Name
	end
	if reached then
		ResidentDebug.Trace(MOVEMENT_CHANNEL, string.format("Arrived at station: %s", residentName), metadata)
		local seat = ensureSeatResult or findSeat(stationModel)
		return true, { EntryCFrame = entryCFrame, Seat = seat, EntryAttachment = entryAttachment }
	end
	ResidentDebug.Trace(MOVEMENT_CHANNEL, string.format("Failed to reach station: %s", residentName), metadata)
	return false, nil
end

function ResidentMovement.GoToWorldPosition(residentState: any, targetPosition: Vector3, opts: MoveOptions?): boolean
	local cancelToken = opts and opts.CancelToken or nil
	local timeout = if opts and opts.TimeoutSeconds then math.max(opts.TimeoutSeconds, 1) else DEFAULT_TIMEOUT
	local labelCandidate = opts and opts.DebugName or nil
	local label = if labelCandidate and labelCandidate ~= "" then labelCandidate else "Roam"
	local reached, moveMeta = moveToTarget(residentState, targetPosition, cancelToken, timeout, label)
	if moveMeta == nil then
		moveMeta = {
			GoalPosition = targetPosition,
			Label = label,
		}
	end
	local metadata = moveMeta :: { [string]: any }
	metadata.Resident = getResidentName(residentState)
	if reached then
		ResidentDebug.Trace(MOVEMENT_CHANNEL, string.format("Arrived at %s: %s", label, metadata.Resident), metadata)
	else
		ResidentDebug.Trace(
			MOVEMENT_CHANNEL,
			string.format("Failed to reach %s: %s", label, metadata.Resident),
			metadata
		)
	end
	return reached
end

function ResidentMovement.FaceStation(residentState: any, entryCFrame: CFrame)
	local root = getHumanoidRootPart(residentState)
	if not root then
		return
	end
	ResidentDebug.Trace(MOVEMENT_CHANNEL, string.format("Facing station for %s", getResidentName(residentState)), {
		EntryPosition = entryCFrame.Position,
	})
	local position = root.Position
	local forward = entryCFrame.LookVector
	local orientation = CFrame.new(position, position + forward)
	root.CFrame = orientation
end

function ResidentMovement.SeatResident(residentState: any, seat: Seat, token: CancelToken?): boolean
	local humanoid = getHumanoid(residentState)
	if not humanoid then
		return false
	end
	ResidentDebug.Trace(MOVEMENT_CHANNEL, string.format("Seat attempt for %s", getResidentName(residentState)), {
		SeatName = seat.Name,
	})
	seat:Sit(humanoid)
	local start = os.clock()
	while humanoid.SeatPart ~= seat do
		if token and token.Cancelled then
			ResidentDebug.Trace(
				MOVEMENT_CHANNEL,
				string.format("Seat cancelled for %s", getResidentName(residentState))
			)
			return false
		end
		if os.clock() - start > 3 then
			break
		end
		RunService.Heartbeat:Wait()
	end
	local success = humanoid.SeatPart == seat
	ResidentDebug.Trace(
		MOVEMENT_CHANNEL,
		string.format("Seat result for %s: %s", getResidentName(residentState), success and "success" or "failed")
	)
	return humanoid.SeatPart == seat
end

function ResidentMovement.LeaveSeat(residentState: any, seat: Seat?)
	local humanoid = getHumanoid(residentState)
	if not humanoid then
		return
	end
	local root = getHumanoidRootPart(residentState)
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
	ResidentDebug.Trace(MOVEMENT_CHANNEL, string.format("Leaving seat for %s", getResidentName(residentState)), {
		SeatName = currentSeat.Name,
	})
	humanoid.Sit = false
	humanoid.Jump = true
	local start = os.clock()
	while humanoid.SeatPart ~= nil and os.clock() - start < 2 do
		RunService.Heartbeat:Wait()
		humanoid.Sit = false
		humanoid.Jump = true
	end
	if humanoid.SeatPart ~= nil then
		ResidentDebug.Trace(
			MOVEMENT_CHANNEL,
			string.format("Seat release timeout for %s", getResidentName(residentState)),
			{
				SeatName = currentSeat.Name,
			}
		)
		humanoid:ChangeState(Enum.HumanoidStateType.Jumping)
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
			local seatCFrame = currentSeat.CFrame
			-- Push the resident slightly upward and forward so we break any lingering weld.
			root.CFrame = seatCFrame * CFrame.new(0, 2, -2)
		end
	end
	if root then
		root:SetNetworkOwner(nil)
	end
end

return ResidentMovement
