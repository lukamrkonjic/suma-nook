"""Convert the extracted GG Plain Ground mesh to Suma's tile footprint.

Run:
  blender --background --python art_source/blender/process_gg_plain_ground.py
"""

from __future__ import annotations

from pathlib import Path

import bpy


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source/imported/garden_galaxy/plain_ground/Ground_base.obj"
OUTPUT = ROOT / "assets/3d/reworked/tile_plain_ground.glb"
AUTHORED_FOOTPRINT = 1.70


def load_obj_geometry(path: Path):
    vertices = []
    faces = []
    for raw_line in path.read_text(encoding="utf-8").splitlines():
        fields = raw_line.split()
        if not fields:
            continue
        if fields[0] == "v":
            unity_x, unity_y, unity_z = map(float, fields[1:4])
            # Unity is Y-up/left-handed; Blender is Z-up/right-handed.
            vertices.append(
                (
                    unity_x * AUTHORED_FOOTPRINT,
                    -unity_z * AUTHORED_FOOTPRINT,
                    unity_y,
                )
            )
        elif fields[0] == "f":
            faces.append(
                tuple(int(field.split("/")[0]) - 1 for field in fields[1:])
            )
    return vertices, faces


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    vertices, faces = load_obj_geometry(SOURCE)
    mesh = bpy.data.meshes.new("plain_ground_body_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    for polygon in mesh.polygons:
        polygon.use_smooth = False

    block = bpy.data.objects.new("plain_ground_body", mesh)
    bpy.context.scene.collection.objects.link(block)
    material = bpy.data.materials.new("plain_ground_gg")
    material.diffuse_color = (0.90900004, 0.90475237, 0.87077105, 1.0)
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = material.diffuse_color
    principled.inputs["Metallic"].default_value = 0.0
    principled.inputs["Roughness"].default_value = 1.0
    mesh.materials.append(material)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        export_yup=True,
        export_apply=False,
        export_materials="EXPORT",
    )
    print(f"Exported {OUTPUT}")


if __name__ == "__main__":
    main()
