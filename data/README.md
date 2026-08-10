# Data

All game content is JSON here, loaded into typed definitions by
`scripts/core/registries.gd` (cross-references validated at startup — a bad id
fails loudly, never silently).

- `tuning.json` — every gameplay constant: movement, camera, pond ambience,
  autosave, save path/version, tutorial guarantees.
- `fishing_balance.json` — every void-fishing tunable: timing, pool weights,
  haul sizes, bundle ranges, hidden protection, habitat theme mappings.
- `fishing_loot.json` — what the void can return (tile bundles, models,
  keepsakes) referencing building content by stable id; themes, pools,
  rarity, `unlock_group`.
- `fishing_spirits.json`, `fishing_keepsakes.json` — Spirit charms and
  Keepsake charms (see `docs/VOID_FISHING.md`).
- `skills.json` — SkillDefinitions: xp curve, tool type, loot tables, level
  unlocks (`kind`: parcel | recipe | tile | anchor_upgrade). Mining ships as a
  `future: true` definition proving new skills are data-only.
- `items.json` — materials, biome tokens, parcels, tools, equipment, relics. Equipment
  carries `slot`, `asset_id` (visual attachment), and `stats`.
- `tiles.json` — TileDefinitions per terrain family (home_meadow,
  living_grove, stonebound): asset, rarity/weight, unlock levels, terrain
  anchors such as water/minerals, sockets, landmark tags.
- `anchors.json` — Resource Anchors (skill, cycle length, regen).
- `structures.json` — placeable objects, object support policy, and optional
  capability references such as the shared tree/shrub/rock harvest source.
- `itch_structures.json` — generated placeable definitions for the curated
  free itch.io catalog. Do not hand-edit; rebuild it with
  `art_source/blender/process_itch_free_packs.py`.
- `itch_wish_rewards.json` — generated reward extension that makes each
  imported placeable a single-instance sky-wish result in its collection.
- `harvest_profiles.json` — hit counts, maturation/regrowth, visual presenter,
  and Forest/Rock Token yields for data-authored harvest sources.
- `token_boxes.json` — themed box prices and references to their reward pool,
  roll policy, and reveal profile.
- `reward_pools.json`, `reward_roll_policies.json`,
  `reward_reveal_profiles.json` — weighted tile/model contents, reusable roll
  behavior, and non-modal presentation for boxes and visitor gifts.
- `recipes.json` — crafting (inputs → structure/item/parcel output, skill
  unlock levels; unlocks are always deterministic).
- `loot_tables.json` — weighted tables incl. rare layers.
- `parcels.json` — parcel types → family weights for the three-card reveal.
- `enemies.json`, `landmarks.json` — the Overgrown Watchpost encounter chain.

Stable string ids are the only cross-reference currency. Never reuse a
shipped id for different content.

## Extending generated biomes safely

- Add an ordinary full-height land tile to `tiles.json`, give it the common
  trait tag `generation_ground`, and add a matching `biome_tags` value such as
  `meadow`, `forest`, `rocky`, `beach`, or `winter`. Future Nooks can then pick
  it automatically; already revealed Nooks remain untouched saved cells.
- Explicit `resolve` pools in `nook_biomes.json` remain the higher-weight art
  direction. A stale pool id is skipped with a warning, so removing a palette
  entry cannot break generation.
- Never reuse a retired stable id. If a tile definition is removed, existing
  saves convert every occurrence (world and Build Bag) to
  `nook_config.safe_ground_tile_id`, currently `tile_grass`. Removed structures
  are omitted, along with unsupported children.
- Rivers, ponds, height, material patches, and vegetation use absolute
  world-cell noise seeded by the save. Editing their tuning changes only Nooks
  generated afterward, matching chunked sandbox-world behavior.
