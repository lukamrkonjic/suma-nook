#!/usr/bin/env python3
"""Render neutral-clay contact sheets from a user-supplied GLB reference folder.

This is an analysis utility only: it never copies reference geometry into the
project. Each mesh is normalized and rendered as a silhouette/proportion study.

Blender:
  blender --background --factory-startup --python render_reference_boards.py -- \
    <reference_mesh_dir> <output_dir>
"""

import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector


BOARDS = {
    "terrain": [
        "PavingSlab_half__sharedassets0__1202.glb",
        "PavingSlab_chip_R__sharedassets0__1757.glb",
        "Brick Floor top__sharedassets0__1605.glb",
        "Brick Floor step__sharedassets0__1469.glb",
        "Stone Paving block__sharedassets0__1318.glb",
        "Stone Paving step__sharedassets0__1485.glb",
        "ChipFloor_bit__sharedassets0__1814.glb",
        "Cobble corner bit__sharedassets0__1201.glb",
        "SteppingStone__sharedassets0__1484.glb",
        "Log Path__sharedassets0__1756.glb",
        "Pond_corner__sharedassets0__1593.glb",
        "Pond_straight__sharedassets0__1552.glb",
        "Bank_lawn__sharedassets0__1700.glb",
        "Bank_classic__sharedassets0__1228.glb",
        "Bank_water__sharedassets0__1787.glb",
    ],
    "vegetation": [
        "FirTree_foliage__sharedassets0__1709.glb",
        "FirTree_single__sharedassets0__1816.glb",
        "TallTree leaf ball__sharedassets0__1275.glb",
        "TallTree trunk single__sharedassets0__1785.glb",
        "Bush_ball_shape__sharedassets0__1609.glb",
        "Bush_ball_lvs__sharedassets0__1390.glb",
        "Bush_cone_shape__sharedassets0__1629.glb",
        "Bush_cone_lvs__sharedassets0__1508.glb",
        "BerryBush__sharedassets0__1347.glb",
        "Blossom_flowers__sharedassets0__1839.glb",
        "Roses_flowers__sharedassets0__1291.glb",
        "Sunflower__sharedassets0__1687.glb",
        "Mushroom__sharedassets0__1833.glb",
        "FlyMushroom__sharedassets0__1237.glb",
        "DryGrass_leaf__sharedassets0__1565.glb",
    ],
    "props": [
        "Stool__sharedassets0__1396.glb",
        "PlasticStool__sharedassets0__1243.glb",
        "Table_wood__sharedassets0__1199.glb",
        "Table_wood_legs__sharedassets0__1301.glb",
        "Classic Pot__sharedassets0__1489.glb",
        "CutePot__sharedassets0__1903.glb",
        "MetalLantern__sharedassets0__1362.glb",
        "Sign__sharedassets0__1454.glb",
        "WoodFence_piece__sharedassets0__1636.glb",
        "WoodFence_post__sharedassets0__1607.glb",
        "StorageBox_box__sharedassets0__1381.glb",
        "Stump_solid__sharedassets0__1880.glb",
        "DryLog__sharedassets0__1729.glb",
        "Bird Bath__sharedassets0__1364.glb",
        "Bird Table__sharedassets0__1601.glb",
    ],
}


def material(name, color, roughness=0.86):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def world_bounds(objects):
    points = []
    for obj in objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not points:
        return Vector((-0.5, -0.5, -0.5)), Vector((0.5, 0.5, 0.5))
    return (
        Vector(tuple(min(p[i] for p in points) for i in range(3))),
        Vector(tuple(max(p[i] for p in points) for i in range(3))),
    )


def import_normalized(path, center, clay):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = [obj for obj in bpy.data.objects if obj not in before]
    meshes = [obj for obj in imported if obj.type == "MESH"]
    lo, hi = world_bounds(meshes)
    extent = hi - lo
    scale = 1.42 / max(max(extent), 0.001)
    source_center = (lo + hi) * 0.5
    target_center = Vector(center) + Vector((0, 0, extent.z * scale * 0.5))
    normalization = (
        Matrix.Translation(target_center)
        @ Matrix.Scale(scale, 4)
        @ Matrix.Translation(-source_center)
    )
    roots = [obj for obj in imported if obj.parent not in imported]
    for root in roots:
        root.matrix_world = normalization @ root.matrix_world
    for obj in meshes:
        obj.data.materials.clear()
        obj.data.materials.append(clay)
    return imported


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def render_board(name, files, mesh_dir, output_dir):
    clear_scene()
    clay = material("reference_clay", (0.68, 0.46, 0.33))
    floor_mat = material("floor", (0.88, 0.86, 0.79), 0.95)
    missing = []
    cols = 5
    spacing = 2.15
    for index, filename in enumerate(files):
        path = mesh_dir / filename
        if not path.exists():
            missing.append(filename)
            continue
        row, col = divmod(index, cols)
        x = (col - (cols - 1) * 0.5) * spacing
        y = ((len(files) - 1) // cols * 0.5 - row) * spacing
        import_normalized(path, (x, y, 0.0), clay)

    bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, -0.025))
    floor = bpy.context.object
    floor.data.materials.append(floor_mat)

    bpy.ops.object.light_add(type="AREA", location=(-5.5, -6.0, 10.0))
    key = bpy.context.object
    key.data.energy = 1150
    key.data.shape = "DISK"
    key.data.size = 7.5
    look_at(key, (0, 0, 0))
    bpy.ops.object.light_add(type="AREA", location=(7.0, 3.5, 7.0))
    fill = bpy.context.object
    fill.data.energy = 500
    fill.data.size = 6.0
    look_at(fill, (0, 0, 0))

    bpy.ops.object.camera_add(location=(10.5, -15.0, 13.0))
    camera = bpy.context.object
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 12.3
    look_at(camera, (0, 0, 0.35))
    bpy.context.scene.camera = camera

    world = bpy.context.scene.world
    world.color = (0.82, 0.81, 0.76)
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.82, 0.81, 0.76, 1)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.8

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 1800
    scene.render.resolution_y = 1120
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.render.filepath = str(output_dir / f"gg_reference_{name}.png")
    scene.view_settings.look = "AgX - Medium High Contrast"
    scene.render.image_settings.color_mode = "RGBA"
    bpy.ops.render.render(write_still=True)
    print(f"[reference-board] {scene.render.filepath}")
    if missing:
        print("[missing] " + ", ".join(missing))


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) != 2:
        raise SystemExit("usage: render_reference_boards.py <reference_mesh_dir> <output_dir>")
    mesh_dir = Path(argv[0])
    output_dir = Path(argv[1])
    output_dir.mkdir(parents=True, exist_ok=True)
    for name, files in BOARDS.items():
        render_board(name, files, mesh_dir, output_dir)


if __name__ == "__main__":
    main()
