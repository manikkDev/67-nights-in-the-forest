--[[
    @file    ProfileTemplate.luau
    @author  manik
    @date    2025

    @summary
    Default data template applied to every new player profile.

    @description
    Returned as a plain table. ProfileService deep-copies this template
    into a fresh profile via the `template` field of `ProfileStore`.
    All fields are server-authoritative; the client may never write
    to them directly.
]]

return {
	NightsSurvived = 0,
	Hunger = 100,
	MaxHunger = 100,
	Inventory = {},
}
