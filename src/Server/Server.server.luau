--[[
    @file    Server.server.luau
    @author  manik
    @date    2025

    @summary
    Server-side Knit bootstrapper.

    @description
    Requires every ModuleScript inside `src/Server/Services`, then
    starts the Knit framework.  Each service registers itself with
    Knit at require-time, so order does not matter.
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- | Early Sanitization | --
-- The packaged "crafting-table" asset in Workspace ships with nested
-- PackageLink / TextureConfiguration / ModuleScript / Sound content that
-- calls require() on unowned asset IDs and loads unauthorized sounds.
-- These scripts execute on game load before Knit starts.  Strip them as
-- early as possible to minimize the error burst.
do
	local function sanitizeCraftingTable()
		local bench = Workspace:FindFirstChild("crafting-table")
		if not bench then return end
		local doomed: { Instance } = {}
		for _, desc in ipairs(bench:GetDescendants()) do
			local className = desc.ClassName
			if desc:IsA("BaseScript")
				or desc:IsA("ModuleScript")
				or desc:IsA("PackageLink")
				or desc:IsA("TextureConfiguration")
				or desc:IsA("Sound")
				or className == "Package"
				or className == "Configuration"
			then
				table.insert(doomed, desc)
			end
		end
		for _, inst in ipairs(doomed) do
			inst:Destroy()
		end
	end
	sanitizeCraftingTable()
end

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local services = script.Parent.Services

-- // FUNCTIONS // --

-- // INITIALIZATION // --

local failedServices: { string } = {}
for _, module in ipairs(services:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, err = pcall(require, module)
		if not ok then
			table.insert(failedServices, module.Name)
			warn("[Server] Failed to require service", module.Name, "-", err)
		end
	end
end

-- A missing service leaves every dependent system silently degraded, so
-- refuse to boot a partial game: surface a single loud startup failure
-- instead of letting players into a broken server.
if #failedServices > 0 then
	error(("[Server] Startup aborted — %d service(s) failed to load: %s")
		:format(#failedServices, table.concat(failedServices, ", ")))
end

Knit.Start():andThen(function()
	print("[Server] Knit started")
end):catch(warn)
