# Suma Nook — living world progression MVP

A cozy RPG-builder where you level skills to earn the materials and land
pieces used to physically grow and beautify your own miniature world, one
handcrafted tile at a time.

You begin as a small keeper on exactly nine tiles floating in warm cream fog.
Fishing brings materials and fragments of new land; Land Parcels reveal three
handcrafted tile choices; placed tiles bring groves, and groves bring
Woodcutting, crafting, and buildings. Dark silhouettes appear on the horizon —
build toward them, clear their thornlings, and fold reclaimed ruins into a
world that is a physical record of everything you've done.

**"I begin with almost nothing. Everything I do becomes part of my world."**

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
| WASD / arrows / left stick | walk (continuous, camera-relative) |
| E or left click | contextual interact (fish, chop, attack, storage, claim) |
| Space | dodge |
| B | building mode · click place · click placed piece to move |
| R | rotate held piece · X store held piece |
| Q / X | rotate camera 90° · mouse wheel zoom |
| Esc / right click | cancel / close |
| I C K J M | storage · character · skills · collection · world map |
| H | return home safely |
| Cmd/Ctrl+Z, Cmd/Ctrl+Shift+Z | undo / redo placement |
| F1 | debug panel (dev builds only) |

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

**A skill** — add to `data/skills.json` (id, xp curve, tool_type, loot
tables, unlocks). Add its loot tables (`loot_tables.json`), an anchor
(`anchors.json`) and tiles that host it (`tiles.json`). If it needs a new
action sequence beyond fish/chop patterns, extend `SkillActions` — the mining
definition already ships to prove the data path.

**A tile** — model it in `art_source/procedural/build_assets.py` (or drop a
GLB with semantic material names into `assets/3d/final/`), run
`tools/build_assets.sh`, then add an entry to `data/tiles.json` (family,
asset_id, weight, optional anchor/unlock levels). It joins the parcel pools
automatically.

**A Land Parcel type** — add an item (`category: "parcel"`) in `items.json`
plus an entry in `parcels.json` with family weights; optionally a recipe.

**A structure** — GLB + entry in `structures.json` (socket_type decor |
structure, blocks_movement, provides, visitor tags) + a recipe in
`recipes.json`.

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
