# Stylized Rounded Components

A CPU-only Modly mesh-to-mesh process extension for turning noisy AI-generated
assemblies into clean, stylized components before optimization and texturing.

The extension preserves the input coordinate system, origin, orientation, and
total bounds. It accepts GLB, GLTF, OBJ, PLY, and STL through `trimesh` and
always emits a validated GLB.

## Workflow

```text
Generate Mesh
→ Repair
→ Stylized Rounded Components
→ Optimize Mesh
→ Texture Mesh
→ Export Mesh
```

## Modes

- **Rounded Box Reconstruction** finds connected pieces, detects pronounced
  concave seams when an AI generator has fused touching pieces, estimates a
  PCA frame and robust 2nd–98th-percentile dimensions, and replaces every
  retained piece with an analytic rounded cuboid. The mesh has broad planar
  faces, tangent edge strips, spherical corner patches, and optional restrained
  top-corner asymmetry. It never copies rocky dents, spikes, or triangle noise.
- **Smooth Existing** handles every component separately, applies one
  conservative isotropic-remesh pass, then low-strength Taubin smoothing and
  volume restoration. Separate processing keeps neighboring gaps from
  collapsing.

## Presets

| Preset | Main settings |
| --- | --- |
| Soft Stone Wall | Rounded reconstruction, bevel `0.13`, 3 segments, asymmetry `0.025` |
| Smooth Generated Mesh | Conservative remesh, Taubin smoothing, silhouette preservation |
| Chunky Low Poly | Rounded reconstruction, bevel `0.08`, 2 segments, 12k face budget |

Choose **Custom Parameters** in the node to use every exposed control verbatim.
The three named presets intentionally lock their tested parameter sets.

## Modly installation

Use **Models → Install from local folder**, then select this directory. Modly
reads `manifest.json`, provisions the isolated `venv` through `setup.py`, and
lists **Stylized Rounded Components** as a normal mesh-input/mesh-output node.

The Python entry follows Modly's process protocol:

- stdin: one JSON line with `input`, `params`, `workspaceDir`, and `tempDir`;
- stdout: progress, log, done, or descriptive error JSON lines;
- cancellation: broken-pipe, SIGINT, SIGTERM, and SIGBREAK handling, with safe
  checks between component and export stages.

## Output report

The `done.result.stats` payload includes:

- raw, repaired, segmented, removed, and output component counts;
- input and output triangle counts;
- processing duration;
- input/output centers, extents, and center drift;
- output vertex and material-slot counts.

## Dependencies and license

The implementation is authored for Suma and uses NumPy, trimesh, and PyMeshLab.
PyMeshLab is GPL-3.0 software, so distributing the complete extension runtime
must comply with PyMeshLab's license.
