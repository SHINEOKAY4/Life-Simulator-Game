--!strict
-- Shared utility for formatting resident career and shift status strings.

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CareerShiftConfig = require(ReplicatedStorage.Shared.Configurations.CareerShiftConfig)
local JobCatalog = require(ReplicatedStorage.Shared.Configurations.JobCatalog)
local TimeScale = require(ReplicatedStorage.Shared.Utilities.TimeScale)

export type StatusState = "OnShift" | "WindowOpen" | "Scheduled" | "OffDuty" | "Unassigned" | "Unknown"

export type StatusResult = {
	text: string,
	color: Color3,
	state: StatusState,
	jobId: string?,
	jobName: string?,
}

local ShiftStatusFormatter = {}

local SHIFT_STATUS_COLORS = {
	Active = Color3.fromRGB(82, 199, 107),
	Pending = Color3.fromRGB(255, 200, 72),
	Scheduled = Color3.fromRGB(126, 214, 255),
	Idle = Color3.fromRGB(200, 200, 200),
	Unassigned = Color3.fromRGB(220, 98, 86),
}

local CAREER_EMOJIS: { [string]: string } = {
	CafeCrew = "☕",
	OfficeAssistant = "🗂️",
	JuniorProgrammer = "💻",
	FitnessTrainer = "🏋️",
}

local JobById: { [string]: JobCatalog.JobEntry } = {}
for _, job in JobCatalog.Jobs do
	JobById[job.Id] = job
end

type ShiftTemplate = CareerShiftConfig.ShiftTemplate

type ShiftTimingInfo = {
	state: "active" | "upcoming",
	startTime: number,
	endTime: number?,
	dayOffset: number,
	dayOfWeek: number,
}

local DAY_NAMES = {
	"Sun",
	"Mon",
	"Tue",
	"Wed",
	"Thu",
	"Fri",
	"Sat",
}

local function clockBaselineHours(): number
	return (tonumber(Lighting:GetAttribute("StartClockTime")) or 16.5) % 24
end

local function clockToDaySeconds(clockTime: number, secPerDay: number): number
	local baseline = clockBaselineHours()
	local deltaHours = (clockTime - baseline) % 24
	return (deltaHours / 24) * secPerDay
end

local function computeShiftDuration(template: ShiftTemplate, secPerDay: number): (number, number)
	local startSeconds = clockToDaySeconds(template.StartClockTime, secPerDay)
	local endSeconds = clockToDaySeconds(template.EndClockTime, secPerDay)
	local duration = (endSeconds - startSeconds) % secPerDay
	if duration <= 0 then
		duration = secPerDay
	end
	return startSeconds, duration
end

local function isDayAllowed(template: ShiftTemplate, dayIndex: number): boolean
	local dayOfWeek = dayIndex % 7
	for _, allowedDay in template.Days do
		if allowedDay == dayOfWeek then
			return true
		end
	end
	return false
end

local function computeShiftTiming(template: ShiftTemplate): ShiftTimingInfo?
	local secPerDay = TimeScale.GetSecondsPerFullDay()
	local nowSeconds = Workspace:GetServerTimeNow()
	local baseDayIndex = math.floor(nowSeconds / secPerDay)
	local startOffset, duration = computeShiftDuration(template, secPerDay)
	local upcomingStart: number? = nil
	local upcomingDayOffset = 0
	local upcomingDayOfWeek = 0

	for dayOffset = 0, 7 do
		local dayIndex = baseDayIndex + dayOffset
		if isDayAllowed(template, dayIndex) then
			local startTime = dayIndex * secPerDay + startOffset
			local endTime = startTime + duration
			if nowSeconds >= startTime and nowSeconds < endTime then
				return {
					state = "active",
					startTime = startTime,
					endTime = endTime,
					dayOffset = dayOffset,
					dayOfWeek = dayIndex % 7,
				}
			elseif startTime > nowSeconds then
				if upcomingStart == nil or startTime < upcomingStart then
					upcomingStart = startTime
					upcomingDayOffset = dayOffset
					upcomingDayOfWeek = dayIndex % 7
				end
			end
		end
	end

	if upcomingStart then
		return {
			state = "upcoming",
			startTime = upcomingStart,
			endTime = nil,
			dayOffset = upcomingDayOffset,
			dayOfWeek = upcomingDayOfWeek,
		}
	end

	return nil
end

local function formatClockTime(clockTime: number?): string?
	if typeof(clockTime) ~= "number" then
		return nil
	end
	local totalMinutes = math.floor(clockTime * 60 + 0.5)
	local hours24 = math.floor(totalMinutes / 60) % 24
	local minutes = totalMinutes % 60
	local period = if hours24 >= 12 then "PM" else "AM"
	local displayHour = hours24 % 12
	if displayHour == 0 then
		displayHour = 12
	end
	return string.format("%d:%02d %s", displayHour, minutes, period)
end

local function formatTimeUntil(seconds: number): string?
	if seconds <= 0 then
		return nil
	end
	local minutesTotal = math.floor(seconds / 60 + 0.5)
	if minutesTotal <= 1 then
		return "in 1 min"
	end
	local hours = math.floor(minutesTotal / 60)
	local minutes = minutesTotal % 60
	local parts = {}
	if hours > 0 then
		table.insert(parts, string.format("%d hr%s", hours, if hours ~= 1 then "s" else ""))
	end
	if minutes > 0 then
		table.insert(parts, string.format("%d min", minutes))
	end
	if #parts == 0 then
		return "soon"
	end
	return "in " .. table.concat(parts, " ")
end

local function resolveDayPrefix(dayOffset: number, dayOfWeek: number): string
	if dayOffset == 0 then
		return "Today"
	elseif dayOffset == 1 then
		return "Tomorrow"
	end
	return DAY_NAMES[(dayOfWeek % 7) + 1] or "Upcoming"
end

local function resolveCareerName(careerId: string?): string?
	if type(careerId) ~= "string" or careerId == "" then
		return nil
	end
	local job = JobById[careerId]
	if job and type(job.Name) == "string" and job.Name ~= "" then
		return job.Name
	end
	return careerId
end

local function computeStatus(snapshot: any?, residentModel: Model?): StatusResult
	local assignedShiftId = if snapshot and typeof(snapshot.AssignedShiftId) == "string"
		then snapshot.AssignedShiftId
		else ""
	local careerId = if snapshot and typeof(snapshot.CurrentCareerId) == "string" then snapshot.CurrentCareerId else ""
	local isOnShift = residentModel ~= nil and residentModel:GetAttribute("IsOnShift") == true

	local jobName = resolveCareerName(careerId)

	if isOnShift then
		local jobId = residentModel and residentModel:GetAttribute("WorkingJobId")
		local workingJobId = if type(jobId) == "string" and jobId ~= "" then jobId else careerId
		local workingName = resolveCareerName(workingJobId)
		local endClockText: string? = nil
		if assignedShiftId ~= "" then
			local shift = CareerShiftConfig.GetShift(assignedShiftId)
			if shift then
				endClockText = formatClockTime(shift.EndClockTime)
			end
		end
		local segments = { "On Shift" }
		if workingName then
			segments[#segments + 1] = "– " .. workingName
		end
		if endClockText then
			segments[#segments + 1] = "• Ends " .. endClockText
		end
		return {
			text = table.concat(segments, " "),
			color = SHIFT_STATUS_COLORS.Active,
			state = "OnShift",
			jobId = workingJobId ~= "" and workingJobId or careerId,
			jobName = workingName,
		}
	end

	if assignedShiftId ~= "" then
		local shift = CareerShiftConfig.GetShift(assignedShiftId)
		if shift then
			local timing = computeShiftTiming(shift)
			if timing then
				if timing.state == "active" then
					local endClock = formatClockTime(shift.EndClockTime)
					if endClock then
						return {
							text = string.format("Shift window open • Ends %s", endClock),
							color = SHIFT_STATUS_COLORS.Pending,
							state = "WindowOpen",
							jobId = careerId,
							jobName = jobName,
						}
					end
					return {
						text = "Shift window open",
						color = SHIFT_STATUS_COLORS.Pending,
						state = "WindowOpen",
						jobId = careerId,
						jobName = jobName,
					}
				end
				local startClock = formatClockTime(shift.StartClockTime)
				local dayPrefix = resolveDayPrefix(timing.dayOffset, timing.dayOfWeek)
				local relative = formatTimeUntil(timing.startTime - Workspace:GetServerTimeNow())
				local details = {}
				if startClock then
					details[#details + 1] = string.format("%s %s", dayPrefix, startClock)
				else
					details[#details + 1] = dayPrefix
				end
				if relative then
					details[#details + 1] = string.format("(%s)", relative)
				end
				return {
					text = "Next shift: " .. table.concat(details, " "),
					color = SHIFT_STATUS_COLORS.Scheduled,
					state = "Scheduled",
					jobId = careerId,
					jobName = jobName,
				}
			end
			local startClock = formatClockTime(shift.StartClockTime)
			if startClock then
				return {
					text = string.format("Next shift %s", startClock),
					color = SHIFT_STATUS_COLORS.Scheduled,
					state = "Scheduled",
					jobId = careerId,
					jobName = jobName,
				}
			end
		end
		return {
			text = "Shift scheduled",
			color = SHIFT_STATUS_COLORS.Scheduled,
			state = "Scheduled",
			jobId = careerId,
			jobName = jobName,
		}
	end

	if careerId ~= "" then
		if jobName then
			return {
				text = string.format("Off duty – %s", jobName),
				color = SHIFT_STATUS_COLORS.Idle,
				state = "OffDuty",
				jobId = careerId,
				jobName = jobName,
			}
		end
		return {
			text = "Off duty",
			color = SHIFT_STATUS_COLORS.Idle,
			state = "OffDuty",
			jobId = careerId,
			jobName = jobName,
		}
	end

	return {
		text = "No career assigned",
		color = SHIFT_STATUS_COLORS.Unassigned,
		state = "Unassigned",
		jobId = nil,
		jobName = nil,
	}
end

function ShiftStatusFormatter.Compute(snapshot: any?, residentModel: Model?): StatusResult
	return computeStatus(snapshot, residentModel)
end

function ShiftStatusFormatter.FormatClockTime(clockTime: number?): string?
	return formatClockTime(clockTime)
end

function ShiftStatusFormatter.FormatTimeUntil(seconds: number): string?
	return formatTimeUntil(seconds)
end

function ShiftStatusFormatter.GetJobName(jobId: string?): string?
	return resolveCareerName(jobId)
end

function ShiftStatusFormatter.GetStatusColors()
	return SHIFT_STATUS_COLORS
end

function ShiftStatusFormatter.GetCareerEmoji(jobId: string?): string?
	if type(jobId) ~= "string" or jobId == "" then
		return nil
	end
	return CAREER_EMOJIS[jobId]
end

return ShiftStatusFormatter
