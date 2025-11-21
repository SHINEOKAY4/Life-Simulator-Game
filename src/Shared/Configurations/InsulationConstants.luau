--!strict
-- Shared/Configurations/InsulationConstants.luau

return {
	-- Base heat loss per segment (lower is better insulation)
	-- Think of this as U-Value (Thermal Transmittance)

	BaseWallLoss = 0.1, -- Standard wall
	GlassWallLoss = 0.5, -- Glass wall / large window

	RoofLoss = 0.1, -- Standard roof
	FloorLoss = 0.05, -- Heat loss to ground

	WindowLoss = 0.4, -- Window object inserted into wall
	DoorLoss = 0.2, -- Door object

	OpenAirLoss = 1.0, -- Missing wall/roof (Hole)

	-- Simulation
	AmbientTemperature = 20, -- Degrees Celsius
	RateOfChange = 0.05, -- How fast temp moves towards target per tick
}
