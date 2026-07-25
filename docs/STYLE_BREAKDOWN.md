# Style breakdown — what actually makes the Garden Galaxy references look the way they do

Written from direct observation of the three supplied screenshots. Every claim below is a
calibration target for the Style Lab, not a guess.

## Camera

- True orthographic projection. Parallel tile edges never converge; the far corner of the
  diorama is exactly the same scale as the near corner.
- Yaw ≈ 45° (tile diagonals run vertically on screen; both visible side walls of each tile
  block are equally foreshortened).
- Pitch ≈ 33–36° downward (tile tops read as diamonds roughly twice as wide as tall;
  side walls of a 1-unit-tall tile occupy about 55–65% of the height of the top face on
  screen).
- No roll. Horizon-free: the world floats in a flat untextured background color.
- Framing: the whole diorama fits with generous negative space — roughly 15–20% margin of
  pure background on every side. Nothing is cropped by the frame edge.

## Background treatment

- Day: one flat warm cream (#E7E1CC ± a little). NO gradient, NO sky, NO vignette visible.
  The diorama casts NO shadow onto the background — tiles just end and cream begins.
- Rain: flat deep desaturated green-gray (#323B2E-ish). Rain streaks are short pale
  vertical dashes drawn over everything, denser near the top of frame.

## Light

- Single warm key light from screen upper-left. Shadows fall to lower-right, roughly
  along +X screen / slightly down.
- Shadow edges are soft but clearly bounded (penumbra of maybe 5–10% of a tile width),
  not razor-sharp and not blurry blobs.
- Shadow color is a cooler, slightly desaturated multiply of the surface — never black.
  On cream stone the shadow reads as warm gray; on grass as deeper olive.
- Strong contact darkening under every prop (pots, bushes, birds) — this grounding is
  what makes the props look "placed on" rather than "floating over" the tiles. Reads as
  SSAO plus the soft shadow overlapping.
- Lit faces are bright but never clip to white; the brightest stone tops still show hue.

## Palette (sampled by eye from the day references)

- Background cream #E7E1CC, pale stone slabs #D8CFC0→#D8C8B0, brick paving warm
  #C98A54/#B76E35 range, grass BRIGHT yellow-green #BFC72A (this is much yellower than a
  typical "grass green" — key to the look), dark foliage #46532D, soil #8A4A28 with
  chunky darker clods, wood #765026, terracotta #B76E35, water #8FAEAA pale blue-green,
  gold accents #E1B640, flame yellow→orange emissive.
- Rain scene: everything shifts toward olive; grass ≈ #7E8A2E, background #323B2E, fire
  pools push large warm #E8A33C halos onto nearby geometry.
- Saturated accents (gold, red mushroom cap, pink tulip) sit on calm mid-saturation
  fields. At most 2–3 saturated focal props per screen region.

## Modeling language

- Chunky: every object is thicker than realistic. Fence posts ~1/6 tile wide. Petals are
  thick wedges. Stair steps are oversized (3–4 steps per tile, not 8).
- Bevels everywhere but restrained: tile top edges have a small 45° chamfer (~4–6% of
  tile width). Pots, benches, columns all show a visible rounded/chamfered rim that
  catches light as a bright line.
- Normals: mostly smooth-shaded surfaces with weighted/hard edges preserved at big
  angle breaks — rocks and soil clods are deliberately faceted (flat-shaded planes),
  while pots/balustrades read smooth.
- Trees: 2–4 stacked squashed cones (pine) with slightly randomized tilt; trunk is a
  short fat cylinder. Bushes: 1–3 intersecting rounded blobs. No leaf cards, no alpha.
- Soil tiles: the top face carries scattered low flat-shaded "clod" prisms in a darker
  soil tone; grass tiles carry sparse chunky cross-tuft wedges slightly darker/lighter
  than the base.
- Zero texture maps visible. All separation is per-face color + geometry + lighting.

## Tiles

- Tile = block: colored top face + earthy side walls (soil brown, or stacked brick
  courses on paved tiles, or stone). Side walls are darker than tops.
- Water tiles are open-topped basins: visible inner walls, water surface set ~25–35%
  below the land top, slightly transparent pale blue-green, tiny specular sheen, no
  waves visible at rest.
- Adjacent tiles: no visible seams on matching families; different families meet in a
  clean straight color boundary. Small height steps between families are allowed and
  read intentionally (soil tiles sit a touch lower than stone in ref 01).

## Emissives / fire

- Candle flames and campfires are geometry: a teardrop yellow core inside an orange
  outer shell, with visible chunky white smoke puffs (spheres) drifting up.
- Fire emits a WARM local light pool with fast falloff — in the rain shot each fire
  lights maybe a 2–3 tile radius, and the falloff is smooth, never hard-edged.
- Bloom exists but only around genuinely bright emitters (flames, ember trail); the rest
  of the scene has zero haze.

## Prop density & composition

- Dense but composed: each tile carries 0–2 props plus optional micro-scatter. There are
  intentional empty stone/grass tiles as visual rest.
- Focal build (fountain, altar) occupies the composition center; support props ring it.

## What we must NOT do

- No outlines, no pixelation, no gradients in the background, no photoreal textures,
- no blue-gray stone (stone stays warm), no black shadows, no glossy plastic (roughness
  high everywhere except water/gold), no thin geometry that vanishes at distance.
