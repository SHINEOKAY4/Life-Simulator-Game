return function()
	describe("Source tree smoke", function()
		it("loads src root into ReplicatedStorage", function()
			local replicatedStorage = game:GetService("ReplicatedStorage")
			local srcRoot = replicatedStorage:FindFirstChild("src")

			expect(srcRoot).never.to.equal(nil)
		end)

		it("contains expected top-level folders", function()
			local srcRoot = game:GetService("ReplicatedStorage"):FindFirstChild("src")

			expect(srcRoot:FindFirstChild("Server")).never.to.equal(nil)
			expect(srcRoot:FindFirstChild("Shared")).never.to.equal(nil)
			expect(srcRoot:FindFirstChild("Client")).never.to.equal(nil)
			expect(srcRoot:FindFirstChild("Network")).never.to.equal(nil)
		end)

		it("contains critical service folders", function()
			local serverRoot = game:GetService("ReplicatedStorage"):FindFirstChild("src"):FindFirstChild("Server")
			local services = serverRoot and serverRoot:FindFirstChild("Services")

			expect(services).never.to.equal(nil)
			expect(services:FindFirstChild("BuildService")).never.to.equal(nil)
			expect(services:FindFirstChild("TenantService")).never.to.equal(nil)
			expect(services:FindFirstChild("PlayerSession")).never.to.equal(nil)
		end)

		it("contains shared modules compatibility shims", function()
			local shared = game:GetService("ReplicatedStorage"):FindFirstChild("src"):FindFirstChild("Shared")
			local modules = shared and shared:FindFirstChild("Modules")

			expect(modules).never.to.equal(nil)
		end)
	end)
end
