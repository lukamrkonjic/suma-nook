# Cowboy Vest Wardrobe Integration

This is the reference implementation for a deforming body garment in Suma
Nook. The canonical character geometry, material, skin, animation, and
34-bone skeleton remain the wardrobe standard. Its GLB now also carries the
shared semantic armor-region IDs in UV2; the clean pre-bake GLB is preserved
under `art_source/blender/`.

## Production files

- Supplied source, preserved unchanged:
  `art_source/imported/cowboy_vest/cowboy_vest_source.glb`
- Reproducible Blender processor:
  `art_source/blender/process_cowboy_vest.py`
- Editable Blender source:
  `art_source/blender/cowboy_vest/cowboy_vest.blend`
- Production wardrobe bundle:
  `assets/3d/reworked/cowboy_vest.glb`
- Blender processing report:
  `art_source/blender/cowboy_vest/process_report.json`
- Godot runtime/import probe:
  `tests/cowboy_vest_probe.gd`
- Godot capture scene:
  `tests/CowboyVestReview.tscn`

## Fit and skinning procedure

1. Import the current production player and the garment into Blender.
2. Keep the player in its evaluated rest pose and fit the separate garment
   over that body. The fitted source scale is `(0.56, 0.50, 0.40)` with a
   Blender-space offset of `(0.0, -0.015, 0.0)`.
3. Merge coincident source vertices, recalculate normals, apply one
   Catmull-Clark subdivision level, and smooth by a 55-degree angle. This
   removes the supplied mesh's jagged silhouette without changing its design.
4. Add a localized 10 mm normal clearance and 8 mm lateral overlap to the
   upper outer yoke. This keeps the vest outside the shoulder silhouette while
   leaving the torso dimensions and sleeveless armholes unchanged.
5. Copy all body vertex-group weights with Blender Data Transfer using
   `POLYINTERP_NEAREST` (Nearest Face Interpolated), limit each vertex to four
   influences, and normalize. Every exported vest vertex is weighted.
6. Use the exact production player armature and matching bone-group names.
7. Create `BodyExposedForCowboyVest` from the canonical skinned body. Remove
   only 79 triangles centered safely beneath the broad back panel. The front,
   collar, sleeves, armholes, and hem are retained so no visible holes appear.
8. Export the garment and exposed-body mesh together with the helper copy of
   the production skeleton. The GLB contains:
   - `CowboyVest`
   - `BodyExposedForCowboyVest`
   - one 34-bone `Skeleton3D`

## Runtime equipment behavior

`PlayerVisual` instantiates the wardrobe bundle, detaches both skinned meshes
from the bundle's helper skeleton, and reparents them to the already-running
player `Skeleton3D`. Their `Skin` resources and `skeleton = ".."` bindings are
preserved. The helper skeleton is discarded, leaving exactly one live
skeleton.

While the vest is equipped, the canonical body mesh is hidden and
`BodyExposedForCowboyVest` renders in its place with the same player shader.
Unequipping frees both wardrobe meshes and makes the untouched canonical body
visible again.

The vest also declares six reversible coverage points:
`clavicle_l`, `shoulder_l`, `upper_chest_l`, and their right-side partners.
The finer `shoulder_cap`, `armpit`, and `upper_arm_inner` points remain
available but visible for this sleeveless garment. The cap is part of the
player silhouette, so its collision is solved by the vest's authored
clearance rather than creating a body hole.

The item id is `cosmetic_cowboy_vest`. It occupies the `body` slot, is granted
to new and existing development saves, starts equipped when the body slot is
empty, appears in the Character panel, and responds immediately to
equip/unequip changes.

## Rebuild and review

```powershell
node "C:\Dev\suma-nook\tools\bake_player_armor_regions.js" `
  "C:\Dev\suma-nook\art_source\blender\suma_player_pre_armor_regions.glb" `
  "C:\Dev\suma-nook\assets\3d\reworked\suma_player.glb"

& "C:\Software\Blender\blender.exe" --background `
  --python "C:\Dev\suma-nook\art_source\blender\process_cowboy_vest.py"

& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" `
  --headless --path "C:\Dev\suma-nook" --import

& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" `
  --headless --path "C:\Dev\suma-nook" `
  --script res://tests/cowboy_vest_probe.gd

& "C:\Dev\Godot\Godot_v4.6.3-stable_win64_console.exe" `
  --path "C:\Dev\suma-nook" --resolution 900x900 `
  res://tests/CowboyVestReview.tscn -- `
  --shot-dir=res://docs/cowboy_vest_review
```

Review captures are written to `docs/cowboy_vest_review/`.

## Reusing the flow

For another deforming garment, keep the same rest-pose player and armature,
perform the same interpolated weight transfer, and export a semantic garment
mesh plus a conservative `BodyExposedFor*` clone. Rigid wearables such as hats
should continue to use a `BoneAttachment3D` instead of skinning.

Define coverage with `hide_regions` on the item. Prefer interior regions
fully enclosed by the garment. If a body triangle contributes to the visible
silhouette, give the garment physical clearance instead of masking that
triangle. See `docs/PLAYER_ARMOR_REGIONS.md` for the complete contract.

AI-generated clothing is only a shape source. It still needs deliberate fit,
topology cleanup, weight transfer, deformation review, and a conservative
body-coverage pass before it is production wardrobe content.
