--!strict
-- ServerScriptService/Server/Modules/StationActionRegistry.luau

export type HandlerContext = {
	Resident: any,
	CancelToken: {
		Cancelled: boolean,
		Reason: string?,
	},
}

export type StationAssignment = {
	StationType: string,
	StationId: string,
	ResidentName: string?,
	Player: Player?,
	[any]: any,
}

export type StationHandler = (HandlerContext, StationAssignment) -> ()

local StationActionRegistry = {}

local Handlers: { [string]: StationHandler } = {}

function StationActionRegistry.RegisterHandler(stationType: string, handler: StationHandler)
	Handlers[stationType] = handler
end

function StationActionRegistry.GetHandler(stationType: string): StationHandler?
	return Handlers[stationType]
end

function StationActionRegistry.HasHandler(stationType: string): boolean
	return Handlers[stationType] ~= nil
end

function StationActionRegistry.Clear()
	table.clear(Handlers)
end

return StationActionRegistry
