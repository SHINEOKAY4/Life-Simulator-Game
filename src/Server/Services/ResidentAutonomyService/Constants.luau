--!strict

local Constants = {}

Constants.AUTONOMY_TASK = "ResidentAutonomy"
Constants.AUTONOMY_INTERVAL = 1.0
Constants.ROAM_ACTION_NAME = "Auto:Roam"
Constants.ROAM_MIN_INTERVAL_SECONDS = 15

Constants.INTERRUPTED_NEED_RETRY_SECONDS = 3
Constants.FORCED_NEED_TIMEOUT_SECONDS = 6

Constants.JOG_ACTION_NAME = "Auto:Jog"
Constants.JOG_MIN_INTERVAL_SECONDS = 20 -- Reduced from 45 so jogging happens more often
Constants.JOG_DURATION_SECONDS = 30 -- Total time spent jogging (like using a station)
Constants.JOG_TICK_INTERVAL = 3 -- How often to update Fun during jog (every 3 seconds)
Constants.JOG_FUN_PER_TICK = 6 -- Fun gained per tick (30s / 3s = 10 ticks * 6 = 60 total Fun)
Constants.JOG_MOVE_SPEED_MULTIPLIER = 1.8 -- Run faster than normal walk (increased from 1.5)
Constants.JOG_MOVE_TIMEOUT_SECONDS = 12 -- Increased timeout for longer distances
Constants.JOG_WAYPOINT_COUNT = 8 -- More waypoints for continuous movement
Constants.JOG_CHAT_LINES = {
	"Going for a jog!",
	"Time for some exercise.",
	"Running around to clear my head.",
}

return Constants
