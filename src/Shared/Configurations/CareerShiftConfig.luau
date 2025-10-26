--!strict
-- Shared career shift templates and helpers.
-- Day index 0 corresponds to Sunday. Clock times are in 24h format (0-24).

local CareerShiftConfig = {}

type DayOfWeek = number -- 0 (Sunday) to 6 (Saturday)

export type ShiftTemplate = {
	Id: string,
	JobId: string,
	Label: string,
	Days: { DayOfWeek },
	StartClockTime: number,
	EndClockTime: number,
	ReminderMinutes: number?,
}

local DEFAULT_REMINDER_MINUTES = 60

local ShiftTemplates: { ShiftTemplate } = {
	{
		Id = "CafeCrew_Morning",
		JobId = "CafeCrew",
		Label = "Morning Rush",
		Days = { 0, 1, 2, 3, 4, 5 },
		StartClockTime = 6.0,
		EndClockTime = 14.0,
		ReminderMinutes = 60,
	},
	{
		Id = "CafeCrew_Evening",
		JobId = "CafeCrew",
		Label = "Evening Wind Down",
		Days = { 0, 1, 2, 3, 4, 5 },
		StartClockTime = 14.0,
		EndClockTime = 22.0,
		ReminderMinutes = 45,
	},
	{
		Id = "OfficeAssistant_Day",
		JobId = "OfficeAssistant",
		Label = "Office Day",
		Days = { 1, 2, 3, 4, 5 },
		StartClockTime = 8.0,
		EndClockTime = 17.0,
		ReminderMinutes = 60,
	},
	{
		Id = "OfficeAssistant_Swing",
		JobId = "OfficeAssistant",
		Label = "Swing Support",
		Days = { 1, 2, 3, 4 },
		StartClockTime = 12.0,
		EndClockTime = 20.0,
		ReminderMinutes = 45,
	},
	{
		Id = "JuniorProgrammer_Core",
		JobId = "JuniorProgrammer",
		Label = "Core Hours",
		Days = { 1, 2, 3, 4, 5 },
		StartClockTime = 9.0,
		EndClockTime = 18.0,
		ReminderMinutes = 50,
	},
	{
		Id = "JuniorProgrammer_Night",
		JobId = "JuniorProgrammer",
		Label = "Night Maintenance",
		Days = { 0, 1, 2, 3, 4 },
		StartClockTime = 20.0,
		EndClockTime = 4.0,
		ReminderMinutes = 60,
	},
	{
		Id = "FitnessTrainer_Early",
		JobId = "FitnessTrainer",
		Label = "Early Motivator",
		Days = { 1, 2, 3, 4, 5 },
		StartClockTime = 5.0,
		EndClockTime = 13.0,
		ReminderMinutes = 45,
	},
	{
		Id = "FitnessTrainer_Weekend",
		JobId = "FitnessTrainer",
		Label = "Weekend Crowd",
		Days = { 5, 6 },
		StartClockTime = 8.0,
		EndClockTime = 16.0,
		ReminderMinutes = 45,
	},
}

local ShiftsById: { [string]: ShiftTemplate } = {}
local ShiftsByJobId: { [string]: { ShiftTemplate } } = {}

for _, shift in ShiftTemplates do
	local reminder = shift.ReminderMinutes
	if typeof(reminder) ~= "number" or reminder < 0 then
		shift.ReminderMinutes = DEFAULT_REMINDER_MINUTES
	end

	ShiftsById[shift.Id] = shift
	local list = ShiftsByJobId[shift.JobId]
	if not list then
		list = {}
		ShiftsByJobId[shift.JobId] = list
	end
	list[#list + 1] = shift
end

CareerShiftConfig.Shifts = ShiftTemplates
CareerShiftConfig.ShiftsById = ShiftsById
CareerShiftConfig.ShiftsByJobId = ShiftsByJobId
CareerShiftConfig.DEFAULT_REMINDER_MINUTES = DEFAULT_REMINDER_MINUTES

function CareerShiftConfig.GetShift(shiftId: string): ShiftTemplate?
	return ShiftsById[shiftId]
end

function CareerShiftConfig.GetShiftsForJob(jobId: string): { ShiftTemplate }
	return ShiftsByJobId[jobId] or {}
end

return CareerShiftConfig
