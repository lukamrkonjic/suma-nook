---
name: import-asset
description: Import a generated GLB (Meshy, Tripo, etc.) into Suma as a game-ready asset, or replace an existing one. Use when the user gives a path to a .glb and asks to import it, bring it in, or replace an existing prop. Handles measuring against the Garden Galaxy budget, the material mis-snap traps, sizing, wiring into game data, and verification.
---

# Import a generated GLB into Suma

Run the whole sequence. Every step exists because skipping it shipped a broken
asset at least once.

## 1. Measure the source before importing

```bash
mkdir -p artifacts/_probe && cp "<SOURCE.glb>" artifacts/_probe/probe.glb
"/c/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup \
  --python tools/measure_style_fingerprint.py -- --directory artifacts/_probe --out artifacts/probe.json
rm -rf artifacts/_probe
```

Read `triangles`, `welded`, `components`, `dimensions`, `facet_evenness`, and
compute width-over-height as `max(dim[0], dim[1]) / dim[2]`.

Compare against `data/gg_polycount_reference.json`, measured from Garden
Galaxy's 724 shipped assets. **Nothing in that library exceeds 1908
triangles**; category medians run 70-336. A model far above its category is
worth flagging to the user, but is not a reason to refuse the import.

Report anything alarming rather than silently proceeding:
- `welded: false` or `components` equal to the triangle count means split
  vertices; shading will be faceted.
- Many components on a solid object means a fragmented shell.

## 2. Pick the profile

`--profile` selects the material palette and the tree/prop handling. It is
deliberately not guessed from the filename.

| Profile | Use for |
|---|---|
| `tree` | Trees with a trunk and canopy. Splits the canopy for wind. |
| `shrub` | Bushes, broadleaf masses. |
| `wood_prop` | Furniture, tools, crates, anything mostly wood. |
| `stone_prop` | Rocks, masonry, stone ornaments. |
| `generic` | Mixed-material decorations. |

## 3. Work out `--scale` BEFORE importing

The importer rewrites the asset's profile in `data/asset_edits.json`, and
`--scale` defaults to 1.0. **Replacing an asset without passing its existing
scale silently resizes it in game.**

- Check `data/asset_edits.json` for the current `scale`.
- If the model's dimensions differ from the one it replaces, measure the old
  asset too and scale so the world size is preserved: `old_height / new_height`
  (or the longest dimension for a ground prop whose footprint matters).
- Never write a `--smoothing` value. Assets inherit the game-wide default of
  0.85; writing one opts the asset out and it arrives visibly faceted next to
  everything else.

## 4. Import

```bash
python tools/import_meshy_asset.py --source "<SOURCE.glb>" \
  --asset-id <prop_name> --profile <profile> --scale <scale> [--force]
```

`--force` is required to overwrite an existing asset.

**Do not run a chunk pass or a `--tone-ramp` over the result.** The importer
quantises the source texture per face, which follows the model's own design.
Recolouring by face normal on top of that flattens it and breaks how the
colours read.

## 5. Colours must match the source, in Suma's palette

Suma replaces every source texture at import, so the only way an asset keeps
the colours it was designed with is for each region to land on the palette
entry nearest to it. `prepare_model_import.py` does this by perceptual
nearest-colour match per component (`nearest_palette_slot`), not by guessing a
material family from hue rules. The old hue rules overrode the source and got
it plainly wrong -- a desaturated grey-green stone statue classified as
`wood_primary`, a saturated brown.

Nearest-match alone is not enough either, because palette entries from
different materials sit close together in RGB. Warm mid-brown is near
terracotta, and pale shaded wood is near stone, so an unrestricted match sent
a wooden wheelbarrow pink and grey. `PROFILE_PALETTES` therefore limits each
profile to the slots that make sense for it:

| Profile | Reaches |
|---|---|
| `tree` | canopy: pine only. trunk: wood only. |
| `shrub` | canopy: leaf/pine. trunk: wood. |
| `wood_prop` | wood, gold accent, cream/near-black. No stone, no terracotta. |
| `stone_prop` | stone and neutrals, plus wood for wooden parts. |
| `generic` | everything -- use it when an item genuinely spans families, e.g. a red-capped mushroom with a pale stem. |

**Always check the result against the source.** Sample the source's own colours
and confirm the assignment preserves its structure:

```bash
python - <<'PY'
import sys, colorsys
sys.path.insert(0, "tools")
import bpy, prepare_model_import as P
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="<SOURCE.glb>")
obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
samples = P.sampled_materials(obj)
buckets = {}
for comp in P.face_components(obj.data):
    col = P.average_component_color(obj.data, comp, samples)
    srgb = tuple(P._srgb_channel(max(0.0, float(c))) for c in col)
    buckets.setdefault(tuple(round(c * 6) for c in srgb), [0, srgb])[0] += len(comp)
for _, (n, srgb) in sorted(buckets.items(), key=lambda x: -x[1][0])[:8]:
    print(f"faces={n:4} sRGB=({srgb[0]:.2f},{srgb[1]:.2f},{srgb[2]:.2f})")
PY
```

If the source turns out to be a single flat tone, say so rather than inventing
colours. A monochrome source cannot produce a multi-material result, and the
real fix is upstream: generate the reference image with per-part palette hexes
so the separation exists to be matched.

## 6. Check the material assignment for mis-snaps

```bash
python -c "
import json
r=json.load(open('C:/Dev/suma-nook-asset-reviews/<prop_name>/report.json'))
print(r.get('topology_preserved'))
for m,n in sorted(r.get('semantic_face_usage',{}).items(), key=lambda x:-x[1]): print(f'{m:24} {n}')
"
```

The known trap is **`gold_primary` claiming pale warm wood**. A share above 15%
is now demoted automatically, but small stray patches still slip through and
show as bright yellow specks. Fix them at the source, not with a runtime
override:

```bash
"/c/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup \
  --python tools/remap_asset_materials.py -- --asset assets/3d/reworked/<prop_name>.glb \
  --map gold_primary=wood_light
```

That renames the slot **and** writes the palette colour, which matters: renaming
alone fixes the game (MaterialLibrary rebinds by name) while leaving every
offline render showing the old colour.

For a `tree`, also confirm the split worked:

```
PART LeafCanopy  ... (should NOT start at z 0.000)
PART Trunk       ... (should be real geometry, not a 5-face cap)
```

A trunk left inside `LeafCanopy` sways in the foliage wind and renders green.

## 7. Look at the render

`C:/Dev/suma-nook-asset-reviews/<prop_name>/review.png`. Send it to the user.

Note when reporting: **review renders do not apply the runtime 0.85 smoothing**,
so the asset reads more faceted here than it will in game.

## 8. Wire it into game data, if it is new

Skip for a straight replacement of an existing asset.

Both `data/structures.json` and `data/creative_collections.json` are **2-space
indented with CRLF endings**. Re-serialising them through `json.dumps`
reformats 1600+ lines for a 30-line change — insert as text, preserving the
surrounding style. Structures are expanded blocks; collection members are
one-line compact objects.

- `data/structures.json`: copy the nearest existing entry and change `id`,
  `name`, `asset_id`.
- `data/creative_collections.json`: add a member to the right collection.
- **Support slot height**: offsets go through `model_space_offset`, which
  applies `world_model_scale` only — the asset's own edit scale is NOT
  applied, while the visual gets both. So author the offset in already-scaled
  units: `model_height x edit_scale x 1.09` for flat-top furniture
  (`prop_table` measures 1.104, `prop_stool` 1.087). Getting this wrong makes
  everything placed on it float.
- **Any structure with support slots must be declared in the audit** in
  `tests/test_runner.gd` (`expected_supports`), listing what each slot
  accepts. Nine assertions fail until it is.

## 9. Verify

```bash
"/c/Dev/Godot/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --import
"/c/Dev/Godot/Godot_v4.6.3-stable_win64_console.exe" --headless --path . --script tests/test_runner.gd
```

The reimport is required — without it Godot renders the stale cached mesh.

`FAIL: Soft-daylight uses balanced 4x MSAA and a bounded shadow map` is
**pre-existing and unrelated**: `project.godot` ships `msaa_3d=3` and
`directional_shadow/size=8192` while the test expects 2 and 4096. Report it as
pre-existing; do not "fix" it as part of an import.

Optionally confirm smoothing resolves:

```bash
"/c/Dev/Godot/Godot_v4.6.3-stable_win64_console.exe" --headless --path . \
  --script tests/smoothing_weld_probe.gd -- <prop_name>
```

## 10. Commit and push

Commit message should record the measured before/after, the profile and scale
used, any mis-snap fixed, and the suite result. Push to the current branch.

Note: `git commit -m` with a here-string breaks on embedded double quotes in
PowerShell — write the message to a file and use `git commit -F`.
