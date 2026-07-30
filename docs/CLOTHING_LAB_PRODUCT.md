# Clothing Lab — Product Direction

## Product thesis

Clothing Lab can become a standalone commercial humanoid garment fitting and
binding application for Godot and Unity projects.

The product should not initially promise support for every possible character
or renderer. Its first reliable contract should be:

- Standard humanoid characters.
- Rest/T-pose and A-pose source handling.
- GLB and FBX character and garment inputs.
- Tops, bottoms, shoes, gloves, headwear, rigid accessories, and skinned
  clothing.
- Godot 4 and current Unity humanoid projects.
- Deterministic fitting, body-weight transfer, animation validation, and
  engine-ready export.

Suma Nook remains the first production integration and quality benchmark.

## Existing product strengths

The current Clothing Lab already demonstrates the core workflow:

- Full character and garment preview.
- Editable, persistent full-body rig landmarks.
- Rest-pose-safe fitting controls.
- Body-region coverage selection.
- Same-skeleton weight transfer and binding.
- Animation and pose previews.
- Undo, redo, numeric dragging, and axis-constrained editing.
- Advisory diagnostics with artist authority.
- Separate draft, build, review, and publish stages.
- Deterministic Blender processing with review artifacts.

## Proposed architecture

### Engine-neutral desktop application

The main application owns:

- Character/body profiles.
- Humanoid bone mapping.
- Garment transforms and fitting metadata.
- Coverage and underlayer regions.
- Weight transfer and deformation validation.
- Neutral GLB/FBX export.
- A versioned JSON garment manifest.

No Godot `res://` paths, Unity asset GUIDs, or Suma-specific mesh names should
exist in this layer.

### Godot adapter

A small editor plugin should:

- Import the neutral garment package.
- Connect skinned meshes to the intended `Skeleton3D`.
- Create character-part resources.
- Configure body coverage/underlayer masks.
- Validate bone names and rest transforms.

### Unity adapter

A Unity Package Manager package should:

- Import the same neutral package.
- Configure `SkinnedMeshRenderer` and humanoid bone mappings.
- Create prefabs and materials.
- Configure body coverage/underlayer masks.
- Validate Avatar and bind-pose compatibility.

## Neutral garment package

Each exported garment should contain:

- Fitted and skinned mesh.
- Skeleton contract identifier and bone map.
- Rest-pose metadata.
- Slot and layering category.
- Hidden body regions.
- Cloth-underlayer regions and material choice.
- Material and palette metadata.
- Attachment sockets where applicable.
- Validation report and preview thumbnails.

## Implemented no-hole underlayer system

Hiding covered skin must never create a visible empty cavity when a character
walks, bends, or raises an arm. A hidden body region is not equivalent to
empty space: clothing or an undershirt should still occupy that volume.

Suma Nook now uses a generated **skinned cloth underlayer** for every skinned
garment that declares hidden body regions:

1. Use the artist-selected hidden body regions as the starting coverage map.
2. Duplicate only the necessary body triangles into a lightweight
   `ClothingUnderlayer` mesh.
3. Preserve the body's existing bone weights and bind it to the same
   skeleton.
4. Transfer UVs from the nearest vertices on the fitted garment's dominant
   material surface. This preserves the garment's actual texture instead of
   sampling it with unrelated body UVs.
5. Reuse that exact garment material and all later palette/tint styling.
6. Inset the underlayer slightly beneath the outer garment to prevent
   clipping and z-fighting.
7. Give outer garments a shallower inset than inner layers so overlapping
   animated clothing remains deterministic.
8. Validate the result in rest pose, idle, walk, bent-elbow, raised-arm, and
   gameplay-camera views.

This adds no bones, cloth simulation, or physics. It reuses existing body
weights and only a small subset of body geometry. Generation happens once
when an appearance is assembled; runtime animation has only the cost of a
small additional skinned mesh and no per-frame CPU work.

The same generator runs in Clothing Lab, so hidden-region choices can be
reviewed with the editable garment and the bound Final Output before
publishing. Garment visibility also controls its underlayer.

Future per-garment authoring modes:

- `AUTO_CLOTH_UNDERLAYER` — the currently implemented safe default, matching
  the garment's dominant material surface.
- `BASE_LAYER_MATERIAL` — visible shirt/lining beneath an outer garment.
- `MATCH_GARMENT_MATERIAL` — seamless interior matching the garment.
- `OPEN` — explicit artist choice for genuinely open or bare regions.

The automated result must remain editable: artists choose coverage regions and
may override the material or disable underfill for intentional openings.

## Generalization work

The Suma-specific implementation must be replaced by:

- Automatic skeleton discovery plus a manual bone-mapping fallback.
- Configurable coordinate systems, scales, and rest poses.
- A body-region painter/generator rather than predefined mesh-region IDs.
- Material adapters instead of a single body shader.
- Per-project character profiles and garment libraries.
- Configurable Blender discovery instead of a hard-coded executable path.
- Engine adapters that consume the same versioned output schema.
- Batch processing and compatibility reports for studios.

## Commercial shape

Possible packaging:

- Free evaluation edition.
- Indie perpetual license.
- Studio per-seat license.
- Optional team, batch-processing, and source-control features.
- Godot and Unity adapters included or sold as supported integrations.

Godot's MIT license permits commercial distribution with attribution. Blender
is GPL software; the safest first release should use a separately installed
Blender worker and include a deliberate licensing review before considering a
bundled Blender runtime.

## Product principle

Automation should remove repetitive technical work without overruling visual
judgment. Diagnostics remain advisory whenever an artist can see that the
result is correct; only missing inputs or outputs should stop an operation.
