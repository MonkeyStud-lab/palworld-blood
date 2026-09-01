# Blueprint-first blood (approach #1)

Lua should only **detect hits and pass numbers**. Blueprint `ModActor` should **spawn all FX**.

## Why this exists

UE4SS crashes when Lua spawns Niagara / touches meshes inside (or right after) `MulticastDamageReact`. Blueprint spawning stays inside Unreal’s normal object lifetime.

## Blocker today

Shipped `LogicMods/BloodFX.pak` only exposes:

- `SpawnWallSplatter(Location, Direction, Scale)`

Everything else (hit Niagara, ground decals, pools, head gore) is still spawned from Lua by reading ModActor asset properties.

**To finish approach #1 you must cook a new LogicMod** (extend BloodFX or add `BloodRelay`) in **UE 5.1** with the Palworld Modding Kit:
https://pwmodding.wiki/docs/developers/ue4ss-modding/logic-mods/introduction

## Target ModActor API (Lua will call these)

Add **Custom Events** or **Blueprint Callable** functions on `ModActor`:

| Function | Inputs | Behavior |
|----------|--------|----------|
| `SpawnHitBlood` | `Location` (Vector), `Direction` (Vector), `Scale` (float) | Spawn `HitBloodFX` at location, facing direction. **No mesh attach.** |
| `SpawnGroundBlood` | `Location`, `Direction`, `Count` (int), `Size` (float) | Trace down / place blood decals from `BloodDecalMaterial(s)`. |
| `SpawnWallSplatter` | `Location`, `Direction`, `Scale` | **Already exists** in current pak. |
| `SpawnBloodPoolAt` | `Location`, `bHeadshot` (bool) | Spawn `BP_BloodPool` at location. Do **not** attach to corpse. |
| `SpawnHeadGoreAt` | `Location` | Spawn `HeadGoreFX` at location (world space). Optional short neck spray **unattached**. |

### Rules for BP graphs

1. Use only the vectors Lua passes — do not take an Actor/Mesh from Lua.
2. Prefer `Spawn System at Location` / `Spawn Decal at Location`, never `Attach to Component` from a Lua-held mesh.
3. Keep references to VFX/materials as ModActor defaults (same assets you already use).
4. Cap concurrent FX in BP if needed (e.g. max 8 hit systems).

### Soft asset paths (already in BloodFX.pak)

Examples Lua falls back to today:

- Hit: `/Game/Mods/BloodFX/Realistic_Starter_VFX_Pack_Vol2/Particles/Blood/P_Blood_Splat_Cone.P_Blood_Splat_Cone`
- Pool class: `/Game/Mods/BloodFX/BP_BloodPool.BP_BloodPool_C`

You can keep using ModActor variables `HitBloodFX`, `HeadGoreFX`, `BloodDecalMaterial(s)` as the source assets inside BP.

## Lua side (already in `main.lua`)

With `BP_RELAY.PreferBP = true`, Lua:

1. Snapshots hit location / direction / flags in the damage hook
2. Defers off the native hook
3. Calls the BP functions above when present
4. Falls back to Lua vector spawns if a function is missing (so the current pak still works)

After you cook the new functions, restart the game and check `UE4SS.log` for:

```text
BP RELAY: SpawnHitBlood=yes SpawnGroundBlood=yes ...
```

## Suggested cook layout

Option A — extend original BloodFX ModActor (replace `BloodFX.pak`).  
Option B — new LogicMod `BloodRelay.pak` that soft-references BloodFX assets (keep both paks).

Chunk ID must be unique and non-zero. Pak filename must match the mod folder name for UE4SS LogicMods.

## Test checklist

1. Human hit → ground blood, no crash  
2. Pal hit → ground blood (throttled), no crash  
3. Kill → pool at feet  
4. Human headshot kill → head gore at location (no infinite neck attach)  
5. Log shows BP RELAY methods = yes (not fallback)  
