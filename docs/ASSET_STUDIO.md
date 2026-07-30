# Asset Studio

Asset Studio is Suma Nook's in-game authoring room for production tiles and
models. Open it with `F8`, or choose **Admin > Asset Studio** from the pause
menu.

The left browser is populated from the live tile and structure registries. Tile
entries are grouped by their gameplay family and models by their structure
kind. Selecting an entry instantiates the real GLB through `AssetLibrary`;
layered tiles are shown as a 3x3 seam patch and expose each underlying asset as
an edit target.

The viewport uses the game's camera, lighting rig, weather profiles, materials,
and post-processing. Drag or use the right stick to orbit, use the wheel or
camera zoom actions to zoom, and use the bottom controls to test the asset at
different times of day and in different weather. Wind is a preview-only stress
test for foliage and flexible details.

## Runtime edits

The right inspector edits the selected production asset ID:

- **Desired smoothing** is an absolute value for tiles: `0%` is the exported
  authored relief with flat per-face shading. Moving upward relaxes the exposed
  height field and compresses its relief; `100%` is strongly relaxed, reduced
  to roughly eight percent of its remaining height above the fixed perimeter,
  and position-welded smooth. Snow, grass, stones, moss, flowers, and other
  fused details can participate. The rectangular block, perimeter border,
  bevel, side walls, underside, seams, X/Z footprint, UVs, topology, and
  collision remain authored. Layered structural bases are locked entirely.
  Models retain their source geometry and only smooth from their source-normal
  baseline.
- **Uniform size** appears for models only and ranges from `25%` to `300%`.
  `100%` is the untouched GLB scale. Saving applies the multiplier to every
  instance of that model asset in the current world, structure batches, new
  placements, collision bounds, and future launches. Tile dimensions remain
  locked so terrain footprints, borders, and seams cannot be resized.
- **Material slot** selects a semantic palette material used by the asset.
  Color is always opaque standard RGB: alpha and HDR intensity editing are
  deliberately unavailable. The picker is followed by 114 canonical Suma
  design tokens arranged as searchable material and hue families. Sand, snow,
  and concrete each have dedicated five-step highlight-to-deep ramps; their
  structural side colors remain separately named. Broader families are split
  into focused groups such as grass, moss, leaves, pine, earth, soil,
  terracotta, coral, skin, and hair. The family selector keeps related ramps
  together, the dense three-column grid makes better use of the inspector, and
  search scans every token. Selecting a named swatch applies its production material color
  immediately; a free-picked exception identifies its nearest palette token.
  Color, roughness, and metallic values live on an asset-local duplicate, so
  changing one tile or model does not recolor every asset that uses that
  palette key. Layer-composed tile material overrides are reapplied through the
  same saved asset profile.
- **Reimport** discards unsaved changes and reloads the saved game profile.
- **Authored** restores the untouched GLB normals and palette material values in
  the preview. Saving this state removes that asset's override.

**Save edits to game** writes the profile to `data/asset_edits.json`, clears the
asset and composed-world mesh caches, and rebuilds the running world. New
instances, layered tiles, structure batches, scalable MultiMesh chunks, and the
next game launch all consume the same profile through `AssetLibrary`.

`Ctrl+S` saves the current edit. Closing Asset Studio restores the exact
gameplay pause, camera, lighting, and visibility state it found.
