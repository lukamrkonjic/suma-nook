# Visual fidelity checklist

Gate for calling the visual pass done. Verify each item against
`docs/style_comparisons/` captures at 1920×1080, consistent camera.

## Camera & framing
- [ ] Orthographic; no perspective convergence anywhere.
- [ ] Yaw 45°, pitch ~34°; tile tops read as ~2:1 diamonds.
- [ ] Generous flat-background margin around the diorama; nothing cropped.
- [ ] 90° rotation steps animate briefly and movement stays camera-relative.

## Background & light
- [ ] Day background flat warm cream, no gradient/sky/vignette.
- [ ] Key light from screen upper-left; shadows to lower-right.
- [ ] Shadow edges soft-but-bounded; shadow tone tinted, never black.
- [ ] Contact grounding under every prop (SSAO + shadow overlap).
- [ ] Bright faces keep hue; nothing clips to white.
- [ ] Rain preset: green-gray background, dim cool key, warm fire pools, readable rain.

## Materials & modeling
- [ ] All matte (high roughness); metal/water/gold only exceptions.
- [ ] Zero texture noise; separation via face color + geometry.
- [ ] Tile top edges chamfered; earthy side walls darker than tops.
- [ ] No seams/z-fighting/gaps between connected tiles.
- [ ] Vegetation chunky (stacked cones / blob clusters), no leaf cards.
- [ ] Rocks/soil clods faceted flat-shaded; pots/props smooth-shaded with bevel rims.
- [ ] Grass is warm yellow-green (#BFC72A family), stone warm not blue-gray.
- [ ] Water: pale blue-green basin below land top, slight transparency, gentle ripple.
- [ ] Fire: yellow core + orange shell + chunky smoke; warm compact light pool; bloom
      only on emitters.

## Failure smells (any of these = fail)
- [ ] Looks like: gray-box / asset-store demo / Minecraft / pixel art / glossy mobile
      builder / realistic PBR / mixed AI styles.
- [ ] Black void, black shadows, neon grass, outlines, dithering, ghosting, sharpening
      halos, shadow crawl.

## Character
- [ ] 2.5–3.5 heads tall, chunky clothes, readable at gameplay zoom; not a capsule or
      gray mannequin; shadow matches world softness/direction.
- [ ] Equipment changes clearly visible at gameplay distance.
