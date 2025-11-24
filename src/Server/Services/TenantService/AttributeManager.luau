--!strict
-- Server/Services/TenantService/AttributeManager.luau
-- Manages player and folder attributes for tenant system

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local PlotFinder = require(ReplicatedStorage.Shared.Utilities.PlotFinder)
local ResidentsFolderFinder = require(ReplicatedStorage.Shared.Utilities.ResidentsFolderFinder)

local RESIDENTS_FOLDER_NAME = "Residents"
local MAILBOX_ATTRIBUTE_NAME = "MailboxBalance"
local PROPERTY_VALUE_ATTRIBUTE_NAME = "PropertyValue"
local INCOME_RATE_ATTRIBUTE_NAME = "TenantIncomePerSecond"

local MAX_MAILBOX_BALANCE = 4294967295
local MAX_PROPERTY_VALUE = MAX_MAILBOX_BALANCE

local AttributeManager = {}

local function ensureResidentsFolder(player: Player): Folder?
	local folder = ResidentsFolderFinder.FindFolder(player)
	if folder then
		return folder
	end

	local plotIndex = player:GetAttribute("OwnedPlotIndex")
	if typeof(plotIndex) ~= "number" then
		return nil
	end

	local plotModel = PlotFinder.FindPlot(plotIndex)
	if not plotModel then
		return nil
	end

	local created = Instance.new("Folder")
	created.Name = RESIDENTS_FOLDER_NAME
	created.Parent = plotModel
	return created
end

local function clampValue(value: number, maxValue: number): number
	if value ~= value then -- NaN check
		return 0
	end
	local rounded = math.floor(value + 0.5)
	if rounded < 0 then
		return 0
	elseif rounded > maxValue then
		return maxValue
	end
	return rounded
end

function AttributeManager.ClampMailboxAmount(amount: number): number
	return clampValue(amount, MAX_MAILBOX_BALANCE)
end

function AttributeManager.ClampPropertyValue(value: number): number
	return clampValue(value, MAX_PROPERTY_VALUE)
end

function AttributeManager.SetMailboxBalance(player: Player, balance: number)
	local folder = ensureResidentsFolder(player)
	if folder then
		folder:SetAttribute(MAILBOX_ATTRIBUTE_NAME, balance)
	end
end

function AttributeManager.SetPropertyValue(player: Player, value: number)
	local folder = ensureResidentsFolder(player)
	if folder then
		folder:SetAttribute(PROPERTY_VALUE_ATTRIBUTE_NAME, value)
	end
end

function AttributeManager.SetIncomeRate(player: Player, rate: number)
	player:SetAttribute(INCOME_RATE_ATTRIBUTE_NAME, rate)
end

function AttributeManager.ClearMailbox(player: Player)
	local folder = ResidentsFolderFinder.FindFolder(player)
	if folder then
		folder:SetAttribute(MAILBOX_ATTRIBUTE_NAME, nil)
		folder:SetAttribute(PROPERTY_VALUE_ATTRIBUTE_NAME, nil)
	end
end

function AttributeManager.ClearIncomeRate(player: Player)
	player:SetAttribute(INCOME_RATE_ATTRIBUTE_NAME, 0)
end

return AttributeManager
