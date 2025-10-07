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

return ResidentState
