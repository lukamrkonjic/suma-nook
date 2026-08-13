"""Remove the flat ground disc image generators bake underneath a model.

Run inside Blender:

    blender --background --factory-startup --python tools/strip_ground_disc.py -- \
        --source tent.glb --output tent_clean.glb

A model generated from a reference image often arrives standing on a disc of
"ground" that was part of the picture. In Suma the world already provides the
ground, so the disc reads as a large flat plate under the object -- and it
dominates the model's footprint, which then throws off the import scale.

The disc is identified by shape rather than by a fixed size: a connected
component that is flat, sits at the base, and reaches well beyond the radius of
everything that is not flat-and-at-the-base. On tent.glb the tent's components
reach radius 0.176 while the disc and its rim shards all sit at 0.513-0.514,
so the two groups are never close to each other.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import bmesh
import bpy

# A component counts as flat if its vertical extent is under this share of the
# model's height, and as sitting at the base if it starts within this share of
# the bottom. Measured on tent.glb the disc pieces run 1.1-2.1% extent at
# 0.0-1.4% off the base, so 5% is loose without being close to the tent.
DISC_FLATNESS = 0.05
DISC_BASE_OFFSET = 0.05
# How far past the body's radius a flat base component must reach to be ground
# rather than part of the object. The gap on tent.glb is 0.176 against 0.513.
DISC_RADIUS_FACTOR = 1.3


def parse_args() -> argparse.Namespace:
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--flatness", type=float, default=DISC_FLATNESS)
    parser.add_argument("--base-offset", type=float, default=DISC_BASE_OFFSET)
    parser.add_argument("--radius-factor", type=float, default=DISC_RADIUS_FACTOR)
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Report what would be removed without writing the output.",
    )
    return parser.parse_args(argv)


def face_components(mesh: bmesh.types.BMesh) -> list[list[bmesh.types.BMFace]]:
    seen: set[int] = set()
    components: list[list[bmesh.types.BMFace]] = []
    for face in mesh.faces:
        if face.index in seen:
            continue
        stack = [face]
        seen.add(face.index)
        component: list[bmesh.types.BMFace] = []
        while stack:
            current = stack.pop()
            component.append(current)
            for edge in current.edges:
                for neighbour in edge.link_faces:
                    if neighbour.index not in seen:
                        seen.add(neighbour.index)
                        stack.append(neighbour)
        components.append(component)
    return components


def component_shape(component, base_z: float, height: float) -> dict:
    zs = [vertex.co.z for face in component for vertex in face.verts]
    radii = [
        math.hypot(vertex.co.x, vertex.co.y)
        for face in component
        for vertex in face.verts
    ]
    return {
        "faces": len(component),
        "extent": (max(zs) - min(zs)) / height,
        "base_offset": (min(zs) - base_z) / height,
        "max_radius": max(radii),
        "area": sum(face.calc_area() for face in component),
    }


def main() -> None:
    arguments = parse_args()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(arguments.source))
    mesh_object = next(
        o for o in bpy.context.scene.objects if o.type == "MESH"
    )
    mesh = mesh_object.data
    zs = [vertex.co.z for vertex in mesh.vertices]
    base_z, top_z = min(zs), max(zs)
    height = max(1.0e-9, top_z - base_z)

    working = bmesh.new()
    working.from_mesh(mesh)
    working.faces.ensure_lookup_table()
    components = face_components(working)
    shapes = [component_shape(c, base_z, height) for c in components]

    flat_at_base = [
        index
        for index, shape in enumerate(shapes)
        if shape["extent"] < arguments.flatness
        and shape["base_offset"] < arguments.base_offset
    ]
    body_radius = max(
        [
            shape["max_radius"]
            for index, shape in enumerate(shapes)
            if index not in flat_at_base
        ]
        or [0.0]
    )
    threshold = body_radius * arguments.radius_factor
    doomed = [
        index
        for index in flat_at_base
        if shapes[index]["max_radius"] > threshold
    ]

    removed_faces = sum(shapes[index]["faces"] for index in doomed)
    removed_area = sum(shapes[index]["area"] for index in doomed)
    print(
        f"components={len(components)} flat_at_base={len(flat_at_base)} "
        f"body_radius={body_radius:.3f} threshold={threshold:.3f}"
    )
    print(
        f"removing {len(doomed)} components, {removed_faces} faces, "
        f"{removed_area:.4f} area"
    )
    if not doomed:
        print("nothing matched; the model has no ground disc by these measures")

    if arguments.dry_run:
        working.free()
        return

    condemned = [face for index in doomed for face in components[index]]
    bmesh.ops.delete(working, geom=condemned, context="FACES")
    working.to_mesh(mesh)
    working.free()
    mesh.update()

    remaining_zs = [vertex.co.z for vertex in mesh.vertices]
    remaining_radii = [
        math.hypot(vertex.co.x, vertex.co.y) for vertex in mesh.vertices
    ]
    print(
        f"remaining: {len(mesh.polygons)} faces, "
        f"height {max(remaining_zs) - min(remaining_zs):.4f}, "
        f"radius {max(remaining_radii):.4f}"
    )

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    mesh_object.select_set(True)
    bpy.context.view_layer.objects.active = mesh_object
    bpy.ops.export_scene.gltf(
        filepath=str(arguments.output),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
    )
    print(f"wrote {arguments.output}")


if __name__ == "__main__":
    main()
