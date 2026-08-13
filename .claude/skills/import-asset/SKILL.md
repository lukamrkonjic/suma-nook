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
"/c/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup \\
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
- Do not pass `--smoothing`. The importer now derives it from the measured
  geometry (`derived_smoothing`) and prints the reason; override only when a
  reviewed asset genuinely disagrees with that call.

### Smoothing: the default is not always right

Runtime smoothing blends authored normals toward position-welded ones. It
exists to rescue a **dense unwelded Meshy spray**, where every triangle is its
own shading island and the facets are an export artifact.

It ruins a **welded low-poly model**, where the facets *are* the design. At the
0.85 default the wheelbarrow's normals moved by up to 160 degrees and the fir's
by 174 -- past perpendicular, so lit faces shaded as if they pointed away from
the sun and the models read as melted blobs. Measured from the other direction,
the assets that were never smoothed are the ones that look right: firepit 0.0,
radio 0.42 at a 46-degree shift.

So the importer writes `smoothing: 0.0` when the source is welded (under 2.5
vertices per face) and under 2500 triangles, and inherits the default
otherwise. Confirm with the weld probe in step 9: an authored-shading asset
should report `moved=0`.

## 4. Import

```bash
python tools/import_meshy_asset.py --source "<SOURCE.glb>" \
  --asset-id <prop_name> --profile <profile> --scale <scale> [--force]
```

`--force` is required to overwrite an existing asset.

**Do not run a chunk pass or a `--tone-ramp` over the result.** The importer
assigns colour from the source's own clusters, which follows the model's
design. Recolouring by face normal on top of that flattens it and breaks how
the colours read.

## 5. Colours must match the source, in Suma's palette

Suma replaces every source texture at import, so the only way an asset keeps
the colours it was designed with is for each painted region to land on the
palette entry nearest to it. The importer does this by **clustering the source
and mapping each cluster to its own palette entry**, and prints the mapping:

```
cluster  486 faces sRGB=(0.71,0.56,0.23) -> wood_light
cluster  467 faces sRGB=(0.56,0.44,0.32) -> earth_primary
cluster   47 faces sRGB=(0.82,0.75,0.54) -> sand_top
```

Read those lines. They are the whole colour story of the asset: how many
distinct paints it has, and what each became. A model that comes out visibly
wrong is nearly always visible here first, as a cluster count that does not
match what the source obviously has.

Four things were each wrong at least once, and each is now load-bearing:

- **The whole palette is in play, not a curated subset.** The importer used to
  load 19 colours, and profiles narrowed that to 3-7. A red mushroom cap, green
  moss and brass fittings had nothing to match against and resolved to the
  nearest muted brown or grey. It now matches against all 57 distinct prop
  colours; `usable_palette()` only excludes water, snow, tiles and the
  background creams.
- **Matching is on hue/saturation/value, not RGB channels.** Channel distance
  prefers desaturated middles, because a muted entry is numerically near
  everything -- a saturated orange frame scored closest to `sand_shadow`, and a
  warm grey stem closest to pink `soft_coral`. Hue is weighted hardest since it
  is what identifies a colour.
- **Clustering is by hue and forgiving about value.** Source textures have
  lighting baked in, but Suma relights everything, so a paint's lit and shaded
  samples must reach the *same* entry. Splitting them sent the wheelbarrow's
  lit frame to olive and its shaded frame to mustard: one piece of wood reading
  as two materials.
- **Each cluster gets its own entry**, unless two clusters are genuinely near
  identical. Without that the wheelbarrow's tray, frame and fittings all
  resolved to `wood_light` and the model lost every internal distinction. The
  test is whether the two *clusters* match, not whether the alternatives are
  poor -- keying it on the alternatives let the statue's lit stone and its
  shadow share one entry and flattened the carving to a single tone.

A **hue-band penalty** stops a chromatic colour crossing families when the
palette has a gap. The statue's moss samples at 57 degrees, yellow-green, and
the palette jumps from gold at 51 straight to the first green at 80 -- so the
nearest hue was warm and the moss rendered as a tan smudge across the carving.
Near-greys are exempt, since their hue is noise.

For a `tree` or `shrub` the canopy is restricted to the green band and the
trunk to the warm band, whatever the texture samples -- the wind controller
drives the canopy mesh, so a brown crown reads as broken.

**Expect the result to be more muted than the source.** The GG palette has no
saturated red; a fly agaric's cap lands on `coral`. That is the palette working
as intended, not a bug to chase.

To see the source's clusters without importing:

```bash
"/c/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup \
  --python tools/measure_source_colors.py -- --source "<SOURCE.glb>" --clusters 10
```

If the source turns out to be a single flat tone, say so rather than inventing
colours. The real fix is upstream: generate the reference image with per-part
palette hexes so the separation exists to be matched.

## 6. Check the material assignment for mis-snaps

```bash
python -c "
import json
r=json.load(open('C:/Dev/suma-nook-asset-reviews/<prop_name>/report.json'))
print(r.get('topology_preserved'))
for m,n in sorted(r.get('semantic_face_usage',{}).items(), key=lambda x:-x[1]): print(f'{m:24} {n}')
"
```

Compare the counts against the clusters the importer printed. The old traps
here -- `gold_primary` claiming pale warm wood, wood claiming a stone statue's
crevices -- were symptoms of per-component matching against a narrow palette
and should no longer occur. If something is still mis-snapped, fix it at the
source rather than with a runtime override:

```bash
"/c/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup \
  --python tools/remap_asset_materials.py -- --asset assets/3d/reworked/<prop_name>.glb \
  --map <wrong_slot>=<right_slot>
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

Note when reporting: **review renders never apply runtime smoothing.** For an
asset the importer left at 0.0 the render matches the game; for one that
inherits the default it reads more faceted here than it will in game. Say which
case applies rather than assuming the render is representative.

**A render is not a reimport.** Godot caches the mesh, so step 9's `--import`
is what actually puts the change in front of the player.

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
