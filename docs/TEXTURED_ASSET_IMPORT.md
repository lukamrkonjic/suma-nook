# Textured asset import: palette-shift the texture, keep the detail

Proven on `prop_wishing_well` (2026-08-14), which shipped through every wrong
version of this before landing on the right one. This is the exact recipe, in
order, with the reason each step cannot be skipped.

## When to use this instead of the flat importer

`import_meshy_asset.py` repaints geometry: it clusters the source's colours and
assigns one flat palette material per region of FACES. That is right for models
whose paint follows their geometry. It is wrong for models whose texture IS the
detail — per-stone tonal variation, crevice shading, and above all **paint
boundaries that run through faces**. The well's moss is painted onto parts of
faces; per-face repainting turned whole faces green wherever the average
tipped, and no amount of cluster tuning fixed it, because the failure is the
granularity, not the clustering.

Symptoms that call for this flow: the flat import looks "melted flat" next to
the source render, colours bleed outside their painted regions, or the user
says the source's look must survive exactly.

## The recipe

```bash
"/c/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup \
  --python tools/palette_shift_texture.py -- \
  --source "<SOURCE.glb>" --output assets/3d/reworked/<prop_name>.glb
```

One tool, `tools/palette_shift_texture.py`, does all of it:

1. **Classify every texture PIXEL** with the importer's own band rules
   (`GREEN_BAND`, plus `OLIVE_BAND`: a dull yellow-green at hue 46-55 and
   saturation under 0.5 is moss, a vivid one is gold — hue alone cannot split
   them, measured: the well's moss at 50.2° vs golds at 42-51° but sat 0.55+).
2. **Palette-shift per class**: each class's mean maps to its nearest palette
   entry (greens choose among greens — the family invariant), and every pixel
   becomes `target * pixel / class_mean`. The deviation from the mean — all
   the baked shading — survives exactly; the class lands on the game colour.
3. **Split into two editable material slots via a decal shell** (see below).
4. Ground at the base, flatten shading, export **with normals**.

Then, as for any import:

- Write the smoothing profile (`smoothing: 0.0` for a welded low-poly source)
  and **COMMIT `data/asset_edits.json` immediately**. Running the game rewrites
  that file, the reflex is to `git checkout` it afterwards, and that checkout
  destroyed the well's uncommitted profile once — the asset inherited 0.85 and
  arrived in game as a melted blob.
- `--import`, suite, in-game capture with `tests/asset_ingame_capture.tscn`.

## The traps, each shipped once

- **Blender's `image.pixels` are LINEAR.** All palette maths (band rules,
  entries, means) live in sRGB. Classify and shift in sRGB, convert back to
  linear before writing. Classified in linear, only 0.1% of the well's moss
  registered as green and the base mean came out a shade too dark.
- **Only shift the base-colour texture.** Find it via
  `prepare_model_import.base_color_image(material)`. The other maps encode
  data as colours — the well's `Image_1` is a solid cyan data map, and
  shifting it corrupts the material.
- **A connected Base Color socket ignores `default_value`.** To give a
  material an editable colour factor, build the one node pattern the glTF
  exporter converts into `baseColorFactor`: `TexImage → Mix(RGBA, MULTIPLY,
  Factor 1.0, B = factor colour) → Base Color`.
- **`baseColorFactor` is capped at 1, and factor × texture must reproduce the
  shifted texture exactly.** Normalize each material's texture by its class's
  per-channel MAXIMUM (not by the target colour — half the pixels sit above
  the target and clip, which washed the model out to near-white).
- **Blender 4.5 cannot export `alphaMode: MASK`** (the `blend_method` property
  the exporter keyed on is gone). Patch the glb's JSON chunk after export:
  `alphaMode: "MASK"`, `alphaCutoff: 0.5`. BLEND works but moves the shell
  into the transparent pass, where it stops writing depth.
- **Do not name the materials after palette entries.** MaterialLibrary rebinds
  any material carrying a palette name to the flat palette material, which
  throws the texture away. `well_stone` / `well_moss`, not `sand_top`.
- **Strip every non-albedo texture node from the copied materials.** The
  source's other maps ride along and export as a metallicRoughnessTexture fed
  by the detail image — roughness then follows the picture, dark pixels go
  glossy, and a recoloured-dark class reflects the sky as cyan sheen. Remove
  the nodes BY NAME (`nodes.remove()` invalidates every other python node
  reference; removing by held references crashed) and pin metallic 0,
  roughness 1.
- **Decide shell membership by rasterizing UV footprints, not sampling.** A
  moss sliver a few texels wide along one edge slips between corner/centroid
  samples; its face stays out of the shell and the sliver keeps its base
  colour instead of switching with the moss slot. Rasterize each face's UV
  triangles against the (dilated) mask and include any face that touches it.
- **Painted patch EDGING belongs to the patch.** The well's texture edges its
  moss in dark teal (hue 160-210), just past the green band -- classified
  warm, it kept its blue cast through the stone transfer and rendered as cyan
  outlines around every patch. Classify edging hues with their patch, and use
  a LUMINANCE-only transfer for the moss class (exact target hue scaled by
  brightness) so no within-class hue deviation survives; keep the channel-wise
  transfer for stone, where warm variation is the charm.
- **Dilate the alpha mask past every UV island border.** The mask ends
  exactly at each seam, so the cutoff discards a hair of shell along every
  seam edge inside a patch and the base shows through as thin lines that
  follow the mesh edges. Grow alpha ~3 texels (and pad RGB further than
  that), which also closes the sub-texel bilinear rim at real boundaries.
- **Guard both sides of the alpha edge.** Bilinear sampling blends RGB across
  the cutoff, and the base texture shows through in a sub-pixel rim: pad the
  shell's class colour outward past its mask, pad the base's OTHER-class
  colour into the masked regions (the rim must not wear the original class
  colour, which no slot recolour can reach), and majority-smooth the per-pixel
  classification (9x9 box) so near-threshold pixels join the paint around
  them instead of speckling.

## The decal shell — why the material split has exactly this shape

Goal: recolouring a slot in Asset Studio must move ALL of its class and
nothing else, at pixel accuracy. Two simpler partitions were shipped and both
failed visibly:

1. *Mixed faces on the moss slot*: their stone pixels divide by the dark green
   factor, clip, and smear pale green triangles across the model.
2. *Mixed faces on the stone slot* (pure-moss faces only on the moss slot):
   default looks perfect, but recolouring moss moves only the pure patches —
   the user painted moss red and got a red/green patchwork.

The shape that works is a shell, not a partition:

- The **base mesh** keeps every face on `well_stone`, whose texture holds the
  complete shifted image. Its moss pixels render exactly and are then hidden
  under the shell.
- The **shell** duplicates every face that samples any moss, pushes it 0.004
  outward along vertex normals (wins the depth test, no visible gap), and
  carries `well_moss`: the same texture with per-pixel ALPHA = the moss mask
  and MASK-mode cut-out edges. Only moss pixels are visible on it, with the
  texture's own painted boundary.

Recolouring `well_moss` moves all the moss; `well_stone` moves the stone (its
covered moss pixels shift too, invisibly). Default render is bit-exact.

## Wiring a presenter-owned model

If the asset is presenter-owned rather than a registered structure (the well
replaces the Worldheart wardrobe), add it to `PRESENTER_MODELS` in
`scripts/ui/asset_viewer.gd` so Asset Studio can select it, and instantiate it
through `assets.instantiate(<id>)` — AssetEditLibrary only reaches assets
created that way.
