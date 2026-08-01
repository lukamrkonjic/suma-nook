#!/usr/bin/env python3
"""Build Suma's three hand-authored MASTER TILES and their reusable modules.

This replaces the whole previous construction language. The rejected versions
rendered one visible block per logical cell, so a field of grass read as a grid
of dark cubes. The correction is architectural:

    A LOGICAL TILE IS NOT A VISIBLE BLOCK.

Every master therefore exports as separate pieces:

    <id>_cap.glb      the continuous visible top. Reaches the exact logical
                      boundary on all four sides. No perimeter outline, no
                      border bevel, no side wall, no frame. Two caps placed
                      side by side meet with zero gap and no seam.
    <id>_skirt.glb    one straight exposed-edge skirt, authored along the
                      +Z edge. Placed only where a tile has no compatible
                      neighbour, and rotated into place.
    <id>_corner.glb   the outside corner piece for two adjacent exposed edges.

Only the outside perimeter of a connected region ever shows vertical terrain.

Geometry rules every module obeys:
  * closed volumes, applied transforms, origin at the ground-contact centre;
  * soft controlled bevels built explicitly as chamfer rings, so the triangle
    cost is known and the highlight width is authored rather than emergent;
  * smooth shading declared per face — barrels smooth, caps and chamfers flat —
    which is what gives chunky low-poly forms their soft read without melting
    the silhouette;
  * no cards, no spikes, no needle tips, no untouched primitive silhouettes;
  * broad matte colour regions only, named for the Tile Forge slot contract.

UNITS. Everything is authored in LIVE metres: Suma's grid cell is 1.35 m
(data/tuning.json::tile_size). The art brief quotes its numbers against the
1.70 m authored catalog footprint, so each value below is the brief's number
scaled by 1.35 / 1.70 = 0.794, and the comment states the brief's figure.

Run from the repository root:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/build_tile_masters.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
MODULE_ROOT = ROOT / "tools" / "tile_forge" / "modules"
MASTER_ROOT = ROOT / "tools" / "tile_forge" / "masters"

# --- the shared dimension contract -------------------------------------------

TILE = 1.35                 # logical cell, LIVE metres (brief: 1.70)
HALF = TILE / 2.0           # 0.675
SIDE_HEIGHT = 0.170         # visible terrain side (brief: 0.18-0.24)
TOP_BEVEL = 0.036           # exposed top rounding (brief: 0.035-0.055)
BOTTOM_BEVEL = 0.016        # exposed lower rounding (brief: 0.015-0.025)
BEVEL_SEGMENTS = 3

# Warm, restrained, moderately desaturated. Side walls sit ~13% under their top,
# never near-black, and every family stays inside one hue.
PALETTE = {
    "grass_top": "849660",
    "grass_top_2": "8F9F6C",
    "grass_side": "768755",
    "clump_main": "97A972",
    "clump_dark": "7B8D57",
    "moss": "6B8250",
    "paver_a": "C3B7A4",
    "paver_b": "B6A896",
    "paver_c": "CBC0AE",
    "paver_joint": "9C9083",
    "paver_side": "AC9F8D",
    "wood_a": "B58F5A",
    "wood_b": "A88251",
    "wood_c": "C09B63",
    "wood_gap": "8A6C43",
    "wood_side": "A0804F",
    "clay": "C8C2B6",
}


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
    shader.inputs["Base Color"].default_value = srgb(PALETTE.get(name, "C8C2B6"))
    shader.inputs["Roughness"].default_value = 0.95
    shader.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.18
    result.diffuse_color = srgb(PALETTE.get(name, "C8C2B6"))
    return result


# --- builder -----------------------------------------------------------------


class Builder:
    def __init__(self):
        self.verts = []
        self.faces = []
        self.slots = []
        self.smooth = []

    def add(self, points):
        start = len(self.verts)
        self.verts.extend(points)
        return list(range(start, start + len(points)))

    def face(self, indices, slot, smooth=False):
        if len(indices) < 3:
            return
        self.faces.append(tuple(indices))
        self.slots.append(slot)
        self.smooth.append(smooth)

    def quad(self, a, b, c, d, slot, smooth=False):
        self.face((a, b, c, d), slot, smooth)

    def bridge(self, lower, upper, slot, smooth=False):
        for i in range(len(lower)):
            n = (i + 1) % len(lower)
            self.quad(lower[i], lower[n], upper[n], upper[i], slot, smooth)

    def strip(self, lower, upper, slot, smooth=False):
        """Open bridge — for a skirt that must not wrap around."""
        for i in range(len(lower) - 1):
            self.quad(lower[i], lower[i + 1], upper[i + 1], upper[i], slot, smooth)

    def cap(self, ring, slot, reverse=False, smooth=False):
        self.face(list(reversed(ring)) if reverse else list(ring), slot, smooth)


def commit(builder: Builder, name: str):
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
        polygon.use_smooth = builder.smooth[index]
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def weighted_normals(obj):
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    modifier.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier="WeightedNormal")


def join(objects, name):
    for obj in bpy.context.scene.objects:
        obj.select_set(obj in objects)
    bpy.context.view_layer.objects.active = objects[0]
    if len(objects) > 1:
        bpy.ops.object.join()
    joined = bpy.context.view_layer.objects.active
    joined.name = name
    joined.data.name = name
    return joined


def export(obj, directory: Path, name: str) -> dict:
    directory.mkdir(parents=True, exist_ok=True)
    for other in bpy.context.scene.objects:
        other.select_set(other is obj)
    bpy.context.view_layer.objects.active = obj
    mesh = obj.data
    mesh.calc_loop_triangles()
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    bpy.ops.export_scene.gltf(
        filepath=str(directory / f"{name}.glb"),
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
    return {
        "id": name,
        "path": "res://%s" % str(
            (directory / f"{name}.glb").relative_to(ROOT)
        ).replace("\\", "/"),
        "triangles": len(mesh.loop_triangles),
        "vertices": len(mesh.vertices),
        "size_x": round(max(xs) - min(xs), 4),
        "size_y": round(max(ys) - min(ys), 4),
        "height": round(max(zs) - min(zs), 4),
        "base_z": round(min(zs), 5),
        "materials": [m.name for m in mesh.materials],
    }


# --- geometry helpers --------------------------------------------------------


def rounded_rect(size_x, size_y, corner, segments):
    hx, hy = size_x * 0.5, size_y * 0.5
    radius = min(corner, hx * 0.95, hy * 0.95)
    if radius <= 1e-5 or segments <= 0:
        return [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    points = []
    centres = [
        (hx - radius, -(hy - radius), -math.pi / 2.0),
        (hx - radius, hy - radius, 0.0),
        (-(hx - radius), hy - radius, math.pi / 2.0),
        (-(hx - radius), -(hy - radius), math.pi),
    ]
    for cx, cy, start in centres:
        for step in range(segments + 1):
            angle = start + (math.pi / 2.0) * step / segments
            points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    return points


def inset(points, amount):
    cx = sum(p[0] for p in points) / len(points)
    cy = sum(p[1] for p in points) / len(points)
    result = []
    for x, y in points:
        dx, dy = x - cx, y - cy
        length = math.hypot(dx, dy)
        if length <= amount * 1.5:
            result.append((cx, cy))
        else:
            scale = (length - amount) / length
            result.append((cx + dx * scale, cy + dy * scale))
    return result


def inset_across(points, amount, axis=1):
    """Insets only along one axis, leaving the other free. A board rolled on
    its long edges and left square on its ends fuses seamlessly with the next
    board in the run — which is what stops a deck exposing the cell grid."""
    values = [p[axis] for p in points]
    lo, hi = min(values), max(values)
    mid = (lo + hi) * 0.5
    result = []
    for point in points:
        moved = list(point)
        span = hi - mid
        if span > 1e-6:
            offset = (point[axis] - mid) / span
            moved[axis] = point[axis] - amount * offset
        result.append(tuple(moved))
    return result


def chamfered_slab(builder, outline, thickness, chamfer, segments, slot,
                   side_slot, crown=0.0, roll_axis=None):
    """A broad slab with an authored multi-segment rounded top edge and an
    optional whisper of top convexity. This is the paver and board unit: flat
    enough to walk on, round enough to catch a soft highlight."""
    rings = []
    rings.append(builder.add([(x, y, 0.0) for x, y in outline]))
    shoulder = thickness - chamfer
    rings.append(builder.add([(x, y, shoulder) for x, y in outline]))
    for step in range(1, segments + 1):
        t = step / segments
        # Quarter-circle roll: the highlight rolls off instead of terminating.
        radial = math.sin(t * math.pi * 0.5)
        vertical = 1.0 - math.cos(t * math.pi * 0.5)
        ring_points = (
            inset_across(outline, chamfer * radial, roll_axis)
            if roll_axis is not None
            else inset(outline, chamfer * radial)
        )
        rings.append(builder.add([
            (x, y, shoulder + chamfer * vertical) for x, y in ring_points
        ]))
    builder.bridge(rings[0], rings[1], side_slot)
    for index in range(1, len(rings) - 1):
        builder.bridge(rings[index], rings[index + 1], slot, smooth=True)

    top = rings[-1]
    if crown > 1e-5:
        centre = builder.add([(0.0, 0.0, thickness + crown)])[0]
        for i in range(len(top)):
            n = (i + 1) % len(top)
            builder.face((top[i], top[n], centre), slot, smooth=True)
    else:
        builder.cap(top, slot)
    builder.cap(rings[0], side_slot, reverse=True)


def lobe(builder, cx, cy, heading, base_width, reach, height, rng,
         slot, dark_slot, sides=5):
    """One broad rounded lobe — the grass unit.

    Rings bulge at the base and taper to a small ROUNDED CAP, never to a point.
    The barrel is smooth-shaded so a five-sided tube reads as a soft volume.
    There are no blades, no cards, and no needles anywhere in this shape.
    """
    direction = (math.cos(heading), math.sin(heading))

    def at(t):
        lean = reach * (t ** 1.3)
        rise = height * math.sin(t * math.pi * 0.62) / math.sin(math.pi * 0.62)
        return (cx + direction[0] * lean, cy + direction[1] * lean, rise)

    stops = [0.0, 0.58, 1.0]
    radii = [0.86, 1.0, 0.30]
    phase = heading + math.pi * 0.5
    rings = []
    for index, t in enumerate(stops):
        px, py, pz = at(t)
        half = base_width * 0.5 * radii[index]
        ring = []
        for corner in range(sides):
            angle = phase + math.tau * corner / sides
            ring.append((
                px + math.cos(angle) * half,
                py + math.sin(angle) * half * 0.82,
                pz,
            ))
        rings.append(builder.add(ring))
    builder.bridge(rings[0], rings[1], dark_slot, smooth=True)
    builder.bridge(rings[1], rings[2], slot, smooth=True)
    builder.cap(rings[2], slot, smooth=True)
    builder.cap(rings[0], dark_slot, reverse=True)


def grass_clump(name, seed, lobes, spread, height, slot="clump_main",
                dark_slot="clump_dark"):
    """A soft collectible-game vegetation mass: several broad rounded lobes
    fanning from a thick shared base, one clearly dominant."""
    rng = random.Random(seed)
    builder = Builder()
    heading = rng.uniform(0.0, math.tau)
    # Dominant lobe first, upright and slightly off-centre.
    lobe(builder, spread * 0.04, 0.0, heading, spread * 0.46, spread * 0.14,
         height, rng, slot, dark_slot, sides=6)
    for index in range(lobes - 1):
        heading += 2.39996 + rng.uniform(-0.5, 0.5)
        fall = 1.0 - 0.4 * (index + 1) / max(1, lobes - 1)
        offset = spread * rng.uniform(0.06, 0.18)
        lobe(
            builder,
            math.cos(heading) * offset,
            math.sin(heading) * offset,
            heading,
            spread * rng.uniform(0.36, 0.48),
            spread * rng.uniform(0.26, 0.42),
            height * fall * rng.uniform(0.84, 1.0),
            rng, slot, dark_slot, sides=5,
        )
    obj = commit(builder, name)
    weighted_normals(obj)
    return obj


def paver_module(name, seed, size, thickness, corner):
    """A handcrafted paving stone: rounded-square, restrained asymmetry, broad
    nearly flat top with the faintest convexity, three-segment edge roll."""
    rng = random.Random(seed)
    builder = Builder()
    outline = rounded_rect(
        size * rng.uniform(0.975, 1.0),
        size * rng.uniform(0.975, 1.0),
        corner * rng.uniform(0.9, 1.12),
        3,
    )
    # Restrained asymmetry, applied inward only: one side pulled a little, never
    # enough to read as damage and never enough to cross into the joint.
    skew = rng.uniform(0.004, 0.012)
    outline = [(x - skew * (1.0 if x > 0 else -1.0), y) for x, y in outline]
    chamfered_slab(
        builder, outline, thickness, thickness * 0.42, BEVEL_SEGMENTS,
        "paver_a", "paver_side", crown=thickness * 0.09,
    )
    obj = commit(builder, name)
    weighted_normals(obj)
    return obj


def _retone(obj, slot):
    """Rebinds a module's primary tone. Board-to-board variation belongs to the
    module, not to the cell, so a repeated deck varies along the planks."""
    mesh = obj.data
    for index, existing in enumerate(mesh.materials):
        if existing is not None and existing.name.startswith("wood_a"):
            mesh.materials[index] = material(slot)


def board_module(name, seed, length, width, thickness):
    """A broad chunky board, subtly convex across its width and slightly
    irregular at the ends. Never a thin strip and never a plain extruded bar."""
    rng = random.Random(seed)
    builder = Builder()
    # Square ends, rounded long edges. No end rounding and no end irregularity:
    # both would draw a line at every cell boundary in a repeated deck.
    hx, hy = length * 0.5, width * 0.5
    outline = [(-hx, -hy), (hx, -hy), (hx, hy), (-hx, hy)]
    chamfered_slab(
        builder, outline, thickness, thickness * 0.36, BEVEL_SEGMENTS,
        "wood_a", "wood_side", crown=thickness * 0.10, roll_axis=1,
    )
    obj = commit(builder, name)
    weighted_normals(obj)
    return obj


# --- surface caps ------------------------------------------------------------


def grass_cap(name, seed, resolution=9):
    """The continuous grass top.

    It spans the EXACT logical cell on all four sides and has no perimeter
    treatment of any kind, so two caps meet with zero gap and a field of them
    reads as one lawn. Shape comes from two broad mounds and one shallow
    resting hollow — never from per-vertex noise.
    """
    rng = random.Random(seed)
    builder = Builder()

    mounds = [
        (-0.30, -0.22, 0.88, 0.82, 0.070),
        (0.42, 0.36, 0.72, 0.68, 0.046),
    ]
    hollow = (0.30, -0.46, 0.64, 0.58, -0.034)

    def height_at(u, v):
        total = 0.0
        for cx, cy, ex, ey, amp in mounds:
            d = math.hypot((u - cx) / ex, (v - cy) / ey)
            if d < 1.0:
                total += amp * (0.5 + 0.5 * math.cos(math.pi * min(1.0, d)))
        cx, cy, ex, ey, amp = hollow
        d = math.hypot((u - cx) / ex, (v - cy) / ey)
        if d < 1.0:
            total += amp * (0.5 + 0.5 * math.cos(math.pi * d))
        # The boundary must be exactly flat so neighbouring caps agree.
        edge = 1.0 - max(abs(u), abs(v))
        lock = min(1.0, max(0.0, edge / 0.26))
        return total * (lock * lock * (3.0 - 2.0 * lock))

    grid = []
    for j in range(resolution):
        row = []
        v = -1.0 + 2.0 * j / (resolution - 1)
        for i in range(resolution):
            u = -1.0 + 2.0 * i / (resolution - 1)
            row.append((u * HALF, v * HALF, height_at(u, v)))
        grid.append(builder.add(row))
    for j in range(resolution - 1):
        for i in range(resolution - 1):
            # ONE tone across the cap. A second tone keyed off height snapped
            # to the quad grid and drew a pale rectangle under each tuft group,
            # which reads as a placement pad rather than as terrain shading.
            builder.quad(
                grid[j][i], grid[j][i + 1], grid[j + 1][i + 1], grid[j + 1][i],
                "grass_top", smooth=True,
            )
    obj = commit(builder, name)
    weighted_normals(obj)
    return obj, height_at


def flat_cap(name, height, slot):
    """A dead-flat cap spanning the exact cell. Used under pavers and boards,
    where the constructed pieces provide all the relief."""
    builder = Builder()
    ring = builder.add([
        (-HALF, -HALF, height), (HALF, -HALF, height),
        (HALF, HALF, height), (-HALF, HALF, height),
    ])
    builder.cap(ring, slot)
    return commit(builder, name)


# --- exposed edge pieces -----------------------------------------------------


def edge_skirt(name, slot, side_slot, top_offset=0.0):
    """One straight exposed-edge skirt, authored along the +Y edge in Blender
    (which becomes +Z in Godot).

    This is the piece that only appears where a tile has NO compatible
    neighbour. Internal edges get nothing at all, which is the entire reason a
    connected region stops looking like a grid of blocks.
    """
    builder = Builder()
    top = top_offset
    shoulder = top - TOP_BEVEL
    floor = -SIDE_HEIGHT
    lift = floor + BOTTOM_BEVEL

    # A little lateral resolution so the roll reads smoothly along the run.
    steps = 6
    xs = [-HALF + 2.0 * HALF * i / steps for i in range(steps + 1)]

    def ring(y_offset, z):
        return builder.add([(x, HALF - y_offset, z) for x in xs])

    rings = []
    # Top roll: quarter circle from the cap plane out to the vertical face.
    for step in range(BEVEL_SEGMENTS + 1):
        t = step / BEVEL_SEGMENTS
        rings.append(ring(
            TOP_BEVEL * (1.0 - math.sin(t * math.pi * 0.5)),
            top - TOP_BEVEL * (1.0 - math.cos(t * math.pi * 0.5)),
        ))
    rings.append(ring(0.0, lift))
    # Bottom roll, tucked under so the piece lifts off whatever it sits on.
    for step in range(1, 3):
        t = step / 2.0
        rings.append(ring(
            BOTTOM_BEVEL * math.sin(t * math.pi * 0.5),
            lift - BOTTOM_BEVEL * (1.0 - math.cos(t * math.pi * 0.5)),
        ))

    for index in range(len(rings) - 1):
        tone = slot if index < BEVEL_SEGMENTS else side_slot
        builder.strip(rings[index], rings[index + 1], tone, smooth=index < BEVEL_SEGMENTS)
    obj = commit(builder, name)
    weighted_normals(obj)
    return obj


def edge_corner(name, slot, side_slot, top_offset=0.0):
    """The outside corner where two exposed edges meet, authored at the
    +X/+Y corner. Without it a corner shows a notch between two skirts."""
    builder = Builder()
    top = top_offset
    floor = -SIDE_HEIGHT
    lift = floor + BOTTOM_BEVEL
    steps = 4

    def arc_ring(radial, z):
        points = []
        for step in range(steps + 1):
            angle = (math.pi * 0.5) * step / steps
            points.append((
                HALF - TOP_BEVEL + math.cos(angle) * radial,
                HALF - TOP_BEVEL + math.sin(angle) * radial,
                z,
            ))
        return builder.add(points)

    rings = []
    for step in range(BEVEL_SEGMENTS + 1):
        t = step / BEVEL_SEGMENTS
        rings.append(arc_ring(
            TOP_BEVEL * math.sin(t * math.pi * 0.5),
            top - TOP_BEVEL * (1.0 - math.cos(t * math.pi * 0.5)),
        ))
    rings.append(arc_ring(TOP_BEVEL, lift))
    for step in range(1, 3):
        t = step / 2.0
        rings.append(arc_ring(
            TOP_BEVEL - BOTTOM_BEVEL * math.sin(t * math.pi * 0.5),
            lift - BOTTOM_BEVEL * (1.0 - math.cos(t * math.pi * 0.5)),
        ))
    for index in range(len(rings) - 1):
        tone = slot if index < BEVEL_SEGMENTS else side_slot
        builder.strip(rings[index], rings[index + 1], tone, smooth=index < BEVEL_SEGMENTS)
    obj = commit(builder, name)
    weighted_normals(obj)
    return obj


# --- masters -----------------------------------------------------------------

## Twelve curated grass layouts. Each entry is a list of
## (u, v, module index, scale, yaw) placements in normalized cell space.
## They are authored, not sampled: one dominant cluster, supporting groups,
## and deliberate open space. Adjacent cells pick different layouts by
## coordinate, so a repeated field never shows the same arrangement twice.
GRASS_LAYOUTS = [
    [(0.491, 0.213, 1, 0.96, 300),
     (0.560, 0.365, 2, 1.11, 127),
     (0.371, 0.264, 5, 1.02, 218),
     (-0.217, -0.409, 1, 0.94, 154),
     (-0.240, -0.342, 3, 0.93, 212),
     (-0.212, -0.408, 4, 0.91, 276),
     (0.404, 0.134, 0, 0.97, 142),
     (0.276, -0.006, 0, 1.00, 349),
     (0.201, -0.096, 2, 1.07, 84),
     (0.341, 0.128, 4, 0.94, 72),
     (0.441, -0.078, 3, 0.95, 321),
     (0.343, 0.053, 4, 1.05, 128)],
    [(0.405, -0.422, 0, 1.03, 211),
     (0.325, -0.207, 1, 0.99, 82),
     (0.229, -0.319, 3, 0.93, 200),
     (0.416, -0.264, 3, 1.05, 174),
     (0.397, -0.236, 5, 1.06, 60),
     (0.334, -0.395, 3, 1.05, 24),
     (0.184, 0.338, 1, 1.05, 48),
     (0.354, 0.300, 1, 1.08, 341),
     (0.254, 0.452, 1, 1.11, 166),
     (0.243, 0.342, 1, 0.97, 291),
     (-0.089, 0.199, 3, 0.96, 17),
     (-0.059, 0.126, 3, 0.94, 84),
     (-0.252, 0.192, 2, 1.13, 123)],
    [(0.025, -0.195, 4, 0.94, 285),
     (-0.229, -0.374, 0, 1.10, 286),
     (-0.153, -0.390, 4, 0.98, 279),
     (-0.111, 0.209, 4, 0.98, 167),
     (-0.088, 0.195, 0, 1.00, 140),
     (-0.178, 0.174, 2, 1.11, 54),
     (0.009, 0.253, 0, 1.09, 213),
     (-0.039, 0.063, 0, 1.07, 151),
     (0.437, 0.276, 4, 1.09, 94),
     (0.384, 0.257, 2, 1.10, 331),
     (0.239, 0.194, 0, 1.00, 288),
     (0.377, 0.162, 1, 1.13, 99),
     (0.502, 0.198, 4, 0.91, 177),
     (0.388, -0.230, 3, 1.01, 241),
     (0.155, -0.227, 4, 1.12, 232),
     (0.245, -0.104, 0, 1.03, 275)],
    [(0.286, -0.099, 1, 1.04, 85),
     (0.300, -0.113, 1, 1.01, 237),
     (0.383, 0.120, 2, 0.98, 313),
     (0.377, -0.066, 5, 1.13, 233),
     (-0.321, 0.372, 4, 1.05, 259),
     (-0.346, 0.399, 0, 1.04, 322),
     (-0.393, 0.259, 0, 1.11, 117),
     (-0.530, 0.241, 3, 1.10, 4),
     (-0.457, 0.257, 4, 1.15, 167),
     (-0.071, 0.045, 4, 1.15, 341),
     (0.010, -0.170, 0, 1.03, 333),
     (0.016, 0.111, 1, 0.98, 240),
     (-0.129, -0.026, 2, 1.11, 40),
     (-0.121, -0.100, 0, 1.05, 286),
     (0.333, 0.344, 0, 0.97, 83),
     (0.444, 0.223, 0, 1.08, 170),
     (0.434, 0.408, 4, 1.02, 89)],
    [(0.141, -0.458, 3, 0.97, 42),
     (-0.051, -0.515, 0, 0.99, 95),
     (-0.126, -0.387, 0, 1.01, 209),
     (0.061, -0.195, 2, 0.99, 305),
     (0.047, -0.264, 4, 1.01, 247),
     (0.525, -0.176, 0, 0.90, 172),
     (0.363, 0.081, 5, 0.94, 215),
     (0.388, -0.068, 2, 1.14, 269),
     (-0.453, 0.238, 1, 1.14, 91),
     (-0.376, 0.147, 3, 1.11, 223),
     (-0.212, 0.237, 0, 0.95, 7),
     (-0.483, 0.090, 0, 0.92, 355),
     (-0.232, 0.277, 0, 1.01, 358)],
    [(-0.140, 0.279, 4, 0.95, 192),
     (-0.267, 0.112, 2, 1.05, 244),
     (-0.121, 0.180, 5, 0.92, 42),
     (-0.235, 0.021, 2, 1.12, 324),
     (-0.159, 0.190, 1, 1.07, 123),
     (-0.268, 0.030, 3, 1.04, 273),
     (0.077, -0.441, 1, 1.08, 174),
     (0.044, -0.476, 1, 0.94, 56),
     (-0.050, -0.274, 4, 0.97, 25),
     (0.183, -0.508, 0, 1.00, 64),
     (0.317, -0.193, 1, 1.14, 222),
     (0.454, -0.258, 1, 1.05, 112),
     (0.449, -0.134, 3, 1.03, 170),
     (0.309, -0.375, 3, 1.05, 174),
     (0.301, -0.319, 4, 1.14, 46),
     (0.242, 0.171, 3, 1.08, 39),
     (0.385, 0.200, 2, 1.08, 129),
     (0.383, 0.410, 0, 1.03, 356)],
    [(0.300, -0.349, 2, 1.09, 32),
     (0.527, -0.212, 3, 1.12, 84),
     (0.372, -0.311, 5, 0.91, 307),
     (-0.315, 0.197, 4, 1.01, 143),
     (-0.369, 0.432, 2, 1.00, 325),
     (-0.235, 0.284, 1, 1.14, 176),
     (0.332, 0.125, 2, 0.95, 69),
     (0.238, 0.130, 3, 1.03, 205),
     (0.183, 0.110, 3, 1.03, 166)],
    [(0.440, 0.205, 0, 0.93, 224),
     (0.410, 0.220, 5, 0.90, 11),
     (0.274, 0.194, 1, 1.01, 38),
     (-0.342, 0.128, 2, 0.96, 235),
     (-0.201, 0.302, 0, 1.01, 241),
     (-0.349, 0.387, 0, 0.91, 160),
     (-0.224, 0.370, 3, 0.98, 3),
     (-0.363, 0.554, 3, 1.07, 15),
     (-0.515, 0.399, 3, 1.09, 242),
     (0.071, 0.390, 4, 1.07, 120),
     (0.075, 0.211, 3, 1.08, 59),
     (-0.084, 0.289, 4, 0.93, 174),
     (0.057, 0.377, 2, 1.10, 208),
     (0.096, 0.350, 1, 1.00, 221)],
    [(-0.198, -0.443, 2, 1.07, 296),
     (-0.015, -0.307, 4, 1.11, 74),
     (-0.382, -0.437, 5, 1.00, 280),
     (-0.102, -0.547, 2, 0.96, 300),
     (-0.244, -0.435, 3, 1.04, 352),
     (-0.151, -0.560, 2, 1.00, 100),
     (0.177, 0.329, 0, 1.13, 108),
     (0.236, 0.300, 4, 1.08, 291),
     (0.051, 0.328, 0, 0.92, 270),
     (-0.320, -0.165, 4, 1.03, 262),
     (-0.206, -0.076, 2, 0.92, 21),
     (-0.338, -0.128, 1, 1.05, 155)],
    [(0.012, -0.519, 1, 1.13, 111),
     (-0.314, -0.457, 4, 0.93, 227),
     (-0.087, -0.362, 4, 1.05, 109),
     (-0.198, -0.468, 0, 0.95, 11),
     (-0.334, 0.260, 5, 1.07, 115),
     (-0.080, 0.069, 4, 0.97, 145),
     (-0.375, 0.098, 2, 1.12, 215),
     (-0.352, 0.147, 3, 1.13, 78),
     (0.350, -0.293, 0, 1.03, 126),
     (0.209, -0.462, 0, 0.98, 117),
     (0.107, -0.347, 0, 1.11, 132),
     (0.231, -0.296, 3, 1.13, 239),
     (0.218, -0.560, 0, 1.12, 49),
     (0.450, -0.377, 2, 0.92, 145),
     (0.201, 0.469, 1, 1.13, 93),
     (0.299, 0.268, 3, 1.06, 253),
     (0.313, 0.421, 0, 0.92, 73)],
    [(-0.535, 0.308, 1, 0.95, 211),
     (-0.560, 0.330, 2, 1.10, 290),
     (-0.464, 0.489, 1, 1.02, 90),
     (0.093, 0.069, 4, 0.93, 2),
     (0.133, 0.370, 3, 1.04, 181),
     (0.109, 0.372, 2, 0.93, 187),
     (0.109, 0.333, 2, 0.94, 305),
     (0.038, 0.259, 1, 0.94, 7),
     (0.265, 0.125, 1, 1.08, 123),
     (0.051, 0.011, 4, 1.11, 91),
     (0.112, 0.062, 0, 1.12, 187),
     (0.060, -0.011, 4, 0.90, 332),
     (0.117, -0.218, 5, 0.98, 261),
     (0.002, -0.074, 3, 0.97, 95)],
    [(0.186, 0.400, 2, 1.10, 41),
     (0.157, 0.499, 1, 0.95, 140),
     (0.038, 0.539, 3, 0.99, 81),
     (-0.084, 0.386, 0, 0.92, 256),
     (0.146, 0.474, 2, 1.05, 317),
     (-0.025, 0.328, 4, 1.05, 34),
     (0.560, -0.134, 3, 0.95, 293),
     (0.169, -0.118, 0, 1.02, 261),
     (0.207, -0.173, 2, 0.97, 152),
     (0.478, -0.230, 2, 0.98, 16),
     (-0.062, -0.279, 3, 1.14, 163),
     (-0.013, -0.244, 0, 1.14, 325),
     (-0.246, -0.299, 3, 1.02, 50),
     (-0.319, -0.216, 1, 1.10, 303),
     (-0.038, -0.131, 0, 0.99, 99)],
]


def build_grass_master(records):
    # Carpet tufts, built and shape-gated by build_carpet_tufts.py. Importing
    # them keeps one source of truth: if a tuft fails its silhouette gate it
    # never reaches a tile.
    # The three layered families plus the low ground mats. Index order matters:
    # GRASS_LAYOUTS refers to modules by index, and 0-4 must be the ordinary
    # carpet language with the hero reserved for index 5.
    tuft_ids = [
        "medium_carpet_a", "medium_carpet_b", "medium_carpet_c",
        "small_support_a", "ground_carpet_b", "large_hero_carpet_a",
    ]
    clumps = []
    for tuft_id in tuft_ids:
        source = MODULE_ROOT / "grass" / ("%s.glb" % tuft_id)
        if not source.exists():
            raise SystemExit(
                "missing %s — run build_carpet_tufts.py first" % source
            )
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(source))
        imported = [o for o in bpy.context.scene.objects
                    if o not in before and o.type == "MESH"]
        obj = join(imported, "tuft_%s" % tuft_id)
        # glTF arrives Y-up; the tile maths below is all Blender Z-up.
        obj.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        obj.select_set(False)
        clumps.append(obj)

    skirt = edge_skirt("master_grass_skirt", "grass_top", "grass_side")
    records.append(export(skirt, MASTER_ROOT, "master_grass_skirt"))
    corner = edge_corner("master_grass_corner", "grass_top", "grass_side")
    records.append(export(corner, MASTER_ROOT, "master_grass_corner"))

    # One representative cap plus every authored layout, exported as complete
    # master tiles so a reviewer can see the intended composition directly.
    for layout_index, layout in enumerate(GRASS_LAYOUTS):
        cap, height_at = grass_cap("master_grass_cap_%02d" % layout_index,
                                   4100 + layout_index)
        pieces = [cap]
        for u, v, module, scale, yaw in layout:
            copy = clumps[module].copy()
            copy.data = clumps[module].data.copy()
            bpy.context.scene.collection.objects.link(copy)
            copy.location = (u * HALF, v * HALF, height_at(u, v) - 0.012)
            copy.rotation_euler = (0.0, 0.0, math.radians(yaw))
            copy.scale = (scale, scale, scale)
            pieces.append(copy)
        merged = join(pieces, "master_grass_lush_%02d" % layout_index)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        records.append(export(
            merged, MASTER_ROOT, "master_grass_lush_%02d" % layout_index
        ))
        bpy.data.objects.remove(merged, do_unlink=True)

    for obj in clumps:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(skirt, do_unlink=True)
    bpy.data.objects.remove(corner, do_unlink=True)


def build_paver_master(records):
    joint = 0.030
    size = (TILE - joint) / 2.0        # 0.660 — outer edges inset by joint/2,
    centre = size / 2.0 + joint / 2.0  # so a cell boundary reads as one joint
    corner = 0.088                     # brief 0.08-0.13 authored -> 0.064-0.103
    thickness = 0.052                  # brief 0.045-0.075 authored

    modules = []
    for index in range(4):
        obj = paver_module("gf_paver_%02d" % index, 501 + index, size, thickness, corner)
        records.append(export(obj, MODULE_ROOT / "pavers", "gf_paver_%02d" % index))
        modules.append(obj)

    skirt = edge_skirt("master_paver_skirt", "paver_c", "paver_side")
    records.append(export(skirt, MASTER_ROOT, "master_paver_skirt"))
    corner_piece = edge_corner("master_paver_corner", "paver_c", "paver_side")
    records.append(export(corner_piece, MASTER_ROOT, "master_paver_corner"))

    rng = random.Random(777)
    for variant in range(4):
        base = flat_cap("paver_bed_%02d" % variant, 0.006, "paver_joint")
        pieces = [base]
        order = [0, 1, 2, 3]
        rng.shuffle(order)
        for index, (sx, sy) in enumerate(
            [(-1, -1), (1, -1), (1, 1), (-1, 1)]
        ):
            source = modules[order[index]]
            copy = source.copy()
            copy.data = source.data.copy()
            bpy.context.scene.collection.objects.link(copy)
            copy.location = (sx * centre, sy * centre, rng.uniform(-0.010, 0.010))
            copy.rotation_euler = (0.0, 0.0, math.radians(rng.uniform(-1.5, 1.5)))
            pieces.append(copy)
        merged = join(pieces, "master_soft_pavers_%02d" % variant)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        records.append(export(
            merged, MASTER_ROOT, "master_soft_pavers_%02d" % variant
        ))
        bpy.data.objects.remove(merged, do_unlink=True)

    for obj in modules:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(skirt, do_unlink=True)
    bpy.data.objects.remove(corner_piece, do_unlink=True)


def build_wood_master(records):
    gap = 0.026
    width = (TILE - 3.0 * gap) / 3.0   # outer boards inset by gap/2, so a cell
    thickness = 0.055                  # boundary reads as an ordinary gap
    offsets = [-(width + gap), 0.0, width + gap]

    modules = []
    for index in range(4):
        obj = board_module("gf_board_%02d" % index, 601 + index, TILE, width, thickness)
        _retone(obj, ["wood_a", "wood_b", "wood_c", "wood_a"][index])
        records.append(export(obj, MODULE_ROOT / "boards", "gf_board_%02d" % index))
        modules.append(obj)

    skirt = edge_skirt("master_wood_skirt", "wood_c", "wood_side")
    records.append(export(skirt, MASTER_ROOT, "master_wood_skirt"))
    corner_piece = edge_corner("master_wood_corner", "wood_c", "wood_side")
    records.append(export(corner_piece, MASTER_ROOT, "master_wood_corner"))

    # Four run phases. A renderer picks by world coordinate so boards continue
    # across cells instead of restarting three identical planks in every one.
    rng = random.Random(909)
    for variant in range(4):
        base = flat_cap("wood_bed_%02d" % variant, 0.004, "wood_gap")
        pieces = [base]
        for index, offset in enumerate(offsets):
            source = modules[(index + variant) % len(modules)]
            copy = source.copy()
            copy.data = source.data.copy()
            bpy.context.scene.collection.objects.link(copy)
            copy.location = (0.0, offset, rng.uniform(-0.004, 0.004))
            pieces.append(copy)
        merged = join(pieces, "master_wood_planks_%02d" % variant)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        records.append(export(
            merged, MASTER_ROOT, "master_wood_planks_%02d" % variant
        ))
        bpy.data.objects.remove(merged, do_unlink=True)

    for obj in modules:
        bpy.data.objects.remove(obj, do_unlink=True)
    bpy.data.objects.remove(skirt, do_unlink=True)
    bpy.data.objects.remove(corner_piece, do_unlink=True)


# --- shippable game tiles ----------------------------------------------------
#
# The master pieces above are the art-direction reference and are assembled by
# the region renderer, which builds skirts only on exposed edges. Suma's shipped
# world renderer does not know about edge masks yet, so previewing a master
# in-game needs the ordinary layered contract from docs/TILE_AUTHORING.md:
#
#     base     structural block, y -0.50 .. -0.055, persists when covered
#     surface  the cap plus a short skirt down to the seam, hides when covered
#
# These exports are therefore the SAME art in the shape the current renderer can
# already place, so the Asset Studio and build mode can show it today. They are
# an interim form: once the cap/skirt edge-mask model lands in WorldRenderer the
# surface loses its skirt and internal sides disappear.

GAME_ASSET_ROOT = ROOT / "assets" / "3d" / "reworked"
SEAM = -0.055           # shared thin-terrain seam (docs/TILE_AUTHORING.md)
BLOCK_BOTTOM = -0.50    # exact stack step


def _perimeter_skirt(builder, top_slot, side_slot, bottom, chamfer_bottom):
    """Rolls the cap edge over and drops it to `bottom`, all the way round.

    The roll is the same quarter-circle the exposed-edge skirt uses, so a tile
    previewed in the game reads with the same soft top edge as the master.
    """
    steps = 6
    axis = [-HALF + 2.0 * HALF * i / steps for i in range(steps + 1)]

    def side_points(index, inset_amount, z):
        # 0:+Y 1:+X 2:-Y 3:-X, walked so the ring is continuous and CCW.
        if index == 0:
            return [(x, HALF - inset_amount, z) for x in axis]
        if index == 1:
            return [(HALF - inset_amount, y, z) for y in reversed(axis)]
        if index == 2:
            return [(x, -HALF + inset_amount, z) for x in reversed(axis)]
        return [(-HALF + inset_amount, y, z) for y in axis]

    for side in range(4):
        rings = []
        for step in range(BEVEL_SEGMENTS + 1):
            t = step / BEVEL_SEGMENTS
            rings.append(builder.add(side_points(
                side,
                TOP_BEVEL * (1.0 - math.sin(t * math.pi * 0.5)),
                -TOP_BEVEL * (1.0 - math.cos(t * math.pi * 0.5)),
            )))
        rings.append(builder.add(side_points(side, 0.0, bottom + chamfer_bottom)))
        if chamfer_bottom > 1e-5:
            for step in range(1, 3):
                t = step / 2.0
                rings.append(builder.add(side_points(
                    side,
                    chamfer_bottom * math.sin(t * math.pi * 0.5),
                    bottom + chamfer_bottom * (1.0 - math.sin(t * math.pi * 0.5)),
                )))
        for index in range(len(rings) - 1):
            tone = top_slot if index < BEVEL_SEGMENTS else side_slot
            builder.strip(rings[index], rings[index + 1], tone,
                          smooth=index < BEVEL_SEGMENTS)


def build_surface_layer(name, cap_obj, top_slot, side_slot):
    """cap + rolled perimeter down to the shared seam."""
    builder = Builder()
    _perimeter_skirt(builder, top_slot, side_slot, SEAM, 0.0)
    skirt = commit(builder, name + "_skirt")
    weighted_normals(skirt)
    return join([cap_obj, skirt], name)


def build_base_block(name, side_slot):
    """The structural block, with the bottom edge chamfered so a stacked tile
    lifts off the one below instead of welding to it."""
    builder = Builder()
    top = SEAM
    lift = BLOCK_BOTTOM + BOTTOM_BEVEL
    corners = [(-HALF, -HALF), (HALF, -HALF), (HALF, HALF), (-HALF, HALF)]
    lower = builder.add([(x, y, lift) for x, y in corners])
    upper = builder.add([(x, y, top) for x, y in corners])
    builder.bridge(lower, upper, side_slot)
    for step in range(1, 3):
        t = step / 2.0
        ring = builder.add([
            (
                x - math.copysign(BOTTOM_BEVEL * math.sin(t * math.pi * 0.5), x),
                y - math.copysign(BOTTOM_BEVEL * math.sin(t * math.pi * 0.5), y),
                lift - BOTTOM_BEVEL * (1.0 - math.cos(t * math.pi * 0.5)),
            )
            for x, y in corners
        ])
        builder.bridge(lower, ring, side_slot)
        lower = ring
    builder.cap(lower, side_slot, reverse=True)
    # `_body` is the naming contract the runtime cover classifier and the
    # slot-fill test use to find a tile's structural shell.
    obj = commit(builder, name + "_body")
    weighted_normals(obj)
    return obj


def build_game_tiles(records):
    families = [
        ("grass", "grass_top", "grass_side",
         lambda: grass_cap("game_grass_cap", 4100)[0], 0),
        ("pavers", "paver_c", "paver_side", None, 0),
        ("wood", "wood_c", "wood_side", None, 0),
    ]
    for family, top_slot, side_slot, cap_factory, _unused in families:
        # Reuse the already-authored master as the cap so the game tile and the
        # reference cannot drift apart.
        source_name = {
            "grass": "master_grass_lush_00",
            "pavers": "master_soft_pavers_00",
            "wood": "master_wood_planks_00",
        }[family]
        source_path = MASTER_ROOT / f"{source_name}.glb"
        bpy.ops.import_scene.gltf(filepath=str(source_path))
        imported = [o for o in bpy.context.selected_objects if o.type == "MESH"]
        cap = join(imported, "game_%s_cap" % family)
        # glTF import arrives Y-up; put it back into Blender's Z-up authoring
        # frame before the skirt maths, which all assume Z is vertical.
        cap.rotation_euler = (math.radians(90.0), 0.0, 0.0)
        bpy.context.view_layer.objects.active = cap
        cap.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        cap.select_set(False)

        surface = build_surface_layer(
            "tile_layer_surface_master_%s_cap" % family, cap, top_slot, side_slot
        )
        records.append(export(
            surface, GAME_ASSET_ROOT, "tile_layer_surface_master_%s" % family
        ))
        bpy.data.objects.remove(surface, do_unlink=True)

        base = build_base_block("tile_layer_base_master_%s" % family, side_slot)
        records.append(export(
            base, GAME_ASSET_ROOT, "tile_layer_base_master_%s" % family
        ))
        bpy.data.objects.remove(base, do_unlink=True)


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    records = []
    build_grass_master(records)
    build_paver_master(records)
    build_wood_master(records)
    build_game_tiles(records)

    report = {
        "tile_size": TILE,
        "side_height": SIDE_HEIGHT,
        "top_bevel": TOP_BEVEL,
        "bottom_bevel": BOTTOM_BEVEL,
        "grass_layouts": len(GRASS_LAYOUTS),
        "modules": records,
        "total_triangles": sum(r["triangles"] for r in records),
    }
    MASTER_ROOT.mkdir(parents=True, exist_ok=True)
    (MASTER_ROOT / "master_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    for record in records:
        print("%-30s tris=%4d  %.3f x %.3f x %.3f" % (
            record["id"], record["triangles"],
            record["size_x"], record["size_y"], record["height"]
        ))
    print("TILE MASTERS: %d objects exported" % len(records))


if __name__ == "__main__":
    main()
