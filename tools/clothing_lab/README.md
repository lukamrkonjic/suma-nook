# Clothing Lab

Launch the standalone fitting room:

```powershell
& "C:\Dev\Godot\Godot_v4.6.3-stable_win64.exe" `
  --path "C:\Dev\suma-nook" `
  "res://characters/lab/clothing_lab.tscn"
```

Fit calculations, rig markers, weight-copy, and binding are intentionally
locked to the canonical Rest/T-pose. Imported clothing is expected to use the
same pose. The **Pose / animation** dropdown can visually preview rest pose,
idle, walk, chopping, and fishing without changing any saved fitting data.
Choosing an animation automatically switches away from the static editable
mesh to **Bound / Animated Garment**, which follows the character's live
skeleton. The preview keeps the character grounded from the lowest animated
toe, and the **Animation speed** slider directly below the dropdown adjusts
preview playback from 0.10× to 2.00× without changing the source animation.

## Workflow

1. Select a body profile and the complete appearance on the left.
2. Select clothing, browse to an external `.glb`, then choose **Import
   source**. The GLB is copied unchanged.
3. Adjust explicit whole-garment, torso, sleeve-room and cuff controls.
   **Top section scale**, **Middle section scale**, and **Bottom section
   scale** reshape the garment's horizontal cross-section without changing
   its height. Values blend smoothly over normalized garment height rather
   than dividing the mesh into hard bands, so the control cannot introduce a
   horizontal crack or shading seam. Sleeved tops keep their dedicated sleeve
   length/room controls; section shaping applies to the torso shell. Vests,
   shirts without sleeves, trousers, and other non-sleeved garments apply it
   across their full height.
   **Surface smoothing** blends the garment's lighting normals in real time
   from the authored faceting toward smooth shading. It does not move a
   vertex or change the silhouette, fit, UVs, weights, or topology. The
   percentage is saved in the draft and baked as custom corner normals into
   the Final Output.
   **Surface detail eraser** is a non-destructive source-space brush for
   removing raised buttons, badges, studs, or similar modeled decorations.
   Enter the mode, then left-drag directly over the unwanted detail. The live
   preview relaxes the selected detail plus one local neighbor ring into fixed
   surrounding fabric and samples a nearby cloth UV, so the erased patch uses
   the same color/material without forming a recessed cap. Brush radius and
   smoothing strength are adjustable. New strokes lock to the small source
   components beneath the brush. Normal-direction relief removal is allowed,
   while sideways displacement is tightly capped so large garment panels are
   not reshaped and old button shading disappears.
   An entire drag is one undo step, and **Clear all erased details** restores
   the untouched imported source. Dabs are saved in the fit draft and baked
   before fitting and weight transfer. The reverse/inside shell is protected,
   no faces are deleted, and every build still has to pass the closed-manifold
   topology contract.
   **Align To T-pose** centers both cuffs on measured rest-pose landmarks;
   **Auto Clear Body** increases only the sleeve envelope until the live
   clearance check passes. If a body's markers do not sit at the visual joint
   centers, choose **Edit rig markers**, select a body section, and drag them
   into place. The global map covers crown/hat, head, face, neck, chest,
   abdomen, waist, pelvis, both complete arm chains, and both complete
   leg/foot chains. These reusable body-profile anchors do not move or pose
   the actual Skeleton3D.
4. Select the body regions actually covered by the clothing. Hands remain
   visible unless deliberately checked. Coverage changes hide/show the body
   regions immediately. **Live Preview Hidden Regions** can be turned off
   temporarily when the complete body needs inspection.
   For every skinned garment, these same regions also generate a lightweight
   cloth underlayer. It keeps the body's original skin weights, transfers UVs
   from the fitted garment, and reuses the garment's material. Animated sleeve,
   collar, and hem openings therefore reveal matching fabric rather than an
   empty hole. The layer is created once, follows the same live skeleton, and
   is shown in both Clothing Lab and the game.
   Collared tops should cover both clavicle regions. The mannequin's lower
   collar band is classified as clavicle while its upper neck remains visible,
   preventing pale wedges without making the head float.
5. Choose **1. Save Fit + Rig Draft** to persist only the editable fit,
   hidden-region choices, and reusable global body rig markers.
6. Choose **2. Build Final Output · Copy Weights + Bind**. Blender imports the
   canonical mannequin and raw garment together in Rest/T-pose, canonicalizes
   split seam vertices before anything can move them, matches bilateral sleeve
   vertices one-to-one, applies a feature-masked limited Shrinkwrap only
   to unsafe body-clearance vertices, copies `PlayerMaleBody` weights by
   nearest-face interpolation, relaxes only the transferred shoulder,
   armpit, and elbow weights, cleans/limits/normalizes them, binds only
   `GameExportRig`, synchronizes the weights of coincident UV/material seam
   vertices, merges only truly coincident geometric seam points while
   retaining per-corner UV/material data, triangulates deterministically, and
   exports without animation to a staged Final Output. Cuff weights transition
   smoothly instead of changing at a hard ring. A garment must resolve to a
   closed manifold shell: real neck, cuff, and hem openings need modeled
   thickness and an inner rim, not exposed single-surface boundary edges.
   After every geometry-changing stage, the processor compares boundary
   loops, connected components, wire/non-manifold edges, and Euler
   characteristic against the canonical source. The exact exported GLB is
   canonicalized and checked again. Any opened seam is therefore a hard build
   failure and can never be published. The build is also rejected if
   representative idle, walk, bent-elbow, or raised-arm poses open a seam,
   produce an explosively stretched edge, or leave a boundary T-junction.
7. Under **3. Preview**, switch between **Editable Raw Fit** and **Bound Final
   / Animated Garment**. The staged Final Output is preferred after a build;
   otherwise the currently published bound garment is used. It is loaded
   through Godot's runtime glTF loader—not a visual approximation. Use the
   pose/animation dropdown and speed slider to inspect deformation.
   **3. Open Final Review in Blender** and the review checkbox are helpful
   but optional.
8. Choose **4. Publish Final Output to Game**. Clicking Publish is the final
   confirmation. Any later fit or coverage edit makes the generated output
   stale and requires a fresh build.

Fit measurements—including cuff distance and approximate body clearance—are
always advisory. They appear under **ADVISORY ONLY — NEVER BLOCKING** and
never prevent saving, building, reviewing, or publishing. Manual fit judgment
and selected hidden body regions are authoritative. Only a missing source or
a missing/stale built output can make the requested operation technically
impossible; those are shown as **ACTION NEEDED**, not as fit failures.

## Viewport navigation

- Hold the middle mouse button over the preview and drag in any direction to
  orbit around the character. The cursor is captured until the button is
  released, so long rotations do not stop at the edge of the window. The
  gesture uses an inverted, low-sensitivity modeling-style orbit.
- Use the mouse wheel or the `−` / `+` buttons to zoom.
- `+X`, `-X`, `+Y`, `-Y`, `+Z`, and `-Z` snap to exact right, left, top,
  bottom, front, and back axis views. `3Q` restores the three-quarter view.
- The right stick provides the same two-axis orbit for controller users.
- **Show equipped clothing** temporarily hides only the selected garment,
  which makes it easy to inspect the body and rig markers without changing
  the saved equipment or fit.
- In **Edit rig markers** mode, left-drag a dot in the current camera plane,
  or choose a body section and active joint and use the X/Y/Z nudge buttons.
  Hold `X`, `Y`, or `Z` during a drag to constrain movement to that single
  character-space axis, just like a 3D modeling tool.
  Bilateral mirroring is enabled by default for matching arms and legs;
  centerline crown/head/spine/pelvis markers remain independent. All equipped
  clothing and body-region masks are temporarily hidden so the complete body
  remains visible. Leaving the mode restores the prior preview. **Reset
  markers to skeleton** restores the measured rest-pose bone anchors.

## Numeric editing and history

- **Lock XYZ scale proportions** is enabled by default. Editing any Scale
  axis multiplies all three axes by the same factor, preserving the imported
  garment's current proportions. Uncheck it for independent axis scaling.

- Every numeric field has a `↔` handle. Drag it left/right for continuous
  adjustment; hold Shift for fine control or Ctrl for coarse control.
- The `↶` button beside a field restores that one value to its last
  loaded/saved baseline without touching the other fit settings.
- **Undo** / Ctrl+Z and **Redo** / Ctrl+Y (also Ctrl+Shift+Z) cover typed
  values, drag gestures, presets, auto-fit actions, and coverage edits.
  One continuous handle drag is stored as one undo operation.
- Undo and Redo are also focusable buttons, and the shared controller
  undo/redo actions remain available.

The processor never smooths geometry, decimates, or changes UV/material
corner data. It canonicalizes coincident geometric seam points and adds
zero-displacement support edges only inside the
shoulder/armpit/elbow/cuff deformation zones; these intentional topology
changes are disclosed by Final Output review. The selected surface-smoothing
percentage affects only exported custom normals. Finger
influences sampled at cuffs are collapsed to the matching hand bone, cuff
openings receive a forearm-to-hand transition, and lower-body influences
sampled at a jacket hem are collapsed to hips.

Each build emits a JSON report, an inspectable Blender file, and T-pose,
idle, walk, bent-elbow, raised-arm and gameplay-camera captures under
`art_source/characters/review/`. The exact exported GLB is reimported and
audited again for its closed-manifold topology contract, discontinuous seam
weights, degenerate/sliver triangles, and boundary T-junctions before the
build is accepted. `audit_garment_boundaries.py` and
`audit_processing_stages.py` provide targeted source/stage diagnostics when a
third-party garment fails that contract.
