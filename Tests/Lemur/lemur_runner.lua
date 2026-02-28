package.path = table.concat({
	package.path,
	"./?.lua",
	"./?/init.lua",
}, ";")

local lemur = require("vendor.lemur")

local habitat = lemur.Habitat.new()
local game = habitat.game
local replicatedStorage = game:GetService("ReplicatedStorage")

local srcRoot = habitat:loadFromFs("src")
srcRoot.Name = "src"
srcRoot.Parent = replicatedStorage

local testRoot = habitat:loadFromFs("Tests/Lemur/Specs")
testRoot.Name = "LemurSpecs"
testRoot.Parent = replicatedStorage

local testezRoot = habitat:loadFromFs("vendor/testez/src")
testezRoot.Name = "TestEZ"
testezRoot.Parent = replicatedStorage

local TestEZ = habitat:require(replicatedStorage.TestEZ)
local results = TestEZ.TestBootstrap:run({ replicatedStorage.LemurSpecs }, TestEZ.Reporters.TextReporter)

local failureCount = tonumber(results.failureCount) or 0
local errorCount = tonumber(results.errorCount) or 0
if type(results.errors) == "table" then
	errorCount = math.max(errorCount, #results.errors)
end

if failureCount > 0 or errorCount > 0 then
	os.exit(1)
end

os.exit(0)
