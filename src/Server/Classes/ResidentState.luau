--!strict
-- ServerScriptService/Server/Classes/Resident.lua

export type ResidentData = {
	Name: string,
	Age: number,
	Gender: string,
	Occupation: string,
	Cash: number,
	Mood: number,
	Intelligence: number,
	Fitness: number,
	Social: number,
}

local ResidentState = {}
ResidentState.__index = ResidentState

type ResidentStateInstance = {
	Name: string,
	Age: number,
	Gender: string,
	Occupation: string,
	Cash: number,
	Mood: number,
	Intelligence: number,
	Fitness: number,
	Social: number,
	ShiftClockMin: number,
	ShiftActive: boolean,
}

function ResidentState.new(payload: ResidentData)
	local self = setmetatable({}, ResidentState)
	self.Name = payload.Name
	self.Age = payload.Age
	self.Gender = payload.Gender
	self.Occupation = payload.Occupation
	self.Cash = payload.Cash
	self.Mood = payload.Mood
	self.Intelligence = payload.Intelligence
	self.Fitness = payload.Fitness
	self.Social = payload.Social
	self.ShiftClockMin = 0
	self.ShiftActive = false
	return self
end

function ResidentState:Drift() end

function ResidentState:CanHire(jobName: string, gates): boolean
	self = self :: ResidentStateInstance
	if jobName == "" then
		return false
	end
	if gates.Intelligence and self.Intelligence < gates.Intelligence then
		return false
	end
	if gates.Fitness and self.Fitness < gates.Fitness then
		return false
	end
	if gates.Social and self.Social < gates.Social then
		return false
	end

	return true
end

function ResidentState:BeginShift() end

function ResidentState:StartShift() end

function ResidentState:EndShift() end

function ResidentState:Eat() end

function ResidentState:Rest() end

function ResidentState:Exercise() end

function ResidentState:Socialize() end

return ResidentState
