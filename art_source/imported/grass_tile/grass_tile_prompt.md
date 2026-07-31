# grass tile — generation prompt archive

Date: 2026-07-30  
Pipeline: local Modly — HunyuanDiT 1.2 text-to-image → Hunyuan3D 2.1
shape (image-to-3D) → raw GLB archived here (no decimation; the
repository Blender processor performs controlled cleanup per
`docs/TILE_AUTHORING.md`).  
Art direction: Garden Galaxy screenshots were referenced by the author
for shape language / presentation only; no specific existing tile is
copied. Clean-room per `docs/GG_SPECIAL_ITEM_INSPIRATION.md`.

## Distilled diffusion prompt (as sent to HunyuanDiT)

A single isolated low-poly grass terrain tile for a cozy isometric
video game, orthographic three-quarter isometric view, one thick
square block, straight vertical earth-brown side walls, softly beveled
edges, top covered in chunky sculpted moss-green grass tufts — twelve
to sixteen large rounded clusters of broad wedge-shaped lobes, varied
tuft heights, small mossy gaps between clusters — matte flat colors,
two or three muted sage and moss green tones, warm olive-brown sides
darker than the top, soft studio lighting from the upper left, gentle
contact shadow, plain warm light-beige background, centered, toy-like
collectible game asset, clean readable silhouette, no props, no
flowers, no rocks, no text.

Negative: realistic grass, thin hair-like blades, fur, noise texture,
photorealism, voxel, blocky minecraft cubes, multiple tiles, scene,
environment, horizon, text, watermark, border, pillow-rounded
perimeter, floating pieces, clutter, deep crevices.

## Full authored specification (verbatim, for the Blender processor)

This is a terrain TILE: one thick square rectangular block forming the
ground — not a scene, not multiple tiles, not a model on a tile.

- Orthographic three-quarter isometric camera, yaw ~45°, pitch ~35°
  downward; full top surface and two complete side faces visible; no
  perspective distortion; centered in a square image with generous
  margin; plain horizonless warm light-beige studio background; object
  ~70–75% of frame; soft neutral studio light upper-left; gentle
  ambient fill and subtle contact shadow only; no text/UI/border/
  environment/extra objects.
- Perfectly square modular footprint; thickness ~22–27% of width;
  straight vertical side walls for clean tiling; square corners in
  footprint; small broad bevels on top rim, vertical corners, bottom
  edges; softly manufactured edges, never razor sharp; no cushion/pill
  inflation; level modular top perimeter.
- Grass: NOT a flat plane. ~12–16 large connected clusters, each 3–5
  broad rounded wedge-shaped lobes; chunky sculpted tufts, not blades;
  clusters gently overlap and merge into the ground; all geometry
  within the footprint; varied height/direction/width/spacing; three
  approximate tuft sizes; irregular but even distribution; no central
  hero feature, border, checkerboard, rows, or stripes; a few glimpses
  of smoother mossy ground between clusters; lush at distance, not
  noisy; repeats naturally beside copies; no flowers/rocks/mushrooms/
  branches/props.
- Shape language: cozy collectible-game asset; chunky, tactile, softly
  asymmetrical, gently hand-sculpted; low-poly but not crude/voxel;
  broad readable facets, smooth shading, soft transitions, shallow
  curves; slightly exaggerated thickness; survives moderate mesh
  smoothing; no deep grooves, narrow crevices, spikes, thin fins,
  fragile or floating geometry.
- Materials: matte, softly rough; muted warm moss/sage greens (2–3
  close solid tones); lighter upward tufts, darker recesses; side
  walls warm earthy olive/soil brown, darker than top; solid material
  colors, no painted texture/noise/speckles/decals/gradients — tonal
  variation from geometry, material groups, AO, lighting.
- Target: premium sculpted terrain piece; simple enough for reliable
  image-to-3D reconstruction; charm via silhouette, broad volumes,
  restrained color, soft bevels, tactile relief.
- Avoid: flat painted lawn, smooth green top, realistic grass,
  hair-like blades, hundreds of tiny pieces, Minecraft/voxel, harsh
  cones, Roblox primitives, realistic PBR, high-frequency texture,
  excessive beveling, pillowy perimeter, hollow geometry, floating
  pieces, terrain outside the tile, multiple tiles, props, scenery,
  labels, decorative base.
