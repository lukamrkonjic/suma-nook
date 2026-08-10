# Curated free itch.io catalog

This directory records the reproducible source and review evidence for 411
calm, low-poly placeables imported from 11 free itch.io packs.

## What is kept

- `manifest.json` is the authority for source URLs, archive filenames,
  SHA-256 pins, licenses, and exact include/exclude filters.
- `archives/` keeps redistributable CC0 downloads. WizP's Fishing Village
  archive stays local and git-ignored because its terms prohibit standalone
  redistribution; its hash and terms remain recorded here.
- `licenses/` contains the license/readme evidence copied from each pack.
- `generation_report.json` records every output's source, bounds, palette
  materials, hash, and original geometry/shading signature.
- `review/` contains representative contact sheets rendered from the shipped
  GLBs, not from the source files.

`extracted/` is disposable and git-ignored. Extract each pinned archive into a
folder named after its manifest pack id before rebuilding.

## Rebuild

```powershell
& 'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe' `
  --background --factory-startup `
  --python art_source/blender/process_itch_free_packs.py

& 'C:\Program Files\Blender Foundation\Blender 4.5\blender.exe' `
  --background --factory-startup `
  --python art_source/blender/render_itch_asset_review.py
```

The processor fails if a source hash changes, if a texture or non-Suma material
leaks into a runtime GLB, or if palette conversion changes source vertex, edge,
face, sharp-edge, or smooth-face counts. It intentionally preserves the source
models' faceted geometry and shading; only palette materials and placeable
transforms change.

Generated runtime files are `assets/3d/reworked/itch_*.glb`,
`data/itch_structures.json`, and `data/itch_wish_rewards.json`.

## Curation summary

The catalog includes nature, pond, park, picnic, homestead, treehouse,
workshop, animal, and fishing-village pieces. Paid add-ons were never
downloaded. Combat props, modern vehicles/buildings, trash cans, and other
pieces that break Suma's calm setting are excluded by the manifest filters.
