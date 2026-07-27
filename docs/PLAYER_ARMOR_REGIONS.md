# Player Armor Regions

Suma's armor coverage system is adapted from Imota Idle's Armor Studio
contract. It is reversible and data-driven: the production body stores one
stable semantic region ID per triangle in `UV2.x`, while an equipped item
lists the regions it safely encloses in `hide_regions`.

`PlayerVisual` unions those names into a per-instance `hide_mask`.
`player_character.gdshader` discards only body triangles whose UV2 region bit
is set. Unequipping clears the mask; it never deletes or edits the live player
mesh.

## Stable region IDs

| ID | Region | ID | Region |
|---:|---|---:|---|
| 0 | `head` | 16 | `foot_l` |
| 1 | `neck` | 17 | `thigh_r` |
| 2 | `chest` | 18 | `knee_r` |
| 3 | `abdomen` | 19 | `shin_r` |
| 4 | `hips` | 20 | `foot_r` |
| 5 | `shoulder_l` | 21 | `clavicle_l` |
| 6 | `upper_arm_l` | 22 | `shoulder_cap_l` |
| 7 | `forearm_l` | 23 | `armpit_l` |
| 8 | `hand_l` | 24 | `upper_chest_l` |
| 9 | `shoulder_r` | 25 | `upper_arm_inner_l` |
| 10 | `upper_arm_r` | 26 | `clavicle_r` |
| 11 | `forearm_r` | 27 | `shoulder_cap_r` |
| 12 | `hand_r` | 28 | `armpit_r` |
| 13 | `thigh_l` | 29 | `upper_chest_r` |
| 14 | `knee_l` | 30 | `upper_arm_inner_r` |
| 15 | `shin_l` |  |  |

IDs are append-only because existing asset masks depend on their bit
positions. ID 31 is intentionally unused so the Godot-to-GLSL mask remains a
non-negative 32-bit integer.

## Runtime anchors

Every region also has a semantic `ArmorAnchor_<region>` beneath a
`BoneAttachment3D`. The bone mapping lives in
`assets/player/current_player_profile.tres`, so rigid armor parts can attach
by semantic name without hard-coding Mixamo bones in item logic. Skinned
garments still use the shared skeleton and transferred vertex groups.

## Authoring rules

- Use an item's `hide_regions` only for body triangles fully enclosed by that
  garment.
- Keep armhole, hem, neck, and other visible silhouette triangles unless the
  garment visibly overlaps them from all review angles.
- Solve silhouette collisions with garment clearance and fit, not larger
  masks.
- Use the finer clavicle/cap/armpit/upper-chest/inner-arm points when the broad
  shoulder region is too coarse.
- Review idle, orbit, side, back, and a strongly deformed animation pose.

## Rebuilding the payload

The clean player source is
`art_source/blender/suma_player_pre_armor_regions.glb`. Rebuild the production
payload with:

```powershell
node "C:\Dev\suma-nook\tools\bake_player_armor_regions.js" `
  "C:\Dev\suma-nook\art_source\blender\suma_player_pre_armor_regions.glb" `
  "C:\Dev\suma-nook\assets\3d\reworked\suma_player.glb"
```

The baker preserves existing GLB buffer ranges and appends `TEXCOORD_1`. Its
report includes triangle counts and centroid bounds for every populated
region, making boundary changes auditable.
