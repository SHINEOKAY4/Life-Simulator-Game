--!strict
-- Server/Services/TenantService/ValidationUtils.luau
-- Type validation and normalization utilities

local ValidationUtils = {}

function ValidationUtils.EnsureNumber(value: any, fallback: number): number
	return if typeof(value) == "number" then value else fallback
end

function ValidationUtils.EnsureString(value: any, fallback: string?): string?
	if typeof(value) == "string" and value ~= "" then
		return value
	end
	return fallback
end

function ValidationUtils.EnsureTable<T>(value: any, fallback: T?): T
	if typeof(value) == "table" then
		return value :: T
	end
	return (fallback or {}) :: T
end

function ValidationUtils.IsValidNumber(value: any, minValue: number?): boolean
	if typeof(value) ~= "number" then
		return false
	end
	if minValue and value < minValue then
		return false
	end
	return true
end

return ValidationUtils
