# Glossary

Terms used across the codebase and docs.

| Term | Meaning |
|------|---------|
| **Run** | One full play session — lobby → 67 days → results |
| **Campfire** | Central upgradeable hub; its level gates progression |
| **Safe zone** | Radius around the campfire where enemies can't reach you |
| **Boundary** | Circular wall enclosing the playable area; expands with campfire level |
| **Rescue** | The four missing children held in guarded caves |
| **Junk** | Facility pickups that grind into Scrap at the Shredder |
| **Scrap** | Mid-tier crafting resource from the Grinder |
| **Downed** | Incapacitated life state — ragdolled, revivable |
| **Eliminated** | Final life state — becomes a spectator |
| **FlowState** | Client-visible match state (Lobby → InGame) |
| **RunPhase** | Server-side run phase (Lobby/Day/Night/Ending) |
| **LifeState** | Per-player state: Alive / Downed / Eliminated |
| **Two-place architecture** | Lobby start place + reserved Game sub-place per party |
| **Knit** | The framework pattern: server `Service` + client `Controller` pairs |
