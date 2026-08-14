# Provision refactor: de-hardcode the Worldheart, make the wardrobe a normal model

Agreed with Luka 2026-08-14. The Worldheart conflates two unrelated things: a
reward *service* (the progression loop that surfaces items for the player to
claim — real gameplay, keep it) and the wardrobe's *presentation* (a bespoke
presenter that preloads models, hoists them by hand-tuned constants, and
duplicates work the structure pipeline already does). Every wardrobe bug this
week traces to that conflation: not listed in Asset Studio, then listed but not
selectable, smoothing edits that save but do nothing, clipping through its tile.

The firepit is the proof the right pattern already exists: an ordinary
`structures.json` entry with a `fire` capability, its flame attached by
`StructureVisualFactory`. Special features belong to capabilities on normal
structures, because more models with special features are coming.

## Naming

`Worldheart` → **`Provision`** (the service provisions the player with items).
Generic on purpose: nothing in it names the wardrobe, so the vessel can be
replaced without another rename. Derived names:

- `WorldheartService` → `ProvisionService`; `worldheart_service.gd` moves with it
- `WorldheartPresenter` → dissolves; see below. Anything that survives becomes
  `ProvisionPresenter` (reward miniatures, launch arcs, progress card)
- save/tuning keys `worldheart*` → `provision*` WITH MIGRATION (see below)
- asset ids `worldheart_wardrobe_*` → `prop_gift_wardrobe` (one model; see below)
- `struct_` entry: `struct_gift_wardrobe`

374 occurrences across 23 files plus save data. Do the rename LAST, after the
structural refactor, in its own commit — mechanical, reviewable, revertable.

## Order of work

1. **One model, doors split from the closed state.** Base the open state on the
   regular wardrobe model (Luka's suggestion): split its doors, rest pose SHUT
   (`rotation.y = 0`), animate to an `OPEN_YAW`. This deletes the two-model swap
   (`_set_wardrobe_open_visual`) and the top-of-door gap, which exists because
   the two models disagree about the frame opening. The door detector in
   `tools/build_wardrobe_hinged.py` keys on doors protruding forward, which
   closed doors do not — the split needs a new discriminator (the door panels'
   inset faces vs the stiles; look first, then write the rule). Reuse
   `tools/verify_wardrobe_doors.py` (sweep, minimise depth footprint) with the
   logic inverted: solve for OPEN, not shut. Mind its two measured traps: glTF
   import leaves nodes in QUATERNION rotation mode where `rotation_euler`
   assignment is silently ignored, and `matrix_world` is stale until
   `view_layer.update()`.

2. **Register it as a structure.** `structures.json` entry with a new capability,
   e.g. `hinged_doors: {left: "WardrobeDoorLeft", right: "WardrobeDoorRight",
   open_yaw_deg: ...}`. `StructureVisualFactory` attaches a door controller
   beside its `fire` / `ambient_motion` handling. The swing tweens move from the
   presenter into that controller, unchanged — they are good.

3. **ProvisionService targets a structure instance** instead of owning a visual:
   it knows the instance id of the vessel, asks the renderer for its node, and
   drives the capability controller (open/close) around claims. The reward
   miniatures/launch presentation stays in a slimmed presenter.

4. **Delete the special cases added this week** — they exist only because the
   wardrobe was not a normal model:
   - `PRESENTER_MODELS` + `presenter_model_name` + the null-definition branch in
     `asset_viewer.gd` (it becomes a registered structure, listed normally)
   - `WARDROBE_BASE_HEIGHT` (already 0.0; delete outright)
   - the `worldheart_presenter` line in `_hide_gameplay_presentation` stays only
     for what remains presenter-owned (miniatures)

5. **Rename pass** (`worldheart` → `provision`), including:
   - save keys: read old, write new — `data.get("provision",
     data.get("worldheart", {}))` for at least one release
   - `debug_wardrobe_gift` / debug menu label stay wardrobe-named only if the
     vessel does; prefer "Provision gift"

## Step 1 attempt log — read before retrying the single-model split

`tools/split_closed_wardrobe.py` exists and its DOOR SELECTION is correct and
verified by render: the closed mesh arrives as 998 connected components (most a
single face), so connectivity is useless and doors are selected by a region box
instead. Measured bounds that isolate exactly the two door slabs, backs
included: front plane `y < -0.04` (their back faces sit near -0.07, and cutting
at -0.09 exported hollow doors), `x` within ±0.263, `z` within -0.365..0.418
mesh-local. That yields body 663 / left 153 / right 184.

What is NOT solved is the exported node frame. The attempt baked the object
transform into the vertices to get identity-rotation nodes, and that is where it
went wrong, three times:

1. Baking while the mesh was still parented and deleting the parent afterwards
   left the orphan holding the basis that had compensated for the parent --
   reintroducing the rotation the bake removed. Order must be: capture
   `matrix_world`, unparent, identity the basis, then `data.transform(...)`.
2. Baking shifts the geometry by the grounding lift, so the region box's `z`
   bounds must move with it (+0.5) or the split silently loses most door faces.
3. With transforms baked the cabinet's front lands on glTF **+Z**, which is
   backwards; a 180 degree Z flip fixes the facing but then front is `+y` in
   Blender, inverting both the region test and the hinge-y pick. Even after
   that, in game the shut pose read as turned with the doors hinging like a lid.

**Do not bake.** The working two-model `worldheart_wardrobe_hinged.glb` was
produced by `build_wardrobe_hinged.py`, which left the importer's `world` empty
and its axis conversion untouched and simply parented the split parts under a
new root. Rotation about Godot's `rotation.y` behaved correctly there. Repeat
that structure for the closed split: keep the imported hierarchy, add the root,
re-centre each door on its hinge line, export. Verify with
`verify_wardrobe_doors.py --solve` (mind: glTF import leaves nodes in QUATERNION
mode where `rotation_euler` assignment is silently ignored, and `matrix_world`
is stale until `view_layer.update()`).

The presenter edits for this step are straightforward and were proven to compile
and boot: rest pose becomes shut (doors to `0.0` on close, to `LEFT/
RIGHT_DOOR_OPEN_YAW` on open), `_set_wardrobe_open_visual` collapses to toggling
the cavity, and `wardrobe_open` aliases the single instance. They were reverted
only because the asset underneath them was wrong.

## Already done (this session)

- Asset rebuilt by `tools/rebuild_gift_wardrobe.py`, which records the whole
  four-pass recipe. Two things it fixes for good: the sources author NO glTF
  NORMAL attribute (which is what keeps them welded at 906 vertices and leaves
  shading to the renderer), and every re-export was writing normals, splitting
  the mesh to 5998 vertices -- the "jagged" look. And the palette split is on
  hue/saturation, not value: the source bakes its shading into the texture, so
  value varies WITHIN one paint while hue separates the two paints.

- Both wardrobe glbs grounded at their base (were centre-origined, `z ∈ [-0.5,
  0.5]`, the cause of the tile clipping; every imported asset is grounded, these
  were copied in raw). `WARDROBE_BASE_HEIGHT` zeroed.
- Smoothing edits still will not show on the wardrobe until step 2/3: the studio
  rebuilds the *renderer's* structures on save, and the presenter instantiates
  its models once at setup. Root cause is the architecture; do not patch it.
