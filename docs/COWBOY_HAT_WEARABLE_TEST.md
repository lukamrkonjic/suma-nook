# Cowboy Hat Wearable Test (Removed)

Status: removed after a successful equipment-pipeline test on 2026-07-27.

This note records how the temporary cowboy hat was prepared and integrated so
the workflow can be reused without keeping the test asset or its runtime code.
The original player model was never meant to be edited for this test.

## Source and Blender preparation

The supplied source was `C:\Users\Luka\Downloads\cowboy-hat.glb`. A working
copy was kept under `art_source/imported/cowboy_hat/`, while the production
asset was generated as `assets/3d/reworked/cowboy_hat.glb`.

The Blender processing script performed these steps:

1. Verified the source SHA-256 before processing.
2. Centered the hat, made it Y-up on GLB export, and normalized the brim to a
   player-appropriate footprint.
3. Merged duplicate vertices and recalculated outward normals.
4. Applied one Catmull-Clark subdivision level. This changed the supplied
   1,000-triangle mesh into a smoother 6,000-triangle real-time mesh.
5. Applied smooth-by-angle shading at 58 degrees, retaining intentional crown
   and brim folds while removing the jagged low-poly silhouette.
6. Preserved UVs and embedded/exported the authored material textures.
7. Increased material roughness to keep the response soft and stylized.
8. Baked the player-specific translation and scale into the GLB. This let the
   normal head-equipment code use its standard `1.35` runtime scale without an
   asset-ID-specific branch.

The fit was reviewed in Godot from front and rear/high angles. The player’s
original green cap is part of the character mesh, so it remained visible
underneath; deleting its triangles also deleted the upper scalp and was
explicitly rejected.

## Wearable integration

The temporary runtime integration used the project’s existing equipment
system:

- An item definition named `cosmetic_cowboy_hat` used category `equipment`,
  slot `head`, and asset ID `cowboy_hat`.
- `AssetLibrary` resolved that ID from `assets/3d/reworked/cowboy_hat.glb`.
- `PlayerVisual.apply_equipment()` instantiated the asset under the existing
  head mount, a `BoneAttachment3D` targeting `mixamorigHead`.
- New games acquired and equipped the item. Existing development saves were
  migrated by granting it when absent, without replacing occupied head slots.
- The Character panel exposed the head slot while combat was disabled.
- `equipment_changed` refreshed `PlayerVisual` immediately, allowing the same
  item to be equipped and removed without a bespoke wearable system.

## Verification used

The focused Godot regression:

- equipped the item through `EquipmentManager`;
- asserted that `cowboy_hat` appeared beneath `HeadMountAttachment`;
- unequipped it and asserted that its node disappeared;
- re-equipped it and generated front and rear/high captures;
- retained and validated the original `suma_player.glb` skeleton and animation
  contract.

The full headless suite passed 640 assertions during the test.

## Reusing the approach

For another removable head asset:

1. Preserve the supplied source under `art_source/imported/`.
2. Process and visually review it in Blender.
3. Bake asset-specific fit into the exported GLB when the common head mount is
   sufficient.
4. Add a head-slot item definition whose `asset_id` matches the GLB filename.
5. Decide explicitly how players acquire it; do not silently migrate it unless
   the asset is intended as a starter item.
6. Verify equip, unequip, bone following, front fit, and rear/top fit in Godot.

## Removed artifacts

The test cleanup removed the production GLB, extracted textures, preserved
working copy, Blender source/render/report, item definition, starter/save
migration, Character-panel exception, immediate-refresh hook added for the
test, dedicated assertions, captures, and focused preview script. The temporary
item was also removed from the owned, equipped, appearance, and collection
fields in both the active development save and its backup so strict save
validation continues to succeed.
