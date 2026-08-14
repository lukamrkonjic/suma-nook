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

## Already done (this session)

- Both wardrobe glbs grounded at their base (were centre-origined, `z ∈ [-0.5,
  0.5]`, the cause of the tile clipping; every imported asset is grounded, these
  were copied in raw). `WARDROBE_BASE_HEIGHT` zeroed.
- Smoothing edits still will not show on the wardrobe until step 2/3: the studio
  rebuilds the *renderer's* structures on save, and the presenter instantiates
  its models once at setup. Root cause is the architecture; do not patch it.
