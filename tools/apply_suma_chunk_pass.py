"""Chunk pass: give a generated GLB Suma's facet hierarchy.

Measured problem (tools/measure_style_fingerprint.py): every Meshy organic
ships a perfectly uniform 2000-triangle spray with split vertices, so
facet_evenness lands at 0.41-0.48 while everything that reads as Suma sits
at 0.03-0.20. Uniform triangle density is the "generic low-poly" tell. The
props Luka likes have a size hierarchy -- a few big planes carrying the mass,
small faces only where a detail earns them.

This pass rebuilds that hierarchy without redesigning the model:

  weld       merge the split vertices so the surface is continuous
  dissolve   limited-dissolve merges near-coplanar triangles into large
             faces. Moves no vertex, so the silhouette is bit-exact.
  planarize  flatten each merged region into one true plane, giving the
             clean chunky facets of the crate rather than a lumpy n-gon.
  relax      optional light smoothing that rounds off spike tips; the only
             stage that changes the silhouette, so it is off by default.
  bevel      one fixed-width chamfer catches the key light on every edge,
             which is what makes the radio and crate feel like one kit.
  normals    weighted normals + auto smooth, then flat-export.

Material boundaries survive every stage (dissolve is delimited by material),
so MaterialLibrary's name-based rebinding keeps working.

Run headless:
  blender --background --factory-startup --python tools/apply_suma_chunk_pass.py \
    -- --source assets/3d/reworked/prop_fir.glb --output out.glb \
       --dissolve 12 --bevel 0.008
"""

from __future__ import annotations

import argparse
import json
import math
import statistics
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


def parse_args() -> argparse.Namespace:
    arguments = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument(
        "--dissolve",
        type=float,
        default=12.0,
        help="Limited-dissolve angle in degrees. The main hierarchy lever.",
    )
    parser.add_argument(
        "--planarize",
        type=int,
        default=6,
        help="Planar-faces iterations; 0 leaves merged regions curved.",
    )
    parser.add_argument(
        "--relax",
        type=float,
        default=0.0,
        help="Silhouette smoothing factor, 0.0-0.6. Rounds spike tips.",
    )
    parser.add_argument(
        "--relax-iterations",
        type=int,
        default=3,
    )
    parser.add_argument(
        "--bevel",
        type=float,
        default=0.008,
        help="Chamfer width in metres. 0 disables.",
    )
    parser.add_argument("--bevel-segments", type=int, default=1)
    parser.add_argument("--smooth-angle", type=float, default=35.0)
    parser.add_argument(
        "--subdivide",
        type=int,
        default=0,
        help="Catmull-Clark levels. Each level roughly quadruples triangles, "
        "so 1 is usually enough to stop a smooth-shaded dome banding.",
    )
    parser.add_argument(
        "--shading",
        choices=("faceted", "smooth"),
        default="faceted",
        help="faceted keeps crisp planes for hard-surface props. smooth is "
        "for anything that should read as a rounded mass -- it drops "
        "planarise, hardened bevel normals, and the sharp-edge angle, which "
        "together turn a dome into a dented polyhedron.",
    )
    parser.add_argument(
        "--widen",
        type=float,
        default=1.0,
        help="Horizontal scale about the vertical axis. >1 fattens the mass.",
    )
    parser.add_argument(
        "--squash",
        type=float,
        default=1.0,
        help="Vertical scale about the ground plane. <1 makes it squat.",
    )
    parser.add_argument(
        "--thicken",
        type=float,
        default=1.0,
        help="Extra horizontal scale for objects matching --thicken-match.",
    )
    parser.add_argument(
        "--thicken-match",
        default="trunk",
        help="Case-insensitive substring selecting the parts --thicken affects.",
    )
    parser.add_argument(
        "--thicken-base",
        type=float,
        default=1.0,
        help="Horizontal scale at ground level for matched parts; ramps to "
        "--thicken by --thicken-ramp. Below 1.0 tames a spiky root flare.",
    )
    parser.add_argument(
        "--thicken-ramp",
        type=float,
        default=0.4,
        help="Height fraction over which --thicken-base reaches --thicken.",
    )
    parser.add_argument(
        "--dome",
        type=float,
        default=0.0,
        help="Blend cap geometry onto a dome, 0.0-1.0. Generated mushrooms "
        "arrive as droopy hooked wizard hats; Garden Galaxy caps are round.",
    )
    parser.add_argument(
        "--dome-material",
        default="",
        help="Substring picking which materials count as cap; the rest of "
        "each island is treated as stem and supplies the dome axis.",
    )
    parser.add_argument(
        "--dome-power",
        type=float,
        default=2.6,
        help="Dome profile exponent. 2.0 is a hemisphere; higher is a "
        "fuller, flatter-topped cushion.",
    )
    parser.add_argument(
        "--dome-radius",
        type=float,
        default=1.0,
        help="Scales the measured brim radius. Below 1.0 tucks a wide "
        "generated cap in over its stem.",
    )
    parser.add_argument(
        "--dome-aspect",
        type=float,
        default=0.55,
        help="Cap height as a multiple of cap radius. A generated hat is far "
        "taller than this, so it is compressed. 0 keeps the authored height.",
    )
    parser.add_argument(
        "--preserve-height",
        action="store_true",
        help="Rescale uniformly after squashing so the authored height, and "
        "therefore the footprint the game already places, is unchanged.",
    )
    parser.add_argument(
        "--stem-material",
        default="",
        help="Reassign near-axis faces to this material. Generated trees "
        "often bury a green stem inside the canopy shell.",
    )
    parser.add_argument(
        "--stem-radius",
        type=float,
        default=0.18,
        help="Near-axis cutoff as a fraction of the part's own max radius.",
    )
    parser.add_argument(
        "--stem-height",
        type=float,
        default=0.5,
        help="Only faces below this fraction of the model height may become "
        "stem. Without it the apex, which is also near the axis, turns wood.",
    )
    parser.add_argument(
        "--tone-ramp",
        nargs="*",
        default=[],
        help="Lit-to-shaded material names, e.g. pine_light pine_medium "
        "pine_shadow. Faces are redistributed by normal so the form self-"
        "shades instead of reading as one flat colour.",
    )
    parser.add_argument(
        "--tone-match",
        default="",
        help="Case-insensitive substring selecting which parts get the ramp; "
        "empty applies it everywhere.",
    )
    parser.add_argument("--report", type=Path)
    return parser.parse_args(arguments)


def scene_meshes() -> list[bpy.types.Object]:
    return [item for item in bpy.context.scene.objects if item.type == "MESH"]


def bounds() -> tuple[Vector, Vector]:
    points = [
        item.matrix_world @ vertex.co
        for item in scene_meshes()
        for vertex in item.data.vertices
    ]
    minimum = Vector(tuple(min(p[axis] for p in points) for axis in range(3)))
    maximum = Vector(tuple(max(p[axis] for p in points) for axis in range(3)))
    return minimum, maximum


def fingerprint() -> dict:
    mesh = bmesh.new()
    for item in scene_meshes():
        copy = item.data.copy()
        copy.transform(item.matrix_world)
        mesh.from_mesh(copy)
        bpy.data.meshes.remove(copy)
    bmesh.ops.triangulate(mesh, faces=mesh.faces[:])
    mesh.faces.ensure_lookup_table()

    points = [vertex.co for vertex in mesh.verts]
    minimum = Vector(tuple(min(p[axis] for p in points) for axis in range(3)))
    maximum = Vector(tuple(max(p[axis] for p in points) for axis in range(3)))
    size = maximum - minimum
    diagonal = size.length
    bmesh.ops.remove_doubles(mesh, verts=mesh.verts[:], dist=diagonal * 1.0e-4)
    mesh.faces.ensure_lookup_table()

    areas = sorted(face.calc_area() for face in mesh.faces)
    total = sum(areas)
    p90 = areas[int(len(areas) * 0.9)] if areas else 0.0
    median = statistics.median(areas) if areas else 0.0
    triangles = len(mesh.faces)
    mesh.free()

    return {
        "triangles": triangles,
        "dimensions": [round(value, 4) for value in (size.x, size.y, size.z)],
        "facet_scale": (
            round(math.sqrt(total / triangles) / diagonal, 4)
            if triangles and diagonal
            else 0.0
        ),
        "facet_evenness": round(median / p90, 3) if p90 else 0.0,
    }


def reproportion(arguments: argparse.Namespace) -> None:
    """Fatten and squat the whole model about one shared axis and ground.

    Facet work cannot rescue a silhouette that is simply too tall and too
    thin -- Garden Galaxy's plants are squat and heavy. This deforms every
    part against the *shared* vertical axis and ground plane so a trunk and
    its canopy stay attached, and can thicken named parts further so a
    widened tree does not end up balanced on a wire.
    """
    if (
        abs(arguments.widen - 1.0) < 1.0e-6
        and abs(arguments.squash - 1.0) < 1.0e-6
        and abs(arguments.thicken - 1.0) < 1.0e-6
        and abs(arguments.thicken_base - 1.0) < 1.0e-6
    ):
        return

    minimum, maximum = bounds()
    centre_x = (minimum.x + maximum.x) * 0.5
    centre_y = (minimum.y + maximum.y) * 0.5
    ground = minimum.z
    height = max(maximum.z - ground, 1.0e-6)
    ramp = max(arguments.thicken_ramp, 1.0e-6)
    needle = arguments.thicken_match.lower()

    for item in scene_meshes():
        matched = needle in item.name.lower() or needle in item.data.name.lower()
        to_world = item.matrix_world
        to_local = to_world.inverted()
        for vertex in item.data.vertices:
            point = to_world @ vertex.co
            horizontal = arguments.widen
            if matched:
                # Smoothstep from the base factor up to the full factor, so a
                # fattened trunk does not drag its root flare out with it.
                blend = min(max((point.z - ground) / height / ramp, 0.0), 1.0)
                blend = blend * blend * (3.0 - 2.0 * blend)
                horizontal *= (
                    arguments.thicken_base
                    + (arguments.thicken - arguments.thicken_base) * blend
                )
            point.x = centre_x + (point.x - centre_x) * horizontal
            point.y = centre_y + (point.y - centre_y) * horizontal
            point.z = ground + (point.z - ground) * arguments.squash
            vertex.co = to_local @ point
        item.data.update()


def dome_caps(item: bpy.types.Object, arguments: argparse.Namespace) -> int:
    """Conform cap geometry to a dome of revolution about its own stem.

    Each connected island is one mushroom. Faces using a --dome-material are
    the cap; whatever else the island contains is the stem, and its centre
    gives the axis so a lopsided cap re-centres over the thing holding it up.
    Every cap vertex is then pulled toward the superellipse profile
    (r/R)^p + (z/H)^p = 1, which circularises each cross-section and drags a
    hooked tip back to the crown.
    """
    if arguments.dome <= 0.0 or not arguments.dome_material:
        return 0

    needle = arguments.dome_material.lower()
    materials = list(item.data.materials)
    mesh = bmesh.new()
    mesh.from_mesh(item.data)
    mesh.transform(item.matrix_world)

    extent = max(
        (
            max(v.co[axis] for v in mesh.verts) - min(v.co[axis] for v in mesh.verts)
            for axis in range(3)
        ),
        default=1.0,
    )
    bmesh.ops.remove_doubles(mesh, verts=mesh.verts[:], dist=extent * 5.0e-4)
    mesh.verts.ensure_lookup_table()
    mesh.faces.ensure_lookup_table()

    cap_vertices = set()
    for face in mesh.faces:
        material = (
            materials[face.material_index]
            if face.material_index < len(materials)
            else None
        )
        if material is not None and needle in material.name.lower():
            cap_vertices.update(face.verts)

    seen: set = set()
    moved = 0
    for start in mesh.verts:
        if start in seen:
            continue
        stack = [start]
        seen.add(start)
        island = []
        while stack:
            current = stack.pop()
            island.append(current)
            for edge in current.link_edges:
                other = edge.other_vert(current)
                if other not in seen:
                    seen.add(other)
                    stack.append(other)

        caps = [vertex for vertex in island if vertex in cap_vertices]
        stems = [vertex for vertex in island if vertex not in cap_vertices]
        if len(caps) < 8:
            continue

        anchor = stems or caps
        centre_x = sum(vertex.co.x for vertex in anchor) / len(anchor)
        centre_y = sum(vertex.co.y for vertex in anchor) / len(anchor)
        base = min(vertex.co.z for vertex in caps)
        height = max(max(vertex.co.z for vertex in caps) - base, 1.0e-6)
        power = max(arguments.dome_power, 1.0e-3)

        # The brim sets the radius. Using the cap's max would hand every brim
        # vertex the reach of the droop's far tip and flatten it to a pancake,
        # so take the median across the lowest quarter of the cap instead.
        brim = sorted(
            math.hypot(vertex.co.x - centre_x, vertex.co.y - centre_y)
            for vertex in caps
            if (vertex.co.z - base) / height < 0.25
        )
        if not brim:
            continue
        radius = brim[len(brim) // 2] * arguments.dome_radius

        # A generated hat is far taller than a Garden Galaxy cap; squash the
        # whole cap toward the target aspect before conforming it.
        if arguments.dome_aspect > 0.0:
            target_height = radius * arguments.dome_aspect
            squeeze = 1.0 + (target_height / height - 1.0) * arguments.dome
            for vertex in caps:
                vertex.co.z = base + (vertex.co.z - base) * squeeze
            for vertex in stems:
                if vertex.co.z > base:
                    vertex.co.z = base + (vertex.co.z - base) * squeeze
            height = max(height * squeeze, 1.0e-6)

        for vertex in caps:
            fraction = min(max((vertex.co.z - base) / height, 0.0), 1.0)
            target = radius * max(0.0, 1.0 - fraction**power) ** (1.0 / power)
            offset_x = vertex.co.x - centre_x
            offset_y = vertex.co.y - centre_y
            current = math.hypot(offset_x, offset_y)
            if current < 1.0e-9:
                continue
            blended = current + (target - current) * arguments.dome
            vertex.co.x = centre_x + offset_x / current * blended
            vertex.co.y = centre_y + offset_y / current * blended
            moved += 1

    mesh.transform(item.matrix_world.inverted())
    mesh.to_mesh(item.data)
    mesh.free()
    item.data.update()
    return moved


def normalise_height(original_height: float) -> None:
    """Undo the size change squashing caused, keeping only the shape change."""
    minimum, maximum = bounds()
    height = maximum.z - minimum.z
    if height <= 1.0e-6 or original_height <= 1.0e-6:
        return
    factor = original_height / height
    centre_x = (minimum.x + maximum.x) * 0.5
    centre_y = (minimum.y + maximum.y) * 0.5
    ground = minimum.z
    for item in scene_meshes():
        to_world = item.matrix_world
        to_local = to_world.inverted()
        for vertex in item.data.vertices:
            point = to_world @ vertex.co
            point.x = centre_x + (point.x - centre_x) * factor
            point.y = centre_y + (point.y - centre_y) * factor
            point.z = ground + (point.z - ground) * factor
            vertex.co = to_local @ point
        item.data.update()


def slot_for(item: bpy.types.Object, name: str) -> int | None:
    """Index of a material on this object, appending it if the file has it."""
    for index, material in enumerate(item.data.materials):
        if material is not None and material.name == name:
            return index
    material = bpy.data.materials.get(name)
    if material is None:
        return None
    item.data.materials.append(material)
    return len(item.data.materials) - 1


def retone(
    item: bpy.types.Object,
    arguments: argparse.Namespace,
    axis: Vector,
    stem_ceiling: float,
) -> dict:
    """Assign materials from final geometry: stem by radius, tone by normal.

    Runs after the geometry stages on purpose. Limited dissolve is delimited
    by material, so recolouring first would fence off the very triangles the
    chunk pass needs to merge.
    """
    changes = {"stem": 0, "tone": 0}
    wants_stem = bool(arguments.stem_material)
    ramp = list(arguments.tone_ramp)
    toned = not arguments.tone_match or arguments.tone_match.lower() in item.name.lower()
    if not wants_stem and not (ramp and toned):
        return changes

    stem_index = slot_for(item, arguments.stem_material) if wants_stem else None
    ramp_indices = [slot_for(item, name) for name in ramp] if toned else []
    ramp_indices = [index for index in ramp_indices if index is not None]
    ramp_names = set(ramp)

    to_world = item.matrix_world
    radii = [
        (to_world @ vertex.co - axis).xy.length for vertex in item.data.vertices
    ]
    max_radius = max(radii) if radii else 0.0
    cutoff = max_radius * arguments.stem_radius

    for polygon in item.data.polygons:
        centre = to_world @ polygon.center
        if (
            stem_index is not None
            and centre.z < stem_ceiling
            and (centre - axis).xy.length < cutoff
        ):
            polygon.material_index = stem_index
            changes["stem"] += 1
            continue
        if not ramp_indices:
            continue
        current = item.data.materials[polygon.material_index]
        if current is None or current.name not in ramp_names:
            continue
        normal = (to_world.to_3x3() @ polygon.normal).normalized()
        if normal.z > 0.35:
            polygon.material_index = ramp_indices[0]
        elif normal.z > -0.15 or len(ramp_indices) < 3:
            polygon.material_index = ramp_indices[min(1, len(ramp_indices) - 1)]
        else:
            polygon.material_index = ramp_indices[-1]
        changes["tone"] += 1
    item.data.update()
    return changes


def chunk_object(item: bpy.types.Object, arguments: argparse.Namespace) -> None:
    mesh = bmesh.new()
    mesh.from_mesh(item.data)

    points = [vertex.co for vertex in mesh.verts]
    if not points:
        mesh.free()
        return
    size = Vector(
        tuple(
            max(p[axis] for p in points) - min(p[axis] for p in points)
            for axis in range(3)
        )
    )
    diagonal = max(size.length, 1.0e-6)

    bmesh.ops.remove_doubles(mesh, verts=mesh.verts[:], dist=diagonal * 5.0e-4)
    bmesh.ops.recalc_face_normals(mesh, faces=mesh.faces[:])

    if arguments.dissolve > 0.0:
        bmesh.ops.dissolve_limit(
            mesh,
            angle_limit=math.radians(arguments.dissolve),
            use_dissolve_boundaries=False,
            verts=mesh.verts[:],
            edges=mesh.edges[:],
            delimit={"MATERIAL"},
        )

    # Planar faces flatten each dissolved region into a true plane. That is
    # the chunky crate read, and it is exactly wrong for a rounded mass: the
    # dome becomes a polyhedron and smooth normals over it look dented.
    if arguments.planarize > 0 and arguments.shading != "smooth":
        bmesh.ops.planar_faces(
            mesh,
            faces=mesh.faces[:],
            iterations=arguments.planarize,
            factor=1.0,
        )

    if arguments.relax > 0.0:
        for _ in range(max(1, arguments.relax_iterations)):
            bmesh.ops.smooth_vert(
                mesh,
                verts=mesh.verts[:],
                factor=arguments.relax,
                use_axis_x=True,
                use_axis_y=True,
                use_axis_z=True,
            )

    bmesh.ops.triangulate(mesh, faces=[f for f in mesh.faces if len(f.verts) > 4])
    mesh.to_mesh(item.data)
    mesh.free()
    item.data.update()


def apply_modifiers(item: bpy.types.Object, arguments: argparse.Namespace) -> None:
    smooth = arguments.shading == "smooth"
    bpy.context.view_layer.objects.active = item
    if arguments.subdivide > 0:
        # Smooth shading cannot hide a coarse dome; the banding is the mesh,
        # not the normals. The firepit reads clean because its forms are
        # dense. Subdividing buys that density before anything else runs.
        subsurf = item.modifiers.new("SumaSubdivide", "SUBSURF")
        subsurf.subdivision_type = "CATMULL_CLARK"
        subsurf.levels = arguments.subdivide
        subsurf.render_levels = arguments.subdivide
        bpy.ops.object.modifier_apply(modifier=subsurf.name)
    if arguments.bevel > 0.0:
        bevel = item.modifiers.new("SumaChamfer", "BEVEL")
        bevel.width = arguments.bevel
        bevel.segments = max(1, arguments.bevel_segments)
        bevel.limit_method = "ANGLE"
        bevel.angle_limit = math.radians(25.0)
        # Hardened bevel normals flat-shade every chamfer. On a rounded mass
        # that prints a hard ring around each one.
        bevel.harden_normals = not smooth
        bevel.miter_outer = "MITER_ARC"
        bevel.use_clamp_overlap = True
        # harden_normals needs smooth shading present to write into.
        bpy.ops.object.shade_smooth()
        bpy.ops.object.modifier_apply(modifier=bevel.name)

    if not smooth:
        # Weighted normals bias shading toward the largest faces to keep
        # planes crisp. A rounded mass wants the plain averaged normal.
        weighted = item.modifiers.new("SumaWeightedNormals", "WEIGHTED_NORMAL")
        weighted.keep_sharp = True
        weighted.weight = 60
        bpy.ops.object.modifier_apply(modifier=weighted.name)


def main() -> None:
    arguments = parse_args()
    source = arguments.source.resolve()
    if not source.is_file():
        raise SystemExit(f"Missing source GLB: {source}")

    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(source))
    before = fingerprint()
    before_min, before_max = bounds()

    reproportion(arguments)
    domed = 0
    for item in scene_meshes():
        domed += dome_caps(item, arguments)
    for item in scene_meshes():
        chunk_object(item, arguments)

    bpy.ops.object.select_all(action="DESELECT")
    for item in scene_meshes():
        item.select_set(True)
        apply_modifiers(item, arguments)
        item.select_set(False)

    # Auto smooth marks every edge past the angle as sharp. A chunky dome has
    # plenty of those, so a smooth asset takes the full 180 and shades as one
    # continuous surface -- which is what makes the firepit read clean.
    shading_angle = 180.0 if arguments.shading == "smooth" else arguments.smooth_angle
    for item in scene_meshes():
        bpy.context.view_layer.objects.active = item
        bpy.ops.object.shade_auto_smooth(angle=math.radians(shading_angle))

    if arguments.preserve_height:
        normalise_height(before["dimensions"][2])

    recoloured = {"stem": 0, "tone": 0}
    stage_minimum, stage_maximum = bounds()
    axis = Vector(
        (
            (stage_minimum.x + stage_maximum.x) * 0.5,
            (stage_minimum.y + stage_maximum.y) * 0.5,
            0.0,
        )
    )
    stem_ceiling = stage_minimum.z + (stage_maximum.z - stage_minimum.z) * arguments.stem_height
    for item in scene_meshes():
        changes = retone(item, arguments, axis, stem_ceiling)
        recoloured["stem"] += changes["stem"]
        recoloured["tone"] += changes["tone"]

    after = fingerprint()
    after_min, after_max = bounds()
    drift = max(
        max(abs(after_min[axis] - before_min[axis]) for axis in range(3)),
        max(abs(after_max[axis] - before_max[axis]) for axis in range(3)),
    )

    arguments.output.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(
        filepath=str(arguments.output.resolve()),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_skins=False,
        export_lights=False,
        export_cameras=False,
    )

    report = {
        "source": str(source),
        "output": str(arguments.output),
        "settings": {
            "dissolve": arguments.dissolve,
            "planarize": arguments.planarize,
            "relax": arguments.relax,
            "bevel": arguments.bevel,
            "bevel_segments": arguments.bevel_segments,
            "widen": arguments.widen,
            "squash": arguments.squash,
            "thicken": arguments.thicken,
            "thicken_base": arguments.thicken_base,
            "thicken_ramp": arguments.thicken_ramp,
            "shading": arguments.shading,
            "subdivide": arguments.subdivide,
            "preserve_height": arguments.preserve_height,
            "stem_material": arguments.stem_material,
            "tone_ramp": list(arguments.tone_ramp),
        },
        "cap_vertices_domed": domed,
        "faces_recoloured": recoloured,
        "before": before,
        "after": after,
        "silhouette_drift_metres": round(drift, 5),
    }
    if arguments.report:
        arguments.report.parent.mkdir(parents=True, exist_ok=True)
        arguments.report.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("CHUNK_PASS_REPORT=" + json.dumps(report))


if __name__ == "__main__":
    main()
