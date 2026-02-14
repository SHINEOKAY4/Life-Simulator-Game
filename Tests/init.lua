-- Life-Simulator-Game Test Suite
-- Runs tests using busted (https://github.com/lunarmodules/busted)

-- Run all specs in Tests/Specs/
print("Running Life-Simulator-Game test suite...")

if success then
    print("All tests passed! ✓")
else
    print("Some tests failed!")
    print(result)
    error("Tests failed", 0)
end

return success
