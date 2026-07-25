# MVP report — living world progression rework

Branch `rework/living-world-progression-mvp` · Godot 4.6.3 · Blender 5.1.2
(asset pipeline) · dev Mac (Apple Silicon).

## Verdict

The complete MVP loop is playable and machine-verified: character creation →
composed 3×3 world → continuous free walking → one-click auto-repeat fishing
→ XP/level-ups → guaranteed first Land Parcel → three-card reveal → grid
placement with undo/redo and move-with-cancel → woodcutting on a resting,
regrowing grove → crafting → building placement → horizon watchpost
silhouette → build-toward reveal → telegraphed combat → guardian defeat →
visible cape reward → reclaim with keep/pack/salvage → collection book →
atomic save → reload restoring the exact floating-point player position and
every state. `ALL TESTS PASSED — 100 assertions` (headless core) and
`FULL LOOP PASSED — 57 checks` (real-scene acceptance runner) on the final
commit.

## Systems implemented (all new)

GameCore composition root · JSON→typed-definition registries with startup
cross-validation · seeded named RNG streams (saved) · WorldGrid
(adjacency/overlap/connectivity/sockets/safe-relocation) · WorldRenderer
(state-diff, edge blockers, anchor rest visuals, landmark phases) ·
PlacementController (ghost preview, color-independent validity, rotate,
move/cancel/store, undo/redo, connectivity + standing-cell safety) ·
SkillManager with data-driven unlocks · RewardManager (loot + rare pity +
tutorial guarantees) · ParcelManager (three-choice reveal, reroll, duplicate
→ Pattern Dust, new-tile pity, crash-safe pending reveals) · CraftingManager
(atomic transactions) · Inventory/Stock (rewards can never be lost) ·
EquipmentManager (visible attachments, appearance unlocks separate from
ownership) · CollectionManager · LandmarkManager (horizon ring → reveal →
reclaim → keep/pack/salvage, idempotent guardian reward) · CombatManager +
Enemy AI (telegraphs, leashing, gentle defeat) · SaveManager (versioned,
atomic, backup, missing-definition tolerant) · GameAudio (named events, 57
original generated sounds) · full UI suite (HUD, seven panels, parcel
reveal, character creator, debug panel).

## Systems reused / replaced

Reused as patterns from the v3 prototype: atomic save writes, two-phase
placement transactions, reconciling renderer, generated-audio tooling,
explicit dependency wiring. Replaced wholesale: tile-hop locomotion (now
continuous CharacterBody3D), pixel-art presentation (now low-poly Forward+
diorama), wisp/visitor click economy (removed per anti-pillars; visitor
metadata hooks retained). Old implementation preserved unreferenced in
`legacy/` — safe to delete after play-testing.

## Assets

65 original GLBs generated headlessly (tiles ×16 incl. carved pond basin,
props ×~30, equipment, effects meshes, character proxy + 4 hairstyles,
enemies ×3, watchpost + reclaimed dressing) — `docs/ASSET_PROVENANCE.md`.
Shared palette resource + material library; semantic material rebinding means
palette edits reskin everything without re-export. Tier C hero briefs ready
(`docs/asset_briefs/`): character, watchpost, guardian, outfits. No
reference-game content anywhere.

## Test results

- Headless: 100/100 assertions (see `tests/test_runner.gd` — covers the full
  required list incl. deterministic RNG, pity, guardian idempotency, save
  round-trip with RNG stream state, interrupted-reveal recovery).
- Scene loop: 57/57 checks incl. movement acceptance (no teleport steps,
  diagonal speed, camera-relative after rotation, exact stop retention,
  between-centers save/reload) — `tests/full_loop_runner.tscn`.
- Performance: 120 FPS (vsync-capped) at 1600×900 on the dev Mac with the
  expanded world; no per-frame world scans by design.
- Screenshots: `docs/screenshot_*.png` (12 acceptance moments) +
  `docs/style_comparisons/` (day/rain calibration, Style Lab).

## Known limitations

- Parcel reveal cards preview family/water by color swatch, not a live 3D
  render of the tile.
- Character proxy animates procedurally (tweened pivots), not skeletally；
  the Tier C rigged hero replaces it file-for-file (same state names).
- Mining is data-only by design; stair tile asset exists but no elevated
  terrain ships in the MVP (movement over stairs untested in-world).
- Shelter/Tier A architecture is deliberately simple; a Tier B pass after
  style sign-off should refine the cottage kit.
- Rain background renders darker than the profile value under ACES — tuned to
  taste, worth one more calibration pass against the real reference PNGs.
- **Luka: copy the three Garden Galaxy reference PNGs into
  `docs/style_reference/garden_galaxy/`** (names in that folder's README) —
  the agent could not write binary chat attachments to disk.
- Gamepad: analog axes are mapped; UI focus flow untested on a controller.

## Recommended next development step

Play the loop by hand for 30 relaxed minutes and tune three feels in
`data/tuning.json`: fishing wait band (`fishing_wait_*`), grove rest length
(`anchors.json` regen), and camera zoom bounds. Then commission the Tier C
`character_hero` via the Modly brief — the visible-character upgrade is the
single highest-impact polish item, and it drops in with zero code changes.
