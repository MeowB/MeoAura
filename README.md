# Meo Aura

Meo Aura is a World of Warcraft addon that adds custom aura overlays to Blizzard raid and nameplate frames.

The current development build is `0.2-dev`. Friendly raid and nameplate overlays are usable; enemy-frame tracking is still being redesigned so it can rely on exact player-cast aura data.

## Features

- Enlarged tracked HoTs, externals, and utility auras on friendly raid/group frames.
- Friendly nameplate aura overlays.
- Blizzard options panel for module toggles and icon sizes.
- Slash commands for quick testing and configuration.
- Saved settings through `MeoAuraDB`.

## Installation

1. Download or clone this repository.
2. Copy the repository folder into your World of Warcraft addons directory.
3. Make sure the installed folder is named `MeoAura`.
4. Restart WoW or run `/reload`.

The addon manifest is [MeoAura.toc](MeoAura.toc), and the root folder is now structured as the loadable addon folder.

## Project Layout

- [MeoAura.toc](MeoAura.toc): WoW addon manifest and module load order.
- [Core.lua](Core.lua): addon namespace, saved settings, slash commands, event dispatch, and module registration.
- [Auras.lua](Auras.lua): shared aura reading and filtering helpers.
- [Frames.lua](Frames.lua): frame safety checks and aura overlay rendering.
- [Config.lua](Config.lua): Blizzard options panel.
- [Modules/RaidHots.lua](Modules/RaidHots.lua): compact party/raid HoT overlays.
- [Modules/NameplateDebuffs.lua](Modules/NameplateDebuffs.lua): nameplate debuff overlays.
- [archive/0.1](archive/0.1): preserved legacy `MeoRaidHots` version `0.1` snapshot.
- [docs/assets](docs/assets): reference images and documentation assets.

## Slash Commands

- `/meoaura`, `/meo`, or `/mrh`: open options and print status.
- `/meo status`: print module status.
- `/meo debug`: run raid-frame debug output.
- `/meo debug nameplate`: dump visible nameplate frame/unit/aura diagnostics as a Lua error popup.
- `/meo raid on|off`: toggle raid HoTs.
- `/meo nameplate on|off`: toggle nameplate debuffs.
- `/meo nameplate size 40`: force nameplate debuff icon size for visual testing.
- `/meo nameplate count 8`: set visible nameplate aura slots.
- `/meo nameplate test`: show a forced test icon above visible nameplates.
- `/meo nameplate all|player`: show all timed debuffs or only player-cast timed debuffs.
- `/meo category hots on|off`: toggle HoT category.
- `/meo category dots on|off`: toggle DoT category.
- `/meo category externals on|off`: toggle external defensive category.
- `/meo category utility on|off`: toggle utility buff category.

## Development Notes

See [NEXT_STEPS.md](NEXT_STEPS.md) for the current handoff notes and known unfinished work.

This repository does not currently declare a license.
