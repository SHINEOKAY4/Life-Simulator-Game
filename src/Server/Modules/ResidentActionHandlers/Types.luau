--!strict

export type CancelToken = {
	Cancelled: boolean,
	Reason: string?,
}

export type HandlerContext = {
	Resident: any,
	CancelToken: CancelToken,
}

export type HandlerAssignment = {
	Player: Player?,
	ResidentName: string,
	ResidentState: any,
	StationType: string,
	StationId: string,
	ItemId: string?,
	ItemSpec: { [string]: any }?,
	StationRecord: any?,
	StationModel: Model?,
	NeedName: string?,
	RestModeOverride: string?,
	ManualOverride: boolean?,
	ActionMode: string?,
	TargetContainerId: string?,
	PreparedMealId: string?,
	PreparedMealServings: number?,
	PreparedMealHungerPerPortion: number?,
}

export type RawEffect = { [string]: any }
export type Effect = {
	Need: string,
	InstantAmount: number?,
	RatePerHour: number?,
}

export type RawMoodlet = { [string]: any }
export type Moodlet = {
	Name: string,
	DurationSeconds: number,
	NeedBias: { [string]: number }?,
}

export type ChatOption = {
	Text: string,
	MinClock: number?,
	MaxClock: number?,
	MinNeeds: { [string]: number }?,
	MaxNeeds: { [string]: number }?,
}

export type Behavior = {
	ApproachDistance: number?,
	MoveTimeoutSeconds: number?,
	UseSeat: boolean?,
	DurationSeconds: number?,
	ShouldEnd: ((residentState: any) -> boolean)?,
	Effects: { Effect }?,
	Moodlets: { Moodlet }?,
	ChatPhrases: { ChatOption }?,
	ChatIntervalSeconds: number?,
	RestProfileKey: string?,
	EndReasonProvider: ((residentState: any) -> string?)?,
	EmergencyGuards: { [string]: (residentState: any, value: number, def: any) -> boolean }?,
}

export type BehaviorSpec = {
	ApproachDistance: number?,
	MoveTimeoutSeconds: number?,
	UseSeat: boolean?,
	DurationSeconds: number?,
	ShouldEnd: ((residentState: any) -> boolean)?,
	Effects: { RawEffect }?,
	Moodlets: { RawMoodlet }?,
	ChatPhrases: { any }?,
	ChatIntervalSeconds: number?,
	RestProfileKey: string?,
	EndReasonProvider: ((residentState: any) -> string?)?,
	EmergencyGuards: { [string]: (residentState: any, value: number, def: any) -> boolean }?,
}

return nil
