# Parties & Teleporting

The experience uses a two-place architecture: a Lobby start place and a Game sub-place where reserved match servers run.

## Places

- `Constants.LOBBY_PLACE_ID` — the start place
- `Constants.GAME_PLACE_ID` — the sub-place (each party gets a reserved server)
- `ServerRole.IsGameServer()` / `IsLobby()` tells code which side it is on

## Forming a party

Step onto a teleporter pad (`Teleporter1`–`3`, `PARTY_QUEUE_IDS`). Party size: 1–5 players (`PARTY_MIN_PLAYERS`/`PARTY_MAX_PLAYERS`).

## Teleport data

Cross-server payloads carry a schema version (`PARTY_TELEPORT_DATA_VERSION` = 1) and are dropped after `PARTY_TELEPORT_DATA_MAX_AGE` = 120s. The destination wait cap is 30s; reconnect tickets live 120s.

## SessionRoutingService

Assembles reserved servers, validates expected member lists (`metadataMatches` compares expected user IDs as a set), and tracks `LocalPartyReady` / `DestinationReady` / `PartyTeleportFailed` signals.
