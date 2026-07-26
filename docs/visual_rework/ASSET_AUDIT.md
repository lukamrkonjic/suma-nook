# Asset audit — Garden Galaxy visual reconstruction (2026-07-26)

Ratings are for the PRE-rework assets (the "failure reference" screenshot).
1 = untouched primitive look, 5 = matches the GG modeling language.
Every asset rated 1-2 was rebuilt this pass; nothing rated below 3 remains
visible. Rebuilt files live in `assets/3d/reworked/` (AssetLibrary searches it
first, so same-id GLBs override `final/` with zero code changes).

| Asset id | Old quality | Problems (old) | Action | Replacement |
|---|---|---|---|---|
| tile_grass | 2 | flat cap, razor bevel, noisy scatter | rebuilt | reworked/tile_grass.glb — 3-seg rounded cap, 2 authored clusters |
| tile_grass_flower | 2 | stick flowers, scatter | rebuilt | reworked/tile_grass_flower.glb |
| tile_grass_pond_edge | 2 | vertical red basin, glass water | rebuilt | reworked/…glb — sloped sandy shore, sand floor, water-shader surface |
| tile_path | 2 | flat gray slabs, hard edges | rebuilt | reworked/tile_path.glb — varied warm-ivory slabs, 3-seg bevels |
| tile_garden | 2 | boxy bed | rebuilt | reworked/tile_garden.glb |
| tile_courtyard | 2 | flat rings | rebuilt | reworked/tile_courtyard.glb |
| tile_grove_* (5) | 2 | cone trees, ball bushes | rebuilt | reworked/tile_grove_*.glb — lobed pines/crown trees, soft bushes |
| tile_stone_* (5) | 2 | tetra rocks, gray palette | rebuilt | reworked/tile_stone_*.glb — designed rocks, warm ivory |
| tile_open_water | 1 | flat translucent plane per tile, bands, seams | rebuilt (system) | tile_water_floor.glb + WaterSurface + gg_water.gdshader |
| prop_pine_a/b | 1 | stacked sharp cones, near-black base | rebuilt | reworked/prop_pine_a/b.glb + prop_pine_young — 3 real variants, lobed tiers |
| prop_bush_a/b | 1 | single faceted icosphere | rebuilt | reworked/prop_bush_a/b/c.glb — 4-6 overlapping smooth lobes |
| prop_flowers_* | 1 | stick + blob | rebuilt | reworked — thick bent stems, leaves, 5 shaped petals, center |
| prop_grass_tuft | 1 | paper triangles | rebuilt | reworked — 6 broad curved tapered blades |
| prop_rock_cluster | 2 | jittered tetrahedra | rebuilt | reworked — 3 coordinated designed rocks, flattened tops |
| prop_bench | 2 | razor boxes | rebuilt | reworked — chunky rounded seat, angled back, 3-seg bevels |
| prop_dock | 2 | flat orange rectangle | rebuilt | reworked — individual rounded planks, height variation, soft piles |
| (ferry dock) | 1 | runtime BoxMesh primitives | rebuilt | reworked/prop_dock_ferry.glb via DeliveryPoint |
| (present) | 1 | runtime BoxMesh + ribbons | rebuilt | reworked/prop_present.glb — rounded parcel + bow |
| prop_chest | 2 | sharp box + box lid | rebuilt | reworked — rounded barrel lid, banded |
| prop_lantern | 2 | thin box cage | rebuilt | reworked — 12-seg tapered post, rounded cap, warm-near-black |
| prop_cardboard_box | 3 | acceptable, sharp flaps | rebuilt | reworked — softer bevels |
| prop_pot / planter | 2 | 12-seg ok, harsh lip | rebuilt | reworked — 16-seg, rounded lip |
| prop_fence/gate/sign/stool/table/stump/log | 2 | primitive members | rebuilt | reworked equivalents, weighted normals |
| prop_campfire/shelter/ruin_arch/stone_wall/fishing_marker/mushrooms/reeds | 2-3 | mixed | rebuilt | reworked equivalents |
| underwater floor | — | did not exist | new | tile_water_floor.glb — dish-shaped sand, deep centers |
| underwater flora | — | did not exist | new | eelgrass ×3, broadleaf ×2, reeds ×2, lily ×2, rock groups ×3 |
| character_proxy | 3 | rounded, consistent | kept (proxy) | reserved for Luka's Modly/Blender hero pass |
| equip_* / enemy_* / landmark_watchpost | 3 | off-screen in start world | kept | reserved for Luka (complex hero assets) |

## Modeling standards enforced (all reworked assets)
- Hard surfaces: bevel 3-6% of smallest visible dimension, 2-3 segments,
  weighted normals, applied transforms, bottom-center pivots.
- Curved: pots/posts 12-16 radial segments; rocks ico-based with controlled
  asymmetry + flattened top planes; foliage lobes smooth icospheres.
- Pines: 3-5 overlapping scalloped tiers (`pine_tier()` — tapered, lobed rim,
  flattened underside), tier colors stay green (pine_light/medium); shading
  comes from the sun, never near-black albedo.
- Composition: ≤3 authored clusters per ordinary tile; ≥65-75% quiet surface.

## Reserved for Luka's Modly/Blender route
- Hero player character (current proxy is compatible but replaceable)
- Enemies (thornlings, guardian), landmark watchpost, equipment set dressing
- Any future hero landmark buildings (GG-style houses, fountains, statues)
