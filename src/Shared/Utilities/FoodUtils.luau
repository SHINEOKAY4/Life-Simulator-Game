--!strict
-- ReplicatedStorage/Shared/Utilities/FoodUtils.luau

local FoodUtils = {}

export type IngredientInventory = { [string]: number }
export type MealInventory = { [string]: number }

function FoodUtils.CloneInventory(inventory: IngredientInventory): IngredientInventory
	local clone: IngredientInventory = {}
	for key, value in pairs(inventory) do
		if typeof(key) == "string" and typeof(value) == "number" then
			clone[key] = value
		end
	end
	return clone
end

function FoodUtils.CanSatisfyRecipe(
	ingredients: IngredientInventory,
	requirements: { { IngredientId: string, Quantity: number } }
): boolean
	for _, requirement in ipairs(requirements) do
		local ingredientId = requirement.IngredientId
		local quantity = requirement.Quantity
		if typeof(ingredientId) ~= "string" or ingredientId == "" then
			return false
		end
		if typeof(quantity) ~= "number" or quantity <= 0 then
			return false
		end
		local available = ingredients[ingredientId]
		if typeof(available) ~= "number" or available < quantity then
			return false
		end
	end
	return true
end

function FoodUtils.ApplyIngredientDelta(
	ingredients: IngredientInventory,
	requirements: { { IngredientId: string, Quantity: number } },
	scale: number
)
	for _, requirement in ipairs(requirements) do
		local ingredientId = requirement.IngredientId
		local quantity = math.floor((requirement.Quantity or 0) * scale + 0.5)
		if quantity ~= 0 then
			local current = ingredients[ingredientId] or 0
			local nextValue = current - quantity
			if nextValue <= 0 then
				ingredients[ingredientId] = nil
			else
				ingredients[ingredientId] = nextValue
			end
		end
	end
end

function FoodUtils.AddIngredients(
	ingredients: IngredientInventory,
	additions: { { IngredientId: string, Quantity: number } }
)
	for _, requirement in ipairs(additions) do
		local ingredientId = requirement.IngredientId
		local quantity = requirement.Quantity
		if typeof(ingredientId) == "string" and ingredientId ~= "" then
			if typeof(quantity) ~= "number" then
				quantity = 0
			end
			quantity = math.max(0, math.floor(quantity + 0.5))
			if quantity > 0 then
				ingredients[ingredientId] = (ingredients[ingredientId] or 0) + quantity
			end
		end
	end
end

function FoodUtils.SetMealPortions(inventory: MealInventory, mealId: string, portions: number)
	portions = math.max(0, math.floor(portions + 0.5))
	if portions <= 0 then
		inventory[mealId] = nil
		return
	end
	inventory[mealId] = portions
end

function FoodUtils.AddMealPortions(inventory: MealInventory, mealId: string, portions: number)
	portions = math.max(0, math.floor(portions + 0.5))
	if portions <= 0 then
		return
	end
	local current = inventory[mealId] or 0
	inventory[mealId] = current + portions
end

function FoodUtils.RemoveMealPortions(inventory: MealInventory, mealId: string, portions: number)
	portions = math.max(0, math.floor(portions + 0.5))
	if portions <= 0 then
		return
	end
	local current = inventory[mealId] or 0
	local nextValue = current - portions
	if nextValue <= 0 then
		inventory[mealId] = nil
	else
		inventory[mealId] = nextValue
	end
end

function FoodUtils.ComputeHungerEffect(recipeHunger: number): number
	if typeof(recipeHunger) ~= "number" then
		return 0
	end
	return math.max(0, math.floor(recipeHunger + 0.5))
end

return FoodUtils
