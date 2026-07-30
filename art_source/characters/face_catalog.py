"""ACNH-style face part catalog for the Suma character master build.

Eyes and mouths are flat "sticker" decals: filled 2D silhouettes triangulated,
subdivided, and shrinkwrap-projected onto the head so they hug the skin like
Animal Crossing's face textures — never bulging 3D eyeballs. Noses stay small
3D shapes (ACNH noses are 3D too). Hair styles reuse the scalp-shell +
clay-mass approach of the default swoop.

This module is imported by build_character_master.py via importlib and only
uses the helpers passed in through `ctx` plus bpy/bmesh directly. All shapes
are original designs in the spirit of round, friendly cozy-game faces.

Coordinate space: model space of the master build (ground z = -0.435,
front = -Y, +X = character's left = viewer's right in a front render).
"""

from __future__ import annotations

from math import atan2, cos, pi, radians, sin
from typing import Callable

import bmesh
import bpy

# Decals start on this plane in front of the face and are projected back (+Y)
# onto the head surface.
DECAL_PLANE_Y = -0.30
# Distance decals float off the skin, and per-layer step so stacked layers
# (pupil over sclera, highlight over pupil) never z-fight.
BASE_OFFSET = 0.0018
LAYER_STEP = 0.0014

EYE_X = 0.048
EYE_Z = 0.246
MOUTH_Z = 0.150
NOSE_Z = 0.217


# ------------------------------------------------------------- 2D outlines

def _sgn(value: float) -> float:
    return -1.0 if value < 0.0 else 1.0


def _ellipse(
    cx: float,
    cz: float,
    rx: float,
    rz: float,
    n: int = 48,
    rot_deg: float = 0.0,
    exp: float = 2.0,
    clamp_top: float | None = None,
    clamp_bottom: float | None = None,
) -> list[tuple[float, float]]:
    """Superellipse outline. exp=2 is a plain ellipse; lower is pointier
    (almond), higher is boxier. Clamps flatten lids after rotation."""
    rot = radians(rot_deg)
    points = []
    for i in range(n):
        t = 2.0 * pi * i / n
        c, s = cos(t), sin(t)
        u = rx * _sgn(c) * abs(c) ** (2.0 / exp)
        v = rz * _sgn(s) * abs(s) ** (2.0 / exp)
        ur = u * cos(rot) - v * sin(rot)
        vr = u * sin(rot) + v * cos(rot)
        if clamp_top is not None:
            vr = min(vr, clamp_top)
        if clamp_bottom is not None:
            vr = max(vr, clamp_bottom)
        points.append((cx + ur, cz + vr))
    return points


def _arc3(
    p0: tuple[float, float],
    mid: tuple[float, float],
    p1: tuple[float, float],
    n: int = 24,
) -> list[tuple[float, float]]:
    """Quadratic arc passing through three points."""
    control = (
        2.0 * mid[0] - 0.5 * (p0[0] + p1[0]),
        2.0 * mid[1] - 0.5 * (p0[1] + p1[1]),
    )
    points = []
    for i in range(n + 1):
        t = i / n
        omt = 1.0 - t
        points.append(
            (
                omt * omt * p0[0] + 2 * omt * t * control[0] + t * t * p1[0],
                omt * omt * p0[1] + 2 * omt * t * control[1] + t * t * p1[1],
            )
        )
    return points


def _dedupe(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    result: list[tuple[float, float]] = []
    for point in points:
        if result and abs(point[0] - result[-1][0]) < 1e-6 and abs(
            point[1] - result[-1][1]
        ) < 1e-6:
            continue
        result.append(point)
    if (
        len(result) > 1
        and abs(result[0][0] - result[-1][0]) < 1e-6
        and abs(result[0][1] - result[-1][1]) < 1e-6
    ):
        result.pop()
    return result


def _stroke(
    path: list[tuple[float, float]], width: float, cap_n: int = 8
) -> list[tuple[float, float]]:
    """Closed ribbon outline around a polyline, with rounded caps."""
    path = _dedupe(path)
    half = width / 2.0
    tangents = []
    for i in range(len(path)):
        prev_point = path[max(i - 1, 0)]
        next_point = path[min(i + 1, len(path) - 1)]
        dx, dz = next_point[0] - prev_point[0], next_point[1] - prev_point[1]
        length = max((dx * dx + dz * dz) ** 0.5, 1e-9)
        tangents.append((dx / length, dz / length))
    normals = [(-t[1], t[0]) for t in tangents]
    left = [
        (p[0] + n[0] * half, p[1] + n[1] * half)
        for p, n in zip(path, normals)
    ]
    right = [
        (p[0] - n[0] * half, p[1] - n[1] * half)
        for p, n in zip(path, normals)
    ]
    end_angle = atan2(normals[-1][1], normals[-1][0])
    start_angle = atan2(normals[0][1], normals[0][0])
    end_cap = [
        (
            path[-1][0] + half * cos(end_angle - pi * k / (cap_n + 1)),
            path[-1][1] + half * sin(end_angle - pi * k / (cap_n + 1)),
        )
        for k in range(1, cap_n + 1)
    ]
    start_cap = [
        (
            path[0][0] + half * cos(start_angle + pi + -pi * k / (cap_n + 1)),
            path[0][1] + half * sin(start_angle + pi + -pi * k / (cap_n + 1)),
        )
        for k in range(1, cap_n + 1)
    ]
    return left + end_cap + list(reversed(right)) + start_cap


def _circle(cx: float, cz: float, r: float, n: int = 28) -> list:
    return _ellipse(cx, cz, r, r, n=n)


def _ensure_ccw(points: list[tuple[float, float]]) -> list[tuple[float, float]]:
    """CCW in (x, z) makes the filled face's normal point -Y (to the viewer)."""
    area = 0.0
    for i in range(len(points)):
        x0, z0 = points[i]
        x1, z1 = points[(i + 1) % len(points)]
        area += x0 * z1 - x1 * z0
    return points if area > 0.0 else list(reversed(points))


# ------------------------------------------------------------- decal meshes

def _fill_outline(name: str, outline: list[tuple[float, float]]) -> bpy.types.Object:
    outline = _ensure_ccw(_dedupe(outline))
    mesh = bpy.data.meshes.new(f"{name}Mesh")
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    bm = bmesh.new()
    verts = [bm.verts.new((x, DECAL_PLANE_Y, z)) for x, z in outline]
    bm.faces.new(verts)
    bmesh.ops.triangulate(bm, faces=list(bm.faces), ngon_method="EAR_CLIP")
    # Interior vertices so the sheet can follow the head's curvature once
    # projected; without them large triangles would sink under the convex face.
    for _ in range(2):
        bmesh.ops.subdivide_edges(
            bm, edges=list(bm.edges), cuts=1, use_grid_fill=True
        )
    bm.to_mesh(mesh)
    bm.free()
    return obj


def _project_on_face(
    ctx: dict, obj: bpy.types.Object, offset: float
) -> None:
    """Drape the flat decal onto the head: every vertex is ray-cast from the
    decal plane toward the face (+Y) and rests `offset` in front of the skin.
    Manual ray casts instead of a Shrinkwrap modifier so the offset direction
    is unambiguous (the modifier's project offset lands behind the skin)."""
    depsgraph = bpy.context.evaluated_depsgraph_get()
    body_eval = ctx["body"].evaluated_get(depsgraph)
    # The source head carries a narrow mouth-cavity slot around x=0 in the
    # lower face where a straight ray passes clean through the skin. Nearby
    # samples bridge such gaps so decals drape across like a sticker.
    probes = [
        (0.0, 0.0),
        (0.004, 0.0), (-0.004, 0.0), (0.008, 0.0), (-0.008, 0.0),
        (0.012, 0.0), (-0.012, 0.0), (0.020, 0.0), (-0.020, 0.0),
        (0.028, 0.0), (-0.028, 0.0),
        (0.0, 0.010), (0.0, 0.020), (0.020, 0.010), (-0.020, 0.010),
    ]
    misses = 0
    for vert in obj.data.vertices:
        for dx, dz in probes:
            hit, location, _normal, _index = body_eval.ray_cast(
                (vert.co.x + dx, DECAL_PLANE_Y, vert.co.z + dz),
                (0.0, 1.0, 0.0),
            )
            if hit:
                vert.co.y = location.y - offset
                break
        else:
            misses += 1
    if misses:
        print(f"DECAL_PROJECT_MISS {obj.name} {misses}/{len(obj.data.vertices)}")


def _decal_part(
    ctx,
    name: str,
    layers: list[tuple[list[tuple[float, float]], str, int]],
) -> bpy.types.Object:
    """layers: (outline, material key, stack level). Level 0 hugs the skin,
    higher levels float slightly above the previous ones."""
    objs = []
    for index, (outline, material_key, level) in enumerate(layers):
        obj = _fill_outline(f"{name}_L{index}", outline)
        _project_on_face(ctx, obj, BASE_OFFSET + level * LAYER_STEP)
        material = ctx["materials"][material_key]
        obj.data.materials.append(material)
        for polygon in obj.data.polygons:
            polygon.material_index = 0
            polygon.use_smooth = True
        objs.append(obj)
    return ctx["join_objects"](name, objs)


# --------------------------------------------------------------- eye styles

def _place_eye(
    outline: list[tuple[float, float]], side: float
) -> list[tuple[float, float]]:
    """Eye-local (u, v): +u = toward the temple (outward), +v = up. side=+1 is
    the character's left (+X) eye; mirroring keeps asymmetric details (nasal
    highlights, outer lashes) correct on both eyes."""
    if side > 0.0:
        return [(EYE_X + u, EYE_Z + v) for u, v in outline]
    return [(-EYE_X - u, EYE_Z + v) for u, v in reversed(outline)]


def _eye_pair_layers(
    local_layers: list[tuple[list[tuple[float, float]], str, int]]
) -> list[tuple[list[tuple[float, float]], str, int]]:
    layers = []
    for side in (1.0, -1.0):
        for outline, material_key, level in local_layers:
            layers.append((_place_eye(outline, side), material_key, level))
    return layers


def _lashes(
    base_rx: float, base_rz: float, angles_deg: list[float], length: float
) -> list[tuple[list[tuple[float, float]], str, int]]:
    """Short strokes radiating from the top-outer rim (u > 0)."""
    layers = []
    for angle_deg in angles_deg:
        a = radians(angle_deg)
        u0, v0 = base_rx * cos(a) * 0.92, base_rz * sin(a) * 0.92
        u1, v1 = u0 + cos(a) * length, v0 + sin(a) * length * 0.75
        layers.append((_stroke([(u0, v0), (u1, v1)], 0.0034), "eyes", 0))
    return layers


def build_eye_styles(ctx) -> dict[str, dict]:
    """stem -> {display, layers}. First entry is the default."""
    oval = _ellipse(0, 0, 0.0165, 0.0300)
    shine_hi = (_circle(-0.0045, 0.0125, 0.0052), "highlight", 1)
    shine_lo = (_circle(0.005, -0.0125, 0.0028), "highlight", 1)

    styles: dict[str, dict] = {}
    styles["eyes_oval_pair"] = {
        "display": "Warm Ovals",
        "layers": [(oval, "eyes", 0), shine_hi, shine_lo],
    }
    styles["eyes_dot_pair"] = {
        "display": "Friendly Dots",
        "layers": [
            (_circle(0, 0, 0.0135), "eyes", 0),
            (_circle(-0.004, 0.005, 0.0045), "highlight", 1),
        ],
    }
    styles["eyes_sleepy_pair"] = {
        "display": "Sleepy",
        "layers": [
            (_ellipse(0, 0, 0.0175, 0.028, clamp_top=0.008), "eyes", 0),
            (_circle(-0.004, -0.003, 0.0034), "highlight", 1),
        ],
    }
    styles["eyes_happy_pair"] = {
        "display": "Happy Arcs",
        "layers": [
            (
                _stroke(
                    _arc3((-0.015, -0.006), (0.0, 0.010), (0.015, -0.006)),
                    0.0075,
                ),
                "eyes",
                0,
            )
        ],
    }
    styles["eyes_lash_pair"] = {
        "display": "Long Lashes",
        "layers": [(oval, "eyes", 0), shine_hi]
        + _lashes(0.0165, 0.0300, [28.0, 52.0, 76.0], 0.0105),
    }
    styles["eyes_glance_pair"] = {
        "display": "Side Glance",
        "layers": [
            (_ellipse(0, 0, 0.0165, 0.0300), "eye_white", 0),
            (_ellipse(-0.006, 0, 0.0085, 0.0165), "eyes", 1),
            (_circle(-0.008, 0.007, 0.0035), "highlight", 2),
        ],
    }
    styles["eyes_sparkle_pair"] = {
        "display": "Sparkles",
        "layers": [
            (_ellipse(0, 0, 0.018, 0.032), "eyes", 0),
            (_circle(-0.005, 0.012, 0.007), "highlight", 1),
            (_circle(0.006, -0.010, 0.0038), "highlight", 1),
        ],
    }
    styles["eyes_almond_pair"] = {
        "display": "Almond",
        "layers": [
            (_ellipse(0, 0, 0.019, 0.026, rot_deg=-8.0, exp=1.45), "eyes", 0),
            (_circle(-0.004, 0.009, 0.004), "highlight", 1),
        ],
    }
    styles["eyes_droop_pair"] = {
        "display": "Gentle Droop",
        "layers": [
            (_ellipse(0, 0, 0.0155, 0.028, rot_deg=-14.0), "eyes", 0),
            (_circle(-0.0045, 0.009, 0.0042), "highlight", 1),
        ],
    }
    styles["eyes_wide_pair"] = {
        "display": "Wide Awake",
        "layers": [
            (_ellipse(0, 0, 0.017, 0.031), "eye_white", 0),
            (_ellipse(0, 0, 0.012, 0.022), "eyes", 1),
            (_circle(-0.004, 0.008, 0.0045), "highlight", 2),
        ],
    }
    return styles


# -------------------------------------------------------------- mouth styles

def _mouth(outline_local: list[tuple[float, float]]) -> list:
    return [(x, MOUTH_Z + v) for x, v in outline_local]


def build_mouth_styles(ctx) -> dict[str, dict]:
    open_smile = _dedupe(
        _arc3((-0.016, 0.003), (0.0, 0.0005), (0.016, 0.003))
        + _arc3((0.016, 0.003), (0.0, -0.0145), (-0.016, 0.003))
    )
    grin_open = _dedupe(
        _arc3((-0.015, 0.0035), (0.0, 0.001), (0.015, 0.0035))
        + _arc3((0.015, 0.0035), (0.0, -0.0125), (-0.015, 0.0035))
    )

    styles: dict[str, dict] = {}
    styles["mouth_smile"] = {
        "display": "Gentle Smile",
        "layers": [
            (
                _mouth(
                    _stroke(
                        _arc3((-0.014, 0.005), (0.0, -0.0035), (0.014, 0.005)),
                        0.0058,
                    )
                ),
                "mouth",
                0,
            )
        ],
    }
    styles["mouth_grin"] = {
        "display": "Big Grin",
        "layers": [
            (
                _mouth(
                    _stroke(
                        _arc3((-0.020, 0.008), (0.0, -0.0055), (0.020, 0.008)),
                        0.006,
                    )
                ),
                "mouth",
                0,
            )
        ],
    }
    styles["mouth_open_smile"] = {
        "display": "Open Smile",
        "layers": [
            (_mouth(open_smile), "mouth_inner", 0),
            (_mouth(_ellipse(0.0, -0.0085, 0.0085, 0.0048)), "tongue", 1),
        ],
    }
    styles["mouth_neutral"] = {
        "display": "Soft Line",
        "layers": [
            (
                _mouth(
                    _stroke(
                        _arc3((-0.011, 0.001), (0.0, -0.0005), (0.011, 0.001)),
                        0.005,
                    )
                ),
                "mouth",
                0,
            )
        ],
    }
    styles["mouth_cat"] = {
        "display": "Little W",
        "layers": [
            (
                _mouth(
                    _stroke(
                        _dedupe(
                            _arc3(
                                (-0.014, 0.004), (-0.007, -0.004), (0.0, 0.0025)
                            )
                            + _arc3(
                                (0.0, 0.0025), (0.007, -0.004), (0.014, 0.004)
                            )
                        ),
                        0.0048,
                    )
                ),
                "mouth",
                0,
            )
        ],
    }
    styles["mouth_pout"] = {
        "display": "Pout",
        "layers": [
            (
                _mouth(
                    _stroke(
                        _arc3((-0.011, -0.0025), (0.0, 0.0045), (0.011, -0.0025)),
                        0.0055,
                    )
                ),
                "mouth",
                0,
            )
        ],
    }
    styles["mouth_oh"] = {
        "display": "Surprised",
        "layers": [(_mouth(_ellipse(0.0, -0.001, 0.0075, 0.0095)), "mouth_inner", 0)],
    }
    styles["mouth_smirk"] = {
        "display": "Smirk",
        "layers": [
            (
                _mouth(
                    _stroke(
                        _arc3((-0.012, 0.001), (0.002, -0.002), (0.013, 0.0065)),
                        0.0052,
                    )
                ),
                "mouth",
                0,
            )
        ],
    }
    styles["mouth_tooth"] = {
        "display": "Cheeky Grin",
        "layers": [
            (_mouth(grin_open), "mouth_inner", 0),
            (
                _mouth(_ellipse(0.0, -0.0012, 0.0045, 0.0035, exp=3.0)),
                "tooth",
                1,
            ),
        ],
    }
    styles["mouth_shy"] = {
        "display": "Shy Smile",
        "layers": [
            (
                _mouth(
                    _stroke(
                        _arc3((-0.008, 0.0025), (0.0, -0.001), (0.008, 0.0025)),
                        0.0048,
                    )
                ),
                "mouth",
                0,
            )
        ],
    }
    return styles


# --------------------------------------------------------------- nose styles

def _sphere_nose(
    ctx, name: str, scale: tuple[float, float, float], z: float, y: float
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=24, ring_count=16, location=(0.0, y, z)
    )
    nose = bpy.context.object
    nose.name = name
    nose.scale = scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    ctx["assign_material"](nose, ctx["materials"]["skin"])
    ctx["shade_smooth"](nose)
    return nose


def _fine_metaball(
    name: str,
    elements: list[tuple[float, float, float, float]],
    resolution: float,
) -> bpy.types.Object:
    """metaball_object with a resolution suited to centimeter-scale features
    (the shared helper's 8 mm grid is too coarse for a nose)."""
    mball = bpy.data.metaballs.new(f"{name}Ball")
    mball.resolution = resolution
    mball.render_resolution = resolution
    obj = bpy.data.objects.new(name, mball)
    bpy.context.scene.collection.objects.link(obj)
    for x, y, z, r in elements:
        element = mball.elements.new()
        element.co = (x, y, z)
        element.radius = r
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    converted = bpy.context.object
    converted.name = name
    for polygon in converted.data.polygons:
        polygon.use_smooth = True
    return converted


def build_nose_styles(ctx) -> dict[str, dict]:
    """The default round nose keeps its master-build stem/name."""
    styles: dict[str, dict] = {}
    styles["nose_round"] = {
        "display": "Round Nose",
        "object": _sphere_nose(
            ctx, "NoseRound", (0.021, 0.025, 0.020), NOSE_Z - 0.006, -0.140
        ),
    }
    styles["nose_button"] = {
        "display": "Tiny Button",
        "object": _sphere_nose(
            ctx, "NoseButton", (0.0135, 0.016, 0.0125), NOSE_Z - 0.008, -0.138
        ),
    }
    triangle = _fine_metaball(
        "NoseTriangle",
        [
            (0.0075, -0.141, NOSE_Z + 0.002, 0.0105),
            (-0.0075, -0.141, NOSE_Z + 0.002, 0.0105),
            (0.0, -0.143, NOSE_Z - 0.010, 0.0085),
        ],
        0.0025,
    )
    ctx["remesh_smooth"](triangle, 0.0035, 0.3, 2, 700)
    ctx["assign_material"](triangle, ctx["materials"]["skin"])
    styles["nose_triangle"] = {"display": "Soft Triangle", "object": triangle}
    styles["nose_wide"] = {
        "display": "Wide Oval",
        "object": _sphere_nose(
            ctx, "NoseWide", (0.028, 0.018, 0.015), NOSE_Z - 0.006, -0.138
        ),
    }
    styles["nose_dot"] = {
        "display": "Little Dot",
        "object": _sphere_nose(
            ctx, "NoseDot", (0.0085, 0.010, 0.008), NOSE_Z - 0.008, -0.137
        ),
    }
    return styles


# --------------------------------------------------------------- hair styles

def _scalp_shell(
    ctx, name: str, hairline: Callable, thickness: float
) -> bpy.types.Object:
    body = ctx["body"]
    scalp = body.copy()
    scalp.data = body.data.copy()
    scalp.name = name
    bpy.context.scene.collection.objects.link(scalp)
    # Drop the armature binding the body copy inherits; hair is a rigid part.
    for modifier in list(scalp.modifiers):
        scalp.modifiers.remove(modifier)
    scalp.vertex_groups.clear()
    world = scalp.matrix_world.copy()
    scalp.parent = None
    scalp.matrix_world = world
    mesh = bmesh.new()
    mesh.from_mesh(scalp.data)
    doomed = [
        face
        for face in mesh.faces
        if face.calc_center_median().z < hairline(face.calc_center_median())
    ]
    bmesh.ops.delete(mesh, geom=doomed, context="FACES")
    mesh.to_mesh(scalp.data)
    mesh.free()
    solidify = scalp.modifiers.new("CapThickness", "SOLIDIFY")
    solidify.thickness = thickness
    solidify.offset = 1.0
    ctx["apply_modifier"](scalp, solidify)
    return scalp


def _cone(
    location: tuple[float, float, float],
    rotation: tuple[float, float, float],
    radius: float,
    depth: float,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cone_add(
        vertices=12,
        radius1=radius,
        radius2=0.0,
        depth=depth,
        location=location,
        rotation=tuple(radians(r) for r in rotation),
    )
    return bpy.context.object


def _hair_variant(
    ctx,
    name: str,
    hairline: Callable,
    thickness: float,
    blobs: list[tuple[float, float, float, float]],
    remesh: tuple[float, float, int, int],
    extras: list[bpy.types.Object] | None = None,
) -> bpy.types.Object:
    parts = [_scalp_shell(ctx, f"{name}Shell", hairline, thickness)]
    if blobs:
        parts.append(ctx["metaball_object"](f"{name}Mass", blobs))
    if extras:
        parts.extend(extras)
    hair = ctx["join_objects"](name, parts)
    ctx["remesh_smooth"](hair, *remesh)
    ctx["assign_material"](hair, ctx["materials"]["hair"])
    return hair


def build_hair_styles(ctx) -> dict[str, dict]:
    """Additional styles; the default swoop stays in the master build."""
    default_hairline = ctx["hairline_z"]

    def bob_hairline(center) -> float:
        # Open forehead in front, curtains over the ears and down the nape.
        if center.y < -0.075:
            return 0.318
        if center.y < -0.02:
            return 0.318 - (center.y + 0.075) * 2.6
        return 0.175

    def long_hairline(center) -> float:
        # Open forehead with a long back and soft side curtains.
        if center.y < -0.070:
            return 0.320
        if center.y < 0.015:
            return 0.320 - (center.y + 0.070) * 2.15
        return 0.145

    styles: dict[str, dict] = {}
    styles["hair_crop"] = {
        "display": "Neat Crop",
        "object": _hair_variant(
            ctx,
            "HairCrop",
            default_hairline,
            0.020,
            [
                (-0.055, -0.086, 0.336, 0.024),
                (-0.028, -0.090, 0.340, 0.024),
                (0.0, -0.091, 0.342, 0.024),
                (0.028, -0.090, 0.340, 0.024),
                (0.055, -0.086, 0.336, 0.024),
                (0.0, 0.020, 0.400, 0.062),
                (0.0, 0.050, 0.375, 0.058),
            ],
            (0.0085, 0.40, 3, 3200),
        ),
    }
    spikes = [
        _cone((0.0, -0.055, 0.415), (-20.0, 0.0, 0.0), 0.026, 0.085),
        _cone((0.052, -0.025, 0.412), (0.0, 25.0, 0.0), 0.026, 0.080),
        _cone((-0.052, -0.025, 0.412), (0.0, -25.0, 0.0), 0.026, 0.080),
        _cone((0.030, 0.045, 0.410), (18.0, 12.0, 0.0), 0.026, 0.078),
        _cone((-0.030, 0.045, 0.410), (18.0, -12.0, 0.0), 0.026, 0.078),
        _cone((0.0, 0.005, 0.425), (0.0, 0.0, 0.0), 0.028, 0.085),
    ]
    styles["hair_spiky"] = {
        "display": "Spiky",
        "object": _hair_variant(
            ctx,
            "HairSpiky",
            default_hairline,
            0.020,
            [(0.0, 0.010, 0.400, 0.058)],
            (0.008, 0.30, 2, 3600),
            extras=spikes,
        ),
    }
    styles["hair_bun"] = {
        "display": "Top Bun",
        "object": _hair_variant(
            ctx,
            "HairBun",
            default_hairline,
            0.018,
            [
                (0.0, 0.015, 0.395, 0.062),
                (0.0, 0.045, 0.455, 0.037),
                (0.0, 0.052, 0.475, 0.024),
            ],
            (0.008, 0.42, 3, 3200),
        ),
    }
    styles["hair_bob"] = {
        "display": "Cozy Bob",
        "object": _hair_variant(
            ctx,
            "HairBob",
            bob_hairline,
            0.026,
            [
                (-0.060, -0.088, 0.328, 0.022),
                (-0.020, -0.092, 0.332, 0.023),
                (0.020, -0.092, 0.332, 0.023),
                (0.060, -0.088, 0.328, 0.022),
                (0.0, 0.020, 0.398, 0.064),
            ],
            (0.009, 0.45, 4, 4200),
        ),
    }
    styles["hair_sidepart"] = {
        "display": "Side Part",
        "object": _hair_variant(
            ctx,
            "HairSidePart",
            default_hairline,
            0.020,
            [
                (-0.050, -0.092, 0.350, 0.030),
                (-0.018, -0.098, 0.365, 0.036),
                (0.020, -0.090, 0.392, 0.045),
                (0.060, -0.072, 0.405, 0.044),
                (0.0, 0.030, 0.402, 0.064),
            ],
            (0.0085, 0.42, 3, 3600),
        ),
    }
    styles["hair_ponytail"] = {
        "display": "Ponytail",
        "object": _hair_variant(
            ctx,
            "HairPonytail",
            default_hairline,
            0.020,
            [
                (0.0, 0.025, 0.402, 0.064),
                (0.0, 0.105, 0.365, 0.045),
                (0.0, 0.135, 0.320, 0.040),
                (0.0, 0.145, 0.274, 0.033),
            ],
            (0.0085, 0.40, 3, 4000),
        ),
    }
    styles["hair_twin_puffs"] = {
        "display": "Twin Puffs",
        "object": _hair_variant(
            ctx,
            "HairTwinPuffs",
            default_hairline,
            0.019,
            [
                (0.0, 0.020, 0.400, 0.062),
                (-0.112, 0.040, 0.350, 0.043),
                (-0.126, 0.050, 0.318, 0.036),
                (0.112, 0.040, 0.350, 0.043),
                (0.126, 0.050, 0.318, 0.036),
            ],
            (0.0085, 0.38, 3, 4200),
        ),
    }
    styles["hair_long_waves"] = {
        "display": "Long Waves",
        "object": _hair_variant(
            ctx,
            "HairLongWaves",
            long_hairline,
            0.025,
            [
                (0.0, 0.025, 0.397, 0.064),
                (-0.095, 0.010, 0.302, 0.040),
                (-0.105, 0.025, 0.245, 0.038),
                (-0.098, 0.040, 0.190, 0.034),
                (0.095, 0.010, 0.302, 0.040),
                (0.105, 0.025, 0.245, 0.038),
                (0.098, 0.040, 0.190, 0.034),
                (0.0, 0.105, 0.235, 0.050),
                (0.0, 0.115, 0.175, 0.042),
            ],
            (0.009, 0.45, 4, 5200),
        ),
    }
    return styles


# ------------------------------------------------------------------ catalog

SLOT_SOCKETS = {
    "EYES": "EyesSocket",
    "MOUTH": "MouthSocket",
    "NOSE": "NoseSocket",
    "HAIR": "HairSocket",
}


def build_catalog(ctx) -> dict[str, dict]:
    """Build every catalog part. Returns stem -> {object, slot, socket,
    display}. Insertion order per slot is the player-facing option order and
    the first entry of each slot is the default."""
    catalog: dict[str, dict] = {}
    for stem, spec in build_eye_styles(ctx).items():
        obj = _decal_part(ctx, f"Cat_{stem}", _eye_pair_layers(spec["layers"]))
        catalog[stem] = {
            "object": obj,
            "slot": "EYES",
            "socket": SLOT_SOCKETS["EYES"],
            "display": spec["display"],
        }
    for stem, spec in build_mouth_styles(ctx).items():
        obj = _decal_part(ctx, f"Cat_{stem}", spec["layers"])
        catalog[stem] = {
            "object": obj,
            "slot": "MOUTH",
            "socket": SLOT_SOCKETS["MOUTH"],
            "display": spec["display"],
        }
    for stem, spec in build_nose_styles(ctx).items():
        catalog[stem] = {
            "object": spec["object"],
            "slot": "NOSE",
            "socket": SLOT_SOCKETS["NOSE"],
            "display": spec["display"],
        }
    for stem, spec in build_hair_styles(ctx).items():
        catalog[stem] = {
            "object": spec["object"],
            "slot": "HAIR",
            "socket": SLOT_SOCKETS["HAIR"],
            "display": spec["display"],
        }
    return catalog
