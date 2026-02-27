--!strict
-- Server/Services/TenantService/ValidationUtils.luau
-- Type validation and normalization utilities

local ValidationUtils = {}
local getType = typeof or type

function ValidationUtils.EnsureNumber(value, fallback)
	if getType(value) == "number" then
		return value
	end
	return fallback
end

function ValidationUtils.EnsureString(value, fallback)
	if getType(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

function ValidationUtils.EnsureTable(value, fallback)
	if getType(value) == "table" then
		return value
	end
	return fallback or {}
end

function ValidationUtils.IsValidNumber(value, minValue)
	if getType(value) ~= "number" then
		return false
	end
	if minValue and value < minValue then
		return false
	end
	return true
end

return ValidationUtils
