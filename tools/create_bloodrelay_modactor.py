"""
Run inside Unreal Editor (Palworld Modding Kit) to create BloodRelay ModActor.

Usage (after kit opens successfully):
  Tools -> Execute Python Script -> this file
OR command line:
  UnrealEditor-Cmd.exe "C:/Users/Carde/Projects/PalworldModdingKit/Pal.uproject" -ExecutePythonScript="C:/Users/Carde/Projects/palworld-blood-both/tools/create_bloodrelay_modactor.py"

Creates:
  /Game/Mods/BloodRelay/ModActor
  /Game/Mods/BloodRelay/PAL_BloodRelay  (PrimaryAssetLabel, chunk 778)

Adds BlueprintCallable stub functions matching Lua:
  SpawnHitBlood, SpawnGroundBlood, SpawnBloodPoolAt, SpawnHeadGoreAt

You still need to fill each function graph with Niagara/decal spawns in the Editor.
"""

import unreal

MOD_PATH = "/Game/Mods/BloodRelay"
MOD_ACTOR_NAME = "ModActor"
LABEL_NAME = "PAL_BloodRelay"
CHUNK_ID = 778

def ensure_folder(path: str):
    if not unreal.EditorAssetLibrary.does_directory_exist(path):
        unreal.EditorAssetLibrary.make_directory(path)
        unreal.log(f"Created folder {path}")

def create_mod_actor():
    asset_path = f"{MOD_PATH}/{MOD_ACTOR_NAME}"
    if unreal.EditorAssetLibrary.does_asset_exist(asset_path):
        unreal.log(f"ModActor already exists: {asset_path}")
        return unreal.EditorAssetLibrary.load_asset(asset_path)

    factory = unreal.BlueprintFactory()
    factory.set_editor_property("parent_class", unreal.Actor)
    asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
    bp = asset_tools.create_asset(MOD_ACTOR_NAME, MOD_PATH, unreal.Blueprint, factory)
    unreal.EditorAssetLibrary.save_asset(asset_path)
    unreal.log(f"Created {asset_path}")
    return bp

def create_primary_asset_label():
    asset_path = f"{MOD_PATH}/{LABEL_NAME}"
    if unreal.EditorAssetLibrary.does_asset_exist(asset_path):
        unreal.log(f"PrimaryAssetLabel already exists: {asset_path}")
        return unreal.EditorAssetLibrary.load_asset(asset_path)

    factory = unreal.DataAssetFactory()
    # PrimaryAssetLabel is the class used for chunking LogicMods
    try:
        factory.set_editor_property("data_asset_class", unreal.PrimaryAssetLabel)
    except Exception:
        pass

    asset_tools = unreal.AssetToolsHelpers.get_asset_tools()
    label = asset_tools.create_asset(LABEL_NAME, MOD_PATH, unreal.PrimaryAssetLabel, factory)
    if not label:
        unreal.log_error("Failed to create PrimaryAssetLabel — create it manually in Editor.")
        return None

    # Chunk / cook settings (property names vary slightly by UE version)
    for prop, value in (
        ("chunk_id", CHUNK_ID),
        ("cook_rule", unreal.PrimaryAssetCookRule.ALWAYS_COOK),
        ("label_assets_in_my_directory", True),
    ):
        try:
            label.set_editor_property(prop, value)
        except Exception as ex:
            unreal.log_warning(f"Could not set {prop}: {ex}")

    unreal.EditorAssetLibrary.save_asset(asset_path)
    unreal.log(f"Created {asset_path} chunk={CHUNK_ID}")
    return label

def add_stub_functions(bp):
    """
    UE Python cannot reliably author full Blueprint graphs for Niagara spawns.
    This logs the required function signatures for manual wiring.
    """
    required = [
        "SpawnHitBlood(Location, Direction, Scale)",
        "SpawnGroundBlood(Location, Direction, Count, Size)",
        "SpawnBloodPoolAt(Location, bHeadshot)",
        "SpawnHeadGoreAt(Location)",
    ]
    unreal.log("=== Add these BlueprintCallable functions on ModActor ===")
    for line in required:
        unreal.log(f"  - {line}")
    unreal.log("Implement with Spawn System at Location / Spawn Decal at Location only.")
    unreal.log("See docs/BP_RELAY.md in palworld-blood-both.")

def main():
    ensure_folder(MOD_PATH)
    bp = create_mod_actor()
    create_primary_asset_label()
    if bp:
        add_stub_functions(bp)
    unreal.EditorAssetLibrary.save_directory(MOD_PATH)
    unreal.log("BloodRelay scaffold done.")

if __name__ == "__main__":
    main()
