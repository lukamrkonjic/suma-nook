# Asset brief — outfit_sets (explorer set + landmark cape, hero versions)

- **Asset IDs**: `outfit_explorer_head`, `outfit_explorer_body`, `cape_watchpost` →
  `assets/3d/final/<id>.glb`
- **Purpose**: replace proxy equipment visuals on the character (EquipmentManager
  attaches by definition `scene`, socketed to `head` / body overlay / `back`).
- **Silhouettes**: explorer hood (soft chunky hood + brim), explorer tunic overlay
  (belted, satchel strap), watchpost cape (short rounded leaf-cape, gold clasp).
- **Palette**: `fabric` + `fabric_accent` (runtime-tinted), `gold` clasp, `dark_wood`
  toggles.
- **Material slots**: `fabric`, `fabric_accent`, `gold`, `dark_wood`.
- **Rigging**: skinned to the character_hero rig bones they cover; cape gets 2-bone
  swing chain.
- **Triangle budget**: ≤ 1,500 each.
- **Modly prompt**: "chunky low-poly [hood/tunic/leaf cape] for a cute 3-heads-tall
  character, matte flat colors, soft bevels, cozy diorama game style, no texture detail"
- **Acceptance**: per `_TEMPLATE.md`; equip/unequip leaves no clipping at gameplay zoom
  in idle/walk/chop/fish poses.
