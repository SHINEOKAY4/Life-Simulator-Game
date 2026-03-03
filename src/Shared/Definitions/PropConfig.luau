--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CatalogFolder = ReplicatedStorage.Shared.Definitions.Catalog

local Build = require(CatalogFolder.Build)
local Furniture = require(CatalogFolder.Furniture)
local Appliances = require(CatalogFolder.Appliances)
local Decorations = require(CatalogFolder.Decorations)
local Electronics = require(CatalogFolder.Electronics)
local Utilities = require(CatalogFolder.Utilities)
local Outdoor = require(CatalogFolder.Outdoor)
local Rooms = require(CatalogFolder.Rooms)

local PropConfig = {
	Build = Build,
	Furniture = Furniture,
	Furnitures = Furniture, -- legacy plural alias
	Appliances = Appliances,
	Decorations = Decorations,
	Electronics = Electronics,
	Utilities = Utilities,
	Outdoor = Outdoor,
	Rooms = Rooms,
}

return PropConfig
