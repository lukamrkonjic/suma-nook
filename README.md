# Suma Nook — a world discovered one piece at a time

Suma Nook is a cozy diorama builder about pulling pieces from the unknown,
placing them into a tiny floating world, and shaping that world into the
source of what you discover next.

Fishing from an exposed land edge reaches into the void and returns a broad,
surprising mix of real tiles and models. Water is one of those ordinary,
placeable tiles: use it to build ponds, rivers, lakes, or docks. Skills used
inside the world are more focused. A pond surrounded by sand finds beach
pieces; a pond among pines finds forest pieces; trees and future mining nodes
read the same local biome context. The built world is therefore both the
player's canvas and their gacha steering system.

Duplicates remain useful without threatening a player's last copy. The
Build Bag's **Offer Duplicates** flow lets the player throw three true spare
copies of one exact piece into the void. The void returns a different random
piece from the same Build Bag category. Partial offerings persist safely.

There is no Inspiration currency, wishing-well meter, Vision choice screen,
refund coin, focus shrine, XP ladder, combat grind, survival pressure, or
delivery FOMO.

**"Build the world that teaches the unknown what to send back."**

Current design: `docs/DISCOVERY_PROGRESSION.md` · Onboarding:
`docs/NEW_PLAYER_FLOW.md` · Full decision history:
`docs/DESIGN_MASTER_RECORD.md`

- Architecture: `docs/ARCHITECTURE.md`
- Design pillars: `DESIGN_PILLARS.md` · Scope: `MVP_SCOPE.md`
- Visual target: `docs/STYLE_BREAKDOWN.md` +
  `docs/VISUAL_FIDELITY_CHECKLIST.md`
- Asset pipeline: `docs/ASSET_PIPELINE.md`
- Layered tile system: `docs/TILE_AUTHORING.md`
- Large-world rendering: `docs/PERFORMANCE_AUDIT.md`

## Requirements and running

- Godot **4.6.3**, Forward+ renderer.
- Blender **5.x** only when regenerating assets.
- Open the project and press Play (`scenes/main.tscn`), or run
  `Godot --path .`.
- A first run opens character creation; later runs load
  `user://suma_nook_world.json`.

## Controls

Controllers are hot-pluggable. Suma changes prompts, focus, and pointer
visibility as soon as the active input method changes.

| Action | Keyboard / mouse | Controller |
|---|---|---|
| Pan camera | WASD / middle-mouse drag | right stick |
| Walk / sprint keeper | click ground / Shift | left stick / L3 |
| Interact | F | X / west face |
| Fish the unknown | interact near an exposed land edge | interact |
| Jump | Space | A / south face |
| Build mode / Build Bag | B | Y / north face |
| Place / pick up in build mode | click | A / south face |
| Move build cursor | pointer | D-pad |
| Place detached land | click any empty grid cell | move cursor anywhere, then A |
| Rotate / store held piece | R / X | R3 / X-west |
| Rotate camera | ← / → or Q / X | LB / RB |
| Zoom; build undo / redo | ↑ / ↓ or wheel; Ctrl+Z / Ctrl+Shift+Z | LT / RT |
| Cancel / close | Esc / right click | B / east face |
| Journals | I C K J M | D-pad; LB/RB changes an open page |
| Hide all HUD | H | R3 outside build mode |
| Pause | Esc | Menu / Options |
| Debug asset viewer | F8; drag / wheel | right stick / LT-RT |
| Performance HUD (debug) | F3 | pause menu Admin page |

See `docs/CONTROLLER_SUPPORT.md` for the implementation contract.

## Tests

See `tests/README.md`. The core suite must print `ALL TESTS PASSED`; the
scene-level runner must print `FULL LOOP PASSED`.

## Project structure

`data/` contains validated JSON content. `scripts/core/` loads typed
definitions and composes services. `scripts/features/progression/` owns
discovery pools, local biome resolution, duplicate exchange, and save
migration. `scripts/world/`, `scripts/player/`, and `scripts/ui/` own their
respective runtime and presentation layers. `legacy/` contains unreferenced
pre-rework history.

## How to add content

Everything player-obtainable is data-first.

**A discovery pool** — add an entry to `data/discovery_pools.json`. A pool
declares its source (`void`, `fishing`, `woodcutting`, or a future skill), the
context tags that make it eligible, actions per reward, and weighted tile or
structure entries. The broad void pool should remain eclectic. Local pools
should have a clear biome fantasy and a fallback.

**A tile** — follow `docs/TILE_AUTHORING.md`, add its typed definition to
`data/tiles.json`, give it honest `biome_tags`, and add its ID to
`data/tuning.json::active_tile_ids` when production-ready. Then list it in the
appropriate discovery pools. Water remains a real tile, never background
geometry or a special world layer.

**A structure** — add the GLB and a stable entry in `data/structures.json`.
Use biome tags for pieces that should influence local discovery. Give
skill-bearing objects an anchor capability, then include the structure in
weighted pools where it belongs.

**An activity** — add its definition to `data/skills.json` and an anchor to
`data/anchors.json`. Add one or more source pools to
`data/discovery_pools.json`. Runtime code supplies the local coordinate and
source object; the shared discovery resolver handles context, progress,
reward ownership, presentation, and saving.

**A milestone** — add a `practice` or `journal_page` entry to
`data/milestones.json` with stable rewards.

**A hero asset** — write a brief in `docs/asset_briefs/`, archive its source
under `art_source/`, clean it in Blender, and export the production GLB to
`assets/3d/final/` under the same asset ID.

## License and provenance

All shipped 3D, audio, and code are original and project-owned; see
`docs/ASSET_PROVENANCE.md`. Garden Galaxy material is retained only as
read-only research and style reference.
