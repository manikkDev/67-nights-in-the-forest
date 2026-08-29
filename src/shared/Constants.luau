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

	-- Place IDs for the two-place architecture.
	-- LOBBY_PLACE_ID is the start place (where players form parties).
	-- GAME_PLACE_ID is the sub-place (where reserved match servers run).
	-- Fill in GAME_PLACE_ID after creating the sub-place on the Creator Dashboard.
	LOBBY_PLACE_ID = 84560195693908,
	GAME_PLACE_ID = 0, -- TODO: set after creating the game sub-place

	PARTY_MIN_PLAYERS = 1,
	PARTY_MAX_PLAYERS = 5,
	PARTY_QUEUE_IDS = { "Teleporter1", "Teleporter2", "Teleporter3" },
	PARTY_REQUEST_COOLDOWN = 0.35,
	PARTY_TELEPORT_DATA_VERSION = 1,
	PARTY_TELEPORT_DATA_MAX_AGE = 120,
	PARTY_DESTINATION_WAIT_SECONDS = 30,
	PARTY_RECONNECT_TICKET_SECONDS = 120,
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
