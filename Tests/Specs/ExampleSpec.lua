-- Example spec to prove testing infrastructure works
describe("Example spec", function()
    it("should pass trivially", function()
        assert.equals(true, true)
    end)

    it("should support assertions", function()
        local x = 1 + 1
        assert.equals(2, x)
        assert.is_true(x > 1)
    end)
end)
