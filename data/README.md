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
- `items.json` — materials, parcels, tools, equipment, relics. Equipment
  carries `slot`, `asset_id` (visual attachment), and `stats`.
- `tiles.json` — TileDefinitions per terrain family (home_meadow,
  living_grove, stonebound): asset, rarity/weight, unlock levels, terrain
  anchors such as water/minerals, sockets, landmark tags.
- `anchors.json` — Resource Anchors (skill, cycle length, regen).
- `structures.json` — placeable objects, object support policy, optional
  resource anchors (trees), and future-visitor metadata tags.
- `recipes.json` — crafting (inputs → structure/item/parcel output, skill
  unlock levels; unlocks are always deterministic).
- `loot_tables.json` — weighted tables incl. rare layers.
- `parcels.json` — parcel types → family weights for the three-card reveal.
- `enemies.json`, `landmarks.json` — the Overgrown Watchpost encounter chain.

Stable string ids are the only cross-reference currency. Never reuse a
shipped id for different content.
