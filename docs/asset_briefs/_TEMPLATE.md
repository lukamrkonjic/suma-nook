# Asset brief — <asset_id>

- **Asset ID / export**: `<asset_id>` → `assets/3d/final/<asset_id>.glb`
- **Purpose / gameplay role**:
- **Target silhouette** (one sentence a modeler can verify at gameplay zoom):
- **Dimensions**: (tile = 2.0 m; state size relative to a tile)
- **Pivot**: bottom-center unless noted. **Forward**: -Z.
- **Semantic palette tokens** (from `assets/palettes/gg_material_palette.tres`):
- **Material slots** (semantic names only — Godot rebinds them):
- **Separate/movable parts**:
- **Sockets** (named empties):
- **Collision**: (footprint or simplified shape; authored in Godot)
- **Animations** (semantic names):
- **Triangle budget**: / **LOD**: none unless noted
- **Godot target scene**:
- **Modly prompt**:
- **Negative prompt / unwanted traits**: photoreal texture, gritty noise, thin geometry,
  outlines, mixed styles, high poly count
- **Blender cleanup checklist**: delete disconnected/internal geometry → fix normals /
  non-manifold → simplify to budget (protect silhouette) → apply transforms → bevel key
  edges + weighted normals → semantic material slots with palette flat colors → pivot →
  sockets → export GLB
- **Acceptance**: reads correctly in the production world under day AND rain profiles; matches
  proxy scale within 10%; material slots rebind cleanly; no embedded lights/cameras.
