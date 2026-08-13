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
    # The whole palette, not just PALETTE_KEYS. Loading only those 19 was the
    # reason imports came out desaturated: a red mushroom cap, green moss and
    # brass fittings had no entry to match against, so they resolved to the
    # nearest muted brown or grey. Every name here is also present in
    # assets/palettes/gg_material_palette.tres, which is what lets
    # MaterialLibrary rebind it by name at load.
    return {
        key: value.removeprefix("#")
        for key, value in exact.items()
        if len(value.removeprefix("#")) == 6
    }


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


## Which palette slots each profile is allowed to pick from.
##
## Faithful colour matching picks the nearest palette entry to what the source
## actually looks like, rather than guessing a semantic family from hue rules.
## The restriction exists only where the slot carries structural meaning: a
## tree's canopy must land on a foliage slot for the wind and material
## rebinding to work, whatever its texture happens to sample.
## Neutrals every profile can reach: highlights, shadow, and unpainted metal.
# Colour is decided by clustering the source and mapping each cluster to its
# own palette entry, rather than matching each connected component separately.
# Per-component matching had both failure modes at once: one painted surface
# split across several slots because its lit and shaded halves matched
# differently, and two genuinely different paints collapsed onto one slot. The
# wheelbarrow showed both -- its dark tray, orange frame and gold fittings came
# out as a single flat brown.
#
# Clustering is by hue, and forgiving about value, because the source textures
# have lighting baked in while Suma relights every surface. A paint's lit and
# shaded samples must end up on one palette entry; splitting them sent the
# wheelbarrow's lit frame to olive and its shaded frame to mustard, so one piece
# of wood read as two materials. 7 degrees of hue keeps the orange frame apart
# from the brown tray (12 degrees) while absorbing the shading within each.
CLUSTER_HUE_WINDOW = 0.02
CLUSTER_VALUE_WINDOW = 0.12
CLUSTER_GREY_SATURATION = 0.18
MAX_CLUSTERS = 8
MIN_CLUSTER_FACE_SHARE = 0.01
# Merge threshold for the agglomerative pass. Measured on the wheelbarrow: its
# frame's lit and shaded samples sit 0.104 apart and must merge, while its gold
# fittings sit 0.139 from the lit frame and must not -- they are only 3 degrees
# apart in hue, so nothing but this gap separates them.
CLUSTER_MERGE_DISTANCE = 0.12
# Two palette entries closer than this are the same colour to the eye, so only
# one of them is offered.
MIN_SLOT_SEPARATION = 0.006
# Two clusters closer than this are the same paint, and share one entry.
SLOT_REUSE_TOLERANCE = 0.02

# Families that are never an object's paint. Water and snow are environment,
# tiles belong to the terrain kit, and the background/ground creams are sky and
# plain colours that would read as blown-out white on a prop.
_EXCLUDED_SLOT_TOKENS = (
    "water",
    "snow",
    "tile",
    "uw_",
    "foam",
    "background",
    "plain_ground",
)


def _usable_palette() -> tuple[str, ...]:
    """Palette entries a prop may be painted with, deduplicated by colour.

    The palette carries 120 names for 92 distinct colours -- gold and
    gold_primary are the same value, as are terracotta and terracotta_primary.
    Uniqueness has to be enforced on colour rather than name, or two clusters
    happily take two names for an identical colour and the distinction the
    clustering just recovered is thrown away again.
    """
    by_color: dict[tuple[int, int, int], str] = {}
    for name, raw in GARDEN_GALAXY_COLORS.items():
        if raw is None or len(raw) != 6:
            continue
        if any(token in name for token in _EXCLUDED_SLOT_TOKENS):
            continue
        key = tuple(int(raw[index : index + 2], 16) for index in (0, 2, 4))
        # Shortest name wins, which prefers `gold` over `gold_primary`.
        if key not in by_color or len(name) < len(by_color[key]):
            by_color[key] = name

    # Exact-colour dedup is not enough. stone_highlight and ivory_highlight
    # differ by one step of green out of 255, so uniqueness happily handed one
    # to the statue's lit stone and the other to its shadow -- two names, no
    # visible contrast, a flat white carving. Entries this close are the same
    # colour for the purpose of telling two surfaces apart.
    kept: list[str] = []
    for name in sorted(by_color.values()):
        srgb = _palette_srgb(name)
        if any(
            _perceptual_distance(srgb, _palette_srgb(other))
            < MIN_SLOT_SEPARATION
            for other in kept
        ):
            continue
        kept.append(name)
    return tuple(kept)


# Built on first use: _usable_palette needs _palette_srgb and
# _perceptual_distance, which are defined further down.
_USABLE_PALETTE_CACHE: tuple[str, ...] | None = None


def usable_palette() -> tuple[str, ...]:
    global _USABLE_PALETTE_CACHE
    if _USABLE_PALETTE_CACHE is None:
        _USABLE_PALETTE_CACHE = _usable_palette()
    return _USABLE_PALETTE_CACHE


def band_palette(band: str) -> tuple[str, ...]:
    """Every usable entry whose hue sits in one family.

    A canopy has to land on foliage regardless of what its texture samples,
    because the wind controller drives the canopy mesh and a brown crown reads
    as broken. But restricting it to three hand-picked pines was too tight: the
    fir's canopy samples a yellow-green at 62 degrees and the nearest pine is 45
    degrees away, so it resolved to pine_light -- the lightest option, when the
    source is darker than all three. Offering the whole green family lets the
    match be decided on merit; it picks earthy_olive.
    """
    return tuple(
        name
        for name in usable_palette()
        if _hue_band(_palette_srgb(name)) == band
    )


def _hls(srgb: tuple[float, float, float]) -> tuple[float, float, float]:
    return colorsys.rgb_to_hls(*srgb)


def _same_paint(left: tuple[float, float, float], right: tuple[float, float, float]) -> bool:
    """Whether two sampled colours read as the same paint under shading."""
    left_hue, left_value, left_saturation = left
    right_hue, right_value, right_saturation = right
    if abs(left_value - right_value) >= CLUSTER_VALUE_WINDOW:
        return False
    grey = (
        left_saturation <= CLUSTER_GREY_SATURATION
        and right_saturation <= CLUSTER_GREY_SATURATION
    )
    if grey:
        # A near-grey's hue is numerically unstable, so value alone decides.
        return True
    if (
        left_saturation <= CLUSTER_GREY_SATURATION
        or right_saturation <= CLUSTER_GREY_SATURATION
    ):
        return False
    gap = abs(left_hue - right_hue)
    return min(gap, 1.0 - gap) < CLUSTER_HUE_WINDOW


def cluster_face_colors(mesh, sample_data) -> list[dict]:
    """Group the mesh's faces by the paint they were sampled from."""
    clusters: list[dict] = []
    for polygon in mesh.polygons:
        color = average_component_color(mesh, [polygon.index], sample_data)
        srgb = tuple(_srgb_channel(max(0.0, float(channel))) for channel in color)
        hls = _hls(srgb)
        for cluster in clusters:
            if _same_paint(hls, cluster["hls"]):
                cluster["faces"].append(polygon.index)
                weight = 1.0 / len(cluster["faces"])
                cluster["srgb"] = tuple(
                    current + (new - current) * weight
                    for current, new in zip(cluster["srgb"], srgb)
                )
                cluster["hls"] = _hls(cluster["srgb"])
                break
        else:
            clusters.append({"faces": [polygon.index], "srgb": srgb, "hls": hls})
    clusters.sort(key=lambda cluster: -len(cluster["faces"]))
    clusters = _merge_near_clusters(clusters)
    return _merge_small_clusters(clusters, len(mesh.polygons))


def _combine(host: dict, other: dict) -> None:
    share = len(other["faces"]) / (len(other["faces"]) + len(host["faces"]))
    host["srgb"] = tuple(
        current + (new_value - current) * share
        for current, new_value in zip(host["srgb"], other["srgb"])
    )
    host["hls"] = _hls(host["srgb"])
    host["faces"].extend(other["faces"])


def _merge_near_clusters(clusters: list[dict]) -> list[dict]:
    """Agglomerate clusters whose centroids read as the same paint.

    The single pass above assigns each face to the first cluster it matches,
    so a cluster's centroid drifts as faces accumulate and later faces of the
    same paint can miss it -- the wheelbarrow's frame came out as two clusters
    0.105 apart in value despite a 0.12 window. Comparing settled centroids
    against each other is stable in a way that first-match-wins is not.
    """
    while len(clusters) > 1:
        best_pair = None
        best_distance = CLUSTER_MERGE_DISTANCE
        for left in range(len(clusters)):
            for right in range(left + 1, len(clusters)):
                gap = _perceptual_distance(
                    clusters[left]["srgb"], clusters[right]["srgb"]
                )
                if gap < best_distance:
                    best_distance = gap
                    best_pair = (left, right)
        if best_pair is None:
            break
        left, right = best_pair
        _combine(clusters[left], clusters[right])
        clusters.pop(right)
        clusters.sort(key=lambda cluster: -len(cluster["faces"]))
    return clusters


def _merge_small_clusters(clusters: list[dict], total_faces: int) -> list[dict]:
    """Fold specks and any excess past MAX_CLUSTERS into their nearest neighbour.

    Texture seams and antialiased edges produce a long tail of one- and two-face
    groups. Left alone they would each claim their own palette entry and speckle
    the model with unrelated colours.
    """
    floor = max(1, int(total_faces * MIN_CLUSTER_FACE_SHARE))
    while len(clusters) > 1 and (
        len(clusters) > MAX_CLUSTERS or len(clusters[-1]["faces"]) < floor
    ):
        smallest = clusters.pop()
        host = min(
            clusters,
            key=lambda cluster: _perceptual_distance(
                smallest["srgb"], cluster["srgb"]
            ),
        )
        share = len(smallest["faces"]) / (
            len(smallest["faces"]) + len(host["faces"])
        )
        host["srgb"] = tuple(
            current + (new - current) * share
            for current, new in zip(host["srgb"], smallest["srgb"])
        )
        host["hls"] = _hls(host["srgb"])
        host["faces"].extend(smallest["faces"])
        clusters.sort(key=lambda cluster: -len(cluster["faces"]))
    return clusters


def assign_distinct_slots(
    clusters: list[dict], candidates: tuple[str, ...]
) -> list[str]:
    """One palette entry per cluster, never reusing a colour.

    Largest cluster first, so the colour that carries the object gets the best
    available match and the accents fit around it. Without the uniqueness rule
    the wheelbarrow's tray, frame and fittings all resolved to wood_light and
    the model lost every internal distinction it had.
    """
    remaining = list(candidates)
    chosen: list[str] = []
    taken: dict[str, tuple[float, float, float]] = {}
    for cluster in clusters:
        if not remaining:
            remaining = list(candidates)

        def distance(name: str, cluster=cluster) -> float:
            return _perceptual_distance(cluster["srgb"], _palette_srgb(name))

        overall = min(candidates, key=distance)
        # Uniqueness is a preference, not a rule. Two clusters can be near
        # duplicates -- the mushroom had creams at (0.85,0.74,0.66) and
        # (0.85,0.77,0.68) -- and forcing the second onto a different entry sent
        # it to a brown three families away.
        #
        # The test is whether the two CLUSTERS are near-identical, not whether
        # the alternatives are poor. Keying it on the alternatives instead let
        # the statue's lit stone and its shadow, a real 0.10 value difference,
        # both take ivory_highlight and flatten the carving to one tone.
        if overall in taken and (
            _perceptual_distance(cluster["srgb"], taken[overall])
            < SLOT_REUSE_TOLERANCE
        ):
            chosen.append(overall)
            continue
        best_free = min(remaining, key=distance)
        chosen.append(best_free)
        remaining.remove(best_free)
        taken[best_free] = cluster["srgb"]
    return chosen


# Matching happens on hue/saturation/value, not on RGB channels. Channel
# distance systematically prefers desaturated middle colours, because a muted
# entry sits numerically near everything: a saturated orange frame scored
# closest to sand_shadow, and a warm grey stem scored closest to pink
# soft_coral. Both are far off to the eye while being near in RGB. This also
# subsumes the old warm/cool flip penalty -- crossing from a warm hue to a cool
# grey now costs saturation and hue directly.
#
# Hue dominates because it is what identifies a colour. At a lower hue weight
# the mushroom's red cap scored closer to brown earth_light than to coral: an
# 18-degree hue error was cheaper than a 0.09 saturation error, which is
# backwards.
HUE_WEIGHT = 60.0
SATURATION_WEIGHT = 3.0
VALUE_WEIGHT = 4.0
# Hue is meaningless for a grey and unstable for a near-grey, so its weight
# scales with how chromatic the *less* saturated of the pair is.
CHROMA_REFERENCE = 0.5

# Hue alone still lets a colour cross into the wrong material family when the
# palette has a gap. The statue's moss samples at 57 degrees -- yellow-green --
# and the palette jumps straight from gold at 51 to the first green at 80, so
# the nearest hue was warm wood_highlight and the moss rendered as a tan smudge
# across the carving. Crossing a family boundary costs more than being 20
# degrees off inside one.
#
# Neutrals are exempt. A near-grey's hue is noise, and the statue's own stone
# sits at 48 degrees with almost no saturation -- banding it would have shoved
# pale stone away from ivory for no reason.
#
# The threshold is 0.10, not the 0.25 tried first: this palette's greens are
# all desaturated (leaf_medium 0.14, moss 0.20, pine_light 0.21), so at 0.25
# every one of them counted as a grey and band_palette('green') returned a
# single entry -- the fir's canopy had one candidate rather than a choice.
BAND_CROSSING_PENALTY = 0.10
BAND_NEUTRAL_SATURATION = 0.10
GREEN_BAND = (55.0, 160.0)
COOL_BAND = (160.0, 330.0)


def _hue_band(srgb: tuple[float, float, float]) -> str | None:
    hue, _value, saturation = colorsys.rgb_to_hls(*srgb)
    if saturation < BAND_NEUTRAL_SATURATION:
        return None
    degrees = hue * 360.0
    if GREEN_BAND[0] <= degrees < GREEN_BAND[1]:
        return "green"
    if COOL_BAND[0] <= degrees < COOL_BAND[1]:
        return "cool"
    return "warm"



def _perceptual_distance(left: tuple[float, float, float], right) -> float:
    """Distance between two sRGB colours, scored on hue, saturation and value."""
    left_hue, left_value, left_saturation = colorsys.rgb_to_hls(*left)
    right_hue, right_value, right_saturation = colorsys.rgb_to_hls(*right)
    hue_gap = abs(left_hue - right_hue)
    hue_gap = min(hue_gap, 1.0 - hue_gap)
    chroma = min(1.0, min(left_saturation, right_saturation) / CHROMA_REFERENCE)
    distance = (
        HUE_WEIGHT * chroma * hue_gap**2
        + SATURATION_WEIGHT * (left_saturation - right_saturation) ** 2
        + VALUE_WEIGHT * (left_value - right_value) ** 2
    )
    left_band = _hue_band(left)
    right_band = _hue_band(right)
    if left_band is not None and right_band is not None and left_band != right_band:
        distance += BAND_CROSSING_PENALTY
    return distance


def _palette_srgb(name: str) -> tuple[float, float, float]:
    raw = GARDEN_GALAXY_COLORS[name]
    return tuple(int(raw[index : index + 2], 16) / 255.0 for index in (0, 2, 4))


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
        lower_name = mesh_object.name.lower()
        is_canopy = "leaf" in lower_name or "canopy" in lower_name
        if profile in {"tree", "shrub"}:
            candidates = (
                band_palette("green") if is_canopy else band_palette("warm")
            )
        else:
            # Props match against the whole gamut. Restricting a profile to a
            # handful of slots was what desaturated everything: a stone statue
            # limited to greys lost its moss, and a wheelbarrow limited to wood
            # lost its gold fittings. The clustering already decides how many
            # colours an object has, so the pool only needs to exclude families
            # that are never a prop's paint.
            candidates = usable_palette()

        clusters = cluster_face_colors(mesh, sample_data)
        chosen = assign_distinct_slots(clusters, candidates)

        assignments: list[tuple[list[int], str]] = []
        for cluster, semantic_name in zip(clusters, chosen):
            assignments.append((cluster["faces"], semantic_name))
            usage[semantic_name] += len(cluster["faces"])
            red, green, blue = cluster["srgb"]
            print(
                f"  cluster {len(cluster['faces']):4} faces "
                f"sRGB=({red:.2f},{green:.2f},{blue:.2f}) -> {semantic_name}"
            )

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
