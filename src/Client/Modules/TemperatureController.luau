--!strict
-- Client/Modules/TemperatureController.luau

local Players = game:GetService("Players")

local PlotStateStore = require(script.Parent.Parent.ClientStores.PlotStateStore)

local TemperatureController = {}

type RoomRecord = { [string]: any }

local function resolvePlotContainer(): Folder?
	local plotModel = PlotStateStore.GetPlotModel()
	if plotModel then
		local container = plotModel:FindFirstChild("Container")
		if container and container:IsA("Folder") then
			return container
		end
	end

	local player = Players.LocalPlayer
	local ownedIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(ownedIndex) ~= "number" then
		return nil
	end

	local plotsFolder = workspace:FindFirstChild("Plots")
	if not plotsFolder then
		return nil
	end

	local plot = plotsFolder:FindFirstChild(tostring(ownedIndex))
	if not plot then
		return nil
	end

	local container = plot:FindFirstChild("Container")
	if container and container:IsA("Folder") then
		return container
	end

	return nil
end

local function getRoomRecord(level: number, roomId: number): RoomRecord?
	local rooms = PlotStateStore.GetRoomsForLevel(level)
	if not rooms then
		return nil
	end

	for _, roomValue in ipairs(rooms) do
		local room = roomValue :: RoomRecord
		local matchedId = room.RoomId or room.Id
		if matchedId == roomId then
			return room
		end
	end

	return nil
end

local function getCellIndices(room: RoomRecord): { number }?
	if room.CellIndices and #room.CellIndices > 0 then
		return room.CellIndices
	end
	if room.Cells and #room.Cells > 0 then
		return room.Cells
	end
	return nil
end

local function getFloorModelForCell(level: number, cellIndex: number): (Model | BasePart)?
	local placementKey = PlotStateStore.GetFloorPlacementKeyByIndex(level, cellIndex)
	if not placementKey then
		return nil
	end

	local container = resolvePlotContainer()
	if not container then
		return nil
	end

	local candidate = container:FindFirstChild(placementKey)
	if not candidate then
		return nil
	end

	if candidate:IsA("Model") or candidate:IsA("BasePart") then
		return candidate
	end

	return nil
end

local function getRoomTemperature(level: number, roomId: number): number?
	local room = getRoomRecord(level, roomId)
	if not room then
		return nil
	end

	local cellIndices = getCellIndices(room)
	if not cellIndices then
		return nil
	end

	for _, cellIndex in ipairs(cellIndices) do
		local floorModel = getFloorModelForCell(level, cellIndex)
		if floorModel then
			local temp = floorModel:GetAttribute("Temperature")
			if typeof(temp) == "number" then
				return temp
			end
		end
	end

	return nil
end

function TemperatureController.GetTemperature(level: number, roomId: number): number?
	if typeof(level) ~= "number" or typeof(roomId) ~= "number" then
		return nil
	end

	return getRoomTemperature(level, roomId)
end

return TemperatureController
