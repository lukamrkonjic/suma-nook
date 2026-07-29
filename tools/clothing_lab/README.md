# Clothing Lab

Launch the standalone fitting room:

```powershell
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" `
  --path "C:\Dev\suma-nook" `
  "res://characters/lab/clothing_lab.tscn"
```

The fitting viewport is intentionally locked to the canonical Rest/T-pose.
Imported clothing is expected to use the same pose. Animation/motion
validation happens after binding and never changes the fitting viewport.

## Workflow

1. Select a body profile and the complete appearance on the left.
2. Select clothing, browse to an external `.glb`, then choose **Import
   source**. The GLB is copied unchanged.
3. Adjust explicit whole-garment, torso, sleeve-room and cuff controls.
   **Align To T-pose** centers both cuffs on measured rest-pose landmarks;
   **Auto Clear Body** increases only the sleeve envelope until the live
   clearance check passes.
4. Select the body regions actually covered by the clothing. Hands remain
   visible unless deliberately checked. Coverage changes hide/show the body
   regions immediately. **Live Preview Hidden Regions** can be turned off
   temporarily when the complete body needs inspection.
   Collared tops should cover both clavicle regions. The mannequin's lower
   collar band is classified as clavicle while its upper neck remains visible,
   preventing pale wedges without making the head float.
5. Choose **Save Draft Fit** to persist only the editable fit/config.
6. Choose **Copy Body Weights + Bind Existing Skeleton**. Blender imports the
   canonical mannequin and raw garment together in Rest/T-pose, makes the
   sleeve shells bilateral, applies a feature-masked limited Shrinkwrap only
   to unsafe body-clearance vertices, copies `PlayerMaleBody` weights by
   nearest-face interpolation, relaxes only the transferred shoulder,
   armpit, and elbow weights, cleans/limits/normalizes them, binds only
   `GameExportRig`, and exports without animation to a staged Final Output.
7. Switch between **Raw Fit** and **Final Output**. Final Output is the exact
   generated GLB, loaded through Godot's runtime glTF loader—not a visual
   approximation. Inspect the generated `.blend` with **Open Final Review in
   Blender** when deeper weight inspection is needed.
8. While viewing Final Output, explicitly check the acceptance box and choose
   **Accept Final Output + Save for In-game**. Any fit or coverage edit makes
   the generated output stale and requires a fresh bind/review.

## Viewport navigation

- Hold the middle mouse button over the preview and drag in any direction to
  orbit around the character. The cursor is captured until the button is
  released, so long rotations do not stop at the edge of the window. The
  gesture uses an inverted, low-sensitivity modeling-style orbit.
- Use the mouse wheel or the `−` / `+` buttons to zoom.
- `+X`, `-X`, `+Y`, `-Y`, `+Z`, and `-Z` snap to exact right, left, top,
  bottom, front, and back axis views. `3Q` restores the three-quarter view.
- The right stick provides the same two-axis orbit for controller users.

## Numeric editing and history

- Every numeric field has a `↔` handle. Drag it left/right for continuous
  adjustment; hold Shift for fine control or Ctrl for coarse control.
- The `↶` button beside a field restores that one value to its last
  loaded/saved baseline without touching the other fit settings.
- **Undo** / Ctrl+Z and **Redo** / Ctrl+Y (also Ctrl+Shift+Z) cover typed
  values, drag gestures, presets, auto-fit actions, and coverage edits.
  One continuous handle drag is stored as one undo operation.
- Undo and Redo are also focusable buttons, and the shared controller
  undo/redo actions remain available.

The processor never smooths, decimates, welds, or changes the source normals,
UVs, or materials. It adds zero-smoothing support edges only inside the
shoulder/armpit/elbow/cuff deformation zones; this is the intentional
topology difference clearly disclosed by Final Output review. Finger
influences sampled at cuffs are collapsed to the matching hand bone, cuff
openings receive a forearm-to-hand transition, and lower-body influences
sampled at a jacket hem are collapsed to hips.

Each build emits a JSON report, an inspectable Blender file, and T-pose,
idle, walk, bent-elbow, raised-arm and gameplay-camera captures under
`art_source/characters/review/`.
