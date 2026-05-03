# MeoAura Handoff

Working files:

- [Core.lua](Core.lua)
- [Auras.lua](Auras.lua)
- [Frames.lua](Frames.lua)
- [Config.lua](Config.lua)
- [Modules/RaidHots.lua](Modules/RaidHots.lua)
- [Modules/NameplateDebuffs.lua](Modules/NameplateDebuffs.lua)

## What currently works

- Friendly nameplates show tracked HoTs, externals, and utility spells.
- Raid/group frames show tracked friendly auras.
- Config panel toggles work.
- Login only prints `MeoAura loaded`.

## Open bugs / unfinished work

### 1. Enemy nameplates need a different model

Current Blizzard aura-button styling is too broad for the requirement.
It can show auras from other players, and it cannot reliably mean
`only my dots / CDs / utility`.

Fix:

- Replace enemy nameplate tracking with a combat-log driven cache.
- Key updates off `COMBAT_LOG_EVENT_UNFILTERED`.
- Track auras by destination GUID + spell ID.
- Render only spells that belong to the player and are in the tracked lists.

### 2. Arena work is parked off main

Arena support was removed from the shipping branch after protected-frame
blocking during testing. The experimental combat-log cache work is preserved
on the `arena-module-wip` branch.

### 3. Restricted aura matching caused noise

Several fallback paths for hidden aura names / IDs made enemy frames pick up
unrelated player-cast debuffs.

Fix:

- Do not use broad restricted fallback matching for enemy frames.
- Prefer exact spell IDs from combat log.
- Use a denylist only for rare cases where a tracked aura is too noisy.

### 4. Enemy-frame support needs a clearer spell model

The addon is now conceptually split into:

- friendly HoTs
- externals
- utility
- enemy dots

The remaining work is to define enemy-frame behavior explicitly:

- exact tracked spells
- per-module toggles
- whether a spell belongs on nameplates or future enemy-frame modules

## Recommended next implementation step

1. Add a small combat-log cache module.
2. Record player-cast aura applications/removals by GUID.
3. Feed that cache into enemy nameplate rendering.
4. Keep friendly raid/nameplate code unchanged unless a bug shows up.

## Last known good behavior

- Friendly nameplates are usable.
- Raid/group overlays are usable.
- Enemy Blizzard-button styling is not acceptable for the final requirement.
