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

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local services = script.Parent.Services

-- // FUNCTIONS // --

-- // INITIALIZATION // --

for _, module in ipairs(services:GetChildren()) do
	if module:IsA("ModuleScript") then
		require(module)
	end
end

Knit.Start():andThen(function()
	print("[Server] Knit started")
end):catch(warn)
