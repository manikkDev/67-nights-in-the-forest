--[[
    @file    HarvestController.luau
    @author  manik
    @date    2025

    @summary
    Client-side impact feedback for tree chopping.

    @description
    Listens for the server's TreeChopped signal and applies a short
    procedural camera shake via Humanoid.CameraOffset, decaying over
    time.  Purely cosmetic — no gameplay state is read or written here.

    @exports
    - HarvestController (Knit Controller)
]]

-- // VARIABLES // --

-- | Services | --
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Constants | --
local SHAKE_DURATION = 0.15
local SHAKE_MAGNITUDE = 0.12

-- | Objects | --
local HarvestController = Knit.CreateController({
	Name = "HarvestController",
})

-- // FUNCTIONS // --

--[[
    @summary  Apply a brief decaying random offset to the local
              character's camera to sell a chop impact.
]]
local function shakeCamera()
	task.spawn(function()
		local character = Players.LocalPlayer.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not humanoid then
			return
		end

		local elapsed = 0
		while elapsed < SHAKE_DURATION do
			local dt = task.wait()
			elapsed += dt
			local falloff = 1 - (elapsed / SHAKE_DURATION)
			humanoid.CameraOffset = Vector3.new(
				(math.random() - 0.5) * 2 * SHAKE_MAGNITUDE * falloff,
				(math.random() - 0.5) * 2 * SHAKE_MAGNITUDE * falloff,
				0
			)
		end
		humanoid.CameraOffset = Vector3.zero
	end)
end

-- // INITIALIZATION // --

function HarvestController:KnitStart()
	local harvestService = Knit.GetService("HarvestService")
	harvestService.TreeChopped:Connect(function()
		shakeCamera()
	end)

	print("[HarvestController] Initialised — chop feedback wired")
end

return HarvestController
