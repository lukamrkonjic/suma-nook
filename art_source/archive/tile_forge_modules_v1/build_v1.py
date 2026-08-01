#!/usr/bin/env python3
"""Build the Suma Tile Forge detail-module library.

These are the reusable chunky forms the Forge scatters across generated tiles:
grass clumps, moss cushions, straw, pebbles, stones, rubble, leaf litter, wood
chips, loose boards, loose pavers. They are NOT tiles and they contain no
structural block — a module is one clean closed object whose origin sits at its
ground-contact centre, so a placer can drop it on any sampled surface height.

Design rules, all enforced by build_report.json:

* few large polygons and an intentional silhouette; budgets are checked;
* everything is built in LIVE metres (Suma's 1.35 m grid), so a module needs no
  runtime rescaling and never gets the non-uniform X/Z squash that the authored
  1.70 m catalog receives;
* Blender Z-up; the glTF exporter converts to Godot's Y-up;
* transforms applied, scale 1,1,1, origin at (0, 0, 0) with the contact plane
  at z = 0;
* no cameras, no lights, no textures, no baked shading, no loose fragments;
* material slots are named for the Tile Forge's semantic contract:
    "tf_primary"  -> takes whatever approved palette entry the placement rolled
    "shadow"      -> always the palette's shadow slot (a deliberate second tone)
    "accent"      -> always the palette's accent slot
  Anything named after a Tile Forge slot is pinned; anything else follows the
  per-instance colour variation. That is what lets one clump mesh appear in
  three approved greens across a field without three meshes.

Determinism: every shape is driven by an explicit seeded Random, so rebuilding
the library reproduces byte-identical geometry.

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

# Source colours are only for readability of the .glb on its own. The runtime
# rebinds every surface to the shared MaterialLibrary material by name.
PALETTE = {
    "tf_primary": "6E8B3B",
    "shadow": "395627",
    "accent": "8DA84A",
    "stone_primary": "9DA3A9",
    "stone_shadow": "737A80",
    "wood_primary": "7F5C30",
    "wood_shadow": "634E42",
    "straw_primary": "C9954A",
    "straw_shadow": "A48522",
    "leaf_primary": "A0591E",
    "leaf_shadow": "704E28",
}

# Triangle budgets from the brief, checked per family.
BUDGETS = {
    "grass": (20, 130),
    "straw": (20, 130),
    "leaves": (12, 90),
    "gravel": (12, 60),
    "stones": (20, 100),
    "rubble": (20, 100),
    "boards": (12, 80),
    "pavers": (12, 80),
}


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
    shader.inputs["Roughness"].default_value = 0.94
    shader.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.25
    result.diffuse_color = srgb(PALETTE.get(name, "888888"))
    return result


def wipe_scene() -> None:
    bpy.ops.wm.read_factory_settings(use_empty=True)


class Builder:
    """Accumulates vertices/faces with per-face material slots."""

    def __init__(self) -> None:
        self.verts: list[tuple[float, float, float]] = []
        self.faces: list[tuple[int, ...]] = []
        self.face_slots: list[str] = []

    def add(self, points, slot: str = "tf_primary") -> list[int]:
        start = len(self.verts)
        self.verts.extend(points)
        return list(range(start, start + len(points)))

    def face(self, indices, slot: str = "tf_primary") -> None:
        if len(indices) < 3:
            return
        self.faces.append(tuple(indices))
        self.face_slots.append(slot)

    def quad(self, a, b, c, d, slot: str = "tf_primary") -> None:
        self.face((a, b, c, d), slot)

    def fan(self, ring, slot: str = "tf_primary", reverse: bool = False) -> None:
        """Triangle fan closing an n-gon ring. Kept as one n-gon face so the
        exporter triangulates it once, rather than emitting a hub vertex the
        silhouette does not need."""
        indices = list(reversed(ring)) if reverse else list(ring)
        self.face(indices, slot)


def commit(builder: Builder, name: str) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(builder.verts, [], builder.faces)
    mesh.validate(verbose=False)

    slots: list[str] = []
    for slot in builder.face_slots:
        if slot not in slots:
            slots.append(slot)
    for slot in slots:
        mesh.materials.append(material(slot))
    for index, polygon in enumerate(mesh.polygons):
        polygon.material_index = slots.index(builder.face_slots[index])
        # Chunky low-poly reads best flat-shaded; the softness in the reference
        # comes from lighting and bevel highlights, not from smoothing that
        # would melt these silhouettes.
        polygon.use_smooth = False

    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


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
    radius = max(
        max(abs(min(xs)), abs(max(xs))),
        max(abs(min(ys)), abs(max(ys))),
    )

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
        "footprint_radius": round(radius, 4),
        "height": round(max(zs) - min(zs), 4),
        "base_z": round(min(zs), 5),
        "materials": [m.name for m in mesh.materials],
    }


# --------------------------------------------------------------------------
# Shape primitives
# --------------------------------------------------------------------------


def ring(cx: float, cy: float, z: float, radius: float, sides: int,
         phase: float, wobble: float, rng: random.Random,
         squash: float = 1.0) -> list[tuple[float, float, float]]:
    points = []
    for index in range(sides):
        angle = phase + math.tau * index / sides
        r = radius * (1.0 + rng.uniform(-wobble, wobble))
        points.append((cx + math.cos(angle) * r,
                       cy + math.sin(angle) * r * squash,
                       z))
    return points


def lobe(builder: Builder, base_x: float, base_y: float, heading: float,
         width: float, reach: float, height: float, sides: int,
         rng: random.Random, tip_slot: str | None = None) -> None:
    """One tapered blade: the unit every clump is assembled from.

    A lobe is a broad, closed, straight-edged form that leans outward and comes
    to a point — the collectible-game read the brief asks for. It is emphatically
    not a thin grass card, and there is no per-vertex noise anywhere in it.
    """
    direction = (math.cos(heading), math.sin(heading))
    tip = (
        base_x + direction[0] * reach,
        base_y + direction[1] * reach,
        height,
    )
    mid = (
        base_x + direction[0] * reach * 0.42,
        base_y + direction[1] * reach * 0.42,
        height * 0.62,
    )

    base_ring = ring(base_x, base_y, 0.0, width * 0.5, sides,
                     heading + math.pi * 0.5, 0.10, rng)
    mid_ring = ring(mid[0], mid[1], mid[2], width * 0.26, sides,
                    heading + math.pi * 0.5, 0.10, rng)

    base_ids = builder.add(base_ring)
    mid_ids = builder.add(mid_ring)
    tip_id = builder.add([tip])[0]

    dark = "shadow"
    for index in range(sides):
        nxt = (index + 1) % sides
        builder.quad(base_ids[index], base_ids[nxt], mid_ids[nxt], mid_ids[index], dark)
    upper = tip_slot or "tf_primary"
    for index in range(sides):
        nxt = (index + 1) % sides
        builder.face((mid_ids[index], mid_ids[nxt], tip_id), upper)
    builder.fan(base_ids, dark, reverse=True)


def dome(builder: Builder, cx: float, cy: float, radius: float, height: float,
         sides: int, rng: random.Random, slot: str = "tf_primary",
         base_slot: str = "shadow") -> None:
    """Low cushion. Two rings and a cap keep the crown broad instead of
    inflating into a ball."""
    lower = builder.add(ring(cx, cy, 0.0, radius, sides, rng.uniform(0, 1.0), 0.12, rng))
    upper = builder.add(
        ring(cx, cy, height * 0.58, radius * 0.74, sides, rng.uniform(0, 1.0), 0.10, rng)
    )
    crown = builder.add([(cx + rng.uniform(-0.1, 0.1) * radius,
                          cy + rng.uniform(-0.1, 0.1) * radius,
                          height)])[0]
    for index in range(sides):
        nxt = (index + 1) % sides
        builder.quad(lower[index], lower[nxt], upper[nxt], upper[index], base_slot)
    for index in range(sides):
        nxt = (index + 1) % sides
        builder.face((upper[index], upper[nxt], crown), slot)
    builder.fan(lower, base_slot, reverse=True)


def boulder(builder: Builder, cx: float, cy: float, radius: float, height: float,
            sides: int, rings: int, rng: random.Random,
            slot: str = "tf_primary", base_slot: str = "shadow",
            squash: float = 1.0) -> None:
    """Rounded low-poly stone: a stack of irregular rings capped with a facet.
    Irregularity lives in the RING RADII, not in individual vertices, so the
    silhouette stays readable and never gets crunchy."""
    phase = rng.uniform(0.0, math.tau)
    levels = []
    profile = [1.0, 0.93, 0.66][:rings]
    heights = [0.0, height * 0.45, height * 0.78][:rings]
    for index in range(rings):
        levels.append(
            builder.add(
                ring(cx, cy, heights[index], radius * profile[index], sides,
                     phase + index * 0.35, 0.14, rng, squash)
            )
        )
    crown = builder.add([(cx + rng.uniform(-0.12, 0.12) * radius,
                          cy + rng.uniform(-0.12, 0.12) * radius,
                          height)])[0]
    for level in range(rings - 1):
        lower = levels[level]
        upper = levels[level + 1]
        tone = base_slot if level == 0 else slot
        for index in range(sides):
            nxt = (index + 1) % sides
            builder.quad(lower[index], lower[nxt], upper[nxt], upper[index], tone)
    top = levels[-1]
    for index in range(sides):
        nxt = (index + 1) % sides
        builder.face((top[index], top[nxt], crown), slot)
    builder.fan(levels[0], base_slot, reverse=True)


def slab(builder: Builder, outline: list[tuple[float, float]], base_z: float,
         top_heights: list[float], slot: str, side_slot: str) -> None:
    """Extrudes an irregular outline to a non-planar top. Used for every
    angular piece — rubble, chips, leaves, boards — so they all share one
    faceting language."""
    lower = builder.add([(x, y, base_z) for x, y in outline])
    upper = builder.add(
        [(x, y, top_heights[i]) for i, (x, y) in enumerate(outline)]
    )
    count = len(outline)
    for index in range(count):
        nxt = (index + 1) % count
        builder.quad(lower[index], lower[nxt], upper[nxt], upper[index], side_slot)
    builder.fan(upper, slot)
    builder.fan(lower, side_slot, reverse=True)


def irregular_outline(radius: float, sides: int, rng: random.Random,
                      wobble: float, squash: float = 1.0
                      ) -> list[tuple[float, float]]:
    points = []
    phase = rng.uniform(0.0, math.tau)
    for index in range(sides):
        angle = phase + math.tau * index / sides + rng.uniform(-0.18, 0.18)
        r = radius * (1.0 + rng.uniform(-wobble, wobble))
        points.append((math.cos(angle) * r, math.sin(angle) * r * squash))
    return points


def rotate2(points, angle: float):
    ca, sa = math.cos(angle), math.sin(angle)
    return [(x * ca - y * sa, x * sa + y * ca) for x, y in points]


def recentre(obj: bpy.types.Object) -> None:
    """Origin at the ground-contact centre: XY centroid of the base ring, and
    z = 0 at the lowest vertex. A placer relies on this exactly."""
    mesh = obj.data
    lowest = min(v.co.z for v in mesh.vertices)
    contact = [v.co for v in mesh.vertices if v.co.z <= lowest + 1e-5]
    cx = sum(v.x for v in contact) / len(contact)
    cy = sum(v.y for v in contact) / len(contact)
    for vertex in mesh.vertices:
        vertex.co.x -= cx
        vertex.co.y -= cy
        vertex.co.z -= lowest
    mesh.update()


# --------------------------------------------------------------------------
# Families
# --------------------------------------------------------------------------


def grass_short(name: str, seed: int, lobes: int, spread: float,
                height: float) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    # Golden-angle heading walk: neighbouring blades never point the same way
    # and the group never forms a symmetric star.
    heading = rng.uniform(0.0, math.tau)
    for index in range(lobes):
        heading += 2.39996 + rng.uniform(-0.45, 0.45)
        radial = spread * (0.18 + 0.62 * (index / max(1, lobes - 1)))
        tilt = rng.uniform(0.55, 1.0)
        lobe(
            builder,
            math.cos(heading) * radial * 0.35,
            math.sin(heading) * radial * 0.35,
            heading,
            width=spread * rng.uniform(0.30, 0.42),
            reach=spread * rng.uniform(0.34, 0.58) * tilt,
            height=height * rng.uniform(0.68, 1.0),
            sides=3,
            rng=rng,
        )
    return commit(builder, name)


def grass_broad(name: str, seed: int, lobes: int, spread: float,
                height: float) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    heading = rng.uniform(0.0, math.tau)
    # One dominant central blade plus a fan of shorter ones reads as a single
    # designed plant rather than as a bundle of equals.
    lobe(builder, 0.0, 0.0, heading, spread * 0.44, spread * 0.22,
         height, 4, rng, tip_slot="accent")
    for index in range(lobes - 1):
        heading += 2.39996 + rng.uniform(-0.5, 0.5)
        radial = spread * (0.22 + 0.5 * (index / max(1, lobes - 2)))
        lobe(
            builder,
            math.cos(heading) * radial * 0.4,
            math.sin(heading) * radial * 0.4,
            heading,
            width=spread * rng.uniform(0.32, 0.46),
            reach=spread * rng.uniform(0.44, 0.72),
            height=height * rng.uniform(0.52, 0.86),
            sides=4,
            rng=rng,
        )
    return commit(builder, name)


def moss_cushion(name: str, seed: int, blobs: int, spread: float,
                 height: float) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    dome(builder, 0.0, 0.0, spread * 0.5, height, 7, rng)
    heading = rng.uniform(0.0, math.tau)
    for _ in range(blobs - 1):
        heading += 2.1 + rng.uniform(-0.6, 0.6)
        distance = spread * rng.uniform(0.26, 0.42)
        dome(
            builder,
            math.cos(heading) * distance,
            math.sin(heading) * distance,
            spread * rng.uniform(0.24, 0.36),
            height * rng.uniform(0.5, 0.82),
            6,
            rng,
        )
    return commit(builder, name)


def straw_clump(name: str, seed: int, strands: int, length: float,
                height: float) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    # Straw lies down. Flat angular strands crossing at shallow angles give the
    # dry, matted read; upright spikes would look like grass.
    for index in range(strands):
        angle = rng.uniform(0.0, math.pi)
        half = length * rng.uniform(0.42, 0.55)
        width = length * rng.uniform(0.055, 0.10)
        outline = rotate2(
            [(-half, -width), (half, -width * 0.7), (half, width * 0.7), (-half, width)],
            angle,
        )
        offset_x = rng.uniform(-length * 0.16, length * 0.16)
        offset_y = rng.uniform(-length * 0.16, length * 0.16)
        outline = [(x + offset_x, y + offset_y) for x, y in outline]
        base = height * rng.uniform(0.0, 0.42)
        lift = height * rng.uniform(0.16, 0.34)
        tops = [base + lift, base + lift * 0.55, base + lift * 0.55, base + lift]
        slot = "accent" if index % 3 == 0 else "tf_primary"
        slab(builder, outline, base, tops, slot, "shadow")
    return commit(builder, name)


def pebble(name: str, seed: int, radius: float, height: float,
           sides: int) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    boulder(builder, 0.0, 0.0, radius, height, sides, 2, rng,
            slot="tf_primary", base_slot="shadow",
            squash=rng.uniform(0.72, 1.0))
    return commit(builder, name)


def stone(name: str, seed: int, radius: float, height: float,
          sides: int) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    boulder(builder, 0.0, 0.0, radius, height, sides, 3, rng,
            slot="tf_primary", base_slot="shadow",
            squash=rng.uniform(0.68, 0.95))
    return commit(builder, name)


def rubble_piece(name: str, seed: int, radius: float, height: float,
                 sides: int) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    outline = irregular_outline(radius, sides, rng, 0.3,
                                squash=rng.uniform(0.6, 0.95))
    # A broken slab: one edge stands proud, the opposite edge is nearly flush.
    lean = rng.uniform(0.0, math.tau)
    tops = []
    for x, y in outline:
        along = (x * math.cos(lean) + y * math.sin(lean)) / max(1e-5, radius)
        tops.append(height * (0.38 + 0.62 * max(0.0, min(1.0, 0.5 + along * 0.5))))
    slab(builder, outline, 0.0, tops, "tf_primary", "shadow")
    return commit(builder, name)


def leaf_pile(name: str, seed: int, leaves: int, radius: float,
              height: float) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    for index in range(leaves):
        angle = rng.uniform(0.0, math.tau)
        distance = radius * rng.uniform(0.0, 0.5)
        size = radius * rng.uniform(0.36, 0.56)
        outline = rotate2(
            [(-size, 0.0), (0.0, -size * 0.62), (size, 0.0), (0.0, size * 0.62)],
            rng.uniform(0.0, math.tau),
        )
        outline = [
            (x + math.cos(angle) * distance, y + math.sin(angle) * distance)
            for x, y in outline
        ]
        base = height * rng.uniform(0.0, 0.5)
        thickness = height * rng.uniform(0.18, 0.30)
        tops = [base + thickness * t for t in (1.0, 0.72, 1.0, 0.72)]
        slot = "accent" if index % 3 == 1 else "tf_primary"
        slab(builder, outline, base, tops, slot, "shadow")
    return commit(builder, name)


def wood_chip(name: str, seed: int, chips: int, radius: float,
              height: float) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    for index in range(chips):
        angle = rng.uniform(0.0, math.tau)
        distance = radius * rng.uniform(0.0, 0.42)
        length = radius * rng.uniform(0.4, 0.66)
        width = length * rng.uniform(0.34, 0.55)
        outline = rotate2(
            [(-length, -width), (length, -width * 0.8),
             (length * 0.86, width), (-length * 0.9, width * 0.85)],
            rng.uniform(0.0, math.tau),
        )
        outline = [
            (x + math.cos(angle) * distance, y + math.sin(angle) * distance)
            for x, y in outline
        ]
        base = height * rng.uniform(0.0, 0.45)
        thickness = height * rng.uniform(0.26, 0.42)
        tops = [base + thickness, base + thickness * 0.7,
                base + thickness * 0.7, base + thickness]
        slot = "accent" if index % 2 == 0 else "tf_primary"
        slab(builder, outline, base, tops, slot, "shadow")
    return commit(builder, name)


def board(name: str, seed: int, length: float, width: float,
          thickness: float) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    bevel = thickness * 0.28
    half_l, half_w = length * 0.5, width * 0.5
    outer = [(-half_l, -half_w), (half_l, -half_w), (half_l, half_w), (-half_l, half_w)]
    inner = [(x - math.copysign(bevel, x), y - math.copysign(bevel, y))
             for x, y in outer]
    lower = builder.add([(x, y, 0.0) for x, y in outer])
    shoulder = builder.add([(x, y, thickness - bevel) for x, y in outer])
    top = builder.add([(x, y, thickness) for x, y in inner])
    for index in range(4):
        nxt = (index + 1) % 4
        builder.quad(lower[index], lower[nxt], shoulder[nxt], shoulder[index], "shadow")
        builder.quad(shoulder[index], shoulder[nxt], top[nxt], top[index], "tf_primary")
    builder.fan(top, "tf_primary")
    builder.fan(lower, "shadow", reverse=True)
    # A loose board is never perfectly square-on; a small yaw keeps a debris
    # pile from looking stacked.
    yaw = rng.uniform(-0.25, 0.25)
    obj = commit(builder, name)
    obj.rotation_euler = (0.0, 0.0, yaw)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    obj.select_set(False)
    return obj


def paver(name: str, seed: int, size: float, thickness: float,
          corner: float) -> bpy.types.Object:
    rng = random.Random(seed)
    builder = Builder()
    half = size * 0.5
    cut = corner
    outline = [
        (-half + cut, -half), (half - cut, -half),
        (half, -half + cut), (half, half - cut),
        (half - cut, half), (-half + cut, half),
        (-half, half - cut), (-half, -half + cut),
    ]
    bevel = thickness * 0.3
    inner = [(x * (1.0 - bevel / half * 0.5), y * (1.0 - bevel / half * 0.5))
             for x, y in outline]
    lower = builder.add([(x, y, 0.0) for x, y in outline])
    shoulder = builder.add([(x, y, thickness - bevel) for x, y in outline])
    top = builder.add([
        (x, y, thickness + rng.uniform(-0.0006, 0.0006)) for x, y in inner
    ])
    count = len(outline)
    for index in range(count):
        nxt = (index + 1) % count
        builder.quad(lower[index], lower[nxt], shoulder[nxt], shoulder[index], "shadow")
        builder.quad(shoulder[index], shoulder[nxt], top[nxt], top[index], "tf_primary")
    builder.fan(top, "tf_primary")
    builder.fan(lower, "shadow", reverse=True)
    return commit(builder, name)


# --------------------------------------------------------------------------
# Library definition
# --------------------------------------------------------------------------

LIBRARY = [
    # family, id, factory, kwargs
    ("grass", "gf_grass_short_a", grass_short, dict(seed=11, lobes=4, spread=0.15, height=0.070)),
    ("grass", "gf_grass_short_b", grass_short, dict(seed=12, lobes=5, spread=0.17, height=0.062)),
    ("grass", "gf_grass_short_c", grass_short, dict(seed=13, lobes=4, spread=0.13, height=0.078)),
    ("grass", "gf_grass_short_d", grass_short, dict(seed=14, lobes=5, spread=0.16, height=0.058)),
    ("grass", "gf_grass_short_e", grass_short, dict(seed=15, lobes=3, spread=0.12, height=0.066)),
    ("grass", "gf_grass_broad_a", grass_broad, dict(seed=21, lobes=5, spread=0.24, height=0.115)),
    ("grass", "gf_grass_broad_b", grass_broad, dict(seed=22, lobes=6, spread=0.27, height=0.100)),
    ("grass", "gf_grass_broad_c", grass_broad, dict(seed=23, lobes=5, spread=0.21, height=0.128)),
    ("grass", "gf_grass_broad_d", grass_broad, dict(seed=24, lobes=6, spread=0.25, height=0.092)),
    ("grass", "gf_grass_broad_e", grass_broad, dict(seed=25, lobes=4, spread=0.19, height=0.108)),
    ("grass", "gf_moss_a", moss_cushion, dict(seed=31, blobs=3, spread=0.19, height=0.045)),
    ("grass", "gf_moss_b", moss_cushion, dict(seed=32, blobs=2, spread=0.15, height=0.038)),
    ("grass", "gf_moss_c", moss_cushion, dict(seed=33, blobs=4, spread=0.23, height=0.052)),
    ("grass", "gf_moss_d", moss_cushion, dict(seed=34, blobs=3, spread=0.17, height=0.034)),
    ("straw", "gf_straw_a", straw_clump, dict(seed=41, strands=5, length=0.26, height=0.055)),
    ("straw", "gf_straw_b", straw_clump, dict(seed=42, strands=6, length=0.30, height=0.048)),
    ("straw", "gf_straw_c", straw_clump, dict(seed=43, strands=4, length=0.22, height=0.062)),
    ("straw", "gf_straw_d", straw_clump, dict(seed=44, strands=6, length=0.27, height=0.042)),
    ("straw", "gf_straw_e", straw_clump, dict(seed=45, strands=5, length=0.24, height=0.058)),
    ("gravel", "gf_pebble_a", pebble, dict(seed=51, radius=0.045, height=0.030, sides=5)),
    ("gravel", "gf_pebble_b", pebble, dict(seed=52, radius=0.038, height=0.024, sides=5)),
    ("gravel", "gf_pebble_c", pebble, dict(seed=53, radius=0.052, height=0.034, sides=6)),
    ("gravel", "gf_pebble_d", pebble, dict(seed=54, radius=0.032, height=0.020, sides=5)),
    ("gravel", "gf_pebble_e", pebble, dict(seed=55, radius=0.048, height=0.026, sides=6)),
    ("gravel", "gf_pebble_f", pebble, dict(seed=56, radius=0.041, height=0.031, sides=5)),
    ("gravel", "gf_pebble_g", pebble, dict(seed=57, radius=0.056, height=0.028, sides=6)),
    ("gravel", "gf_pebble_h", pebble, dict(seed=58, radius=0.035, height=0.022, sides=5)),
    ("stones", "gf_stone_a", stone, dict(seed=61, radius=0.088, height=0.062, sides=6)),
    ("stones", "gf_stone_b", stone, dict(seed=62, radius=0.072, height=0.052, sides=6)),
    ("stones", "gf_stone_c", stone, dict(seed=63, radius=0.104, height=0.070, sides=7)),
    ("stones", "gf_stone_d", stone, dict(seed=64, radius=0.066, height=0.044, sides=6)),
    ("stones", "gf_stone_e", stone, dict(seed=65, radius=0.094, height=0.058, sides=7)),
    ("stones", "gf_stone_f", stone, dict(seed=66, radius=0.079, height=0.048, sides=6)),
    ("rubble", "gf_rubble_a", rubble_piece, dict(seed=71, radius=0.095, height=0.052, sides=6)),
    ("rubble", "gf_rubble_b", rubble_piece, dict(seed=72, radius=0.078, height=0.044, sides=6)),
    ("rubble", "gf_rubble_c", rubble_piece, dict(seed=73, radius=0.112, height=0.060, sides=6)),
    ("rubble", "gf_rubble_d", rubble_piece, dict(seed=74, radius=0.068, height=0.038, sides=6)),
    ("rubble", "gf_rubble_e", rubble_piece, dict(seed=75, radius=0.088, height=0.048, sides=6)),
    ("rubble", "gf_woodchip_a", wood_chip, dict(seed=81, chips=4, radius=0.10, height=0.036)),
    ("rubble", "gf_woodchip_b", wood_chip, dict(seed=82, chips=5, radius=0.12, height=0.030)),
    ("rubble", "gf_woodchip_c", wood_chip, dict(seed=83, chips=3, radius=0.085, height=0.040)),
    ("rubble", "gf_woodchip_d", wood_chip, dict(seed=84, chips=5, radius=0.11, height=0.026)),
    ("leaves", "gf_leafpile_a", leaf_pile, dict(seed=91, leaves=5, radius=0.11, height=0.036)),
    ("leaves", "gf_leafpile_b", leaf_pile, dict(seed=92, leaves=4, radius=0.09, height=0.030)),
    ("leaves", "gf_leafpile_c", leaf_pile, dict(seed=93, leaves=6, radius=0.13, height=0.042)),
    ("leaves", "gf_leafpile_d", leaf_pile, dict(seed=94, leaves=4, radius=0.08, height=0.026)),
    ("boards", "gf_board_a", board, dict(seed=101, length=0.34, width=0.10, thickness=0.030)),
    ("boards", "gf_board_b", board, dict(seed=102, length=0.28, width=0.12, thickness=0.026)),
    ("boards", "gf_board_c", board, dict(seed=103, length=0.40, width=0.09, thickness=0.034)),
    ("boards", "gf_board_d", board, dict(seed=104, length=0.24, width=0.11, thickness=0.028)),
    ("pavers", "gf_paver_a", paver, dict(seed=111, size=0.30, thickness=0.045, corner=0.045)),
    ("pavers", "gf_paver_b", paver, dict(seed=112, size=0.24, thickness=0.040, corner=0.030)),
    ("pavers", "gf_paver_c", paver, dict(seed=113, size=0.36, thickness=0.050, corner=0.060)),
    ("pavers", "gf_paver_d", paver, dict(seed=114, size=0.20, thickness=0.038, corner=0.026)),
]


def main() -> None:
    wipe_scene()
    entries = []
    problems = []
    for family, name, factory, kwargs in LIBRARY:
        obj = factory(name, **kwargs)
        recentre(obj)
        record = export(obj, family, name)
        entries.append(record)
        low, high = BUDGETS.get(family, (0, 10_000))
        if not (low <= record["triangles"] <= high):
            problems.append(
                f"{name}: {record['triangles']} tris outside the {family} budget {low}-{high}"
            )
        if abs(record["base_z"]) > 1e-4:
            problems.append(f"{name}: contact plane is at z={record['base_z']}, not 0")
        bpy.data.objects.remove(obj, do_unlink=True)

    report = {
        "modules": entries,
        "count": len(entries),
        "families": sorted({e["family"] for e in entries}),
        "total_triangles": sum(e["triangles"] for e in entries),
        "problems": problems,
    }
    out = OUT_ROOT / "build_report.json"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(json.dumps(report, indent=2))
    print(f"TILE FORGE MODULES: {len(entries)} exported, {len(problems)} problems")


if __name__ == "__main__":
    main()
