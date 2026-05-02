# Changelog

## 0.2-dev

- Renamed the active addon from `MeoRaidHots` to `MeoAura`.
- Split the addon into focused modules under `Modules/`.
- Added saved settings, slash commands, and a Blizzard options panel.
- Added friendly raid/group frame aura overlays.
- Added friendly nameplate aura overlays.
- Kept enemy nameplate and arena debuff support in development pending combat-log based tracking.

## 0.1

- Initial `MeoRaidHots` prototype.
- Added enlarged useful HoT icons on Blizzard raid frames.
- Added a dungeon/nameplate safety fix so forbidden Blizzard nameplate frames do not throw `GetName` errors during compact unit frame updates.
