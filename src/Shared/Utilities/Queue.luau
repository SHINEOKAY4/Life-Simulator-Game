--!strict
-- ReplicatedStorage/Shared/Utilities/Queue.lua
--
-- A clean, idiomatic FIFO (First-In-First-Out) queue implementation for Roblox.
--
-- Features:
--   • O(1) performance for adding and removing items.
--   • Compact and stable memory management (it resets when empty).
--   • Easy-to-read code using common Roblox conventions.
--   • Type-safe with Luau strict mode.
--
-- Example:
--   local Queue = require(ReplicatedStorage.Shared.Queue)
--   local myQueue = Queue.new()
--   myQueue:Push("Apple")
--   myQueue:Push("Banana")
--   print(myQueue:Pop()) --> "Apple"

type QueueInternal = {
	_data: { [number]: any },
	Head: number,
	Tail: number,
}

export type Queue = QueueInternal

local Queue = {}
Queue.__index = Queue

---------------------------------------------------------------------
-- Constructor
---------------------------------------------------------------------

-- Creates and returns a new, empty queue.
function Queue.new(): Queue
	local self: QueueInternal = {
		_data = {},
		Head = 1,
		Tail = 0,
	}

	return (setmetatable(self, Queue) :: any) :: Queue
end

---------------------------------------------------------------------
-- Public Methods
---------------------------------------------------------------------

-- Adds one value to the end of the queue.
function Queue:Push(value: any)
	local queue = self :: Queue
	queue.Tail += 1
	queue._data[queue.Tail] = value
end

-- Adds multiple values to the end of the queue.
-- Returns how many values were added.
function Queue:PushMany(values: { any }): number
	local queue = self :: Queue
	local count = #values
	if count == 0 then
		return 0
	end

	for i = 1, count do
		queue.Tail += 1
		queue._data[queue.Tail] = values[i]
	end

	return count
end

-- Removes and returns the value at the front of the queue.
-- Returns nil if the queue is empty.
function Queue:Pop(): any?
	local queue = self :: Queue
	if queue.Head > queue.Tail then
		return nil
	end

	local value = queue._data[queue.Head]
	queue._data[queue.Head] = nil
	queue.Head += 1

	-- Compact the queue if it becomes empty.
	if queue.Head > queue.Tail then
		queue._data = {}
		queue.Head = 1
		queue.Tail = 0
	end

	return value
end

-- Returns the value at the front of the queue without removing it.
-- Returns nil if the queue is empty.
function Queue:Peek(): any?
	local queue = self :: Queue
	if queue.Head > queue.Tail then
		return nil
	end

	return queue._data[queue.Head]
end

-- Returns the number of items currently in the queue.
function Queue:Size(): number
	local queue = self :: Queue
	return math.max(0, queue.Tail - queue.Head + 1)
end

-- Returns true if the queue has no items.
function Queue:IsEmpty(): boolean
	local queue = self :: Queue
	return queue.Head > queue.Tail
end

-- Removes all items from the queue.
function Queue:Clear()
	local queue = self :: Queue
	queue._data = {}
	queue.Head = 1
	queue.Tail = 0
end

-- Removes and returns up to `limit` items (or all items if limit is nil).
-- Returns them in order from front to back.
function Queue:Drain(limit: number?): { any }
	local queue = self :: Queue
	if queue.Head > queue.Tail then
		return {}
	end

	local availableCount = queue.Tail - queue.Head + 1
	local numberToDrain = if limit then math.min(limit, availableCount) else availableCount
	local results = table.create(numberToDrain)
	local head = queue.Head

	for i = 1, numberToDrain do
		local index = head + i - 1
		results[i] = queue._data[index]
		queue._data[index] = nil
	end

	queue.Head = head + numberToDrain

	if queue.Head > queue.Tail then
		queue._data = {}
		queue.Head = 1
		queue.Tail = 0
	end

	return results
end

-- Returns a copy of all items in the queue in order from front to back.
-- Does not modify the queue.
function Queue:ToArray(): { any }
	local queue = self :: Queue
	local count = queue.Tail - queue.Head + 1
	if count <= 0 then
		return {}
	end

	local array = table.create(count)
	local index = 1

	for i = queue.Head, queue.Tail do
		array[index] = queue._data[i]
		index += 1
	end

	return array
end

---------------------------------------------------------------------
-- Metamethods
---------------------------------------------------------------------

-- Allows using the length operator (#queue) to get the size.
function Queue:__len(): number
	return self:Size()
end

-- Returns a string representation for debugging.
function Queue:__tostring(): string
	return "Queue(size = " .. tostring(self:Size()) .. ")"
end

---------------------------------------------------------------------
-- Return
---------------------------------------------------------------------

return Queue
