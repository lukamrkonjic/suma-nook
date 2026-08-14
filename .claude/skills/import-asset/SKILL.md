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

### Strip a baked ground disc first

A model generated from a reference image often arrives standing on a disc of
"ground" that was part of the picture. Suma supplies the ground, so the disc
renders as a large flat plate under the object -- and because it dominates the
footprint it also throws off the scale calculation in step 3.

It shows up in step 1 as a model far flatter than the object should be:
tent.glb measured 1.0 x 1.0 x 0.288, and its base carried 81% of the total
surface area out to radius 0.514 while the tent itself stayed within 0.214.

```bash
"/c/Program Files/Blender Foundation/Blender 4.5/blender.exe" --background --factory-startup \
  --python tools/strip_ground_disc.py -- --source "<SOURCE.glb>" \
  --output "<SCRATCH>/clean.glb" [--dry-run]
```

It removes connected components that are flat, sit at the base, and reach past
the radius of everything that is not flat-and-at-the-base -- shape, not a fixed
size. Run `--dry-run` first and read the report; if it removes nothing, or
removes a suspiciously large share, the model does not fit the pattern and the
disc needs handling by hand. **Then measure the cleaned file again** and use
those numbers for the scale, not the original's.

Re-exporting splits vertices on a flat-shaded model (tent.glb: 604 faces went
from 1067 vertices to 1812), which is why the importer measures weldedness by
distinct positions rather than raw vertex count. Otherwise a stripped model
looks unwelded and inherits the 0.85 smoothing that melts it.

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
- Generated sources are normalised to a longest edge of 1.0 while the asset
  they replace was authored at its world size, so a scale near 5 is normal
  for a replacement. `prop_shelter` is authored at 1.5 and its replacement
  imported at 4.7.
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

### Shading: the glb must carry NORMAL

**Every asset ships normals. An asset without them arrives in game rounded and
detail-free, and no smoothing setting can recover it.**

Suma decides shading at runtime: `AssetEditLibrary._smoothed_mesh` blends each
surface's OWN normals toward averaged ones by the asset's `model_smoothing`. So
the authored normals are the crisp end of the range the player is adjusting, and
a file without them has no crisp end to blend from.

glTF has no per-face normals, so flat shading costs a vertex split. That split
is not damage and must not be optimised away. Measured on the wardrobe: its
source stores POSITION and TEXCOORD_0 and no NORMAL, which keeps it welded at
906 vertices over 1000 faces -- and shipping it that way made Godot generate
averaged normals across every hard edge. The cabinet lost its door panels, its
bevels and its facets, and `model_smoothing = 0` changed nothing. Every other
shipped asset carries NORMAL; that one was the exception and it looked like it.

Make the shading uniform before exporting, too. Repeated passes accumulate a
custom split-normal layer and leave a scatter of faces smoothed among flat
neighbours -- the wardrobe reached the game with 73 of them -- which reads as
the model being subtly, unevenly wrong. `tools/glb_export.py` does both.

Check any hand-built asset before shipping it:

```bash
python - <<'PY'
import json, struct
data = open("assets/3d/reworked/<prop_name>.glb", "rb").read()
doc = json.loads(data[20 : 20 + struct.unpack("<I", data[12:16])[0]].decode())
print(sorted({k for m in doc["meshes"] for p in m["primitives"] for k in p["attributes"]}))
PY
```

`NORMAL` must be in that list.

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

### When the asset is assembled rather than imported

Some assets are not one source model: the wardrobe is two, merged into one glb
with its doors split onto nodes the game rotates by name. `import_meshy_asset.py`
cannot be used, because `prepare_model_import.py` re-roots and renames, which
destroys exactly the node structure those assets depend on.

Use `tools/palette_map_asset.py` instead. It reuses only the colour half and
leaves every object, name and transform alone.

Then **record the recipe as a script** -- `tools/rebuild_gift_wardrobe.py` is the
model. An assembled asset takes several passes whose order matters, and
reconstructing that order by hand goes wrong: grounding before splitting the
doors silently sinks the open state, because the splitter re-parents with an
identity parent inverse and drops the offset the source's parent empty carried.
A recipe script also means the asset can be rebuilt from the sources after any
tooling fix, which is the only reason the wardrobe's colour and shading bugs
could be fixed without redoing the assembly by hand.

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

### Assign colour per surface, never per triangle

A modelled surface is many triangles and a texture is not perfectly even across
it, so judging each triangle on its own sample lets one half of a quad take a
different palette entry from the other. In game that is a hard-edged triangle of
the wrong colour in the middle of a flat panel -- the single most visible way an
import can fail, and the wardrobe shipped with two of them.

Group faces into continuous surfaces and assign the group. Two conditions,
both needed:

- **Geometric**: neighbouring faces join while their normals agree to about 20
  degrees. Not coplanarity -- these models are gently curved, and a strict
  planar test found 1694 groups across 2000 faces, which is no grouping at all.
- **Colour**: neighbours also have to sample alike. Geometry alone walks
  straight across a paint boundary wherever the form is continuous. The
  wardrobe's corner post runs unbroken from the body down past the plinth, so a
  purely geometric fill averaged the whole post to the body's colour and left a
  light spike hanging in the dark plinth.

Adjacency must be keyed by vertex **position**, not vertex index. Flat shading
splits vertices, so two triangles meeting along an edge hold different indices
for the same two corners; keyed by index the mesh looks like a thousand isolated
faces and nothing ever groups.

Then let a borderline face follow the region around it, but **only** if its own
colour is genuinely undecided -- roughly equidistant between the two cluster
centres. Without that guard a small region that really is a different paint gets
swallowed: the wardrobe's handles are small and completely surrounded by the
door's colour, and they must stay dark.

`tools/palette_map_asset.py` implements all of this.

### Cluster on hue and saturation, not value

Source textures bake their shading in, so **value is the one channel that varies
within a single paint** -- the wardrobe's orange samples #B8843E on the lit door
and #6F3102 on the shaded side. Between two paints it is the reverse: measured
on that model, its brown and its orange overlap in value and separate cleanly on
hue (28-30 vs 34-36 degrees) and saturation (0.32-0.37 vs 0.55-0.58).

Splitting on value grouped the shaded side with the top slab -- a different
paint -- and gave a two-tone model three tones. Value still has to decide for
assets with unsaturated regions, where hue is meaningless noise; switch on
whether every face carries real saturation.

### When the cluster count is wrong

The default merge distance cannot be right for every model, and the two failure
cases are genuinely indistinguishable from the texture alone. Measured: the
wheelbarrow's lit and shaded frame sit 0.103 apart and *must* merge, while the
tent's canvas and its cream bindings sit 0.084 apart and *must not*. One paint
under two lights looks exactly like two paints of similar hue.

So when a reference image shows more materials than the import finds -- tent2
came back as a single 1200-face cluster where the image plainly has canvas,
poles and bindings -- lower it:

```bash
python tools/import_meshy_asset.py --source "<SOURCE.glb>" --asset-id <prop>   --profile <profile> --scale <scale> --color-merge-distance 0.06 --force
```

Sweep it rather than guessing, with `--skip-render --no-install` so nothing is
written, and pick a value in the middle of a stable band. The tent gave three
clusters from 0.06 all the way down to 0.03, so 0.06 is safe; a value that only
works in a narrow window is fitted to noise.

### Matching a reference image exactly

Nearest-match works from the texture, which is often far more washed out than
the render the user is comparing against. When the user supplies a reference
image and asks for it to be matched, map the clusters deliberately instead:
find the palette entry nearest each colour *in the image*, then remap. The
tent's canvas sampled as a dull tan but the image is mustard, which is `gold` at
a distance of 0.038.

Beware that HLS saturation is unreliable for very light colours, so a cream can
score badly against the near-neutral entry that actually looks right -- the
tent's cream binding ranked `sand_top` first and `warm_white` fourth, and
`warm_white` is the correct read. Trust the image over the ranking for pale
tones.

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

When the palette genuinely cannot hold a colour, say so and name the slots
explicitly rather than tuning the clustering until something else comes out. The
wardrobe's mid orange (#C9954A) has no saturated equivalent, so it resolves
lighter; `palette_map_asset.py --slot <name>` records that decision in the
recipe instead of leaving it to be rediscovered. Naming the slots is also what
lets the user pick the colours themselves afterwards.

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

Note `--map` takes space-separated pairs, so repeating the flag silently keeps
only the last one: `--map a=b c=d`, not `--map a=b --map c=d`.

That renames the slot **and** writes the palette colour, which matters: renaming
alone fixes the game (MaterialLibrary rebinds by name) while leaving every
offline render showing the old colour. The colour comes from
`data/garden_galaxy_reference_palette.json`, the same file the importer uses --
it used to come from `gg_material_palette.tres`, which holds different values
for every slot and darkened them a second time, so a canvas remapped to `gold`
rendered dark olive.

### Check the layout, not just the counts

Cluster counts say how many paints were found, not whether they landed on the
right parts. Sample the SOURCE's own regions and compare with the slots the
asset ended up with -- for anything with an obvious structure, name the regions
by geometry and tabulate:

| region | source samples | slot assigned |
|---|---|---|
| top slab | #9C734B | `wood_light` |
| base / feet | #8C6746 | `wood_light` |
| side panel | #C9954A | `sand_top` |
| door front | #BC873B | `sand_top` |

That table is what caught the wardrobe's side panel being grouped with its top
instead of its doors. Mind that a naive region test picks up more than intended:
"faces whose normal points sideways at maximum x" also catches the sides of an
overhanging top slab and base, which mixed two paints into one row and made a
correct assignment look broken. Constrain by height as well.

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

### A Blender render can answer the wrong question

Blender shades a glb with Blender's rules, and Godot's differ in exactly the way
that matters. A wardrobe with no NORMAL attribute rendered crisply facetted in
review -- Blender computed flat faces -- and arrived in game rounded, because
Godot generated averaged ones. The review looked right while the asset was
broken.

So when the user reports something that the review render does not show, capture
the engine's own output before theorising:

```bash
"/c/Dev/Godot/Godot_v4.6.3-stable_win64_console.exe" --path . \
  tests/asset_ingame_capture.tscn -- --shot-dir=res://artifacts/asset_capture \
  --asset=<prop_name> --smoothing=0.0
```

That harness opens the real game, selects the asset in the Asset Studio and
saves a screenshot. Two things it had to learn: a fresh save opens the
collection prompt over the whole screen, so hide it before capturing; and
smoothing has to be set BEFORE the model is built, since setting it afterwards
leaves the mesh already made.

Running the game rewrites `data/asset_edits.json`, so `git checkout` it
afterwards unless you meant to change a profile.

### Deciding whether a defect is colour or geometry

Colour bugs and modelling artifacts look alike once the palette puts a light
region against a dark one. Settle it in one step: **re-render with every
material forced to a single flat colour.** If the shape survives, it is
geometry, and no amount of clustering work will remove it.

That test ended a long hunt on the wardrobe's back corner. The spike there is in
the user's own source model -- the body's bottom ring steps up by 0.023 at the
mitre where the corner post dies into the plinth -- and it is invisible in the
source only because both parts are near-identical browns there. Say so and offer
to change the geometry, rather than tuning the colour mapping to hide it.

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

The suite is green: any failure is yours. (It used to ship one stale MSAA
failure, which this skill told you to wave through; the test now pins the
authored values and passes, so there is nothing left to excuse.)

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
