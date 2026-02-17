--!strict
-- Unit tests for FriendService

local FriendService = assert(loadfile("src/Server/Services/FriendService.luau"))()

describe("FriendService", function()
	before_each(function()
		FriendService._ResetForTests()
	end)

	it("should add friend relationship bi-directionally", function()
		local added = FriendService.AddFriend(1, 2)
		assert.is_true(added)

		local p1Friends = FriendService.GetFriends(1)
		local p2Friends = FriendService.GetFriends(2)

		assert.equals(1, #p1Friends)
		assert.equals(2, p1Friends[1])
		assert.equals(1, #p2Friends)
		assert.equals(1, p2Friends[1])
	end)

	it("should fire FriendRequest signal on add", function()
		local firedPlayerId, firedFriendId
		FriendService.FriendRequest:Connect(function(playerId, friendId)
			firedPlayerId = playerId
			firedFriendId = friendId
		end)

		local added = FriendService.AddFriend("a", "b")
		assert.is_true(added)
		assert.equals("a", firedPlayerId)
		assert.equals("b", firedFriendId)
	end)

	it("should not add duplicate friend relationship", function()
		assert.is_true(FriendService.AddFriend(10, 11))
		assert.is_false(FriendService.AddFriend(10, 11))
	end)

	it("should reject adding self as friend", function()
		assert.is_false(FriendService.AddFriend(8, 8))
	end)

	it("should reject nil ids on add", function()
		assert.is_false(FriendService.AddFriend(nil, 2))
		assert.is_false(FriendService.AddFriend(1, nil))
	end)

	it("should remove existing friend relationship from both sides", function()
		assert.is_true(FriendService.AddFriend(4, 5))
		assert.is_true(FriendService.RemoveFriend(4, 5))

		assert.equals(0, #FriendService.GetFriends(4))
		assert.equals(0, #FriendService.GetFriends(5))
	end)

	it("should return false when removing non-existent relationship", function()
		assert.is_false(FriendService.RemoveFriend(20, 21))
	end)

	it("should return sorted friend list", function()
		assert.is_true(FriendService.AddFriend(100, "zeta"))
		assert.is_true(FriendService.AddFriend(100, "alpha"))
		assert.is_true(FriendService.AddFriend(100, "delta"))

		local friends = FriendService.GetFriends(100)
		assert.same({ "alpha", "delta", "zeta" }, friends)
	end)
end)
