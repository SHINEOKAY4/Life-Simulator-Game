--!strict
-- Unified placed object utilities - iterate and query efficiently

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ItemFinder = require(ReplicatedStorage.Shared.Utilities.ItemFinder)

local PlacedObjectUtils = {}

-- Minimal placed object type - compatible with both SavedPlacedObject and client types
export type PlacedObject = {
	id: string,
	cellX: number?,
	cellZ: number?,
	yLevel: number?,
	facing: string?,
	Metadata: { [string]: any }?,
}

export type ObjectFilter = {
	RequiresPower: boolean?,
	RequiresWater: boolean?,
	RequiresInternet: boolean?,
	HasTag: string?,
	HasTags: { string }?,
	ItemType: string?,
	Level: number?,
}

-- Iterate placed objects with optional filtering
function PlacedObjectUtils.IterateObjects(
	placedObjects: { [string]: PlacedObject },
	filter: ObjectFilter?,
	callback: (key: string, obj: PlacedObject, spec: any) -> ()
)
	for key, obj in pairs(placedObjects) do
		local spec = ItemFinder.FindItemById(obj.id)
		if not spec then
			continue
		end

		-- Apply filters
		if filter then
			if filter.Level and obj.yLevel ~= filter.Level then
				continue
			end

			if filter.RequiresPower and not spec.RequiresPower then
				continue
			end

			if filter.RequiresWater and not spec.RequiresWater then
				continue
			end

			if filter.RequiresInternet and not spec.RequiresInternet then
				continue
			end

			if filter.HasTag and spec.Tags then
				if not table.find(spec.Tags, filter.HasTag) then
					continue
				end
			end

			if filter.HasTags and spec.Tags then
				local hasAll = true
				for _, tag in ipairs(filter.HasTags) do
					if not table.find(spec.Tags, tag) then
						hasAll = false
						break
					end
				end
				if not hasAll then
					continue
				end
			end

			if filter.ItemType and spec.ItemType ~= filter.ItemType then
				continue
			end
		end

		callback(key, obj, spec)
	end
end

-- Sum numeric property across all objects matching filter
function PlacedObjectUtils.SumProperty(
	placedObjects: { [string]: PlacedObject },
	propertyPath: string,
	filter: ObjectFilter?
): number
	local total = 0

	PlacedObjectUtils.IterateObjects(placedObjects, filter, function(_, _, spec)
		local value = spec[propertyPath]
		if typeof(value) == "number" and value > 0 then
			total += value
		end
	end)

	return total
end

-- Count objects matching filter
function PlacedObjectUtils.CountObjects(placedObjects: { [string]: PlacedObject }, filter: ObjectFilter?): number
	local count = 0

	PlacedObjectUtils.IterateObjects(placedObjects, filter, function()
		count += 1
	end)

	return count
end

-- Find first object matching condition
function PlacedObjectUtils.FindObject(
	placedObjects: { [string]: PlacedObject },
	predicate: (key: string, obj: PlacedObject, spec: any) -> boolean
): (string?, PlacedObject?, any?)
	for key, obj in pairs(placedObjects) do
		local spec = ItemFinder.FindItemById(obj.id)
		if spec and predicate(key, obj, spec) then
			return key, obj, spec
		end
	end

	return nil, nil, nil
end

return PlacedObjectUtils
