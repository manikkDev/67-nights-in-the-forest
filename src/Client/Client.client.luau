--[[
    @file    Client.client.luau
    @author  manik
    @date    2025

    @summary
    Client-side Knit bootstrapper.

    @description
    Requires every ModuleScript inside `src/Client/Controllers`, then
    starts the Knit framework.  Each controller registers itself with
    Knit at require-time, so order does not matter.
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local controllers = script.Parent.Controllers

-- // FUNCTIONS // --

-- // INITIALIZATION // --

for _, module in ipairs(controllers:GetChildren()) do
	if module:IsA("ModuleScript") then
		local ok, err = pcall(require, module)
		if not ok then
			warn("[Client] Failed to require controller", module.Name, "-", err)
		end
	end
end

Knit.Start():andThen(function()
	print("[Client] Knit started")
end):catch(warn)
