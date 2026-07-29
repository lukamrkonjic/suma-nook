#!/usr/bin/env python3
"""Build the shared structural and flat-surface tile layers.

These assets are deliberately incomplete pieces. Runtime tile definitions
assemble one base, one surface, and any optional detail/edge layers into a
single logical tile. The shared measurements come from tile_profiles.py:

* authored footprint: 1.70 x 1.70 m;
* structural depth: y -0.50 to -0.055 after Godot's Y-up conversion;
* flat surface skin: y -0.055 to 0.0;
* deep constructed base: y -0.50 to -0.20 for surfaces whose readable
  joints, gaps, or material thickness occupy y -0.20 to 0.0;
* exact boundary contact, with no inter-tile bevel groove.

Run from the repository root:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/build_tile_core_layers.py
"""

from __future__ import annotations

import sys
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "3d" / "reworked"
SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import tile_profiles

PALETTE = {
    "earth_mid": "955F3B",
    "grass_primary": "8DA84A",
}


def srgb(hex_value: str) -> tuple[float, float, float, float]:
    values = [int(hex_value[index:index + 2], 16) / 255.0 for index in (0, 2, 4)]
    linear = [
        value / 12.92
        if value <= 0.04045
        else ((value + 0.055) / 1.055) ** 2.4
        for value in values
    ]
    return (*linear, 1.0)


def material(name: str) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    result = bpy.data.materials.new(name=name)
    result.use_nodes = True
    shader = result.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = srgb(PALETTE[name])
    shader.inputs["Roughness"].default_value = 0.8
    shader.inputs["Metallic"].default_value = 0.0
    return result


def export_one(asset_id: str, obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    output = OUT / f"{asset_id}.glb"
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_texcoords=True,
        export_normals=True,
        export_materials="EXPORT",
        export_animations=False,
        export_skins=False,
        export_lights=False,
        export_cameras=False,
    )
    print(f"[tile-layer] {output.relative_to(ROOT)}")
    bpy.data.objects.remove(obj, do_unlink=True)


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    base, surface = tile_profiles.build_shell(
        "tile_layer_standard",
        "grass_primary",
        "earth_mid",
        "micro_bevel_square",
        material,
    )
    base.name = "tile_layer_base_standard_body"
    base.data.name = "tile_layer_base_standard_body_mesh"
    surface.name = "tile_layer_surface_flat_cap"
    surface.data.name = "tile_layer_surface_flat_cap_mesh"
    export_one("tile_layer_base_standard", base)
    export_one("tile_layer_surface_flat", surface)

    deep_base, unused_deep_surface = tile_profiles.build_shell(
        "tile_layer_deep_recess",
        "grass_primary",
        "earth_mid",
        "deep_recess_constructed",
        material,
    )
    deep_base.name = "tile_layer_base_deep_recess_body"
    deep_base.data.name = "tile_layer_base_deep_recess_body_mesh"
    export_one("tile_layer_base_deep_recess", deep_base)
    bpy.data.objects.remove(unused_deep_surface, do_unlink=True)


if __name__ == "__main__":
    main()
