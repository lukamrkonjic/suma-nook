#!/usr/bin/env python3
"""Build the Suma Tile Forge detail-module library (v2).

The v1 library was rejected on sight: spiky grass, crossed sticks for straw,
pebbles too small to read, and flat cards everywhere. Those are not tuning
problems, so this is a rebuild of the modelling language rather than an edit of
the old numbers.

What changed, and why:

* every module is a CLOSED VOLUME. There are no cards, no zero-thickness
  triangles, and no single-vertex needle tips. A blade ends in a blunt cap ring
  at roughly a quarter of its base width, which is what makes it read as a
  thick stylised leaf instead of a spike.
* organic forms get their softness from SMOOTH-SHADED BARRELS: a five- or
  six-sided tapered tube shaded smooth around its length and flat across its
  caps reads as a rounded volume at no extra triangles. Cheap, and it is how
  the reference look is actually built.
* constructed forms (pavers, boards, stones, rubble) get a REAL CHAMFER from
  Blender's bevel modifier, then weighted normals. That chamfer is the thing
  that catches a highlight and stops a piece reading as an untreated cube.
* everything is sized to READ AT THE GAMEPLAY CAMERA. Detail modules are
  0.13-0.34 m wide and 0.06-0.21 m tall in LIVE metres on a 1.35 m tile. The
  v1 pebbles were 0.03 m across; at gameplay distance they were dots.
* pavers and boards are authored at their EXACT placed size, so the layout
  generator positions them at scale 1.0 and their chamfers never distort.

Conventions unchanged from v1: Blender Z-up (the exporter converts), origin at
the ground-contact centre, applied transforms, no cameras/lights/textures, and
material slots named for the Tile Forge's semantic contract —

    "tf_primary"  follows whatever approved palette entry the placement rolled
    "shadow"      pinned to the palette's shadow slot
    "accent"      pinned to the palette's accent slot

Run from the repository root:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/build_tile_forge_modules.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT_ROOT = ROOT / "tools" / "tile_forge" / "modules"

# Only for readability of a .glb opened on its own; the runtime rebinds by name.
PALETTE = {
    "tf_primary": "6E8B3B",
    "shadow": "395627",
    "accent": "8DA84A",
}

# Budgets from the art brief, checked per family and reported.
BUDGETS = {
    "grass": (40, 320),
    "straw": (40, 300),
    "leaves": (30, 300),
    "stones": (20, 100),
    "rubble": (20, 100),
    "boards": (24, 130),
    "pavers": (24, 130),
}

SMOOTH_ANGLE = math.radians(46.0)


# --------------------------------------------------------------------------
# Blender plumbing
# --------------------------------------------------------------------------


def srgb(hex_value: str) -> tuple[float, float, float, float]:
    values = [int(hex_value[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    linear = [
        v / 12.92 if v <= 0.04045 else ((v + 0.055) / 1.055) ** 2.4
        for v in values
    ]
    return (*linear, 1.0)


def material(name: str) -> bpy.types.Material:
    existing = bpy.data.materials.get(name)
    if existing is not None:
        return existing
    result = bpy.data.materials.new(name=name)
    result.use_nodes = True
    shader = result.node_tree.nodes["Principled BSDF"]
    shader.inputs["Base Color"].default_value = srgb(PALETTE.get(name, "888888"))
    shader.inputs["Roughness"].default_value = 0.95
    shader.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.22
    result.diffuse_color = srgb(PALETTE.get(name, "888888"))
    return result


class Builder:
    """Vertex/face accumulator carrying a material slot and a shading flag per
    face. Shading is declared per face rather than derived from an angle, so a
    barrel can be smooth while its own cap stays crisp."""

    def __init__(self) -> None:
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.slots: list[str] = []
        self.smooth: list[bool] = []

    def add(self, points) -> list[int]:
        start = len(self.verts)
        self.verts.extend(points)
        return list(range(start, start + len(points)))

    def face(self, indices, slot="tf_primary", smooth=False) -> None:
        if len(indices) < 3:
            return
        self.faces.append(tuple(indices))
        self.slots.append(slot)
        self.smooth.append(smooth)

    def quad(self, a, b, c, d, slot="tf_primary", smooth=False) -> None:
        self.face((a, b, c, d), slot, smooth)

    def bridge(self, lower, upper, slot="tf_primary", smooth=False) -> None:
        """Quad ring between two equal-length rings."""
        count = len(lower)
        for index in range(count):
            nxt = (index + 1) % count
            self.quad(lower[index], lower[nxt], upper[nxt], upper[index], slot, smooth)

    def cap(self, ring, slot="tf_primary", reverse=False, smooth=False) -> None:
        indices = list(reversed(ring)) if reverse else list(ring)
        self.face(indices, slot, smooth)


def commit(builder: Builder, name: str) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(builder.verts, [], builder.faces)
    mesh.validate(verbose=False)

    slots: list[str] = []
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


def apply_bevel(obj: bpy.types.Object, width: float, segments: int,
                angle_deg: float = 40.0, harden: bool = True) -> None:
    """The real chamfer. Constructed pieces get this; it is the difference
    between a slab that catches a highlight along its rim and a slab that looks
    like an untreated box."""
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new(name="Chamfer", type="BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(angle_deg)
    modifier.miter_outer = "MITER_ARC"
    modifier.harden_normals = harden and segments > 1
    if modifier.harden_normals:
        # harden_normals needs smooth shading to have anything to harden.
        for polygon in obj.data.polygons:
            polygon.use_smooth = True
    bpy.ops.object.modifier_apply(modifier="Chamfer")


def apply_weighted_normals(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new(name="WeightedNormal", type="WEIGHTED_NORMAL")
    modifier.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier="WeightedNormal")


def triangulate(obj: bpy.types.Object) -> None:
    bpy.context.view_layer.objects.active = obj
    modifier = obj.modifiers.new(name="Triangulate", type="TRIANGULATE")
    modifier.min_vertices = 5
    bpy.ops.object.modifier_apply(modifier="Triangulate")


def recentre(obj: bpy.types.Object) -> None:
    """Origin at the ground-contact centre: the XY centroid of the lowest ring,
    with z = 0 at the contact plane. Placement relies on this exactly."""
    mesh = obj.data
    lowest = min(v.co.z for v in mesh.vertices)
    contact = [v.co for v in mesh.vertices if v.co.z <= lowest + 1e-4]
    cx = sum(v.x for v in contact) / len(contact)
    cy = sum(v.y for v in contact) / len(contact)
    for vertex in mesh.vertices:
        vertex.co.x -= cx
        vertex.co.y -= cy
        vertex.co.z -= lowest
    mesh.update()


def export(obj: bpy.types.Object, family: str, name: str) -> dict:
    directory = OUT_ROOT / family
    directory.mkdir(parents=True, exist_ok=True)
    path = directory / f"{name}.glb"

    for other in bpy.context.scene.objects:
        other.select_set(other is obj)
    bpy.context.view_layer.objects.active = obj

    mesh = obj.data
    mesh.calc_loop_triangles()
    triangles = len(mesh.loop_triangles)
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]

    bpy.ops.export_scene.gltf(
        filepath=str(path),
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
        "family": family,
        "path": f"res://tools/tile_forge/modules/{family}/{name}.glb",
        "triangles": triangles,
        "vertices": len(mesh.vertices),
        "footprint_radius": round(
            max(max(abs(min(xs)), abs(max(xs))), max(abs(min(ys)), abs(max(ys)))), 4
        ),
        "size_x": round(max(xs) - min(xs), 4),
        "size_y": round(max(ys) - min(ys), 4),
        "height": round(max(zs) - min(zs), 4),
        "base_z": round(min(zs), 5),
        "materials": [m.name for m in mesh.materials],
    }


# --------------------------------------------------------------------------
# Volumetric primitives
# --------------------------------------------------------------------------


def ring(cx, cy, z, rx, ry, sides, phase, wobble, rng):
    points = []
    for index in range(sides):
        angle = phase + math.tau * index / sides
        scale = 1.0 + (rng.uniform(-wobble, wobble) if wobble > 0.0 else 0.0)
        points.append((cx + math.cos(angle) * rx * scale,
                       cy + math.sin(angle) * ry * scale,
                       z))
    return points


def blade(builder: Builder, base_x, base_y, heading, base_width, reach,
          height, sides, rng, tip_ratio=0.26, bend=0.55, slot="tf_primary"):
    """One thick tapered lobe — the unit every plant clump is built from.

    Four rings and a BLUNT CAP, never a point. The cross-section is a five- or
    six-gon shaded smooth along its length, so the lobe reads as a rounded
    volume; the cap stays flat so the tip still has a definite end. Its base
    ring is wide and planted, which is what stops a clump looking like cutlery
    standing in a pot.
    """
    direction = (math.cos(heading), math.sin(heading))
    # The lobe leans out along a shallow arc: straight lobes read as a fan of
    # identical shapes, and hard bends read as broken.
    def path(t):
        lean = reach * (t ** 1.35)
        rise = height * math.sin(t * math.pi * bend) / max(1e-5, math.sin(math.pi * bend))
        return (base_x + direction[0] * lean, base_y + direction[1] * lean, rise)

    widths = [1.0, 0.82, 0.52, tip_ratio]
    stops = [0.0, 0.36, 0.72, 1.0]
    rings = []
    phase = heading + math.pi * 0.5
    for index, t in enumerate(stops):
        px, py, pz = path(t)
        half = base_width * 0.5 * widths[index]
        # Slightly flattened across the lobe, the way a real leaf section is.
        rings.append(builder.add(
            ring(px, py, pz, half, half * 0.72, sides, phase, 0.0, rng)
        ))

    for index in range(len(rings) - 1):
        builder.bridge(rings[index], rings[index + 1], slot, smooth=True)
    builder.cap(rings[-1], slot, smooth=False)
    builder.cap(rings[0], "shadow", reverse=True, smooth=False)


def dome(builder: Builder, cx, cy, rx, ry, height, sides, rng, wobble=0.1,
         slot="tf_primary", base_slot="shadow", crown=0.62):
    """Broad planted mound. Used as the base every clump grows out of, and on
    its own as a moss cushion."""
    phase = rng.uniform(0.0, math.tau)
    lower = builder.add(ring(cx, cy, 0.0, rx, ry, sides, phase, wobble, rng))
    mid = builder.add(
        ring(cx, cy, height * crown, rx * 0.78, ry * 0.78, sides, phase, wobble * 0.6, rng)
    )
    top = builder.add(
        ring(cx, cy, height, rx * 0.34, ry * 0.34, sides, phase, wobble * 0.4, rng)
    )
    builder.bridge(lower, mid, base_slot, smooth=True)
    builder.bridge(mid, top, slot, smooth=True)
    builder.cap(top, slot, smooth=True)
    builder.cap(lower, base_slot, reverse=True)


def boulder(builder: Builder, cx, cy, rx, ry, height, sides, rng,
            slot="tf_primary", base_slot="shadow"):
    """Rounded asymmetric stone with a broad stable bottom and several large
    planar transitions. Flat-shaded so the chamfer added afterwards reads as a
    crisp highlight line rather than a smear."""
    phase = rng.uniform(0.0, math.tau)
    # Irregularity lives in the ring radii and in a lateral drift per level, so
    # the silhouette stays large and readable instead of getting crunchy.
    drift_x = rng.uniform(-0.16, 0.16) * rx
    drift_y = rng.uniform(-0.16, 0.16) * ry
    profile = [(0.0, 1.0), (0.52, 0.96), (1.0, 0.40)]
    rings = []
    for index, (t, scale) in enumerate(profile):
        rings.append(builder.add(ring(
            cx + drift_x * t,
            cy + drift_y * t,
            height * t,
            rx * scale,
            ry * scale,
            sides,
            phase + t * 0.5,
            0.13,
            rng,
        )))
    for index in range(len(rings) - 1):
        builder.bridge(rings[index], rings[index + 1], base_slot if index == 0 else slot)
    builder.cap(rings[-1], slot)
    builder.cap(rings[0], base_slot, reverse=True)


def wedge(builder: Builder, cx, cy, heading, length, width, thickness, rng,
          slot="tf_primary", taper=0.45, base_z=0.0):
    """A thick ribbon lying down: the straw and leaf unit. It is a solid with
    four rings along its length, not a card — a card is what made v1 straw look
    like crossed sticks."""
    direction = (math.cos(heading), math.sin(heading))
    across = (-direction[1], direction[0])
    stops = [-0.5, -0.16, 0.2, 0.5]
    widths = [taper, 1.0, 0.9, taper * 0.8]
    heights = [0.35, 1.0, 0.92, 0.4]
    lower_rings = []
    upper_rings = []
    for index, t in enumerate(stops):
        px = cx + direction[0] * length * t
        py = cy + direction[1] * length * t
        half = width * 0.5 * widths[index]
        top = thickness * heights[index]
        floor = base_z * (0.35 + 0.65 * heights[index])
        lower_rings.append(builder.add([
            (px + across[0] * half, py + across[1] * half, floor),
            (px - across[0] * half, py - across[1] * half, floor),
        ]))
        upper_rings.append(builder.add([
            (px + across[0] * half * 0.78, py + across[1] * half * 0.78, floor + top),
            (px - across[0] * half * 0.78, py - across[1] * half * 0.78, floor + top),
        ]))
    for index in range(len(stops) - 1):
        a, b = lower_rings[index], lower_rings[index + 1]
        c, d = upper_rings[index], upper_rings[index + 1]
        builder.quad(a[0], b[0], d[0], c[0], slot, smooth=True)      # outer side
        builder.quad(b[1], a[1], c[1], d[1], slot, smooth=True)      # inner side
        builder.quad(c[0], d[0], d[1], c[1], slot, smooth=False)     # top
        builder.quad(a[1], b[1], b[0], a[0], "shadow", smooth=False)  # underside
    builder.face((lower_rings[0][0], lower_rings[0][1], upper_rings[0][1],
                  upper_rings[0][0]), "shadow")
    builder.face((lower_rings[-1][1], lower_rings[-1][0], upper_rings[-1][0],
                  upper_rings[-1][1]), "shadow")


def rounded_rect(size_x, size_y, corner, segments):
    """CCW rounded rectangle outline in the XY plane."""
    hx, hy = size_x * 0.5, size_y * 0.5
    radius = min(corner, hx * 0.9, hy * 0.9)
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


def slab(builder: Builder, outline, thickness, top_heights=None,
         slot="tf_primary", side_slot="shadow"):
    """Extrudes a closed outline into a solid with an optionally uneven top.
    Rubble uses this raw form; constructed pieces use chamfered_slab."""
    lower = builder.add([(x, y, 0.0) for x, y in outline])
    if top_heights is None:
        top_heights = [thickness] * len(outline)
    upper = builder.add([(x, y, top_heights[i]) for i, (x, y) in enumerate(outline)])
    builder.bridge(lower, upper, side_slot)
    builder.cap(upper, slot)
    builder.cap(lower, side_slot, reverse=True)


def inset_outline(outline, amount):
    """Shrinks a convex outline towards its centroid. Rounded rectangles are
    convex, so this is exact and needs no edge-offset machinery."""
    cx = sum(x for x, _ in outline) / len(outline)
    cy = sum(y for _, y in outline) / len(outline)
    result = []
    for x, y in outline:
        dx, dy = x - cx, y - cy
        length = math.hypot(dx, dy)
        if length <= amount * 1.5:
            result.append((cx, cy))
        else:
            scale = (length - amount) / length
            result.append((cx + dx * scale, cy + dy * scale))
    return result


def chamfered_slab(builder: Builder, outline, thickness, chamfer,
                   top_heights=None, slot="tf_primary", side_slot="shadow"):
    """A constructed piece with an EXPLICIT top chamfer.

    Blender's bevel modifier produced the same read at four times the triangle
    count on an already-rounded outline, so the chamfer is built directly: three
    rings, one extra quad band, and a rim that catches the key light exactly the
    way the reference pieces do. The wide face stays flat, which is what keeps a
    paver a slab instead of a pillow.
    """
    if top_heights is None:
        top_heights = [thickness] * len(outline)
    shoulder = [h - chamfer for h in top_heights]
    top_points = inset_outline(outline, chamfer)

    lower = builder.add([(x, y, 0.0) for x, y in outline])
    mid = builder.add([(x, y, shoulder[i]) for i, (x, y) in enumerate(outline)])
    upper = builder.add([
        (x, y, top_heights[i]) for i, (x, y) in enumerate(top_points)
    ])
    builder.bridge(lower, mid, side_slot)
    # The chamfer band is smooth-shaded so it reads as a soft highlight rather
    # than as a second hard facet.
    builder.bridge(mid, upper, slot, smooth=True)
    builder.cap(upper, slot)
    builder.cap(lower, side_slot, reverse=True)


# --------------------------------------------------------------------------
# Families
# --------------------------------------------------------------------------


def grass_clump(name, seed, lobes, spread, height, base_ratio=0.30,
                sides=5, accent_every=0, lean=1.0) -> bpy.types.Object:
    """A soft stylised plant mass: a planted base dome with thick tapered lobes
    leaning in different directions. One hero lobe establishes the silhouette;
    the rest support it at descending heights."""
    rng = random.Random(seed)
    builder = Builder()
    # A LOW mound, not a plate. The first attempt used a wide flat dome and the
    # clump read as blades stuck in a hexagonal pot; the base only has to close
    # the bottom of the mass, so it stays small and gets buried by the lobes.
    dome(builder, 0.0, 0.0, spread * base_ratio, spread * base_ratio * 0.9,
         height * 0.17, 6, rng, wobble=0.08)

    heading = rng.uniform(0.0, math.tau)
    # Hero lobe: tallest, most upright, and slightly off-centre so the clump
    # has a direction rather than radial symmetry.
    blade(builder, spread * 0.05, 0.0, heading, spread * 0.46, spread * 0.18 * lean,
          height, sides, rng, tip_ratio=0.34, bend=0.70)
    for index in range(lobes - 1):
        heading += 2.39996 + rng.uniform(-0.5, 0.5)
        fall = 1.0 - 0.38 * (index + 1) / max(1, lobes - 1)
        # Lobes start close to the centre and lean only a little, so they
        # overlap into one mass instead of splaying out like an agave.
        offset = spread * rng.uniform(0.05, 0.17)
        blade(
            builder,
            math.cos(heading) * offset,
            math.sin(heading) * offset,
            heading,
            spread * rng.uniform(0.34, 0.46),
            spread * rng.uniform(0.32, 0.50) * lean,
            height * fall * rng.uniform(0.8, 1.0),
            sides,
            rng,
            tip_ratio=rng.uniform(0.28, 0.38),
            bend=rng.uniform(0.50, 0.64),
            slot=("accent" if accent_every > 0 and index % accent_every == 0
                  else "tf_primary"),
        )
    return commit(builder, name)


def moss_cluster(name, seed, blobs, spread, height) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    dome(builder, 0.0, 0.0, spread * 0.54, spread * 0.48, height, 7, rng, 0.12)
    heading = rng.uniform(0.0, math.tau)
    for index in range(blobs - 1):
        heading += 2.2 + rng.uniform(-0.7, 0.7)
        distance = spread * rng.uniform(0.3, 0.46)
        dome(
            builder,
            math.cos(heading) * distance,
            math.sin(heading) * distance,
            spread * rng.uniform(0.3, 0.42),
            spread * rng.uniform(0.28, 0.4),
            height * rng.uniform(0.55, 0.85),
            6, rng, 0.12,
        )
    return commit(builder, name)


def straw_mass(name, seed, pieces, spread, height) -> bpy.types.Object:
    """A compact golden sheaf.

    Built from the same tapered lobes as a grass clump, but flatter, wider, and
    leaning further out, with every third lobe taking the accent tone. The
    earlier ribbon-on-a-mound version presented its dark undersides to the
    camera and read as a shell; lobes keep their lit faces up.
    """
    return grass_clump(
        name, seed, pieces, spread, height,
        base_ratio=0.34, sides=4, accent_every=3, lean=1.45
    )


def leaf_cluster(name, seed, leaves, spread, height) -> bpy.types.Object:
    """Low, wide, and almost flat: leaf litter caught in a drift. Same lobes,
    strongly leant over so they lie rather than stand."""
    return grass_clump(
        name, seed, leaves, spread, height,
        base_ratio=0.36, sides=4, accent_every=2, lean=1.8
    )


def stone(name, seed, width, depth, height, sides) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    boulder(builder, 0.0, 0.0, width * 0.5, depth * 0.5, height, sides, rng)
    return commit(builder, name)


def rubble_piece(name, seed, width, depth, height, sides) -> bpy.types.Object:
    """A broken chunk: broad flat bottom, one proud edge, large planar faces."""
    rng = random.Random(seed)
    builder = Builder()
    outline = []
    phase = rng.uniform(0.0, math.tau)
    for index in range(sides):
        angle = phase + math.tau * index / sides + rng.uniform(-0.2, 0.2)
        r = 1.0 + rng.uniform(-0.22, 0.22)
        outline.append((math.cos(angle) * width * 0.5 * r,
                        math.sin(angle) * depth * 0.5 * r))
    lean = rng.uniform(0.0, math.tau)
    tops = []
    for x, y in outline:
        along = (x * math.cos(lean) + y * math.sin(lean)) / max(1e-5, width * 0.5)
        tops.append(height * (0.44 + 0.56 * max(0.0, min(1.0, 0.5 + along * 0.5))))
    slab(builder, outline, height, tops)
    return commit(builder, name)


def paver(name, seed, size_x, size_y, thickness, corner) -> bpy.types.Object:
    """A broad slab with substantial thickness, softly rounded corners, and a
    mostly flat top. Authored at its exact placed size so the layout generator
    never has to scale it and distort the chamfer."""
    rng = random.Random(seed)
    builder = Builder()
    outline = rounded_rect(size_x, size_y, corner, 1)
    # A whisper of top unevenness: identical flat tops across nine pavers read
    # as one printed sheet.
    tops = [thickness + rng.uniform(-0.0015, 0.0015) for _ in outline]
    chamfered_slab(builder, outline, thickness, thickness * 0.30, tops)
    return commit(builder, name)


def board(name, seed, length, width, thickness) -> bpy.types.Object:
    """Broad, thick, softly bevelled, subtly irregular. Never a thin strip."""
    rng = random.Random(seed)
    builder = Builder()
    outline = rounded_rect(length, width, min(width * 0.14, 0.030), 1)
    tops = [thickness + rng.uniform(-0.002, 0.002) for _ in outline]
    chamfered_slab(builder, outline, thickness, thickness * 0.28, tops)
    return commit(builder, name)


# --------------------------------------------------------------------------
# Library definition
# --------------------------------------------------------------------------

# (family, id, factory, kwargs, bevel(width, segments) or None)
LIBRARY = [
    # --- grass: five clumps, chunky and readable at gameplay distance --------
    ("grass", "gf_clump_hero_a", grass_clump,
     dict(seed=101, lobes=8, spread=0.33, height=0.165), None),
    ("grass", "gf_clump_hero_b", grass_clump,
     dict(seed=102, lobes=8, spread=0.31, height=0.150, sides=6), None),
    ("grass", "gf_clump_mid_a", grass_clump,
     dict(seed=103, lobes=7, spread=0.27, height=0.130), None),
    ("grass", "gf_clump_mid_b", grass_clump,
     dict(seed=104, lobes=6, spread=0.25, height=0.118), None),
    ("grass", "gf_clump_small_a", grass_clump,
     dict(seed=105, lobes=5, spread=0.19, height=0.092), None),
    ("grass", "gf_clump_small_b", grass_clump,
     dict(seed=106, lobes=5, spread=0.17, height=0.082), None),
    ("grass", "gf_moss_a", moss_cluster, dict(seed=111, blobs=3, spread=0.26, height=0.070), None),
    ("grass", "gf_moss_b", moss_cluster, dict(seed=112, blobs=4, spread=0.30, height=0.082), None),
    ("grass", "gf_moss_c", moss_cluster, dict(seed=113, blobs=2, spread=0.20, height=0.058), None),

    # --- straw: chunky masses, not sticks -----------------------------------
    ("straw", "gf_straw_a", straw_mass, dict(seed=201, pieces=7, spread=0.30, height=0.110), None),
    ("straw", "gf_straw_b", straw_mass, dict(seed=202, pieces=8, spread=0.32, height=0.098), None),
    ("straw", "gf_straw_c", straw_mass, dict(seed=203, pieces=6, spread=0.26, height=0.118), None),
    ("straw", "gf_straw_d", straw_mass, dict(seed=204, pieces=7, spread=0.28, height=0.090), None),
    ("straw", "gf_straw_e", straw_mass, dict(seed=205, pieces=5, spread=0.21, height=0.100), None),

    # --- leaves --------------------------------------------------------------
    ("leaves", "gf_leaf_a", leaf_cluster, dict(seed=301, leaves=6, spread=0.28, height=0.068), None),
    ("leaves", "gf_leaf_b", leaf_cluster, dict(seed=302, leaves=7, spread=0.31, height=0.060), None),
    ("leaves", "gf_leaf_c", leaf_cluster, dict(seed=303, leaves=5, spread=0.23, height=0.066), None),
    ("leaves", "gf_leaf_d", leaf_cluster, dict(seed=304, leaves=6, spread=0.25, height=0.056), None),

    # --- stones: three small, three medium, two hero ------------------------
    ("stones", "gf_stone_small_a", stone,
     dict(seed=401, width=0.145, depth=0.125, height=0.075, sides=6), (0.008, 1)),
    ("stones", "gf_stone_small_b", stone,
     dict(seed=402, width=0.130, depth=0.140, height=0.068, sides=6), (0.008, 1)),
    ("stones", "gf_stone_small_c", stone,
     dict(seed=403, width=0.160, depth=0.130, height=0.082, sides=5), (0.008, 1)),
    ("stones", "gf_stone_mid_a", stone,
     dict(seed=411, width=0.225, depth=0.195, height=0.118, sides=6), (0.010, 1)),
    ("stones", "gf_stone_mid_b", stone,
     dict(seed=412, width=0.205, depth=0.230, height=0.130, sides=6), (0.010, 1)),
    ("stones", "gf_stone_mid_c", stone,
     dict(seed=413, width=0.250, depth=0.210, height=0.105, sides=7), (0.010, 1)),
    ("stones", "gf_stone_hero_a", stone,
     dict(seed=421, width=0.330, depth=0.285, height=0.190, sides=7), (0.012, 1)),
    ("stones", "gf_stone_hero_b", stone,
     dict(seed=422, width=0.300, depth=0.330, height=0.175, sides=6), (0.012, 1)),

    # --- rubble --------------------------------------------------------------
    ("rubble", "gf_rubble_hero", rubble_piece,
     dict(seed=501, width=0.310, depth=0.255, height=0.115, sides=5), (0.012, 1)),
    ("rubble", "gf_rubble_mid_a", rubble_piece,
     dict(seed=502, width=0.235, depth=0.200, height=0.090, sides=5), (0.010, 1)),
    ("rubble", "gf_rubble_mid_b", rubble_piece,
     dict(seed=503, width=0.210, depth=0.245, height=0.082, sides=6), (0.010, 1)),
    ("rubble", "gf_rubble_small_a", rubble_piece,
     dict(seed=504, width=0.155, depth=0.135, height=0.062, sides=5), (0.008, 1)),
    ("rubble", "gf_rubble_small_b", rubble_piece,
     dict(seed=505, width=0.140, depth=0.160, height=0.055, sides=5), (0.008, 1)),

    # --- pavers: authored at exact placed sizes for a 1.35 m tile -----------
    # 2x2 with a 0.030 seam: (1.35 - 0.030) / 2 = 0.660
    ("pavers", "gf_paver_large", paver,
     dict(seed=601, size_x=0.660, size_y=0.660, thickness=0.058, corner=0.055), None),
    ("pavers", "gf_paver_large_alt", paver,
     dict(seed=602, size_x=0.660, size_y=0.660, thickness=0.054, corner=0.070), None),
    # 3x3 with a 0.030 seam: (1.35 - 0.060) / 3 = 0.430
    ("pavers", "gf_paver_mid", paver,
     dict(seed=603, size_x=0.430, size_y=0.430, thickness=0.052, corner=0.045), None),
    ("pavers", "gf_paver_mid_alt", paver,
     dict(seed=604, size_x=0.430, size_y=0.430, thickness=0.048, corner=0.058), None),
    # Wide filler: spans two 3x3 cells plus their seam.
    ("pavers", "gf_paver_wide", paver,
     dict(seed=605, size_x=0.890, size_y=0.430, thickness=0.055, corner=0.048), None),
    ("pavers", "gf_paver_tall", paver,
     dict(seed=606, size_x=0.430, size_y=0.890, thickness=0.055, corner=0.048), None),
    # Small support piece for a mixed layout.
    ("pavers", "gf_paver_small", paver,
     dict(seed=607, size_x=0.300, size_y=0.300, thickness=0.046, corner=0.038), None),

    # --- boards: broad and thick, authored for a 1.35 m deck ---------------
    # 3 boards with a 0.026 seam: (1.35 - 0.052) / 3 = 0.4326
    ("boards", "gf_board_a", board,
     dict(seed=701, length=1.350, width=0.4326, thickness=0.062), None),
    ("boards", "gf_board_b", board,
     dict(seed=702, length=1.350, width=0.4326, thickness=0.058), None),
    ("boards", "gf_board_c", board,
     dict(seed=703, length=1.350, width=0.4326, thickness=0.066), None),
    # 4-board variant: (1.35 - 0.078) / 4 = 0.318
    ("boards", "gf_board_narrow_a", board,
     dict(seed=711, length=1.350, width=0.318, thickness=0.060), None),
    ("boards", "gf_board_narrow_b", board,
     dict(seed=712, length=1.350, width=0.318, thickness=0.055), None),
    # Half-length board for a staggered joint.
    ("boards", "gf_board_half", board,
     dict(seed=721, length=0.662, width=0.4326, thickness=0.060), None),
]


def main() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    entries = []
    problems = []
    for family, name, factory, kwargs, bevel in LIBRARY:
        obj = factory(name, **kwargs)
        if bevel is not None:
            apply_bevel(obj, bevel[0], bevel[1])
        apply_weighted_normals(obj)
        triangulate(obj)
        recentre(obj)
        record = export(obj, family, name)
        entries.append(record)

        low, high = BUDGETS.get(family, (0, 10_000))
        if not (low <= record["triangles"] <= high):
            problems.append(
                "%s: %d tris outside the %s budget %d-%d"
                % (name, record["triangles"], family, low, high)
            )
        if abs(record["base_z"]) > 1e-4:
            problems.append("%s: contact plane at z=%s, not 0" % (name, record["base_z"]))
        widest = max(record["size_x"], record["size_y"])
        if family in ("grass", "straw", "leaves", "stones", "rubble") and widest < 0.085:
            problems.append(
                "%s: %.3f m wide reads as a dot at the gameplay camera" % (name, widest)
            )
        bpy.data.objects.remove(obj, do_unlink=True)

    report = {
        "modules": entries,
        "count": len(entries),
        "families": sorted({e["family"] for e in entries}),
        "total_triangles": sum(e["triangles"] for e in entries),
        "problems": problems,
    }
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    (OUT_ROOT / "build_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    for line in problems:
        print("PROBLEM %s" % line)
    print("TILE FORGE MODULES v2: %d exported, %d problems, %d tris total" % (
        len(entries), len(problems), report["total_triangles"]
    ))


if __name__ == "__main__":
    main()
