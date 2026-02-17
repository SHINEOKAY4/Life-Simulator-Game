local function ensureTaskSpawn()
	local function spawnImpl(executable, ...)
		if type(executable) == "thread" then
			local ok, err = coroutine.resume(executable, ...)
			if not ok then
				error(err, 0)
			end
			return executable
		end

		local thread = coroutine.create(executable)
		local ok, err = coroutine.resume(thread, ...)
		if not ok then
			error(err, 0)
		end
		return thread
	end

	if type(task) ~= "table" then
		_G.task = {
			spawn = spawnImpl,
		}
		return
	end

	if type(task.spawn) ~= "function" then
		task.spawn = spawnImpl
	end
end

local function loadGoodSignal()
	local ok, signalModule

	if type(game) == "userdata" or type(game) == "table" then
		ok, signalModule = pcall(function()
			local replicatedStorage = game:GetService("ReplicatedStorage")
			return require(replicatedStorage.Packages.GoodSignal)
		end)
		if ok and signalModule then
			return signalModule
		end
	end

	ensureTaskSpawn()
	ok, signalModule = pcall(function()
		return assert(loadfile("Packages/GoodSignal/init.luau"))()
	end)
	if ok and signalModule then
		return signalModule
	end

	error("FriendService failed to load GoodSignal")
end

local GoodSignal = loadGoodSignal()

local FriendService = {
	FriendRequest = GoodSignal.new(),
}

local friendMap = {}

local function ensureFriendSet(playerId)
	if friendMap[playerId] == nil then
		friendMap[playerId] = {}
	end
	return friendMap[playerId]
end

local function isValidPlayerId(playerId)
	return playerId ~= nil
end

function FriendService.AddFriend(playerId, friendId)
	if not isValidPlayerId(playerId) or not isValidPlayerId(friendId) then
		return false
	end
	if playerId == friendId then
		return false
	end

	local playerFriends = ensureFriendSet(playerId)
	local targetFriends = ensureFriendSet(friendId)
	if playerFriends[friendId] then
		return false
	end

	playerFriends[friendId] = true
	targetFriends[playerId] = true
	FriendService.FriendRequest:Fire(playerId, friendId)
	return true
end

function FriendService.RemoveFriend(playerId, friendId)
	if not isValidPlayerId(playerId) or not isValidPlayerId(friendId) then
		return false
	end

	local playerFriends = friendMap[playerId]
	local targetFriends = friendMap[friendId]
	if not playerFriends or not playerFriends[friendId] then
		return false
	end

	playerFriends[friendId] = nil
	if targetFriends then
		targetFriends[playerId] = nil
	end
	return true
end

function FriendService.GetFriends(playerId)
	if not isValidPlayerId(playerId) then
		return {}
	end

	local out = {}
	local playerFriends = friendMap[playerId]
	if not playerFriends then
		return out
	end

	for friendId, _ in pairs(playerFriends) do
		table.insert(out, friendId)
	end
	table.sort(out, function(a, b)
		return tostring(a) < tostring(b)
	end)
	return out
end

function FriendService._ResetForTests()
	friendMap = {}
	FriendService.FriendRequest:DisconnectAll()
	FriendService.FriendRequest = GoodSignal.new()
end

return FriendService
