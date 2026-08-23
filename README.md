# Blood Splatter for Humans + Pals

Standalone UE4SS replacement for [Blood Splatter](https://github.com/petyr1710/blood-splatter) that adds blood FX to **human NPCs and pals**.

**Steam Workshop:** https://steamcommunity.com/sharedfiles/filedetails/?id=3788875509
| Target | Hit spray / decals | Death blood pool | Headshot decapitation |
|--------|--------------------|------------------|------------------------|
| Human NPCs | Yes | Yes | Yes |
| Pals (wild / party / base) | Yes | Yes | No |
| Player | No | No | No |

## Requirements

- UE4SS for Palworld (Workshop or manual)

## Installation

1. **Uninstall the original Blood Splatter mod** (Workshop unsubscribe and/or delete its `BloodAndDecapitation` folder and `BloodFX.pak`). Loading both will double-hook damage and can crash or duplicate FX.
2. Copy `BloodAndDecapitation` into your UE4SS `Mods` folder:
   - Workshop UE4SS: `Palworld\Mods\NativeMods\UE4SS\Mods\`
   - Manual UE4SS: e.g. `Palworld\Pal\Binaries\Win64\ue4ss\Mods\`
3. Copy `LogicMods\BloodFX.pak` into `Palworld\Pal\Content\Paks\LogicMods\` (create `LogicMods` if needed).

## Debug

In-game, press **Ctrl+F8** to dump loaded `PalCharacter` class ancestry and human/pal/player classification to `UE4SS.log`.

## Credits

- Original Blood Splatter mod by [petyr1710](https://github.com/petyr1710/blood-splatter)
- VFX pack: [Realistic Blood VFX by Hivemind](https://fab.com/s/cfc2f41832a0) (bundled via upstream `BloodFX.pak`)

## Notes

- Client-side visuals only; does not change save data.
- After a Palworld update, wait for a compatible UE4SS build before using this mod.
- Pal surface wound overlays and pal decapitation are intentionally out of scope (per-species skeletons).
