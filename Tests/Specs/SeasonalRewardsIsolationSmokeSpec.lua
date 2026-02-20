--!strict
-- Smoke test: ensure the seasonal rewards integration spec can run in isolation.

describe("Seasonal Rewards Isolation Smoke", function()
	it("runs the seasonal rewards integration spec in isolation", function()
		local logPath = "/tmp/seasonal_rewards_integration_smoke.log"
		local cmd =
			"PATH=\"$HOME/.luarocks/bin:$PATH\" busted Tests/Specs/SeasonalRewardsIntegrationSpec.lua > "
			.. logPath
			.. " 2>&1"
		local ok, reason, code = os.execute(cmd)

		local passed = false
		local exitCode = -1
		if type(ok) == "number" then
			exitCode = ok
			passed = ok == 0
		elseif type(ok) == "boolean" then
			exitCode = code or (ok and 0 or 1)
			passed = ok and exitCode == 0 and reason == "exit"
		end

		if not passed then
			local output = "(no output captured)"
			local handle = io.open(logPath, "r")
			if handle then
				output = handle:read("*a") or output
				handle:close()
			end
			error(
				string.format(
					"Isolated integration run failed (exit=%s).\nCommand: %s\nOutput:\n%s",
					tostring(exitCode),
					cmd,
					output
				)
			)
		end
	end)
end)
