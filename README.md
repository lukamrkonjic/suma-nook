# Suma Nook — cozy ferry-fed world builder

A cozy diorama builder where periodic ferry deliveries bring finished pieces
of land. Walk freely, choose tiles from Land Parcels, place and decorate them,
and enjoy optional catch-and-release Fishing and Woodland Tending for XP,
journal discoveries, and rare direct world rewards.

You begin on a nine-cell island: six land cells and three connected water cells
across its northern edge. A little ferry approaches the dock, unloads one
Land Parcel, and leaves you three handcrafted tile choices. There is no
material-loot grind, combat loop, survival pressure, or delivery FOMO.

**"A small world arrives one beautiful piece at a time."**

- Design pillars: `DESIGN_PILLARS.md` · Scope: `MVP_SCOPE.md` · Report:
  `MVP_REPORT.md` · Rework history: `REWORK_AUDIT.md`
- Architecture: `docs/ARCHITECTURE.md` · Visual target:
  `docs/STYLE_BREAKDOWN.md` + `docs/VISUAL_FIDELITY_CHECKLIST.md`
- Asset pipeline (incl. Modly → Blender Tier C flow): `docs/ASSET_PIPELINE.md`

## Requirements & running

- Godot **4.6.3** (`/Applications/Godot.app`), Forward+ renderer.
- Blender **5.x** only if you regenerate assets (`tools/build_assets.sh`).
- Run: open the project and press Play (`scenes/main.tscn` is the main
  scene), or `Godot --path . `.
- First run opens character creation; afterwards the save at
  `user://suma_nook_world.json` loads automatically.

## Controls

| Input | Action |
|---|---|
| WASD / left stick | walk (continuous, camera-relative; overrides click travel) |
| Left click ground | walk there |
| Left click object / E | approach and interact / contextual interact |
| Space | dodge |
| B | building mode · click place · click placed piece to move |
| R | rotate held piece · X store held piece |
| ← / → or Q / X | rotate camera 90° with the grid |
| ↑ / ↓ or mouse wheel / trackpad | zoom camera |
| Esc / right click | cancel / close |
| I C K J M | Tile/Build Libraries · character · hobbies · collection · world map |
| H | return home safely |
| Cmd/Ctrl+Z, Cmd/Ctrl+Shift+Z | undo / redo placement |
| F1 | debug panel (dev builds only) |

The debug panel includes **Open Asset World**, a curated gallery of terrain
tiles and substantial player-placeable decorations. Use WASD or drag to pan,
the wheel/trackpad to zoom, Q/X to rotate, the section picker to jump, and H
for the complete overview. Small scatter meshes stay hidden until they are
promoted to intentional placeable content.

## Tests

See `tests/README.md` — headless core suite (must print `ALL TESTS PASSED`)
and the windowed full-loop acceptance runner (must print `FULL LOOP PASSED`).

## Project structure

`data/` JSON content → `scripts/core/registries.gd` typed definitions ·
`scripts/` (core / systems / world / player / visuals / ui) ·
`assets/3d` generated GLBs · `art_source/` Blender pipeline sources ·
`scenes/` main, lighting rig, VisualStyleLab · `tools/` asset + audio
generators · `legacy/` pre-rework prototype (unreferenced, safe to delete).

## How to add content

Everything is data-first; the checklists below are complete — no engine code
changes needed unless stated.

**A hobby** — add to `data/skills.json` (stable id, XP curve, tool type,
direct tile reward chance/pool, collection category/entries, milestones), an
anchor in `anchors.json`, and host tiles in `tiles.json`. Ordinary hobby
actions intentionally have no common material drop table.

**A tile** — model it in `art_source/procedural/build_assets.py` (or drop a
GLB with semantic material names into `assets/3d/final/`), run
`tools/build_assets.sh`, then add an entry to `data/tiles.json` (family,
asset_id, weight, optional anchor/unlock levels). It joins the parcel pools
automatically. Elevation is data-driven: `stackable` allows the tile to be an
upper block, `supports_tiles` allows another block above it, and
`supports_decor` allows objects on its surface. Stairs should use
`surface_kind: "stairs"`, `supports_tiles: false`, and
`supports_decor: true`.

**A Land Parcel type** — add an item (`category: "parcel"`) in `items.json`
plus an entry in `parcels.json` with family weights; optionally a recipe.

**A structure** — GLB + entry in `structures.json` (socket_type decor |
structure, blocks_movement, provides, visitor tags) + a recipe in
`recipes.json`. Decorations allow elevated placement by default; set
`allow_elevated: false` for objects that must remain at ground level.

**A landmark** — landmark scene GLB (+ optional reclaimed dressing GLB),
entry in `landmarks.json` (footprint, distance band, enemy roster, guardian,
rewards, salvage). The horizon scheduler, reveal, encounter, reclaim, pack,
and salvage flows are generic.

**Equipment** — item entry with `slot`, `asset_id`, `stats`; grant it from a
recipe, loot table, or guardian reward. Visuals attach automatically via the
named mounts on the character.

**A hero (Tier C) asset** — write a brief in `docs/asset_briefs/`, generate
via Modly into `art_source/modly/<id>/`, clean in Blender, export the GLB to
`assets/3d/final/<same_asset_id>.glb`. No code changes.

## License / provenance

All 3D, audio, and code are original and project-owned
(`docs/ASSET_PROVENANCE.md`). Garden Galaxy screenshots are read-only style
references only (`docs/style_reference/garden_galaxy/`) and are not shipped.
