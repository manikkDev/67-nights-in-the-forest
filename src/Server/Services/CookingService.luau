--[[
    @file    CookingService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative raw-meat-to-cooked-meat conversion at the Bonfire.

    @description
    Raw meat is converted to cooked meat automatically when it is dropped
    onto the lit Campfire.  Cooked meat restores more Hunger when eaten via
    ForageService's RequestEat.  The actual cooking logic is handled inside
    CampfireService so fueling and cooking share one drop-only interaction.

    @exports
    - (no public API; auto-cook handled by CampfireService)
]]

-- // VARIABLES // --

-- | Services | --
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- | Modules | --
local Knit = require(ReplicatedStorage.Packages.Knit)

-- | Objects | --
local CookingService = Knit.CreateService({
	Name = "CookingService",
})

-- | Configuration | --
-- Drop-only cooking no longer needs range/cooldown constants.

-- | State Management | --
-- Cooking logic now lives in CampfireService to support drop-only cooking.

-- // INITIALIZATION // --

function CookingService:KnitStart()
	-- Raw meat is cooked automatically when dropped onto the lit fire.
	print("[CookingService] Initialised — prompt removed; auto-cook via CampfireService")
end

return CookingService
