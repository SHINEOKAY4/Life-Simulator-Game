local PlayerProfileService = {
	profiles = {},
}

local function buildProfile(bio, favoriteColor, joinDate)
	return {
		bio = bio or "",
		favorite_color = favoriteColor or "white",
		join_date = joinDate or os.date("!%Y-%m-%d"),
		last_updated = os.date("!%Y-%m-%d"),
	}
end

function PlayerProfileService.NewPlayer(bio, favoriteColor, joinDate)
	return buildProfile(bio, favoriteColor, joinDate)
end

function PlayerProfileService.SetProfile(playerId, bio, favoriteColor, joinDate)
	if playerId == nil then
		return nil
	end

	local profile = buildProfile(bio, favoriteColor, joinDate)
	PlayerProfileService.profiles[playerId] = profile
	return profile
end

function PlayerProfileService.GetProfile(playerId)
	return PlayerProfileService.profiles[playerId]
end

function PlayerProfileService.UpdateProfile(playerId, newBio, newColor, newJoinDate)
	local profile = PlayerProfileService.profiles[playerId]
	if not profile then
		return false
	end

	if newBio ~= nil then
		profile.bio = newBio
	end
	if newColor ~= nil then
		profile.favorite_color = newColor
	end
	if newJoinDate ~= nil then
		profile.join_date = newJoinDate
	end
	profile.last_updated = os.date("!%Y-%m-%d")
	return true
end

return PlayerProfileService
