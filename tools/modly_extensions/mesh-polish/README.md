# Mesh Polish

Mesh Polish is a Modly mesh-to-mesh process extension. It repairs the supplied
surface, temporarily separates disconnected components, performs conservative
PyMeshLab isotropic remeshing and Taubin smoothing on each component, validates
the result against the source, and exports a GLB in the original scene space.

It does not substitute components, infer new shapes, fuse nearby pieces, fill
large openings, or change the source scene hierarchy.

## Workflow

`Generate Mesh -> Repair -> Mesh Polish -> Optimize Mesh -> Texture Mesh -> Export`

## Presets

- **Soft Polish**: 2% target edges, 0.75% remesh distance, 4 Taubin passes.
- **Standard Polish**: 2% target edges, 1% remesh distance, 6 Taubin passes.
- **Strong Polish**: 1.5% target edges, 1.5% remesh distance, 10 Taubin passes.
- **Normals Only**: repair and smooth normals, with no vertex movement.
- **Preserve Hard Surface**: 35-degree remesh features, 2 Taubin passes,
  and 45-degree normal splitting.

Named presets use their tested values. Select **Custom Parameters** in Modly to
use the individual node controls.

## Safety behavior

Every component is restored to its exact source vertex centroid. Mesh Polish
then checks component count, finite coordinates, boundary growth, dimensions,
whole-scene bounds, and symmetric closest-surface displacement. If requested
smoothing is too strong, the extension retries with fewer Taubin passes. If a
safe processed result cannot be found, that component falls back to its
repaired source surface.

The emitted process report includes triangle counts, connected-component
count, maximum surface displacement, bounds change, processing time, effective
smoothing passes, and any safety fallbacks.
