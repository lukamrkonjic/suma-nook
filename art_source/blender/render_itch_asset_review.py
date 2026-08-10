#!/usr/bin/env python3
"""Render palette-preserving review boards for the generated itch catalog."""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


ROOT = Path(__file__).resolve().parents[2]
IMPORT_ROOT = ROOT / "art_source" / "imported" / "itch_free_packs"
REPORT = IMPORT_ROOT / "generation_report.json"
OUTPUT = IMPORT_ROOT / "review"
COLS = 6
ROWS = 4
SLOTS = COLS * ROWS
SPACING_X = 2.25
SPACING_Y = 2.2


def material(name: str, color: tuple[float, float, float], roughness: float = 0.9):
    result = bpy.data.materials.new(name)
    result.use_nodes = True
    result.diffuse_color = (*color, 1.0)
    shader = result.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Roughness"].default_value = roughness
    return result


def look_at(obj, target: Vector) -> None:
    obj.rotation_euler = (target - obj.location).to_track_quat("-Z", "Y").to_euler()


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes, bpy.data.curves, bpy.data.materials,
        bpy.data.cameras, bpy.data.lights,
    ):
        for item in list(collection):
            if item.users == 0:
                collection.remove(item)


def bounds(objects):
    points = []
    for obj in objects:
        if obj.type == "MESH":
            points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    return (
        Vector(tuple(min(point[index] for point in points) for index in range(3))),
        Vector(tuple(max(point[index] for point in points) for index in range(3))),
    )


def import_for_slot(path: Path, center: Vector):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = [obj for obj in bpy.data.objects if obj not in before]
    lo, hi = bounds(imported)
    size = hi - lo
    visual_scale = min(1.22 / max(size.x, size.y, 0.001), 1.48 / max(size.z, 0.001))
    source_center = Vector(((lo.x + hi.x) * 0.5, (lo.y + hi.y) * 0.5, lo.z))
    transform = Matrix.Translation(center) @ Matrix.Scale(visual_scale, 4) @ Matrix.Translation(-source_center)
    imported_set = set(imported)
    for root in [obj for obj in imported if obj.parent not in imported_set]:
        root.matrix_world = transform @ root.matrix_world
    return imported


def choose(entries: list[dict]) -> list[dict]:
    if len(entries) <= SLOTS:
        return entries
    indices = [round(index * (len(entries) - 1) / (SLOTS - 1)) for index in range(SLOTS)]
    return [entries[index] for index in indices]


def setup_studio(pack_name: str, subtitle: str) -> None:
    floor_material = material("review_floor", (0.79, 0.77, 0.69))
    text_material = material("review_text", (0.14, 0.09, 0.065))
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.025))
    bpy.context.object.data.materials.append(floor_material)

    for content, location, size in (
        (pack_name, (-6.6, 5.15, 0.02), 0.42),
        (subtitle, (-6.6, 4.68, 0.02), 0.22),
    ):
        bpy.ops.object.text_add(location=location)
        label = bpy.context.object
        label.data.body = content
        label.data.align_x = "LEFT"
        label.data.size = size
        label.data.extrude = 0.004
        label.data.materials.append(text_material)

    bpy.ops.object.light_add(type="AREA", location=(-6.5, -7.5, 12.5))
    key = bpy.context.object
    key.data.energy = 1350
    key.data.shape = "DISK"
    key.data.size = 8.5
    look_at(key, Vector((0, 0, 0)))

    bpy.ops.object.light_add(type="AREA", location=(7.5, 4.0, 8.0))
    fill = bpy.context.object
    fill.data.energy = 650
    fill.data.size = 7.0
    look_at(fill, Vector((0, 0, 0)))

    bpy.ops.object.camera_add(location=(11.5, -16.5, 15.0))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 13.6
    look_at(camera, Vector((0, 0, 0.2)))
    bpy.context.scene.camera = camera

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.79, 0.78, 0.72, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.75


def render_pack(pack: dict, entries: list[dict]) -> None:
    clear_scene()
    selection = choose(entries)
    for index, entry in enumerate(selection):
        row, col = divmod(index, COLS)
        x = (col - (COLS - 1) * 0.5) * SPACING_X
        y = ((ROWS - 1) * 0.5 - row) * SPACING_Y - 0.25
        import_for_slot(ROOT / entry["output"], Vector((x, y, 0)))
    setup_studio(
        pack["name"],
        f"{len(entries)} palette-ported models • showing {len(selection)}",
    )
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 1120
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(OUTPUT / f"{pack['id']}.png")
    scene.view_settings.look = "AgX - Medium High Contrast"
    bpy.ops.render.render(write_still=True)
    print(f"[review] {scene.render.filepath}")


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    report = json.loads(REPORT.read_text(encoding="utf-8"))
    for pack in report["packs"]:
        entries = [entry for entry in report["assets"] if entry["pack_id"] == pack["id"]]
        render_pack(pack, entries)
    print(f"ITCH REVIEW COMPLETE boards={len(report['packs'])}")


if __name__ == "__main__":
    main()
