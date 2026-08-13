# Meshy asset import

`tools/import_meshy_asset.py` is Suma's guarded path from a generated GLB to a
clean, game-ready model. It removes baked grime, lighting, normal-map noise,
and metallic/roughness noise by replacing them with the checked-in Garden
Galaxy reference palette and Suma's shared material response.

The importer deliberately does **not** remesh, decimate, subdivide, relax, or
move vertices. A geometry gate compares vertex, face, triangle, connected-form,
and bounding-dimension counts before installation. Smoothing is a restrained
runtime normal blend saved in `data/asset_edits.json`; it changes shading, not
the silhouette. Tree imports also separate the classified canopy from the
trunk without changing topology so `LeafCanopy` receives Suma's existing wind.

## One-command import

Run this from the repository root with Blender 4.5 installed at the default
location:

```powershell
python tools/import_meshy_asset.py `
  --source "C:\Users\Luka\Downloads\my_model.glb" `
  --asset-id prop_my_model `
  --profile generic
```

This produces:

- `assets/3d/reworked/prop_my_model.glb`, ready for `AssetLibrary`;
- a restrained default smoothing profile in `data/asset_edits.json`;
- `../suma-nook-asset-reviews/prop_my_model/review.png`;
- `../suma-nook-asset-reviews/prop_my_model/report.json`, including source and
  output hashes, topology counts, dimensions, texture counts, semantic material
  usage, installed path, scale, and smoothing.

The model still needs a deliberate `data/structures.json` and
`data/creative_collections.json` entry before it appears in the Build Bag.
Those gameplay choices are not guessed from pixels.

## Profiles

| Profile | Use for | Default smoothing | Special handling |
| --- | --- | ---: | --- |
| `tree` | Trees with one generated source mesh | 0.82 | Splits one sealed `LeafCanopy` for wind |
| `shrub` | Broadleaf bushes with one generated source mesh | 0.26 | Splits one sealed `LeafCanopy` for wind and uses broadleaf greens |
| `wood_prop` | Furniture, radios, cabinets, wood tools | 0.42 | Favors warm wood, cream, gold, dark and sage accents |
| `stone_prop` | Rocks, wells, masonry, stone ornaments | 0.34 | Favors the reference stone ramp |
| `generic` | Mixed-material decorations | 0.30 | Uses all restrained semantic families |

Use `--scale 0.6` to save a game-wide size correction. Override the normal
blend only when the neutral render proves the default is wrong, for example
`--smoothing 0.18`.

For a composed prop containing exactly three grounded forms, an explicitly
requested variety turn can be recorded with `--rotate-medium-cluster 24`. It
rigidly rotates the middle-height form around its own base. The receipt records
the angle, pivot, component/face count, and cluster heights; topology must still
pass unchanged.

## Review-first workflow

For an unusual or important model, stage it without modifying the game:

```powershell
python tools/import_meshy_asset.py `
  --source "C:\Users\Luka\Downloads\my_model.glb" `
  --asset-id prop_my_model `
  --profile generic `
  --no-install
```

Inspect the reported PNG, then rerun without `--no-install`. Existing assets
are protected from replacement unless `--force` is passed after review. Use
`--allow-untextured` only for a deliberately untextured source; otherwise a
missing albedo fails the safety gate instead of producing a guessed result.

## What remains art direction

The process standardizes material cleanliness, palette, surface response,
grounding, safe normal smoothing, and tree wind compatibility. It cannot turn
a fundamentally malformed silhouette or broken generated topology into a good
model without sculpting. Such an asset should be regenerated or hand-authored,
not automatically deformed. The wardrobe is intentionally outside this
pipeline and retains its authored material treatment.
