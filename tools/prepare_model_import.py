"""Prepare generated GLBs for Suma without changing their silhouettes.

Usage (through Blender):
  blender --background --factory-startup --python tools/prepare_model_import.py -- \
    --source model.glb --output assets/3d/reworked/prop_model.glb --mode prop

Tree mode separates the texture-classified canopy from the trunk while keeping
the complete crown in one mesh. Suma's existing foliage controller can then
move the leaves without opening cracks between individual crown pieces. Normal
softening remains a non-destructive runtime asset profile, so this tool never
relaxes or subdivides authored geometry.
"""

from __future__ import annotations

import argparse
import colorsys
import json
import math
import sys
from collections import defaultdict, deque
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector
from mathutils.kdtree import KDTree


CANOPY_GREEN_RATIO_MIN = 0.60
CANOPY_CENTER_HEIGHT_FRACTION_MIN = 0.08
# Per-face trunk rescue, for trees that arrive as one welded shell.
#
# Measured on fir_tree.glb: trunk faces sample G/R 0.66-0.69 -- brown, but
# above CANOPY_GREEN_RATIO_MIN, so the trunk was filed under canopy. Colour
# alone is not enough to separate them, because the darkest foliage also
# reaches 0.66. Radius is what disambiguates: that trunk sits at 0.25-0.28 of
# the model's max radius while foliage at the same heights starts at 0.73.
TRUNK_GREEN_RATIO_MAX = 0.80
TRUNK_RADIUS_FRACTION_MAX = 0.35
# Gold is an accent -- a hinge, a latch, a rim. It is never most of an object.
#
# The per-component `face_count <= 32` guard on the gold rule assumes a gold
# fitting arrives as one small shell, which fails on a fragmented mesh: a
# bamboo table split into 64 components put 38 of them (443 faces, 47% of the
# model) over the gold threshold. Measured, those components share the hue of
# the wood ones almost exactly -- 0.094 against 0.097 -- and differ only in
# value, 0.80 against 0.70. The rule was separating the lit side of one
# material from its shaded side, not gold from wood. So cap gold by its share
# of the whole object and demote it when it is clearly the main surface.
GOLD_MAX_FACE_SHARE = 0.15
TEXTURE_SAMPLE_SIZE = 512
PALETTE_KEYS = (
    "pine_light",
    "pine_medium",
    "pine_shadow",
    "leaf_medium",
    "leaf_olive",
    "wood_light",
    "wood_primary",
    "wood_deep",
    "warm_white",
    "ivory_highlight",
    "warm_near_black",
    "gold_primary",
    "soft_sage_gray",
    "stone_light",
    "stone_mid",
    "stone_shadow",
    "terracotta_light",
    "terracotta_primary",
    "terracotta_shadow",
)


def load_reference_colors() -> dict[str, str]:
    palette_path = (
        Path(__file__).resolve().parents[1]
        / "data"
        / "garden_galaxy_reference_palette.json"
    )
    exact = json.loads(palette_path.read_text(encoding="utf-8"))["exact"]
    missing = [key for key in PALETTE_KEYS if key not in exact]
    if missing:
        raise RuntimeError(f"Reference palette is missing {missing}")
    return {key: exact[key].removeprefix("#") for key in PALETTE_KEYS}


GARDEN_GALAXY_COLORS = load_reference_colors()


def parse_args() -> argparse.Namespace:
    argv = sys.argv
    arguments = argv[argv.index("--") + 1 :] if "--" in argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--mode", choices=("prop", "tree"), required=True)
    parser.add_argument("--root-name", required=True)
    parser.add_argument("--report", type=Path)
    parser.add_argument(
        "--rotate-medium-cluster",
        type=float,
        default=0.0,
        help=(
            "Rotate the middle-sized grounded spatial cluster around its base "
            "by this many degrees. Intended for multi-form prop composition."
        ),
    )
    parser.add_argument(
        "--style-profile",
        choices=("none", "tree", "shrub", "wood_prop", "stone_prop", "generic"),
        default="none",
    )
    return parser.parse_args(arguments)


def clear_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)


def _upstream_image(node, visited=None):
    visited = visited or set()
    if node in visited:
        return None
    visited.add(node)
    if node.type == "TEX_IMAGE" and node.image is not None:
        return node.image
    for socket in node.inputs:
        for link in socket.links:
            image = _upstream_image(link.from_node, visited)
            if image is not None:
                return image
    return None


def base_color_image(material: bpy.types.Material):
    if material is None or material.node_tree is None:
        return None
    for node in material.node_tree.nodes:
        if node.type != "BSDF_PRINCIPLED":
            continue
        base_color = node.inputs.get("Base Color")
        if base_color is not None:
            for link in base_color.links:
                image = _upstream_image(link.from_node)
                if image is not None:
                    return image
    for node in material.node_tree.nodes:
        if (
            node.type == "TEX_IMAGE"
            and node.image is not None
            and node.image.colorspace_settings.name != "Non-Color"
        ):
            return node.image
    return None


def sampled_texture(image):
    if image is None:
        return None
    sample = image.copy()
    sample.scale(TEXTURE_SAMPLE_SIZE, TEXTURE_SAMPLE_SIZE)
    return sample, sample.pixels[:]


def sampled_materials(mesh_object: bpy.types.Object):
    samples = {}
    for index, material in enumerate(mesh_object.data.materials):
        sample = sampled_texture(base_color_image(material))
        if sample is not None:
            samples[index] = sample
        elif material is not None:
            samples[index] = Vector(material.diffuse_color[:3])
    return samples


def face_components(mesh: bpy.types.Mesh) -> list[list[int]]:
    vertex_faces: dict[int, list[int]] = defaultdict(list)
    for polygon in mesh.polygons:
        for vertex_index in polygon.vertices:
            vertex_faces[vertex_index].append(polygon.index)

    unseen = {polygon.index for polygon in mesh.polygons}
    components: list[list[int]] = []
    while unseen:
        first = unseen.pop()
        queue = deque([first])
        component = []
        while queue:
            face_index = queue.popleft()
            component.append(face_index)
            for vertex_index in mesh.polygons[face_index].vertices:
                for neighbor in vertex_faces[vertex_index]:
                    if neighbor in unseen:
                        unseen.remove(neighbor)
                        queue.append(neighbor)
        components.append(component)
    return components


def average_component_color(mesh, face_indices, material_samples) -> Vector:
    if not material_samples:
        return Vector((0.0, 0.0, 0.0))
    uv_data = mesh.uv_layers.active.data if mesh.uv_layers.active is not None else None
    result = Vector((0.0, 0.0, 0.0))
    count = 0
    for face_index in face_indices:
        polygon = mesh.polygons[face_index]
        sample_data = material_samples.get(polygon.material_index)
        if sample_data is None:
            continue
        if isinstance(sample_data, Vector):
            result += sample_data
            count += 1
            continue
        if uv_data is None or not polygon.loop_indices:
            continue
        image, pixels = sample_data
        width, height = image.size
        uv = sum(
            (uv_data[index].uv for index in polygon.loop_indices),
            Vector((0.0, 0.0)),
        ) / len(polygon.loop_indices)
        x = min(width - 1, max(0, int((uv.x % 1.0) * width)))
        y = min(height - 1, max(0, int((uv.y % 1.0) * height)))
        offset = (y * width + x) * 4
        result += Vector((pixels[offset], pixels[offset + 1], pixels[offset + 2]))
        count += 1
    return result / count if count else result


def component_center(mesh, face_indices) -> Vector:
    vertex_indices = {
        vertex_index
        for face_index in face_indices
        for vertex_index in mesh.polygons[face_index].vertices
    }
    coordinates = [mesh.vertices[index].co for index in vertex_indices]
    minimum = Vector(
        tuple(min(coordinate[axis] for coordinate in coordinates) for axis in range(3))
    )
    maximum = Vector(
        tuple(max(coordinate[axis] for coordinate in coordinates) for axis in range(3))
    )
    return (minimum + maximum) * 0.5


def _component_bounds(mesh, face_indices) -> tuple[Vector, Vector]:
    vertex_indices = {
        vertex_index
        for face_index in face_indices
        for vertex_index in mesh.polygons[face_index].vertices
    }
    coordinates = [mesh.vertices[index].co for index in vertex_indices]
    minimum = Vector(
        tuple(min(coordinate[axis] for coordinate in coordinates) for axis in range(3))
    )
    maximum = Vector(
        tuple(max(coordinate[axis] for coordinate in coordinates) for axis in range(3))
    )
    return minimum, maximum


def _component_vertex_indices(mesh, component: list[int]) -> set[int]:
    return {
        vertex_index
        for face_index in component
        for vertex_index in mesh.polygons[face_index].vertices
    }


def _minimum_vertex_gap(
    mesh,
    first_vertices: set[int],
    second_vertices: set[int],
) -> float:
    if len(first_vertices) > len(second_vertices):
        first_vertices, second_vertices = second_vertices, first_vertices
    tree = KDTree(len(second_vertices))
    for tree_index, vertex_index in enumerate(second_vertices):
        tree.insert(mesh.vertices[vertex_index].co, tree_index)
    tree.balance()
    return min(
        tree.find(mesh.vertices[vertex_index].co)[2]
        for vertex_index in first_vertices
    )


def _touching_component_groups(mesh, components: list[list[int]]) -> list[list[list[int]]]:
    """Group disconnected shells that physically form the same authored prop."""
    component_vertices = [
        _component_vertex_indices(mesh, component) for component in components
    ]
    points = [vertex.co for vertex in mesh.vertices]
    minimum = Vector(
        tuple(min(point[axis] for point in points) for axis in range(3))
    )
    maximum = Vector(
        tuple(max(point[axis] for point in points) for axis in range(3))
    )
    contact_distance = (maximum - minimum).length * 0.002
    parents = list(range(len(components)))

    def find(index: int) -> int:
        while parents[index] != index:
            parents[index] = parents[parents[index]]
            index = parents[index]
        return index

    def union(first: int, second: int) -> None:
        first_root = find(first)
        second_root = find(second)
        if first_root != second_root:
            parents[second_root] = first_root

    for first in range(len(components)):
        for second in range(first + 1, len(components)):
            if (
                _minimum_vertex_gap(
                    mesh,
                    component_vertices[first],
                    component_vertices[second],
                )
                <= contact_distance
            ):
                union(first, second)

    grouped_indices: dict[int, list[int]] = defaultdict(list)
    for index in range(len(components)):
        grouped_indices[find(index)].append(index)
    return [
        [components[index] for index in group]
        for group in grouped_indices.values()
    ]


def rotate_medium_grounded_cluster(
    mesh_object: bpy.types.Object, degrees: float
) -> dict:
    """Rigidly turn the medium of three spatial prop forms around its base."""
    mesh = mesh_object.data
    components = face_components(mesh)
    grouped_components = _touching_component_groups(mesh, components)
    if len(grouped_components) != 3:
        raise RuntimeError(
            "Expected three physically separate prop groups, found "
            f"{len(grouped_components)}"
        )

    group_records = []
    for group in grouped_components:
        vertex_indices = {
            vertex_index
            for component in group
            for face_index in component
            for vertex_index in mesh.polygons[face_index].vertices
        }
        coordinates = [mesh.vertices[index].co for index in vertex_indices]
        minimum_z = min(coordinate.z for coordinate in coordinates)
        maximum_z = max(coordinate.z for coordinate in coordinates)
        center = sum(coordinates, Vector()) / len(coordinates)
        group_records.append(
            {
                "center": [round(value, 7) for value in center],
                "components": len(group),
                "faces": sum(len(component) for component in group),
                "vertices": vertex_indices,
                "minimum_z": minimum_z,
                "maximum_z": maximum_z,
                "height": maximum_z - minimum_z,
            }
        )
    ordered = sorted(group_records, key=lambda record: record["height"])
    if not ordered[0]["height"] < ordered[1]["height"] < ordered[2]["height"]:
        summary = [
            {
                key: value
                for key, value in record.items()
                if key != "vertices"
            }
            for record in group_records
        ]
        raise RuntimeError(
            "Three complete small/medium/large prop clusters were not isolated: "
            f"{summary}"
        )
    selected = ordered[1]
    coordinates = [mesh.vertices[index].co for index in selected["vertices"]]
    base_band = selected["minimum_z"] + selected["height"] * 0.08
    base_coordinates = [
        coordinate for coordinate in coordinates if coordinate.z <= base_band
    ]
    if not base_coordinates:
        raise RuntimeError("Could not find a stable base for medium prop cluster")
    pivot = sum(base_coordinates, Vector()) / len(base_coordinates)
    angle = math.radians(degrees)
    cosine = math.cos(angle)
    sine = math.sin(angle)
    for vertex_index in selected["vertices"]:
        coordinate = mesh.vertices[vertex_index].co
        offset_x = coordinate.x - pivot.x
        offset_y = coordinate.y - pivot.y
        coordinate.x = pivot.x + offset_x * cosine - offset_y * sine
        coordinate.y = pivot.y + offset_x * sine + offset_y * cosine
    mesh.update()
    result = {
        "operation": "rotate_medium_grounded_cluster",
        "degrees": degrees,
        "pivot": [round(value, 7) for value in pivot],
        "components": selected["components"],
        "faces": selected["faces"],
        "height": round(selected["height"], 7),
        "cluster_heights": [round(record["height"], 7) for record in ordered],
    }
    print("Applied authored cluster adjustment", result)
    return result


def subset_object(source, face_indices, name: str) -> bpy.types.Object:
    mesh = source.data.copy()
    keep = set(face_indices)
    edit_mesh = bmesh.new()
    edit_mesh.from_mesh(mesh)
    edit_mesh.faces.ensure_lookup_table()
    bmesh.ops.delete(
        edit_mesh,
        geom=[face for face in edit_mesh.faces if face.index not in keep],
        context="FACES",
    )
    bmesh.ops.delete(
        edit_mesh,
        geom=[vertex for vertex in edit_mesh.verts if not vertex.link_faces],
        context="VERTS",
    )
    edit_mesh.to_mesh(mesh)
    edit_mesh.free()
    mesh.name = f"{name}Mesh"

    result = source.copy()
    result.data = mesh
    result.name = name
    source.users_collection[0].objects.link(result)
    return result


def center_object_origin(mesh_object: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    mesh_object.select_set(True)
    bpy.context.view_layer.objects.active = mesh_object
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")


def _srgb_channel(linear: float) -> float:
    return (
        linear * 12.92
        if linear <= 0.0031308
        else 1.055 * math.pow(linear, 1.0 / 2.4) - 0.055
    )


def _linear_channel(srgb: float) -> float:
    return (
        srgb / 12.92
        if srgb <= 0.04045
        else math.pow((srgb + 0.055) / 1.055, 2.4)
    )


def _semantic_family(
    profile: str,
    object_name: str,
    color: Vector,
    face_count: int,
    allow_gold: bool = True,
) -> str:
    lower_name = object_name.lower()
    if profile == "tree":
        return "pine" if "leaf" in lower_name or "canopy" in lower_name else "wood"
    if profile == "shrub":
        return "leaf" if "leaf" in lower_name or "canopy" in lower_name else "wood"

    if any(token in lower_name for token in ("leaf", "canopy", "foliage", "plant")):
        return "leaf"
    if any(token in lower_name for token in ("stone", "rock", "concrete")):
        return "stone"
    if any(token in lower_name for token in ("trunk", "wood", "branch")):
        return "wood"

    red, green, blue = (max(0.0, float(channel)) for channel in color)
    srgb = tuple(_srgb_channel(channel) for channel in (red, green, blue))
    hue, saturation, value = colorsys.rgb_to_hsv(*srgb)
    if green > red * 1.06 and green > blue * 1.08:
        return "leaf"
    if value < 0.28:
        return "charcoal"
    if value > 0.76 and saturation < 0.26:
        return "cream"
    if saturation < 0.16:
        return "stone"
    if (
        allow_gold
        and 0.065 <= hue <= 0.18
        and value > 0.78
        and saturation < 0.58
        and face_count <= 32
    ):
        return "gold"
    if 0.20 <= hue <= 0.48 and saturation > 0.13:
        return "leaf"
    if profile == "stone_prop" and saturation < 0.32:
        return "stone"
    if hue <= 0.055 or hue >= 0.96:
        return "terracotta"
    if 0.48 <= hue <= 0.72:
        return "metal"
    return "wood"


def _semantic_tone(family: str, color: Vector) -> str:
    value = max(_srgb_channel(max(0.0, float(channel))) for channel in color)
    if family == "pine":
        if value < 0.61:
            return "pine_shadow"
        if value < 0.70:
            return "pine_medium"
        return "pine_light"
    if family == "leaf":
        return "leaf_olive" if value < 0.57 else "leaf_medium"
    if family == "wood":
        if value < 0.52:
            return "wood_deep"
        if value < 0.74:
            return "wood_primary"
        return "wood_light"
    if family == "cream":
        return "warm_white" if value > 0.82 else "ivory_highlight"
    if family == "gold":
        return "gold_primary"
    if family == "metal":
        return "soft_sage_gray"
    if family == "stone":
        if value < 0.49:
            return "stone_shadow"
        if value < 0.70:
            return "stone_mid"
        return "stone_light"
    if family == "terracotta":
        if value < 0.48:
            return "terracotta_shadow"
        if value < 0.68:
            return "terracotta_primary"
        return "terracotta_light"
    return "warm_near_black"


def _flat_material(semantic_name: str) -> bpy.types.Material:
    existing = bpy.data.materials.get(semantic_name)
    if existing is not None:
        return existing
    material = bpy.data.materials.new(semantic_name)
    material.use_nodes = True
    shader = next(
        node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED"
    )
    raw = GARDEN_GALAXY_COLORS[semantic_name]
    srgb = tuple(int(raw[index : index + 2], 16) / 255.0 for index in (0, 2, 4))
    shader.inputs["Base Color"].default_value = (
        *(_linear_channel(channel) for channel in srgb),
        1.0,
    )
    shader.inputs["Roughness"].default_value = 0.88
    shader.inputs["Metallic"].default_value = (
        0.18 if semantic_name in {"gold_primary", "soft_sage_gray"} else 0.0
    )
    shader.inputs["Specular IOR Level"].default_value = 0.20
    return material


def apply_flat_style(
    mesh_objects: list[bpy.types.Object], profile: str
) -> dict[str, int]:
    """Replace baked Meshy texture noise with clean semantic colour regions."""
    usage: dict[str, int] = defaultdict(int)
    for mesh_object in mesh_objects:
        mesh = mesh_object.data
        sample_data = sampled_materials(mesh_object)
        classified: list[tuple[list[int], Vector, str]] = []
        for face_indices in face_components(mesh):
            color = average_component_color(mesh, face_indices, sample_data)
            family = _semantic_family(
                profile,
                mesh_object.name,
                color,
                len(face_indices),
            )
            classified.append((face_indices, color, family))

        total_faces = sum(len(face_indices) for face_indices, _, _ in classified)
        gold_faces = sum(
            len(face_indices)
            for face_indices, _, family in classified
            if family == "gold"
        )
        if total_faces and gold_faces > total_faces * GOLD_MAX_FACE_SHARE:
            # Not an accent. Re-run those components with gold unavailable, so
            # they fall through to the wood/stone path their hue actually fits.
            classified = [
                (
                    face_indices,
                    color,
                    _semantic_family(
                        profile,
                        mesh_object.name,
                        color,
                        len(face_indices),
                        allow_gold=False,
                    )
                    if family == "gold"
                    else family,
                )
                for face_indices, color, family in classified
            ]

        assignments: list[tuple[list[int], str]] = []
        for face_indices, color, family in classified:
            semantic_name = _semantic_tone(family, color)
            assignments.append((face_indices, semantic_name))
            usage[semantic_name] += len(face_indices)

        semantic_names = sorted({name for _, name in assignments})
        mesh.materials.clear()
        for semantic_name in semantic_names:
            mesh.materials.append(_flat_material(semantic_name))
        material_indices = {
            semantic_name: index
            for index, semantic_name in enumerate(semantic_names)
        }
        for face_indices, semantic_name in assignments:
            for face_index in face_indices:
                mesh.polygons[face_index].material_index = material_indices[semantic_name]
        mesh.update()
    print("Flat Garden Galaxy materials", dict(sorted(usage.items())))
    return usage


def split_tree_canopy(source: bpy.types.Object) -> list[bpy.types.Object]:
    mesh = source.data
    sample_data = sampled_materials(source)
    canopy_faces: list[int] = []
    trunk_faces: list[int] = []
    canopy_component_count = 0
    minimum_z = min(vertex.co.z for vertex in mesh.vertices)
    maximum_z = max(vertex.co.z for vertex in mesh.vertices)
    canopy_height_min = minimum_z + (
        maximum_z - minimum_z
    ) * CANOPY_CENTER_HEIGHT_FRACTION_MIN
    axis_x = (
        min(vertex.co.x for vertex in mesh.vertices)
        + max(vertex.co.x for vertex in mesh.vertices)
    ) * 0.5
    axis_y = (
        min(vertex.co.y for vertex in mesh.vertices)
        + max(vertex.co.y for vertex in mesh.vertices)
    ) * 0.5
    maximum_radius = max(
        math.hypot(vertex.co.x - axis_x, vertex.co.y - axis_y)
        for vertex in mesh.vertices
    )

    for face_indices in face_components(mesh):
        center = component_center(mesh, face_indices)
        color = average_component_color(mesh, face_indices, sample_data)
        green_ratio = color.y / max(color.x, 0.0001)
        is_canopy = (
            center.z >= canopy_height_min
            and green_ratio >= CANOPY_GREEN_RATIO_MIN
        )
        if not is_canopy:
            trunk_faces.extend(face_indices)
            continue

        # A generated tree usually arrives as ONE welded shell, so its trunk
        # sits inside this component rather than beside it. Judging the whole
        # component by its average colour then files the trunk under canopy,
        # which has two visible consequences: the trunk inherits the foliage
        # wind and sways, and it renders green. Re-check each face against its
        # own sampled colour, plus its distance from the trunk axis so dark
        # foliage is not mistaken for bark.
        component_canopy: list[int] = []
        for face_index in face_indices:
            face_center = mesh.polygons[face_index].center
            radius = math.hypot(face_center.x - axis_x, face_center.y - axis_y)
            face_color = average_component_color(mesh, [face_index], sample_data)
            is_trunk = (
                face_color.y / max(face_color.x, 0.0001) < TRUNK_GREEN_RATIO_MAX
                and radius < maximum_radius * TRUNK_RADIUS_FRACTION_MAX
            )
            if is_trunk:
                trunk_faces.append(face_index)
            else:
                component_canopy.append(face_index)
        if not component_canopy:
            continue
        canopy_faces.extend(component_canopy)
        canopy_component_count += 1

    if canopy_component_count == 0 or not trunk_faces:
        raise RuntimeError("Could not distinguish canopy from trunk")

    objects = [subset_object(source, trunk_faces, "Trunk")]
    leaf = subset_object(source, canopy_faces, "LeafCanopy")
    center_object_origin(leaf)
    objects.append(leaf)
    bpy.data.objects.remove(source, do_unlink=True)
    print(
        f"Separated {canopy_component_count} canopy shells into one sealed crown"
    )
    return objects


def ground_under_root(root: bpy.types.Object, mesh_objects) -> None:
    minimum_height = min(
        (mesh_object.matrix_world @ vertex.co).z
        for mesh_object in mesh_objects
        for vertex in mesh_object.data.vertices
    )
    root.location.z -= minimum_height


def make_root(name: str, mesh_objects) -> bpy.types.Object:
    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)
    for child in [item for item in bpy.context.scene.objects if item != root and item.parent is None]:
        world_transform = child.matrix_world.copy()
        child.parent = root
        child.matrix_world = world_transform
    ground_under_root(root, mesh_objects)
    return root


def export_glb(output: Path) -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(output),
        export_format="GLB",
        export_yup=True,
        export_normals=True,
        export_texcoords=True,
        export_materials="EXPORT",
    )


def geometry_report(mesh_objects: list[bpy.types.Object]) -> dict:
    bpy.context.view_layer.update()
    points = [
        mesh_object.matrix_world @ vertex.co
        for mesh_object in mesh_objects
        for vertex in mesh_object.data.vertices
    ]
    minimum = Vector(
        tuple(min(point[axis] for point in points) for axis in range(3))
    )
    maximum = Vector(
        tuple(max(point[axis] for point in points) for axis in range(3))
    )
    dimensions = maximum - minimum
    return {
        "mesh_objects": len(mesh_objects),
        "vertices": sum(len(item.data.vertices) for item in mesh_objects),
        "faces": sum(len(item.data.polygons) for item in mesh_objects),
        "triangles": sum(
            max(0, len(polygon.vertices) - 2)
            for item in mesh_objects
            for polygon in item.data.polygons
        ),
        "components": sum(
            len(face_components(item.data)) for item in mesh_objects
        ),
        "dimensions": [round(value, 7) for value in dimensions],
        "minimum": [round(value, 7) for value in minimum],
        "maximum": [round(value, 7) for value in maximum],
    }


def texture_report(mesh_objects: list[bpy.types.Object]) -> dict:
    materials = {
        material
        for item in mesh_objects
        for material in item.data.materials
        if material is not None
    }
    albedo_images = {
        base_color_image(material)
        for material in materials
        if base_color_image(material) is not None
    }
    return {
        "materials": len(materials),
        "albedo_images": len(albedo_images),
    }


def _same_dimensions(before: dict, after: dict) -> bool:
    return all(
        math.isclose(first, second, rel_tol=1.0e-5, abs_tol=1.0e-5)
        for first, second in zip(before["dimensions"], after["dimensions"])
    )


def main() -> None:
    arguments = parse_args()
    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(arguments.source.resolve()))
    mesh_objects = [
        item for item in bpy.context.scene.objects if item.type == "MESH"
    ]
    if not mesh_objects:
        raise RuntimeError(f"Expected mesh geometry in {arguments.source}")
    if arguments.mode == "tree" and len(mesh_objects) != 1:
        raise RuntimeError(
            f"Tree separation expects one generated mesh, got {len(mesh_objects)}"
        )

    source = mesh_objects[0]
    source_geometry = geometry_report(mesh_objects)
    source_textures = texture_report(mesh_objects)
    authored_adjustments = []
    if not math.isclose(arguments.rotate_medium_cluster, 0.0, abs_tol=1.0e-6):
        if len(mesh_objects) != 1 or arguments.mode != "prop":
            raise RuntimeError(
                "Medium cluster rotation requires one generated prop mesh"
            )
        authored_adjustments.append(
            rotate_medium_grounded_cluster(source, arguments.rotate_medium_cluster)
        )
    if arguments.mode == "tree":
        mesh_objects = split_tree_canopy(source)
    elif len(mesh_objects) == 1:
        source.name = f"{arguments.root_name}Body"
        source.data.name = f"{arguments.root_name}BodyMesh"
    semantic_usage = {}
    if arguments.style_profile != "none":
        semantic_usage = apply_flat_style(mesh_objects, arguments.style_profile)
    root = make_root(arguments.root_name, mesh_objects)
    for item in list(bpy.context.scene.objects):
        if item.type == "EMPTY" and item != root and not item.children:
            bpy.data.objects.remove(item, do_unlink=True)
    prepared_geometry = geometry_report(mesh_objects)
    topology_keys = ("vertices", "faces", "triangles", "components")
    if arguments.mode == "tree":
        # Separating the canopy from the trunk cuts one welded shell into two
        # objects, which necessarily duplicates vertices along the seam and
        # raises the component count. Those two counters therefore cannot be
        # held fixed in tree mode without forbidding the split itself. Faces
        # and triangles stay strict, and they are what actually prove nothing
        # was added, removed, remeshed, decimated, or subdivided.
        topology_keys = ("faces", "triangles")
    topology_preserved = all(
        source_geometry[key] == prepared_geometry[key] for key in topology_keys
    )
    dimensions_preserved = _same_dimensions(source_geometry, prepared_geometry)
    if not topology_preserved or (
        not dimensions_preserved and not authored_adjustments
    ):
        raise RuntimeError(
            "Import safety check failed: geometry or silhouette dimensions changed"
        )
    export_glb(arguments.output.resolve())
    report = {
        "version": 1,
        "source": str(arguments.source.resolve()),
        "output": str(arguments.output.resolve()),
        "profile": arguments.style_profile,
        "mode": arguments.mode,
        "root_name": arguments.root_name,
        "source_geometry": source_geometry,
        "prepared_geometry": prepared_geometry,
        "source_textures": source_textures,
        "semantic_face_usage": dict(sorted(semantic_usage.items())),
        "authored_adjustments": authored_adjustments,
        "topology_preserved": topology_preserved,
        "topology_checked": list(topology_keys),
        "dimensions_preserved": dimensions_preserved,
    }
    if arguments.report is not None:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(
            json.dumps(report, indent=2) + "\n", encoding="utf-8"
        )
    print(f"Prepared {arguments.output}")


if __name__ == "__main__":
    main()
