# Asset queue

Status values: AI-NOW (agent building), STYLE-GATE (waits for Style Lab pass),
LUKA-MODLY (Tier C, needs Luka), CLEANUP (generated, needs Blender pass), INTEGRATED,
REJECTED (with reason).

## Tier A (agent) — terrain
| asset | status |
|---|---|
| tile_grass / tile_grass_flower / tile_grass_pond_edge / tile_path / tile_garden / tile_courtyard | INTEGRATED |
| tile_grove_mature / grove_birch / grove_mossy / grove_autumn / grove_flowering | INTEGRATED |
| tile_stone_clearing / stone_mossy / stone_ruin / stone_crystal / stone_road | INTEGRATED |
| water basin sub-mesh (pond edge) | INTEGRATED |

## Tier A — vegetation & props
| asset | status |
|---|---|
| pine ×2, bush ×2, flowers ×3, reeds, mushrooms, tufts, stump, log | INTEGRATED |
| bench, stool, table, fence, gate, lantern, campfire, shelter/cottage, planter, pot, chest, dock, sign, ruin arch, stone wall | INTEGRATED |
| fishing rod, axes ×2, sword, bobber | INTEGRATED |
| effect meshes: flame core/outer, smoke puff, ripple ring, wood chip | INTEGRATED |

## Tier B (agent, post style-gate)
| asset | status |
|---|---|
| thornling stalker / lobber, watchpost guardian | INTEGRATED (styled low-poly, upgradeable) |
| watchpost ruin cluster (tower, gate, rubble) | INTEGRATED (proxy-grade; Tier C brief exists for hero version) |

## Tier C (Luka via Modly → Blender) — briefs in docs/asset_briefs/
| asset | status |
|---|---|
| character_hero (final player model + hair library) | LUKA-MODLY (proxy INTEGRATED) |
| watchpost_hero (elaborate landmark) | LUKA-MODLY (proxy INTEGRATED) |
| guardian_hero | LUKA-MODLY (proxy INTEGRATED) |
| outfit/armor sets | LUKA-MODLY (proxy INTEGRATED) |

## Progression rework placeholders (need real art)
| asset | status |
|---|---|
| wishing_well_hero (struct_wishing_well — currently reuses prop_stone_well; wants: basin glow, domain-colored refund carvings, evolution stages) | AI-NOW (placeholder INTEGRATED) |
| shrine_hero (struct_shrine — currently reuses prop_birdbath; wants: focus pedestal, hovering focused item) | AI-NOW (placeholder INTEGRATED) |
| inspiration wisp VFX (domain-colored spirits flying to the well; speed-buff trail) | AI-NOW |

## Rejected
| asset | reason |
|---|---|
| pixel-art sprite set (v3) | superseded visual direction; kept in legacy/ history only |
