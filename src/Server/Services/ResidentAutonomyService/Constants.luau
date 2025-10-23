--!strict

local Constants = {}

Constants.AUTONOMY_TASK = "ResidentAutonomy"
Constants.AUTONOMY_INTERVAL = 1.0
Constants.ROAM_ACTION_NAME = "Auto:Roam"
Constants.ROAM_MIN_INTERVAL_SECONDS = 15

Constants.BEG_ACTION_NAME = "Auto:Beg"
Constants.BEG_ACTION_LABEL = "beg"
Constants.BEG_TICK_SECONDS = 1
Constants.BEG_CHAT_INTERVAL_SECONDS = 18
Constants.BEG_STATION_REFRESH_INTERVAL = 5
Constants.BEG_PAYOUT_CURRENCY = "Cash"
Constants.BEG_PAYOUT_PER_SECOND = 0.2
Constants.BEG_CHAT_LINES = {
	"Spare a little change?",
	"Anything helps, thank you...",
	"Trying to make it through the day...",
}
Constants.BEG_SPOT_FORWARD_OFFSET = 14
Constants.BEG_SPOT_LATERAL_JITTER = 6
Constants.BEG_SPOT_HEIGHT_OFFSET = 0
Constants.BEG_SPOT_FORWARD_VARIANCE = 4
Constants.BEG_SPOT_MAX_ANGLE_DEGREES = 30
Constants.BEG_MOVE_TIMEOUT_SECONDS = 12

return Constants
