--[[
    @file    Constants.luau
    @author  manik
    @date    2025

    @summary
    Shared constants replicated to both client and server.

    @description
    Central place for game-wide constants that both sides need.
    Add values here as the codebase grows across phases.
]]

return {
	STORE_NAME = "67Nights_v2",
	MAX_PLAYERS = 8,
	ITEMS_PATH = "Assets Items",
	MATCH_WAIT_SECONDS = 3599,
	MATCH_START_FADE_SECONDS = 0.6,

	-- Create-Party intro sequence
	MATCH_COUNTDOWN_SECONDS = 5,
	MATCH_STORY_FADE_SECONDS = 1.2,
	MATCH_STORY_HOLD_SECONDS = 5,
	MATCH_DAY1_HOLD_SECONDS = 2,
	MATCH_REVEAL_SECONDS = 2.5,
}
