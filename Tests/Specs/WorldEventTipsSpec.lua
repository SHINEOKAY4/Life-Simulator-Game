--!strict
-- Tests/Specs/WorldEventTipsSpec.lua
-- Validates that WorldEventService TipMultiplier buffs are applied in TipsService.

local function loadModule(path)
	return assert(loadfile(path))()
end

describe("TipsService integrates WorldEventService TipMultiplier", function()
	local tipsService
	local worldEventService
	local originalHttpService
	local originalInstance
	local originalRaycastParams
	local originalVector3
	local originalCFrame

	before_each(function()
		originalHttpService = _G.HttpService
		originalInstance = _G.Instance
		originalRaycastParams = _G.RaycastParams
		originalVector3 = _G.Vector3
		originalCFrame = _G.CFrame

		_G.HttpService = { GenerateGUID = function() return "tip-id" end }
		_G.Instance = {
			new = function(className)
				return { ClassName = className }
			end,
		}
		_G.Enum = { RaycastFilterType = { Exclude = "Exclude" } }
		_G.RaycastParams = {
			new = function()
				return { FilterType = nil, FilterDescendantsInstances = nil }
			end,
		}
		_G.Vector3 = { new = function(x, y, z) return { X = x, Y = y, Z = z } end, zero = {} }
		_G.CFrame = { new = function(position) return { Position = position } end }

		_G.game = {
			GetService = function(_, serviceName)
				if serviceName == "ReplicatedStorage" then
					return {
						Network = {
							TipsPackets = {
								TipDropped = {
									FireClient = function() end,
								},
								ClaimTip = {
									OnServerEvent = { Connect = function() end },
								},
							},
						},
					}
				end
				if serviceName == "ServerScriptService" then
					return {
						Server = {
							Services = {
								CurrencyService = {
									Add = function() end,
								},
								PlayerSession = {
									GetDataAwait = function() return { Cash = 0 } end,
								},
								ResidentService = {
									GetResidents = function() return {} end,
								},
								WorldEventService = loadModule("src/Server/Services/WorldEventService.luau"),
							},
							Utilities = {
								WorldUpdate = { Subscribe = function() end },
							},
						},
					}
				end
				if serviceName == "Workspace" then
					return {
						Raycast = function()
							return nil
						end,
					}
				end
				if serviceName == "Players" then
					return { GetPlayers = function() return {} end }
				end
				return {}
			end,
		}

		tipsService = loadModule("src/Server/Services/TipsService.luau")
		worldEventService = loadModule("src/Server/Services/WorldEventService.luau")
	end)

	after_each(function()
		_G.HttpService = originalHttpService
		_G.Instance = originalInstance
		_G.RaycastParams = originalRaycastParams
		_G.Vector3 = originalVector3
		_G.CFrame = originalCFrame
		_G.game = nil
	end)

	it("applies the TipMultiplier buff when spawning tips", function()
		local injectedWorldEventService = _G.game:GetService("ServerScriptService").Server.Services.WorldEventService
		injectedWorldEventService._ResetForTests()
		injectedWorldEventService._SetClock(function() return 100 end)
		injectedWorldEventService._SetRng(function() return 3 end)
		injectedWorldEventService.GetStateSnapshot(nil)
		tipsService._SetWorldEventServiceForTests(injectedWorldEventService)

		local capturedAmount
		local function attachTipCapture()
			local patched = {
				TipDropped = {
					FireClient = function(_, firstArg, secondArg)
						local payload = secondArg or firstArg
						if type(payload) == "table" then
							capturedAmount = payload.Amount
						end
					end,
				},
			}
			if tipsService._SetPacketsForTests then
				tipsService._SetPacketsForTests(patched)
				return
			end
			if tipsService._TipsPackets ~= nil then
				tipsService._TipsPackets = patched
				return
			end
			local upvalueName
			local upvalueIndex
			local index = 1
			while true do
				local name, _ = debug.getupvalue(tipsService.SpawnTip, index)
				if not name then
					break
				end
				if name == "TipsPackets" then
					upvalueName = name
					upvalueIndex = index
					debug.setupvalue(tipsService.SpawnTip, upvalueIndex, patched)
					break
				end
				index = index + 1
			end
			assert.is_truthy(upvalueName == "TipsPackets")
		end

		attachTipCapture()
		local player = { UserId = 1, Character = nil }
		tipsService.SpawnTip(player, "Resident", 10, nil, "Test")

		assert.equals(13, capturedAmount)
	end)

	it("falls back to base amount when TipMultiplier is invalid", function()
		local capturedAmount
		local function attachTipCapture()
			local patched = {
				TipDropped = {
					FireClient = function(_, firstArg, secondArg)
						local payload = secondArg or firstArg
						if type(payload) == "table" then
							capturedAmount = payload.Amount
						end
					end,
				},
			}
			if tipsService._SetPacketsForTests then
				tipsService._SetPacketsForTests(patched)
				return
			end
			if tipsService._TipsPackets ~= nil then
				tipsService._TipsPackets = patched
				return
			end
			local index = 1
			while true do
				local name = debug.getupvalue(tipsService.SpawnTip, index)
				if not name then
					break
				end
				if name == "TipsPackets" then
					debug.setupvalue(tipsService.SpawnTip, index, patched)
					break
				end
				index = index + 1
			end
		end

		local index = 1
		while true do
			local name = debug.getupvalue(tipsService.SpawnTip, index)
			if not name then
				break
			end
			if name == "getTipMultiplier" then
				debug.setupvalue(tipsService.SpawnTip, index, function() return -5 end)
				break
			end
			index = index + 1
		end

		attachTipCapture()
		local player = { UserId = 7, Character = nil }
		tipsService.SpawnTip(player, "Resident", 10, nil, "Test")

		assert.equals(10, capturedAmount)
	end)
end)
