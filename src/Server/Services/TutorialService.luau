--!strict
local ServerScriptService = game:GetService("ServerScriptService")

local ServicesFolder = ServerScriptService.Server.Services
local PlayerSession = require(ServicesFolder.PlayerSession)
local CurrencyService = require(ServicesFolder.CurrencyService)

--[[
	Tutorial Plan:
	1. Introduce the player to the game.
	2. Camera work pointing to the new tenant arriving at the plot.
	3. Show players how to get the tenant.
	4. Show them how to get a bed.
	5. Explain how scoring affects income.
	6. Done.
]]

local TutorialService = {}

function TutorialService.Init()
	-- Initialize any listeners if needed
end

function TutorialService.OnPlayerAdded(player: Player)
	local profile = PlayerSession.GetDataAwait(player)
	if not profile then
		return
	end

	local tutorialState = profile.TutorialState
	if not tutorialState then
		-- Handle case where TutorialState might be missing from old profiles (reconciliation should handle this but good to be safe)
		tutorialState = {
			IsCompleted = false,
			Step = 0,
			HasReceivedStartingCash = false,
		}
		profile.TutorialState = tutorialState
	end

	if not tutorialState.HasReceivedStartingCash then
		-- Give 1000 cash
		CurrencyService.Add(player, "Cash", 1000, profile.CurrencyState, { Source = "TutorialStartingCash" })
		tutorialState.HasReceivedStartingCash = true
		print("Given starting cash to " .. player.Name)
	end
end

return TutorialService
