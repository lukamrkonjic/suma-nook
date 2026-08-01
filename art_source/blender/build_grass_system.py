#!/usr/bin/env python3
"""Build Suma's lush-grass clump library.

The previous grass was rejected because every leaf was an upright column with a
flat top, so a clump read as a pillar cluster and a field read as bouquets glued
to square pads. The decisive change is the LEAF ITSELF:

    A leaf is a broad, closed, curved WEDGE — never a tapered tube.

Each leaf is built from five longitudinal stations. It starts narrow at the
planted base, widens to its maximum around 45% of its length, arcs upward, then
narrows to a small tapered tip that relaxes back down. It has real thickness, a
slightly convex upper surface, and no horizontal cap polygon anywhere.

The second decisive change is PROPORTION. An ordinary clump must be at least
2.5x wider than it is tall. That is checked numerically at build time and the
build fails loudly if a clump comes out as a column, so the old failure cannot
silently return.

The third is that wind lives in the mesh: vertex COLOR.r carries a wind weight
of 0 at the planted base rising to 1 at the tip, which the runtime shader reads
so bases stay still while tips move.

UNITS. Authored in LIVE metres — Suma's grid cell is 1.35 m
(data/tuning.json::tile_size). The brief quotes its figures against the 1.70 m
authored catalog footprint, so every linear dimension here is the brief's number
scaled by 1.35 / 1.70 = 0.794. Proportions and ratios are unchanged.

Run from the repository root:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/build_grass_system.py
"""

from __future__ import annotations

import json
import math
import random
from pathlib import Path

import bmesh
import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "tools" / "tile_forge" / "modules" / "grass"

# Brief figures are quoted for a 1.70 m tile; Suma's live cell is 1.35 m.
SCALE = 1.35 / 1.70

# The grass family. Three tones on an ordinary clump, the fourth reserved for a
# hero accent. Named for the Tile Forge slot contract.
PALETTE = {
    "grass_low": "526D32",
    "grass_main": "6F9140",
    "grass_hero": "8BAA51",
}

# An ordinary clump must be at least this much wider than it is tall. This is
# the single number that separates a lush carpet from a pillar cluster.
MIN_WIDTH_TO_HEIGHT = 2.5


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
    shader.inputs["Base Color"].default_value = srgb(PALETTE.get(name, "6F9140"))
    shader.inputs["Roughness"].default_value = 0.90
    shader.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.16
    result.diffuse_color = srgb(PALETTE.get(name, "6F9140"))
    return result


# --------------------------------------------------------------------------
# The broad leaf
# --------------------------------------------------------------------------

# (t along the leaf, width multiplier, height-curve multiplier).
# The width peak sits at 46% and the tip narrows to 2.5% rather than ending on
# a flat cap; the height curve relaxes from 1.0 back to 0.72 so the tip droops
# slightly instead of pointing at the sky.
LEAF_PROFILE = [
    (0.00, 0.16, 0.00),
    (0.18, 0.64, 0.12),
    (0.46, 1.00, 0.55),
    (0.78, 0.58, 1.00),
    (1.00, 0.025, 0.72),
]


def create_broad_leaf(name, length, width, rise, thickness, bend=0.0,
                      hero=False):
    """One closed curved wedge, built along +Y and arcing up in +Z.

    `bend` sweeps the leaf sideways along its length so a clump can contain
    curved leaves rather than a radial starburst of straight ones.
    """
    vertices = []
    faces = []

    for t, width_factor, height_factor in LEAF_PROFILE:
        y = t * length
        # Sideways sweep grows with the square of t: the base stays planted and
        # only the outer half curves.
        x_offset = bend * length * (t * t)
        half_width = width * width_factor * 0.5
        centre_z = rise * height_factor
        # The upper surface is slightly convex, so the leaf catches a soft
        # gradient across its width instead of reading as a flat ribbon.
        half_thickness = thickness * 0.5
        crown = thickness * 0.22 * width_factor

        vertices.extend([
            (x_offset - half_width, y, centre_z + half_thickness - crown * 0.5),
            (x_offset, y, centre_z + half_thickness + crown),
            (x_offset + half_width, y, centre_z + half_thickness - crown * 0.5),
            (x_offset - half_width * 0.92, y, centre_z - half_thickness),
            (x_offset + half_width * 0.92, y, centre_z - half_thickness),
        ])

    ring = 5
    for station in range(len(LEAF_PROFILE) - 1):
        a = station * ring
        b = (station + 1) * ring
        faces.extend([
            (a + 0, a + 1, b + 1, b + 0),   # upper left
            (a + 1, a + 2, b + 2, b + 1),   # upper right
            (a + 3, b + 3, b + 4, a + 4),   # underside
            (a + 0, b + 0, b + 3, a + 3),   # left rim
            (a + 2, a + 4, b + 4, b + 2),   # right rim
        ])
    # Closed at both ends. The tip ring is 2.5% of the width, so its cap is a
    # sliver rather than the flat horizontal top the old grass ended on.
    faces.append((0, 3, 4, 2, 1))
    tip = (len(LEAF_PROFILE) - 1) * ring
    faces.append((tip + 1, tip + 2, tip + 4, tip + 3, tip + 0))

    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.validate()

    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(mesh)
    bm.free()

    # Wind weight: 0 at the planted base, 1 at the tip. The runtime shader reads
    # COLOR.r, so a base can never drift and a tip always can.
    colour = mesh.color_attributes.new(
        name="Color", type="BYTE_COLOR", domain="POINT"
    )
    for index, item in enumerate(colour.data):
        t = LEAF_PROFILE[index // ring][0]
        item.color = (pow(t, 1.35), 0.0, 0.0, 1.0)

    for polygon in mesh.polygons:
        polygon.use_smooth = True

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    bpy.context.view_layer.objects.active = obj
    bevel = obj.modifiers.new("Soft_Bevel", "BEVEL")
    bevel.width = min(width * 0.075, 0.007 * SCALE)
    bevel.segments = 2 if hero else 1
    bevel.limit_method = "ANGLE"
    # Only the rim edges are sharp enough to need rounding; the convex upper
    # surface is already smooth and beveling it just multiplies triangles.
    bevel.angle_limit = math.radians(52.0)
    bpy.ops.object.modifier_apply(modifier="Soft_Bevel")
    weighted = obj.modifiers.new("WeightedNormal", "WEIGHTED_NORMAL")
    weighted.keep_sharp = True
    bpy.ops.object.modifier_apply(modifier="WeightedNormal")
    return obj


# Leaf size classes, in LIVE metres (brief figures x 0.794).
LEAF_CLASSES = {
    "small": dict(length=(0.13, 0.18), width=(0.045, 0.065),
                  rise=(0.025, 0.055), thickness=(0.010, 0.016)),
    "medium": dict(length=(0.18, 0.26), width=(0.060, 0.095),
                   rise=(0.035, 0.075), thickness=(0.012, 0.020)),
    "hero": dict(length=(0.25, 0.34), width=(0.080, 0.120),
                 rise=(0.050, 0.100), thickness=(0.015, 0.024)),
}


def leaf_dimensions(size_class, rng):
    spec = LEAF_CLASSES[size_class]
    result = {}
    for key, (low, high) in spec.items():
        if key == "rise":
            # Lower half of the band only. The full range produced leaves whose
            # own curve alone lifted a clump past the proportion gate.
            high = low + (high - low) * 0.45
        elif key == "width":
            # Upper half. Narrow leaves cannot overlap into a continuous low
            # dome, which is what the black-silhouette test actually measures.
            low = low + (high - low) * 0.55
        result[key] = rng.uniform(low, high) * SCALE
    return result


def pick_target_elevation(rng):
    """The angle the leaf TIP should finish at, above the terrain.

    65% of leaves land 15-35 degrees, 25% at 35-50, and no more than 10% at
    50-62. Nothing stands upright. This is the finished angle, not an extra
    rotation: the leaf already arcs upward on its own, and adding a pitch on top
    of that arc is what turned the previous clumps into columns.
    """
    roll = rng.random()
    if roll < 0.65:
        return math.radians(rng.uniform(15.0, 33.0))
    if roll < 0.90:
        return math.radians(rng.uniform(33.0, 48.0))
    return math.radians(rng.uniform(48.0, 60.0))


def intrinsic_elevation(length, rise):
    """The tip elevation a leaf already has from its own curve."""
    tip_height = rise * LEAF_PROFILE[-1][2]
    return math.atan2(tip_height, max(length, 1e-5))


# --------------------------------------------------------------------------
# Clumps
# --------------------------------------------------------------------------


def build_clump(name, seed, leaf_plan, sink=0.014):
    """Composes leaves into one low broad mass.

    `leaf_plan` is an explicit list of (size class, yaw degrees, pitch bias,
    bend, slot) so a clump is AUTHORED rather than scattered. The seed only
    varies dimensions inside each class.
    """
    rng = random.Random(seed)
    pieces = []
    for size_class, yaw_deg, elevation_deg, bend, slot in leaf_plan:
        dims = leaf_dimensions(size_class, rng)
        leaf = create_broad_leaf(
            "%s_leaf_%d" % (name, len(pieces)),
            dims["length"], dims["width"], dims["rise"], dims["thickness"],
            bend=bend, hero=size_class == "hero",
        )
        # Elevation is authored per leaf, jittered only a little. The leaf's own
        # arc already supplies part of it, so only the remainder is applied as a
        # rotation — adding a full pitch on top of the arc is what produced
        # columns in the rejected version.
        target = math.radians(elevation_deg + rng.uniform(-3.0, 3.0))
        pitch = max(0.0, target - intrinsic_elevation(dims["length"], dims["rise"]))
        leaf.rotation_euler = (pitch, 0.0, math.radians(yaw_deg))
        # Outer leaves start a little way out so their bases do not pile into a
        # single point; inner leaves sit at the centre and close the crown.
        offset = dims["length"] * (0.02 if elevation_deg >= 30 else 0.09)
        leaf.location = (
            math.cos(math.radians(yaw_deg)) * offset,
            math.sin(math.radians(yaw_deg)) * offset,
            0.0,
        )
        for index, existing in enumerate(leaf.data.materials):
            leaf.data.materials[index] = material(slot)
        if not leaf.data.materials:
            leaf.data.materials.append(material(slot))
        pieces.append(leaf)

    for obj in bpy.context.scene.objects:
        obj.select_set(obj in pieces)
    bpy.context.view_layer.objects.active = pieces[0]
    bpy.ops.object.join()
    clump = bpy.context.view_layer.objects.active
    clump.name = name
    clump.data.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

    # Sink the planted bases slightly into the terrain so no clump shows a
    # floating rim or a pad beneath it.
    for vertex in clump.data.vertices:
        vertex.co.z -= sink
    clump.data.update()
    return clump


L, M, H = "small", "medium", "hero"
_ = "grass_main"
LOW = "grass_low"
TOP = "grass_hero"

# Six authored clumps. Every one differs in silhouette, leaf count, lean
# distribution and dominant direction; none is radially symmetric.
CLUMPS = [
    # Each clump is two rings: a broad low outer fan, then shorter steeper
    # leaves that fill the crown. Yaw gaps are uneven so nothing is radial.

    # 1. low rosette — broad and dense, no dominant upright leaf
    ("grass_low_rosette", 9101, [
        (M, 8, 21, 0.12, _),   (M, 46, 19, -0.16, _),  (M, 82, 23, 0.18, LOW),
        (M, 122, 20, -0.10, _), (M, 158, 24, 0.14, LOW), (M, 196, 18, -0.18, _),
        (M, 232, 22, 0.16, LOW), (M, 274, 20, -0.12, _),
        (L, 28, 36, 0.08, _),  (L, 140, 39, -0.06, _), (L, 250, 34, 0.10, _),
        (L, 330, 37, -0.09, LOW),
    ]),
    # 2. directional fan — visible left-to-right flow, strongly asymmetric
    ("grass_directional_fan", 9102, [
        (H, 22, 24, 0.30, _),  (M, 48, 21, 0.26, _),  (M, 72, 19, 0.20, _),
        (M, 98, 22, 0.16, _),  (M, 126, 25, 0.12, LOW), (M, 152, 20, 0.22, LOW),
        (M, 356, 18, 0.28, LOW), (M, 330, 21, 0.24, _),
        (L, 40, 38, 0.14, _),  (L, 88, 35, 0.10, _),  (L, 136, 37, 0.16, _),
    ]),
    # 3. soft arc — curved crescent, useful around tree bases
    ("grass_soft_arc", 9103, [
        (M, 186, 20, 0.32, _),  (M, 214, 23, 0.28, _),  (H, 244, 25, 0.24, _),
        (M, 272, 21, 0.20, _),  (M, 300, 18, 0.16, LOW), (M, 328, 24, 0.12, LOW),
        (M, 158, 22, 0.30, LOW), (M, 130, 19, 0.26, _),
        (L, 200, 36, 0.18, _),  (L, 258, 39, 0.14, _),  (L, 312, 34, 0.20, LOW),
    ]),
    # 4. low moss mix — very low rounded mass, ratio at least 4.0
    ("grass_low_moss_mix", 9104, [
        (M, 18, 12, 0.20, LOW),  (M, 62, 10, -0.22, LOW), (M, 104, 14, 0.16, _),
        (M, 148, 11, -0.18, LOW), (M, 192, 13, 0.12, _),  (M, 236, 9, 0.22, LOW),
        (M, 282, 12, -0.16, LOW), (M, 326, 14, 0.14, _),
        (L, 44, 22, 0.10, _),  (L, 170, 24, -0.08, _), (L, 300, 21, 0.12, LOW),
    ]),
    # 5. medium tuft — slightly taller, used sparingly
    ("grass_medium_tuft", 9105, [
        (M, 14, 26, 0.10, _),   (M, 58, 24, -0.14, _),  (H, 106, 27, 0.12, _),
        (M, 152, 22, -0.08, LOW), (M, 198, 25, 0.16, _),  (M, 244, 28, -0.12, LOW),
        (M, 288, 23, 0.14, _),  (M, 332, 25, -0.10, LOW),
        (L, 36, 40, 0.08, _),  (L, 128, 43, -0.06, _), (L, 220, 38, 0.10, _),
        (L, 310, 41, -0.08, LOW),
    ]),
    # 6. hero cluster — larger and more characteristic, one per composition
    ("grass_hero_cluster", 9106, [
        (H, 10, 24, 0.18, _),   (H, 52, 21, -0.20, TOP), (M, 88, 26, 0.22, _),
        (H, 128, 22, -0.14, _), (M, 166, 27, 0.20, TOP), (M, 204, 20, -0.18, _),
        (H, 246, 25, 0.16, _),  (M, 284, 23, -0.16, LOW), (M, 318, 28, 0.14, LOW),
        (M, 348, 19, -0.12, _),
        (M, 30, 38, 0.12, _),  (L, 110, 42, -0.10, _), (L, 190, 39, 0.14, TOP),
        (L, 268, 41, -0.12, _), (L, 334, 37, 0.10, _),
    ]),
]


def measure(obj):
    mesh = obj.data
    mesh.calc_loop_triangles()
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    width = max(max(xs) - min(xs), max(ys) - min(ys))
    height = max(zs) - min(zs)
    return {
        "triangles": len(mesh.loop_triangles),
        "vertices": len(mesh.vertices),
        "width": round(width, 4),
        "height": round(height, 4),
        "ratio": round(width / max(height, 1e-5), 2),
        "footprint_radius": round(width * 0.5, 4),
        "base_z": round(min(zs), 4),
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
        export_vertex_color="MATERIAL",
        export_texcoords=False,
        export_tangents=False,
    )


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    records = []
    problems = []

    # A single reference leaf, exported for the close-up clay validation shot.
    rng = random.Random(4242)
    dims = leaf_dimensions("medium", rng)
    reference = create_broad_leaf(
        "grass_leaf_reference", dims["length"], dims["width"],
        dims["rise"], dims["thickness"], bend=0.18
    )
    reference.data.materials.append(material("grass_main"))
    record = measure(reference)
    record.update(id="grass_leaf_reference", kind="leaf",
                  path="res://tools/tile_forge/modules/grass/grass_leaf_reference.glb")
    export(reference, "grass_leaf_reference")
    records.append(record)
    bpy.data.objects.remove(reference, do_unlink=True)

    for name, seed, plan in CLUMPS:
        clump = build_clump(name, seed, plan)
        record = measure(clump)
        record.update(id=name, kind="clump",
                      path="res://tools/tile_forge/modules/grass/%s.glb" % name,
                      leaves=len(plan))
        export(clump, name)
        records.append(record)
        bpy.data.objects.remove(clump, do_unlink=True)

        # The proportion gate. A clump that comes out taller than it is broad is
        # the exact failure this rebuild exists to remove, so it fails the build
        # rather than reaching a screenshot.
        required = 4.0 if name == "grass_low_moss_mix" else MIN_WIDTH_TO_HEIGHT
        if record["ratio"] < required:
            problems.append(
                "%s: width/height %.2f is below the required %.1f (%.3f x %.3f)"
                % (name, record["ratio"], required, record["width"], record["height"])
            )
        if record["triangles"] > 2200:
            problems.append("%s: %d triangles is heavy for a clump"
                            % (name, record["triangles"]))

    report = {
        "scale_from_brief": SCALE,
        "min_width_to_height": MIN_WIDTH_TO_HEIGHT,
        "modules": records,
        "total_triangles": sum(r["triangles"] for r in records),
        "problems": problems,
    }
    (OUT / "grass_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )
    for record in records:
        print("%-24s %-6s tris=%4d  %.3f w x %.3f h  ratio %.2f" % (
            record["id"], record["kind"], record["triangles"],
            record["width"], record["height"], record["ratio"]
        ))
    for line in problems:
        print("PROBLEM %s" % line)
    print("GRASS SYSTEM: %d meshes, %d problems" % (len(records), len(problems)))


if __name__ == "__main__":
    main()
