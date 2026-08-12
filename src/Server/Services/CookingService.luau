--[[
    @file    CookingService.luau
    @author  manik
    @date    2025

    @summary
    Server-authoritative raw-meat-to-cooked-meat conversion at the Bonfire.

    @description
    Wires a "Cook Meat" ProximityPrompt onto the Campfire anchor.  While
    the fire is lit, triggering it converts all of the player's carried
    RawMeat into CookedMeat (which restores more Hunger when eaten via
    ForageService's RequestEat).  Mirrors CampfireService's all-at-once
    feed pattern for consistency.

    @exports
    - (no public API; entirely ProximityPrompt driven)
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
