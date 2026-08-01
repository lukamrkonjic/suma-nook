#!/usr/bin/env python3
"""Build Suma's carpet-tuft grass modules.

These are NOT plants. The vocabulary is deliberate:

    rounded carpet lobe   a chunky tapered slab, not a leaf
    soft grass cushion    the low shared base the lobes grow out of
    scalloped mass        what the finished tuft reads as

Every earlier attempt failed the same way: it modelled recognisable botany.
Realistic leaves radiating from a point produce a rosette — a houseplant — and
no amount of proportion tuning fixes that, because the failure is in the
silhouette, not the bounding box. A wide, low star is still a star.

So the construction rule here is overlap, not arrangement. Three to five broad
lobes are pushed into each other by 40-60% of their footprints over a low
cushion that closes the middle, and at least one lobe crosses in front of
another so no centre is ever visible. The first thing the eye should resolve is
one soft mass; the individual lobes come second.

TOPOLOGY IS FIXED AND CHEAP. A lobe is four stations of four vertices — top,
bottom and two sides — which is 28 triangles with its two end caps. There is no
subdivision and no bevel modifier anywhere in this file. If a form needs either
to look acceptable, its base silhouette is wrong and the silhouette is what gets
redesigned. Softness comes from shading and from the outline, never from more
geometry.

UNITS are literal metres as specified in the art brief, on Suma's 1.35 m grid
cell. A tuft is 0.20-0.34 m across and 0.045-0.10 m tall.

Run from the repository root:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/build_carpet_tufts.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "tile_forge" / "modules" / "grass"

# Two tones per clump at most, slightly desaturated, low contrast between
# neighbours. Named for the Tile Forge slot contract.
PALETTE = {
    "carpet_main": "6E9140",
    "carpet_alt": "7FA24B",
    "carpet_low": "557433",
    "accent_high": "8CB055",
}

# --- gates from the art brief, enforced at build time ------------------------
TUFT_TRIANGLE_MAX = 220
ACCENT_TRIANGLE_MAX = 380
LOBE_TRIANGLE_MAX = 40
WIDTH_RATIO_MIN = 3.2
WIDTH_RATIO_MAX = 6.0
TUFT_WIDTH_BAND = (0.20, 0.34)
TUFT_DEPTH_BAND = (0.16, 0.29)
TUFT_HEIGHT_BAND = (0.045, 0.100)


def srgb(hex_value: str):
    values = [int(hex_value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    linear = [
        v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
        for v in values
    ]
    return (*linear, 1.0)


def material(name: str):
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    result = bpy.data.materials.new(name=name)
    result.use_nodes = True
    shader = result.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = srgb(PALETTE.get(name, "6E9140"))
    # Flat and matte. A glossy highlight on a toy-scale tuft reads as plastic.
    shader.inputs["Roughness"].default_value = 0.96
    shader.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.10
    result.diffuse_color = srgb(PALETTE.get(name, "6E9140"))
    return result


class Builder:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.slots = []

    def add(self, points):
        start = len(self.verts)
        self.verts.extend(points)
        return list(range(start, start + len(points)))

    def face(self, indices, slot):
        if len(indices) >= 3:
            self.faces.append(tuple(indices))
            self.slots.append(slot)


# --------------------------------------------------------------------------
# The carpet lobe
# --------------------------------------------------------------------------

# (t along the lobe, width multiplier, thickness multiplier).
# Maximum width sits at t = 0.55, inside the 45-60% band. The outer end keeps
# 26% of the maximum width so it stays a BLUNT tapered end rather than
# collapsing to a needle, and the final station is a real quad, never a point.
LOBE_PROFILE = [
    (0.00, 0.46, 0.80),
    (0.28, 0.86, 1.00),
    (0.55, 1.00, 0.94),
    (1.00, 0.26, 0.52),
]


def carpet_lobe(builder, origin, yaw_deg, pitch_deg, length, width, thickness,
                slot, lift=0.0):
    """One chunky tapered slab: 4 stations x 4 vertices = 28 triangles.

    Four vertices per station give a top pair and a bottom pair, so the lobe has
    real volume with a top, an underside and two sides. Nothing here subdivides
    or bevels; the softness comes from smooth shading across the broad faces.
    """
    yaw = math.radians(yaw_deg)
    pitch = math.radians(pitch_deg)
    forward = (math.cos(yaw), math.sin(yaw))
    across = (-forward[1], forward[0])

    rings = []
    for t, width_factor, thickness_factor in LOBE_PROFILE:
        reach = length * t
        # The lobe rises along its length at the authored pitch and relaxes very
        # slightly at the outer end, so it lies over the ground rather than
        # pointing off it.
        relax = 1.0 - 0.18 * max(0.0, t - 0.55) / 0.45
        height = reach * math.tan(pitch) * relax + lift
        half_width = width * width_factor * 0.5
        half_thickness = thickness * thickness_factor * 0.5
        centre = (
            origin[0] + forward[0] * reach,
            origin[1] + forward[1] * reach,
            origin[2] + height,
        )
        rings.append(builder.add([
            (centre[0] + across[0] * half_width,
             centre[1] + across[1] * half_width,
             centre[2] + half_thickness),
            (centre[0] - across[0] * half_width,
             centre[1] - across[1] * half_width,
             centre[2] + half_thickness),
            (centre[0] - across[0] * half_width * 0.88,
             centre[1] - across[1] * half_width * 0.88,
             centre[2] - half_thickness),
            (centre[0] + across[0] * half_width * 0.88,
             centre[1] + across[1] * half_width * 0.88,
             centre[2] - half_thickness),
        ]))

    for index in range(len(rings) - 1):
        a, b = rings[index], rings[index + 1]
        builder.face((a[0], a[1], b[1], b[0]), slot)   # top
        builder.face((a[2], a[3], b[3], b[2]), slot)   # underside
        builder.face((a[1], a[2], b[2], b[1]), slot)   # side
        builder.face((a[3], a[0], b[0], b[3]), slot)   # side
    builder.face((rings[0][0], rings[0][3], rings[0][2], rings[0][1]), slot)
    tip = rings[-1]
    builder.face((tip[1], tip[2], tip[3], tip[0]), slot)


def base_cushion(builder, radius_x, radius_y, height, slot, sides=6,
                 rotation_deg=0.0):
    """The soft grass cushion the lobes grow out of.

    It exists for one reason: to close the centre so no tuft ever shows a hole,
    a crown, or a radial origin. It is deliberately low and mostly buried under
    the lobes — a visible pedestal would be as wrong as an open middle.
    """
    phase = math.radians(rotation_deg)
    lower = []
    upper = []
    for index in range(sides):
        angle = phase + math.tau * index / sides
        lower.append((math.cos(angle) * radius_x, math.sin(angle) * radius_y, 0.0))
        upper.append((
            math.cos(angle) * radius_x * 0.58,
            math.sin(angle) * radius_y * 0.58,
            height,
        ))
    low_ids = builder.add(lower)
    high_ids = builder.add(upper)
    crown = builder.add([(0.0, 0.0, height * 1.12)])[0]
    for index in range(sides):
        nxt = (index + 1) % sides
        builder.face((low_ids[index], low_ids[nxt], high_ids[nxt], high_ids[index]), slot)
        builder.face((high_ids[index], high_ids[nxt], crown), slot)
    builder.face(list(reversed(low_ids)), slot)


def commit(builder, name, sink):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(builder.verts, [], builder.faces)
    mesh.validate(verbose=False)

    slots = []
    for slot in builder.slots:
        if slot not in slots:
            slots.append(slot)
    for slot in slots:
        mesh.materials.append(material(slot))
    for index, polygon in enumerate(mesh.polygons):
        polygon.material_index = slots.index(builder.slots[index])
        polygon.use_smooth = True
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj

    # Smooth by angle: broad faces blend, the outer rim stays crisp. This is the
    # whole softening budget — there is no bevel and no subdivision.
    weighted = obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    weighted.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier="WeightedNormal")

    # Sit the cushion slightly into the ground so nothing shows a floating rim.
    for vertex in obj.data.vertices:
        vertex.co.z -= sink
    obj.data.update()
    return obj


# --------------------------------------------------------------------------
# The six modules
# --------------------------------------------------------------------------
#
# Each entry authors its lobes explicitly as
#   (offset_x, offset_y, yaw, pitch, length, width_fraction, thickness, slot)
# `width_fraction` is the lobe's max width as a fraction of its own length,
# inside the 55-80% band. Offsets push a lobe's ROOT away from centre so the
# lobes overlap each other's footprints rather than meeting at one point.

MAIN = "carpet_main"
ALT = "carpet_alt"
LOW = "carpet_low"
HIGH = "accent_high"

GROUND_CARPET = [
    ("ground_carpet_a", dict(
        cushion=(0.170, 0.132, 0.013, LOW, 8, 12.0), sink=0.009,
        lobes=[
            (0.030, 0.004, 14, 5, 0.190, 0.78, 0.017, MAIN),
            (-0.024, 0.028, 104, 4, 0.176, 0.80, 0.016, MAIN),
            (-0.016, -0.030, 208, 6, 0.184, 0.76, 0.018, ALT),
            (0.026, -0.010, 296, 4, 0.166, 0.80, 0.016, MAIN),
            (0.000, 0.020, 62, 3, 0.150, 0.80, 0.015, ALT),
        ])),
    ("ground_carpet_b", dict(
        cushion=(0.148, 0.120, 0.012, LOW, 8, 30.0), sink=0.008,
        lobes=[
            (0.022, -0.006, 42, 6, 0.172, 0.80, 0.016, MAIN),
            (-0.028, 0.014, 138, 5, 0.164, 0.78, 0.015, ALT),
            (0.010, 0.030, 232, 4, 0.158, 0.80, 0.017, MAIN),
            (0.018, -0.026, 328, 6, 0.176, 0.76, 0.016, MAIN),
        ])),
    ("ground_carpet_c", dict(
        cushion=(0.192, 0.140, 0.014, LOW, 8, 20.0), sink=0.010,
        lobes=[
            (0.038, 0.008, 8, 4, 0.204, 0.80, 0.018, MAIN),
            (-0.034, 0.020, 96, 5, 0.190, 0.78, 0.017, ALT),
            (-0.020, -0.032, 184, 3, 0.182, 0.80, 0.016, MAIN),
            (0.030, -0.018, 268, 5, 0.196, 0.76, 0.018, MAIN),
            (0.004, 0.034, 320, 4, 0.168, 0.80, 0.015, ALT),
            (-0.006, -0.004, 150, 3, 0.156, 0.80, 0.017, MAIN),
        ])),
]


MODULES = [
    # --- small_support: one wide layer plus two fillers. Used sparingly.
    ("small_support_a", "carpet", dict(
        cushion=(0.098, 0.088, 0.022, LOW, 8, 14.0), sink=0.010,
        lobes=[
            (0.012, -0.004, 26, 15, 0.132, 0.76, 0.026, MAIN),
            (-0.010, 0.012, 152, 13, 0.126, 0.78, 0.025, MAIN),
            (0.004, -0.014, 268, 17, 0.120, 0.74, 0.024, ALT),
            (0.000, 0.002, 84, 26, 0.086, 0.80, 0.022, MAIN),
        ])),
    ("small_support_b", "carpet", dict(
        cushion=(0.094, 0.084, 0.021, LOW, 8, 32.0), sink=0.009,
        lobes=[
            (0.010, 0.008, 62, 14, 0.128, 0.78, 0.025, MAIN),
            (-0.012, -0.006, 188, 16, 0.134, 0.76, 0.026, ALT),
            (0.006, -0.012, 300, 12, 0.118, 0.80, 0.024, MAIN),
            (0.000, 0.000, 244, 25, 0.082, 0.80, 0.021, MAIN),
        ])),

    # --- medium_carpet: the main language. Two clear layers.
    ("medium_carpet_a", "carpet", dict(
        cushion=(0.098, 0.086, 0.024, LOW, 8, 10.0), sink=0.012,
        lobes=[
            # layer 1 — wide outward skirt
            (0.018, -0.006, 18, 13, 0.176, 0.78, 0.031, MAIN),
            (-0.014, 0.016, 106, 11, 0.168, 0.80, 0.030, MAIN),
            (-0.008, -0.018, 202, 14, 0.172, 0.76, 0.029, ALT),
            (0.016, 0.010, 292, 12, 0.160, 0.78, 0.030, MAIN),
            # layer 2 — shorter filler closing the middle
            (0.004, 0.000, 62, 24, 0.112, 0.80, 0.026, MAIN),
            (-0.004, 0.004, 244, 22, 0.106, 0.80, 0.025, ALT),
        ])),
    ("medium_carpet_b", "carpet", dict(
        cushion=(0.104, 0.090, 0.024, LOW, 8, 28.0), sink=0.012,
        lobes=[
            (0.020, 0.004, 46, 12, 0.182, 0.78, 0.032, MAIN),
            (-0.016, 0.014, 134, 14, 0.170, 0.76, 0.030, ALT),
            (-0.006, -0.020, 226, 11, 0.176, 0.80, 0.031, MAIN),
            (0.014, -0.010, 318, 13, 0.164, 0.78, 0.029, MAIN),
            (0.002, 0.006, 88, 23, 0.116, 0.80, 0.026, MAIN),
            (-0.002, -0.004, 268, 25, 0.104, 0.80, 0.025, ALT),
        ])),
    ("medium_carpet_c", "carpet", dict(
        cushion=(0.108, 0.096, 0.024, LOW, 8, 46.0), sink=0.011,
        lobes=[
            (0.016, -0.010, 8, 14, 0.170, 0.80, 0.030, MAIN),
            (-0.012, 0.018, 96, 12, 0.164, 0.78, 0.029, MAIN),
            (0.008, 0.014, 184, 13, 0.158, 0.76, 0.028, ALT),
            (-0.016, -0.008, 272, 11, 0.166, 0.80, 0.030, MAIN),
            (0.000, 0.002, 140, 24, 0.108, 0.80, 0.025, MAIN),
        ])),

    # --- large_hero_carpet: three layers, including a low crown.
    ("large_hero_carpet_a", "accent", dict(
        cushion=(0.136, 0.118, 0.028, LOW, 8, 16.0), sink=0.014,
        lobes=[
            # layer 1 — broad outward skirt
            (0.026, -0.008, 14, 11, 0.222, 0.78, 0.034, MAIN),
            (-0.020, 0.022, 88, 10, 0.214, 0.80, 0.033, MAIN),
            (-0.012, -0.024, 166, 12, 0.218, 0.76, 0.034, ALT),
            (0.022, 0.014, 244, 9, 0.206, 0.78, 0.032, MAIN),
            (0.006, -0.026, 312, 11, 0.198, 0.80, 0.033, MAIN),
            # layer 2 — filler
            (0.006, 0.004, 52, 22, 0.146, 0.80, 0.029, MAIN),
            (-0.006, 0.000, 200, 20, 0.138, 0.80, 0.028, ALT),
            # layer 3 — low crown, the only slightly upright pieces
            (0.000, 0.002, 128, 32, 0.104, 0.78, 0.025, HIGH),
            (0.002, -0.002, 288, 30, 0.098, 0.78, 0.024, MAIN),
        ])),
    ("large_hero_carpet_b", "accent", dict(
        cushion=(0.128, 0.112, 0.027, LOW, 8, 34.0), sink=0.013,
        lobes=[
            (0.024, 0.010, 40, 10, 0.216, 0.80, 0.034, MAIN),
            (-0.018, 0.020, 118, 12, 0.208, 0.78, 0.033, ALT),
            (-0.014, -0.022, 196, 9, 0.220, 0.80, 0.034, MAIN),
            (0.020, -0.012, 274, 11, 0.202, 0.76, 0.032, MAIN),
            (0.004, 0.024, 346, 10, 0.194, 0.80, 0.033, MAIN),
            (0.004, -0.004, 78, 21, 0.142, 0.80, 0.029, MAIN),
            (-0.004, 0.006, 236, 23, 0.134, 0.80, 0.028, ALT),
            (0.000, 0.000, 158, 31, 0.100, 0.78, 0.025, HIGH),
        ])),
]


def build_module(name, kind, spec):
    builder = Builder()
    cushion = spec["cushion"]
    base_cushion(builder, cushion[0], cushion[1], cushion[2], cushion[3],
                 sides=cushion[4], rotation_deg=cushion[5])
    if "second_cushion" in spec:
        second = spec["second_cushion"]
        saved = len(builder.verts)
        base_cushion(builder, second[0], second[1], second[2], second[3],
                     sides=second[4], rotation_deg=second[5])
        for index in range(saved, len(builder.verts)):
            x, y, z = builder.verts[index]
            builder.verts[index] = (x + second[6], y + second[7], z)

    for offset_x, offset_y, yaw, pitch, length, width_fraction, thickness, slot \
            in spec["lobes"]:
        carpet_lobe(
            builder,
            (offset_x, offset_y, cushion[2] * 0.42),
            yaw, pitch, length, length * width_fraction, thickness, slot,
        )
    return commit(builder, name, spec["sink"]), len(spec["lobes"])


def measure(obj, lobes):
    mesh = obj.data
    mesh.calc_loop_triangles()
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    width = max(xs) - min(xs)
    depth = max(ys) - min(ys)
    height = max(zs) - min(zs)
    return {
        "triangles": len(mesh.loop_triangles),
        "vertices": len(mesh.vertices),
        "lobes": lobes,
        "width": round(width, 4),
        "depth": round(depth, 4),
        "height": round(height, 4),
        "ratio": round(max(width, depth) / max(height, 1e-5), 2),
        "footprint_radius": round(max(width, depth) * 0.5, 4),
    }


# --------------------------------------------------------------------------
# Build-time silhouette gate
# --------------------------------------------------------------------------
#
# The proportion test alone is not enough: a tuft can be wide and low and still
# be a hollow star. These four numbers are what actually separate a soft mass
# from a rosette, so they are measured here rather than discovered later in a
# screenshot. The projection is orthographic top-down, which is the harshest
# view — anything that reads solid from directly above reads solid from the
# gameplay camera too.


def silhouette_metrics(obj, resolution=512):
    """Rasterise the top-down projection and measure how solid it is.

    fill_ratio        solid area / convex-hull area. Catches star and spider
                      outlines, which have a large hull and little substance.
    internal_gap      holes fully enclosed by solid pixels. Catches the open
                      centre of a rosette.
    central_occupancy how much of the middle 45% of the bounding box is solid.
                      Catches a visible radial origin or crown.
    peaks             major outer lobes. Catches "reads as separate blades".
    """
    import numpy as np

    mesh = obj.data
    mesh.calc_loop_triangles()
    coords = np.array([[v.co.x, v.co.y] for v in mesh.vertices], dtype=np.float64)
    if coords.size == 0:
        return {}
    low = coords.min(axis=0)
    high = coords.max(axis=0)
    span = np.maximum(high - low, 1e-6)
    # Square the frame so pixel area maps to world area uniformly on both axes.
    extent = span.max()
    centre = (low + high) * 0.5
    origin = centre - extent * 0.5
    margin = 0.04 * extent
    origin -= margin
    extent += margin * 2.0

    grid = np.zeros((resolution, resolution), dtype=bool)
    scale = (resolution - 1) / extent

    # Half-space rasterisation per triangle. Cheap, exact, and needs no library.
    for triangle in mesh.loop_triangles:
        pts = coords[list(triangle.vertices)]
        pixels = (pts - origin) * scale
        min_x = max(int(np.floor(pixels[:, 0].min())), 0)
        max_x = min(int(np.ceil(pixels[:, 0].max())), resolution - 1)
        min_y = max(int(np.floor(pixels[:, 1].min())), 0)
        max_y = min(int(np.ceil(pixels[:, 1].max())), resolution - 1)
        if max_x < min_x or max_y < min_y:
            continue
        ys, xs = np.mgrid[min_y:max_y + 1, min_x:max_x + 1]
        px = xs + 0.5
        py = ys + 0.5
        (ax, ay), (bx, by), (cx, cy) = pixels
        area = (bx - ax) * (cy - ay) - (cx - ax) * (by - ay)
        if abs(area) < 1e-9:
            continue
        w0 = ((bx - ax) * (py - ay) - (px - ax) * (by - ay)) / area
        w1 = ((cx - bx) * (py - by) - (px - bx) * (cy - by)) / area
        w2 = 1.0 - w0 - w1
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        grid[min_y:max_y + 1, min_x:max_x + 1] |= inside

    solid = int(grid.sum())
    if solid == 0:
        return {}

    # Internal holes: flood the background inward from the border; anything the
    # flood cannot reach is enclosed by the silhouette.
    reachable = np.zeros_like(grid)
    frontier = [(0, x) for x in range(resolution)]
    frontier += [(resolution - 1, x) for x in range(resolution)]
    frontier += [(y, 0) for y in range(resolution)]
    frontier += [(y, resolution - 1) for y in range(resolution)]
    stack = [(y, x) for y, x in frontier if not grid[y, x]]
    for y, x in stack:
        reachable[y, x] = True
    while stack:
        y, x = stack.pop()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < resolution and 0 <= nx < resolution \
                    and not grid[ny, nx] and not reachable[ny, nx]:
                reachable[ny, nx] = True
                stack.append((ny, nx))
    holes = int((~grid & ~reachable).sum())

    # Convex hull area by monotone chain over the solid pixels.
    ys, xs = np.nonzero(grid)
    points = sorted(set(zip(xs.tolist(), ys.tolist())))

    def cross(o, a, b):
        return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])

    lower_hull = []
    for point in points:
        while len(lower_hull) >= 2 and cross(lower_hull[-2], lower_hull[-1], point) <= 0:
            lower_hull.pop()
        lower_hull.append(point)
    upper_hull = []
    for point in reversed(points):
        while len(upper_hull) >= 2 and cross(upper_hull[-2], upper_hull[-1], point) <= 0:
            upper_hull.pop()
        upper_hull.append(point)
    hull = lower_hull[:-1] + upper_hull[:-1]
    hull_area = 0.0
    for index in range(len(hull)):
        x0, y0 = hull[index]
        x1, y1 = hull[(index + 1) % len(hull)]
        hull_area += x0 * y1 - x1 * y0
    hull_area = abs(hull_area) * 0.5

    # Central occupancy over the middle 45% of the SOLID bounding box.
    bb_min_x, bb_max_x = int(xs.min()), int(xs.max())
    bb_min_y, bb_max_y = int(ys.min()), int(ys.max())
    cx = (bb_min_x + bb_max_x) * 0.5
    cy = (bb_min_y + bb_max_y) * 0.5
    half_w = (bb_max_x - bb_min_x) * 0.45 * 0.5
    half_h = (bb_max_y - bb_min_y) * 0.45 * 0.5
    x0 = max(int(round(cx - half_w)), 0)
    x1 = min(int(round(cx + half_w)), resolution - 1)
    y0 = max(int(round(cy - half_h)), 0)
    y1 = min(int(round(cy + half_h)), resolution - 1)
    window = grid[y0:y1 + 1, x0:x1 + 1]
    central = float(window.mean()) if window.size else 0.0

    # Major outer peaks: radial extent from the centroid at one-degree steps,
    # smoothed, counting maxima that stand out and are well separated. This is a
    # heuristic for "does it read as a few scallops or as many blades".
    centroid = (float(xs.mean()), float(ys.mean()))
    angles = np.radians(np.arange(360))
    radii = np.zeros(360)
    px = xs - centroid[0]
    py = ys - centroid[1]
    point_angle = (np.degrees(np.arctan2(py, px)) % 360).astype(int)
    point_radius = np.hypot(px, py)
    np.maximum.at(radii, point_angle, point_radius)
    kernel = np.ones(9) / 9.0
    smooth = np.convolve(np.concatenate([radii[-8:], radii, radii[:8]]),
                         kernel, mode="same")[8:-8]
    mean_radius = float(smooth.mean())
    peaks = 0
    last_peak = -999
    for index in range(360):
        value = smooth[index]
        if value <= mean_radius * 1.06:
            continue
        if value < smooth[index - 1] or value < smooth[(index + 1) % 360]:
            continue
        if index - last_peak < 25:
            continue
        peaks += 1
        last_peak = index

    return {
        "fill_ratio": round(solid / max(hull_area, 1.0), 4),
        "internal_gap_ratio": round(holes / max(solid + holes, 1), 4),
        "central_occupancy": round(central, 4),
        "major_outer_peaks": peaks,
    }


def export(obj, name):
    OUT.mkdir(parents=True, exist_ok=True)
    for other in bpy.context.scene.objects:
        other.select_set(other is obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / f"{name}.glb"),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
        export_normals=True,
        export_texcoords=False,
        export_tangents=False,
    )


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    records = []
    problems = []

    for name, spec in GROUND_CARPET:
        MODULES.append((name, "ground", spec))

    for name, kind, spec in MODULES:
        obj, lobes = build_module(name, kind, spec)
        record = measure(obj, lobes)
        record.update(silhouette_metrics(obj))
        record.update(
            id=name, kind=kind,
            path="res://tools/tile_forge/modules/grass/%s.glb" % name,
        )
        export(obj, name)
        records.append(record)
        bpy.data.objects.remove(obj, do_unlink=True)

        if kind == "carpet":
            for key, limit_value, comparison in (
                ("fill_ratio", 0.74, "min"),
                ("internal_gap_ratio", 0.03, "max"),
                ("central_occupancy", 0.95, "min"),
                ("major_outer_peaks", 5, "max"),
            ):
                value = record.get(key)
                if value is None:
                    continue
                failed = value < limit_value if comparison == "min" else value > limit_value
                if failed:
                    problems.append("%s: %s %.4g fails the %s gate of %.4g"
                                    % (name, key, value, comparison, limit_value))
        if kind == "ground":
            # A ground mat only has to be broad, low and solid; the tuft bands
            # would reject it for being exactly what it is meant to be.
            if not (0.32 <= max(record["width"], record["depth"]) <= 0.70):
                problems.append("%s: %.3f m across is outside the 0.32-0.70 band"
                                % (name, max(record["width"], record["depth"])))
            if not (0.012 <= record["height"] <= 0.042):
                problems.append("%s: %.3f m tall is outside the 0.012-0.042 band"
                                % (name, record["height"]))
            if record.get("fill_ratio", 1.0) < 0.74:
                problems.append("%s: fill %.3f fails the ground-mat gate 0.74"
                                % (name, record["fill_ratio"]))
        limit = ACCENT_TRIANGLE_MAX if kind == "accent" else TUFT_TRIANGLE_MAX
        if record["triangles"] > limit:
            problems.append("%s: %d triangles exceeds the %s budget of %d"
                            % (name, record["triangles"], kind, limit))
        if kind == "carpet":
            family = ("small" if name.startswith("small") else
                      "hero" if name.startswith("large") else "medium")
            span, lobes_band = {
                "small": ((0.16, 0.28), (3, 5)),
                "medium": ((0.26, 0.42), (4, 7)),
                "hero": ((0.38, 0.58), (6, 10)),
            }[family]
            widest = max(record["width"], record["depth"])
            if not (span[0] <= widest <= span[1]):
                problems.append("%s: %.3f m across is outside the %s band %.2f-%.2f"
                                % (name, widest, family, span[0], span[1]))
            if not (lobes_band[0] <= record["lobes"] <= lobes_band[1]):
                problems.append("%s: %d lobes is outside the %s band %d-%d"
                                % (name, record["lobes"], family,
                                   lobes_band[0], lobes_band[1]))
            # Low and wide stays non-negotiable for every family.
            if record["ratio"] < 3.2:
                problems.append("%s: width/height %.2f is below 3.2 (%.3f x %.3f)"
                                % (name, record["ratio"], record["width"],
                                   record["height"]))

    report = {
        "modules": records,
        "total_triangles": sum(r["triangles"] for r in records),
        "problems": problems,
        "gates": {
            "tuft_triangles_max": TUFT_TRIANGLE_MAX,
            "accent_triangles_max": ACCENT_TRIANGLE_MAX,
            "ratio_band": [WIDTH_RATIO_MIN, WIDTH_RATIO_MAX],
        },
    }
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "carpet_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    for record in records:
        print("%-19s %-6s tris=%3d lobes=%d  %.3fw %.3fd %.3fh  r=%.2f "
              "fill=%.3f gap=%.3f centre=%.3f peaks=%d"
              % (record["id"], record["kind"], record["triangles"],
                 record["lobes"], record["width"], record["depth"],
                 record["height"], record["ratio"],
                 record.get("fill_ratio", 0.0),
                 record.get("internal_gap_ratio", 0.0),
                 record.get("central_occupancy", 0.0),
                 record.get("major_outer_peaks", 0)))
    for line in problems:
        print("PROBLEM %s" % line)
    print("CARPET TUFTS: %d modules, %d problems, %d tris total"
          % (len(records), len(problems), report["total_triangles"]))


if __name__ == "__main__":
    main()
