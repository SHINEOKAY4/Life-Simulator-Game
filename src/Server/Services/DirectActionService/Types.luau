--!strict

local Types = {}

export type StationRecord = {
	Id: string,
	Residents: { string },
	Occupied: boolean,
	Model: Model?,
	ActiveOverride: string?,
}

export type StationAssignment = {
	Player: Player,
	ResidentName: string,
	ResidentState: any,
	StationType: string,
	StationId: string,
	ItemId: string,
	ItemSpec: { [string]: any },
	StationRecord: StationRecord,
	StationModel: Model,
	NeedName: string?,
	RestModeOverride: string?,
	ManualOverride: boolean?,
	ActionMode: string?,
	TargetContainerId: string?,
	PreparedMealId: string?,
	PreparedMealServings: number?,
	PreparedMealHungerPerPortion: number?,
}

return Types
