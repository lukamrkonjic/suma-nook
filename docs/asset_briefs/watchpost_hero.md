# Asset brief — watchpost_hero (Overgrown Watchpost, hero version)

- **Asset ID / export**: `watchpost_hero` → `assets/3d/final/watchpost_hero.glb`
- **Purpose**: replaces the proxy ruin cluster used by landmark `overgrown_watchpost`.
- **Silhouette**: broken round stone watchtower (~3.5 m tall) with a collapsed crown,
  attached gate arch, tumbled block piles, ivy mats and moss patches; one dead tree.
- **Dimensions**: fits a 2×2-tile footprint (4×4 m), tower on the rear cell.
- **Palette**: `pale_stone` weathered walls, `dark_stone` shadow courses, `dark_foliage`
  ivy, `moss` accents, `dark_wood` gate remains, `gold` one buried emblem accent.
- **Material slots**: `pale_stone`, `dark_stone`, `dark_foliage`, `moss`, `dark_wood`,
  `gold`.
- **Separate parts**: tower, arch, rubble_a/b/c, ivy — so the reclaimed state can hide
  rubble and add planters via script.
- **Sockets**: `guardian_spawn`, `enemy_spawn_a/b`, `reward_pedestal`, `banner`.
- **Collision**: blocked cells map provided in landmark definition; simple boxes.
- **Animations**: none (state swaps are scene-side).
- **Triangle budget**: ≤ 12,000.
- **Godot target**: referenced by `data/landmarks.json` → `overgrown_watchpost.scene`.
- **Modly prompt**: "overgrown ruined low-poly stone watchtower with broken arch gate,
  chunky faceted stones, moss and ivy, cozy diorama game style, matte flat colors, soft
  bevels, no outlines, no photoreal texture"
- **Acceptance**: per `_TEMPLATE.md`; silhouette must read as 'dark mysterious tower' when
  rendered black in fog at 8 tiles distance.
