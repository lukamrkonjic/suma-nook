"""Prepare the imported wooden-planks model as the Suma Nook tile
``tile_wooden_planks``.

The source GLB (Luka's generated model) is retained under
``art_source/imported/wooden_planks``.  This focused script:

  1. welds and de-triangulates the generated mesh (merge-by-distance,
     tris-to-quads, limited dissolve) and smooths shading so no scanline
     triangles survive;
  2. drops the baked textures and quantises each plank to the nearest Suma
     wood palette tone by sampling the source base-colour texture — palette
     materials, zero texture files, MaterialLibrary rebinding keeps working;
  3. normalises the block to the tile contract: exactly TILE (1.70 m) square,
     exactly BLOCK_DEPTH (0.50 m) deep, walkable top at z = 0, mesh named
     ``planks_cap`` so the runtime classifier treats it as structural;
  4. exports ``assets/3d/reworked/tile_wooden_planks.glb``.

Run with Blender 5.x from the repository root:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/process_wooden_planks_tile.py
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "art_source" / "imported" / "wooden_planks" / "wooden_planks_source.glb"
OUTPUT = ROOT / "assets" / "3d" / "reworked" / "tile_wooden_planks.glb"
EXPECTED_SOURCE_SHA256 = "6157e17e003697ca41e56126b4a4887cd18f5ec6494aadf05420d8896f091f00"

TILE = 1.70
BLOCK_DEPTH = 0.50

MERGE_DISTANCE = 0.0008        # weld duplicate verts (source is ~1 m wide)
DISSOLVE_ANGLE_DEG = 6.0       # merge coplanar-ish triangles into plank faces
SMOOTH_ANGLE_DEG = 38.0        # soften plank edges, keep board seams crisp

# Suma wood ramp, darkest to lightest — sampled plank tones snap onto these.
# Mirrors assets/palettes/gg_material_palette.tres; keep in sync.
WOOD_RAMP = ["wood_warm_shadow", "wood_primary", "wood_gold", "wood_light"]
PALETTE = {
    "wood_warm_shadow": "875324",
    "wood_primary": "A76D2D",
    "wood_gold": "B98237",
    "wood_light": "C99849",
}


def srgb(hex_value: str) -> tuple[float, float, float, float]:
    values = [int(hex_value[index:index + 2], 16) / 255.0 for index in (0, 2, 4)]
    linear = [
        value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4
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
    material.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])
    return material


def base_color_image(material: bpy.types.Material) -> bpy.types.Image:
    """The image feeding the Principled BSDF's Base Color input."""
    for node in material.node_tree.nodes:
        if node.type != "BSDF_PRINCIPLED":
            continue
        for link in material.node_tree.links:
            if link.to_node == node and link.to_socket.name == "Base Color":
                source = link.from_node
                if source.type == "TEX_IMAGE" and source.image:
                    return source.image
    raise RuntimeError("No base-colour texture found on the source material")


def sample_luminance(image: bpy.types.Image, pixels: list[float], uv) -> float:
    width, height = image.size
    x = min(max(int(uv[0] % 1.0 * width), 0), width - 1)
    y = min(max(int(uv[1] % 1.0 * height), 0), height - 1)
    index = (y * width + x) * image.channels
    r, g, b = pixels[index], pixels[index + 1], pixels[index + 2]
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def mesh_islands(mesh: bpy.types.Mesh) -> list[int]:
    """Connected-component id per polygon (planks are separate shells in the
    generated model; one shell = one board = one palette tone)."""
    parent = list(range(len(mesh.polygons)))

    def find(a: int) -> int:
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    vert_owner: dict[int, int] = {}
    for poly in mesh.polygons:
        for vert in poly.vertices:
            if vert in vert_owner:
                ra, rb = find(vert_owner[vert]), find(poly.index)
                if ra != rb:
                    parent[rb] = ra
            else:
                vert_owner[vert] = poly.index
    return [find(index) for index in range(len(mesh.polygons))]


def main() -> None:
    if not SOURCE.is_file():
        raise FileNotFoundError(f"Missing planks source: {SOURCE}")
    source_hash = hashlib.sha256(SOURCE.read_bytes()).hexdigest()
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(
            "Planks source changed unexpectedly: "
            f"wanted {EXPECTED_SOURCE_SHA256}, found {source_hash}"
        )

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))

    meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
    if len(meshes) != 1:
        raise RuntimeError(f"Expected one mesh in the planks source, found {len(meshes)}")
    obj = meshes[0]
    obj.name = "planks_cap"
    source_triangles = sum(len(p.vertices) - 2 for p in obj.data.polygons)

    # ---- palette quantisation (sample BEFORE cleanup, per plank shell) ----
    image = base_color_image(obj.material_slots[0].material)
    pixels = list(image.pixels)
    islands = mesh_islands(obj.data)
    uv_layer = obj.data.uv_layers.active.data
    island_samples: dict[int, list[float]] = {}
    for poly in obj.data.polygons:
        u = v = 0.0
        for loop_index in poly.loop_indices:
            u += uv_layer[loop_index].uv[0]
            v += uv_layer[loop_index].uv[1]
        count = max(len(poly.loop_indices), 1)
        island_samples.setdefault(islands[poly.index], []).append(
            sample_luminance(image, pixels, (u / count, v / count)))

    island_tone: dict[int, int] = {}
    medians = []
    for island, values in island_samples.items():
        values.sort()
        medians.append((values[len(values) // 2], island))
    medians.sort()
    for rank, (_luminance, island) in enumerate(medians):
        island_tone[island] = min(
            int(rank * len(WOOD_RAMP) / max(len(medians), 1)), len(WOOD_RAMP) - 1)
    per_poly_tone = [island_tone[islands[p.index]] for p in obj.data.polygons]

    obj.data.materials.clear()
    for name in WOOD_RAMP:
        obj.data.materials.append(semantic_material(name))
    for poly in obj.data.polygons:
        poly.material_index = per_poly_tone[poly.index]

    # ---- cleanup: weld, de-triangulate, smooth ----
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=MERGE_DISTANCE)
    bpy.ops.mesh.tris_convert_to_quads(
        face_threshold=math.radians(DISSOLVE_ANGLE_DEG),
        shape_threshold=math.radians(DISSOLVE_ANGLE_DEG),
    )
    bpy.ops.mesh.dissolve_limited(
        angle_limit=math.radians(DISSOLVE_ANGLE_DEG),
        delimit={"MATERIAL"},
    )
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")
    try:
        bpy.ops.object.shade_auto_smooth(angle=math.radians(SMOOTH_ANGLE_DEG))
    except Exception:
        bpy.ops.object.shade_smooth()
    # Face-weighted normals flatten the shading across the big dissolved
    # faces — without this the plank sides show a soft diagonal gradient
    # where the old triangulation used to be.
    weighted = obj.modifiers.new("wnormal", "WEIGHTED_NORMAL")
    weighted.keep_sharp = True
    weighted.weight = 80

    # ---- normalise to the tile contract ----
    points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    lower = Vector(tuple(min(p[i] for p in points) for i in range(3)))
    upper = Vector(tuple(max(p[i] for p in points) for i in range(3)))
    size = upper - lower
    centre = (lower + upper) * 0.5
    scale = Matrix.Diagonal(Vector((TILE / size.x, TILE / size.y, BLOCK_DEPTH / size.z))).to_4x4()
    obj.matrix_world = (
        Matrix.Translation(Vector((0.0, 0.0, 0.0)))
        @ scale
        @ Matrix.Translation(Vector((-centre.x, -centre.y, -upper.z)))
        @ obj.matrix_world
    )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
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

    final_points = [obj.matrix_world @ Vector(corner) for corner in obj.bound_box]
    final_lower = [round(min(p[i] for p in final_points), 4) for i in range(3)]
    final_upper = [round(max(p[i] for p in final_points), 4) for i in range(3)]
    tone_counts = {name: 0 for name in WOOD_RAMP}
    for poly in obj.data.polygons:
        tone_counts[WOOD_RAMP[poly.material_index]] += 1
    print("PLANKS_PROCESS_REPORT=" + json.dumps({
        "source": str(SOURCE.relative_to(ROOT)),
        "source_sha256": source_hash,
        "output": str(OUTPUT.relative_to(ROOT)),
        "plank_shells": len(island_samples),
        "triangles_before": source_triangles,
        "faces_after": len(obj.data.polygons),
        "bounds_min": final_lower,
        "bounds_max": final_upper,
        "tone_faces": tone_counts,
    }, indent=2))


if __name__ == "__main__":
    main()
