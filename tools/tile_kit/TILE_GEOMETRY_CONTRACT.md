# Procedural Tile Geometry Contract

This contract is based on measured Garden Galaxy reference exports. The
exported GLBs are research evidence only; Suma's runtime and baked library
remain fully procedural Godot geometry.

## Observed reference geometry

- `Ground_base` is an exact `1.0 x 1.0 x 0.5` square prism (24 vertices,
  12 triangles). Its horizontal bounds are exactly `-0.5 ... 0.5` on both
  axes; no neighbour state rounds or indents that structural footprint.
- Grass and sand use the same square ground-body contract. Decorative grass
  is a separate surface/detail system, not a deformation of the block sides.
- `Snow_Full` is a separate detailed cap with exact `1.0 x 1.0` horizontal
  bounds. Its height varies up to `0.178604`, including along the perimeter,
  but every perimeter vertex remains on `x/z = +/-0.5`. The irregularity is
  vertical relief, never an inward V-shaped bite.
- `Brick Floor top` is an integrated square replacement top with exact
  `1.0 x 1.0` bounds and a vertical range of `-0.18 ... 0`. Its joints are
  recessed into the top; the bricks do not float above a rounded carrier.
- `Geom Paving` likewise retains the exact square structural footprint.
  `Cobble` is a shallow detail mesh (`0.054232` total height) over a separate
  exact-square `Cobble base`; its horizontal margin is only about
  `0.005 ... 0.009` per outer edge.

## Suma implementation contract

1. Every ordinary tile body is the same exact slot-sized square prism.
   Its complete visible side shell uses one material and one colour; a second
   horizontal "lower dirt" band is not part of the tile contract.
2. Every ordinary replaceable cap fills the same exact square footprint for
   every neighbour mask. Adjacency may change vertical relief, visibility, or
   detail, but may never change the cap's horizontal perimeter.
3. Natural detail is a height field over that square cap. Exposed edges keep
   their relief and close with a vertical detailed side, while same-material
   edges continue a deterministic world-space field. Mixed shared edges may
   return to the common carrier level. The top sheet and perimeter closures
   are separate generated roles: a connected edge emits no wall at all, so
   adjacent cells can never render coplanar skirts and z-fight.
4. Constructed surfaces use a shallow recessed square carrier and embedded
   pieces that finish at the walk plane. Gaps expose only the shallow carrier,
   never the tile's deep side wall.
5. True basins, ramps, and explicitly authored special shapes are exceptions
   to the ordinary-cap rule. Their lower structural body remains exact square.
6. Topology-invariant base and top-sheet roles are baked once and reused.
   Only lightweight perimeter/transition roles receive neighbour variants.
   Natural relief is capped at a 32-by-32 grid so placement-time topology
   refreshes stay bounded without changing the exact perimeter contract.

The regression tests enforce body invariance, square cap footprint, neighbour
mask footprint invariance, exposed-wall culling, one-material shells, exact
periodic relief edges, and the maximum constructed-surface recess.
