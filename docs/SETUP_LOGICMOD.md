# Set up Palworld LogicMod tooling (BloodRelay)

Finishes **approach #1**: Blueprint owns blood FX; Lua only relays hit vectors.

Official docs:

- Prerequisites: https://pwmodding.wiki/docs/developers/palworld-modding-kit/prerequisites  
- Installation: https://pwmodding.wiki/docs/developers/palworld-modding-kit/installation  

Need roughly **50–80 GB** free (UE 5.1 + kit + Wwise + cook).

---

## Done on this machine

| Step | Status |
|------|--------|
| .NET 6 SDK | Installed |
| Epic Games Launcher | Installed (UE library opened) |
| VS 2022 Community | Installing / adding C++ + MSVC 14.38 — wait for VS Installer to finish |
| Clone [PalworldModdingKit](https://github.com/localcc/PalworldModdingKit) | `C:\Users\Carde\Projects\PalworldModdingKit\Pal.uproject` |
| Scaffold `Content/Mods/BloodRelay/` | Created + README |
| Editor Python scaffold | `tools/create_bloodrelay_modactor.py` |
| After-UE helper | `tools/after-ue51-installed.ps1` |

Re-run helper anytime:

```powershell
cd C:\Users\Carde\Projects\palworld-blood-both
powershell -ExecutionPolicy Bypass -File tools\setup-logicmod-prereqs.ps1
```

## Hard blockers (I cannot finish these for you)

These need **your Epic / Audiokinetic logins** and multi‑GB downloads:

1. Sign into **Epic** → install **Unreal Engine 5.1**
2. Sign into **Audiokinetic** → install **Wwise 2021.1.11** + offline UE integration into the kit
3. After both succeed, run:

```powershell
powershell -ExecutionPolicy Bypass -File C:\Users\Carde\Projects\palworld-blood-both\tools\after-ue51-installed.ps1
```

That scaffolds ModActor. Niagara/decal graphs + cooking `BloodRelay.pak` still need the Editor (I can walk those once UE opens cleanly).

---

## Finish in the GUI (you must click / sign in)

### 1. Visual Studio **2022** (not 2025/2026)

Installer should already be open. Confirm:

- Workload: **Desktop development with C++**
- Individual component: **MSVC v143 … (v14.38-17.8)**

### 2. Unreal Engine **5.1**

1. Epic Games Launcher → sign in  
2. **Unreal Engine** → **Library** → **+** → install **5.1** (or 5.1.1)

### 3. Wwise **2021.1.11** (required even with no audio)

1. Audiokinetic Launcher: https://www.audiokinetic.com/download/  
2. Account + install Wwise **2021.1.11** (SDK C++, Windows, VS 2022)  
3. Download **Offline Integration Files** for that version  
4. Copy into kit `Plugins\Wwise` (wiki steps)  
5. In `Wwise.uplugin`, set EngineVersion to **5.1**

### 4. Open the kit

Double-click:

`C:\Users\Carde\Projects\PalworldModdingKit\Pal.uproject`

First open **compiles** — be patient.

---

## Create BloodRelay ModActor

Folder (already on disk): `Content/Mods/BloodRelay/`  
See `README_CREATE_MODACTOR.txt` there.

1. Blueprint Actor named exactly **`ModActor`**  
2. **Primary Asset Label**: Chunk **778**, Always Cook, label this directory  
3. BlueprintCallable functions — **exact names Lua expects**:

| Function | Inputs |
|----------|--------|
| `SpawnHitBlood` | Location, Direction, Scale |
| `SpawnGroundBlood` | Location, Direction, Count, Size |
| `SpawnBloodPoolAt` | Location, bHeadshot |
| `SpawnHeadGoreAt` | Location |

World-space spawns only (no mesh attach). Soft-ref `/Game/Mods/BloodFX/...` assets while `BloodFX.pak` is loaded, or copy assets in.

4. Package → rename chunk pak to **`BloodRelay.pak`**  
5. Copy to `Palworld\Pal\Content\Paks\LogicMods\BloodRelay.pak`  
6. Keep `BloodFX.pak` if you soft-ref it  

API details: [`docs/BP_RELAY.md`](BP_RELAY.md)

---

## Verify

In `UE4SS.log` after combat:

```text
BP RELAY: SpawnHitBlood=true SpawnGroundBlood=true ...
```

Then we bump Workshop to 1.1.0.

---

## Common failures

| Error | Fix |
|-------|-----|
| Pal could not be compiled | VS 2022 + MSVC 14.38 + .NET 6 + Wwise |
| Class for ModActor invalid | Pak filename must be `BloodRelay.pak` |
| BP RELAY all false/nil | Wrong function names or ModActor not loaded |
