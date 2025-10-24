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
Constants.BEG_PAYOUT_CHANCE = 0.05 -- 5% chance per tick to earn money (nerfed from 15%)
Constants.BEG_PAYOUT_MIN = 0 -- Minimum payout when successful (can be $0)
Constants.BEG_PAYOUT_MAX = 2 -- Maximum payout when successful (nerfed from 5)
Constants.BEG_CHAT_LINES = {
	"Spare a little change?",
	"Anything helps, thank you...",
	"Trying to make it through the day...",
}
Constants.BEG_ROAM_MIN_DISTANCE = 10 -- Minimum distance from spawn to roam
Constants.BEG_ROAM_MAX_DISTANCE = 25 -- Maximum distance from spawn to roam
Constants.BEG_ROAM_HEIGHT_OFFSET = 0
Constants.BEG_MOVE_TIMEOUT_SECONDS = 12
Constants.BEG_ROAM_INTERVAL_SECONDS = 8 -- How often to pick a new roam spot while begging

return Constants
