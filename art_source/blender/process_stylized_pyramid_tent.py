"""Prepare the authored pyramid tent for Suma Nook.

The source GLB is retained under ``art_source/imported``. This focused script
normalizes it to the one-tile placement envelope, replaces its four authored
material families with Suma Nook semantic palette materials, and exports the
stable production asset ``prop_shelter.glb``.

Run with Blender 5.x:

    blender --background --factory-startup \
        --python art_source/blender/process_stylized_pyramid_tent.py
"""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT
    / "art_source"
    / "imported"
    / "stylized_pyramid_tent"
    / "stylized_pyramid_tent_source.glb"
)
OUTPUT = ROOT / "assets" / "3d" / "reworked" / "prop_shelter.glb"
EXPECTED_SOURCE_SHA256 = "bec3d941c56f8c82fef0de32e6570f6a8e11784aad219e2d0c5f6afee6cf7589"

# The gameplay tile is 1.70 m square. A 1.50 m visual footprint leaves a
# deliberate 10 cm inset on every edge, including the model's corner pegs.
TARGET_FOOTPRINT_METERS = 1.50

PALETTE = {
    "cream_fabric": "DDD0B6",
    "brown_fabric": "845739",
    "earthy_olive": "6B6F2F",
    "wood_light": "C99849",
}

MATERIAL_MAPPING = {
    "Warm Canvas": "cream_fabric",
    "Shaded Door Canvas": "brown_fabric",
    "Olive Painted Trim": "earthy_olive",
    "Warm Amber Wood": "wood_light",
}


def srgb(hex_value: str) -> tuple[float, float, float, float]:
    values = [int(hex_value[index : index + 2], 16) / 255.0 for index in (0, 2, 4)]
    linear = [
        value / 12.92
        if value <= 0.04045
        else ((value + 0.055) / 1.055) ** 2.4
        for value in values
    ]
    return (*linear, 1.0)


def semantic_material(name: str) -> bpy.types.Material:
    material = bpy.data.materials.new(name=name)
    material.use_nodes = True
    nodes = material.node_tree.nodes
    nodes.clear()
    output = nodes.new("ShaderNodeOutputMaterial")
    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.inputs["Base Color"].default_value = srgb(PALETTE[name])
    shader.inputs["Roughness"].default_value = 0.78
    shader.inputs["Metallic"].default_value = 0.0
    shader.inputs["IOR"].default_value = 1.45
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def world_bounds(meshes: list[bpy.types.Object]) -> tuple[Vector, Vector]:
    points = [
        mesh.matrix_world @ Vector(corner)
        for mesh in meshes
        for corner in mesh.bound_box
    ]
    if not points:
        raise RuntimeError("The supplied tent contains no mesh geometry")
    lower = Vector(tuple(min(point[axis] for point in points) for axis in range(3)))
    upper = Vector(tuple(max(point[axis] for point in points) for axis in range(3)))
    return lower, upper


def triangle_count(meshes: list[bpy.types.Object]) -> int:
    return sum(
        len(polygon.vertices) - 2
        for mesh in meshes
        for polygon in mesh.data.polygons
    )


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing tent source: {SOURCE}")
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(
            "Tent source changed unexpectedly: "
            f"wanted {EXPECTED_SOURCE_SHA256}, found {source_hash}"
        )

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))

    imported = list(bpy.context.scene.objects)
    meshes = [obj for obj in imported if obj.type == "MESH"]
    lower, upper = world_bounds(meshes)
    size = upper - lower
    footprint = max(size.x, size.y)
    scale = TARGET_FOOTPRINT_METERS / footprint
    center = (lower + upper) * 0.5
    normalization = (
        Matrix.Translation(
            Vector((-center.x * scale, -center.y * scale, -lower.z * scale))
        )
        @ Matrix.Scale(scale, 4)
    )

    root = bpy.data.objects.new("prop_shelter", None)
    bpy.context.scene.collection.objects.link(root)
    for obj in [candidate for candidate in imported if candidate.parent is None]:
        original_world = obj.matrix_world.copy()
        obj.parent = root
        obj.matrix_world = normalization @ original_world

    palette_materials = {
        name: semantic_material(name)
        for name in PALETTE
    }
    assignments: dict[str, int] = {name: 0 for name in PALETTE}
    unknown_materials: set[str] = set()
    for mesh in meshes:
        for slot in mesh.material_slots:
            source_name = slot.material.name if slot.material else ""
            semantic_name = MATERIAL_MAPPING.get(source_name)
            if semantic_name is None:
                unknown_materials.add(source_name or "<none>")
                continue
            slot.material = palette_materials[semantic_name]
            assignments[semantic_name] += 1
    if unknown_materials:
        raise RuntimeError(
            "Unmapped tent materials: " + ", ".join(sorted(unknown_materials))
        )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for obj in imported:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_skins=False,
        export_lights=False,
        export_cameras=False,
    )

    output_lower, output_upper = world_bounds(meshes)
    print(
        "TENT_PROCESS_REPORT="
        + json.dumps(
            {
                "source": str(SOURCE.relative_to(ROOT)),
                "source_sha256": source_hash,
                "output": str(OUTPUT.relative_to(ROOT)),
                "scale_factor": scale,
                "bounds_meters": {
                    "minimum": list(output_lower),
                    "maximum": list(output_upper),
                    "size": list(output_upper - output_lower),
                },
                "mesh_count": len(meshes),
                "triangle_count": triangle_count(meshes),
                "material_assignments": assignments,
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
