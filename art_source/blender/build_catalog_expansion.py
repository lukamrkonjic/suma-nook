#!/usr/bin/env python3
"""Build Suma Nook's clean-room catalog expansion — lush diorama pass.

This script only authors original Suma geometry.  It does not read, import, or
derive geometry from Garden Galaxy or any private audit evidence.

Surface language comes from suma_surface_kit — a port of Imota's procedural
rock & snow systems (faceted grounded crag lobes, authored cluster layouts,
paper-snow dusting of lit faces) extended into per-material tile generators:
clods for dirt, setts and slabs for stone, dunes for sand, billows for snow,
gravel and scree for path metal.  See the kit's docstring for provenance.

Style contract (docs/visual_rework/ASSET_AUDIT.md + reference boards):
  - nothing is machine-straight: blocks are corner-wonked, posts lean and
    taper, disc outlines drift with low-frequency noise;
  - rounded everywhere: generous multi-segment bevels, grounded lobes, lathe
    profiles with bellies, no razor edges;
  - tiles read as plump diorama chunks: soft rounded caps over chunky faceted
    soil bodies, with all coverable relief inside the 0..0.05 budget demanded
    by tile_visual_factory's classifier (structural meshes keep the
    `_body`/`_cap` suffixes);
  - warmth comes from the shared palette; lushness comes from baked moss,
    leaves and hand-scattered grounded stones, never from uniform noise.

Run from the repository root:
  C:/Software/Blender/blender.exe --background --factory-startup \
      --python art_source/blender/build_catalog_expansion.py
"""

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

import build_gg_assets as base
import suma_surface_kit as kit

TILE = base.TILE
BLOCK_DEPTH = base.BLOCK_DEPTH
RELIEF_MAX = kit.RELIEF_MAX


# ---------------------------------------------------------------- primitives
def torus(name, major_radius, minor_radius, loc, material, major_segments=20, minor_segments=8):
    bpy.ops.mesh.primitive_torus_add(
        major_radius=major_radius,
        minor_radius=minor_radius,
        major_segments=major_segments,
        minor_segments=minor_segments,
        location=loc,
    )
    obj = bpy.context.active_object
    obj.name = name
    obj.data.materials.append(base.mat(material))
    bpy.ops.object.shade_smooth()
    return obj


def cone_between(name, start, end, radius_a, radius_b, material, verts=16):
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = base.rcyl(
        name,
        radius_a,
        direction.length,
        (a + b) * 0.5,
        material,
        verts=verts,
        r2=radius_b,
        bevel=0.008,
        segments=1,
    )
    return base.orient_local_z(obj, direction)


def orient(obj, rotation, pivot=None):
    """Rotate a mesh whose transforms were baked flat.  base.rbox / base.lobe /
    base.uv_sphere run transform_apply with the operator's default
    location=True, so their vertices carry world positions and the object
    origin stays at the scene origin — a plain rotation_euler would orbit the
    whole scene origin.  Rotate the vertices about the mesh's own centre (or
    an explicit pivot) instead."""
    euler = rotation if isinstance(rotation, Euler) else Euler(
        rotation if isinstance(rotation, (tuple, list)) else (0.0, 0.0, rotation))
    matrix = euler.to_matrix()
    verts = obj.data.vertices
    if pivot is None:
        centre = Vector()
        for v in verts:
            centre += v.co
        centre /= max(len(verts), 1)
    else:
        centre = Vector(pivot)
    for v in verts:
        v.co = centre + matrix @ (v.co - centre)
    return obj


def wonk(obj, rng, amount=0.02, lock_top=False):
    """Hand-cut look: drift every vertex, optionally keeping the top plane
    level (caps must keep their walkable plane exactly at the authored z)."""
    top = max(v.co.z for v in obj.data.vertices)
    for v in obj.data.vertices:
        if lock_top and v.co.z >= top - 1e-4:
            v.co.x += rng.uniform(-amount, amount) * 0.6
            v.co.y += rng.uniform(-amount, amount) * 0.6
            continue
        v.co.x += rng.uniform(-amount, amount)
        v.co.y += rng.uniform(-amount, amount)
        v.co.z += rng.uniform(-amount, amount)
    return obj


def wonk_box(name, size, loc, material, rng, amount=0.02, bevel=0.045, segments=3, lock_top=False, flat=False):
    obj = base.rbox(name, size, loc, material, bevel=bevel, segments=segments, flat=flat)
    return wonk(obj, rng, amount, lock_top=lock_top)


def slab(name, radius, height, loc, material, rng, verts=9, stretch=(1.0, 1.0), wobble=0.09, bevel=None):
    """Organic rounded disc — the outline drifts with low-frequency noise so
    plates, lids and column drums read as hand-shaped, never turned."""
    width = bevel if bevel is not None else min(height * 0.42, 0.035)
    obj = base.rcyl(name, radius, height, loc, material, verts=verts, bevel=width, segments=2, flat=True)
    p1, p2 = rng.uniform(0, math.tau), rng.uniform(0, math.tau)
    for v in obj.data.vertices:
        ang = math.atan2(v.co.y, v.co.x)
        k = 1.0 + wobble * (0.62 * math.sin(ang * 2.0 + p1) + 0.38 * math.sin(ang * 3.0 + p2))
        v.co.x *= k * stretch[0]
        v.co.y *= k * stretch[1]
    obj.rotation_euler.z = rng.uniform(0, math.tau)
    return obj


def lathe(name, profile, loc, material, verts=14, flat=False, rng=None, wobble=0.0):
    """Surface of revolution from (z, radius) pairs — pottery, columns,
    churns.  Optional per-ring wobble keeps the profile hand-thrown."""
    vs = []
    for (z, r) in profile:
        ox = oy = 0.0
        rr = r
        if rng is not None and wobble > 0.0 and r > 1e-4:
            rr = r * (1.0 + rng.uniform(-wobble, wobble))
            ox, oy = rng.uniform(-wobble, wobble) * r * 0.5, rng.uniform(-wobble, wobble) * r * 0.5
        for i in range(verts):
            a = math.tau * i / verts
            vs.append((math.cos(a) * rr + ox, math.sin(a) * rr + oy, z))
    faces = []
    for ring in range(len(profile) - 1):
        for i in range(verts):
            n = (i + 1) % verts
            faces.append((ring * verts + i, ring * verts + n,
                          (ring + 1) * verts + n, (ring + 1) * verts + i))
    faces.append(tuple(reversed(tuple(range(verts)))))
    top0 = (len(profile) - 1) * verts
    faces.append(tuple(range(top0, top0 + verts)))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(vs, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = Vector(loc)
    obj.data.materials.append(base.mat(material))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    if flat:
        bpy.ops.object.shade_flat()
    else:
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(46))
        except Exception:
            bpy.ops.object.shade_smooth()
    return obj


# ---------------------------------------------------------------- tile shell
def tile_base(prefix, top_mat, side_mat, _rng=None, profile="micro_bevel_square"):
    """Tile shell in an explicit geometry profile (tile_profiles.py): exact
    slot fill, planar flat-shaded top, thin turf skin.  The old universal
    rounded cap (thick beveled smooth-shaded slab over an inset wonked body)
    is gone — organic character now comes from the surface-kit overlays, and
    silhouette character from the chosen profile."""
    import tile_profiles
    return tile_profiles.build_shell(prefix, top_mat, side_mat, profile, base.mat)


def lane_run(prefix, points, material, rng, r=0.3, height=0.04, stretch=(0.95, 1.22)):
    """A worn route of overlapping soft grounded lobes along a polyline; the
    union reads as one organic path with rounded, wandering edges.  Each lobe's
    centre is pulled in just far enough that its extent ends AT the tile edge
    (0.85), so lanes still meet neighbouring tiles without overhanging the
    footprint the full-loop suite enforces."""
    objs = []
    spread = max(stretch)
    for i, (x, y) in enumerate(points):
        radius = r * rng.uniform(0.88, 1.08)
        reach = radius * spread
        lobe_x = x + rng.uniform(-0.025, 0.025)
        lobe_y = y + rng.uniform(-0.025, 0.025)
        lobe_x = math.copysign(min(abs(lobe_x), max(0.0, 0.85 - reach)), lobe_x)
        lobe_y = math.copysign(min(abs(lobe_y), max(0.0, 0.85 - reach)), lobe_y)
        objs.append(kit.capped_lobe(
            f"{prefix}_{i}",
            radius,
            (lobe_x, lobe_y),
            material,
            rng=rng,
            height=height * rng.uniform(0.9, 1.0),
            seg=9, rings=4,
            stretch=stretch,
        ))
    return objs


# ---------------------------------------------------------------- tiles
def build_tiles():
    rng = random.Random(2711)

    # Dirt: warm turned soil — grounded clods and a pocket of stones.
    tiles = tile_base("dirt", "earth_light", "earth_shadow")
    tiles += kit.clod_field("dirt_clod", rng, count=13)
    tiles += kit.scree_patch("dirt_scree", rng, (0.44, -0.4), count=3)
    tiles.append(kit.capped_lobe("dirt_stone", 0.06, (-0.46, 0.38), "stone_mid_light",
                                 rng=rng, height=0.04, seg=5, rings=2))
    base.export("tile_dirt", tiles)

    # Dirt road: a worn wandering lane pressed into grass, gravel at its edges.
    tiles = tile_base("dirt_road", "grass_primary", "earth_mid")
    lane = [(rng.uniform(-0.07, 0.07), -0.72 + i * 0.29) for i in range(6)]
    tiles += lane_run("dirt_road_lane", lane, "earth_light", rng, r=0.31)
    tiles += kit.scree_patch("dirt_road_scree_a", rng, (-0.5, -0.3), count=3,
                             mats=kit.EARTH_RAMP)
    tiles += kit.scree_patch("dirt_road_scree_b", rng, (0.48, 0.34), count=3)
    base.export("tile_dirt_road", tiles)

    # Crossroad: two worn routes meeting in a soft trampled middle.
    tiles = tile_base("dirt_cross", "grass_primary", "earth_mid")
    lane_a = [(rng.uniform(-0.05, 0.05), -0.72 + i * 0.29) for i in range(6)]
    lane_b = [(-0.72 + i * 0.29, rng.uniform(-0.05, 0.05)) for i in range(6)]
    tiles += lane_run("dirt_cross_a", lane_a, "earth_light", rng, r=0.29)
    tiles += lane_run("dirt_cross_b", lane_b, "earth_light", rng, r=0.29, stretch=(1.22, 0.95))
    tiles.append(kit.capped_lobe("dirt_cross_mid", 0.32, (0, 0), "earth_light",
                                 rng=rng, height=0.044, seg=9, rings=4))
    tiles += kit.scree_patch("dirt_cross_scree", rng, (0.52, -0.52), count=3)
    base.export("tile_dirt_crossroad", tiles)

    # Mud: dark and wet — soft sodden patches, clods, one standing puddle and
    # a moss-topped stepping stone.
    tiles = tile_base("mud", "earth_mid", "earth_deep")
    for i, (x, y, r) in enumerate([(-0.36, -0.3, 0.32), (0.3, 0.36, 0.36), (0.42, -0.4, 0.22)]):
        tiles.append(kit.capped_lobe(f"mud_wet_{i}", r, (x, y), "earth_deep", rng=rng,
                                     height=0.028, seg=9, rings=4,
                                     stretch=(rng.uniform(1.05, 1.4), rng.uniform(0.65, 0.9))))
    tiles += kit.clod_field("mud_clod", rng, count=6, r_range=(0.05, 0.085),
                            mats=["earth_light", "earth_mid"])
    tiles.append(slab("mud_puddle", 0.24, 0.026, (-0.06, 0.1, 0.013), "water_shallow", rng,
                      verts=11, stretch=(1.25, 0.85), wobble=0.14, bevel=0.006))
    step = kit.capped_lobe("mud_step", 0.14, (0.16, -0.16), "stone_mid_light",
                           rng=rng, height=RELIEF_MAX, seg=6, rings=3)
    kit.dust(step, "moss_primary", min_nz=0.6)
    tiles.append(step)
    base.export("tile_mud", tiles)

    # Snowfield: plump paper-snow chunk, faint billows, one frosted stone
    # breaking the surface.
    tiles = tile_base("snow", "warm_white", "stone_mid_light", profile="soft_recessed_top")
    tiles += kit.snow_billows("snow_billow", rng, [
        (-0.3, 0.22, 0.3, (1.4, 0.9)),
        (0.34, -0.2, 0.27, (1.3, 0.85)),
        (0.04, 0.52, 0.2, (1.2, 0.8)),
    ], height=0.038)
    tiles.append(kit.snow_bound_rock("snow_rock", rng, (0.44, 0.4), r=0.09))
    base.export("tile_snowfield", tiles)

    # Snow drift: banked powder waves with bright crests.
    tiles = tile_base("snow_drift", "warm_white", "stone_mid_light", profile="soft_recessed_top")
    tiles += kit.snow_billows("drift_billow", rng, [
        (-0.36, -0.34, 0.36, (1.4, 0.8)),
        (0.36, 0.36, 0.32, (1.35, 0.75)),
        (0.22, -0.44, 0.24, (1.25, 0.7)),
        (-0.44, 0.32, 0.22, (1.2, 0.72)),
    ], height=0.046, crest=kit.SNOW_CREST_MAT)
    tiles.append(kit.snow_bound_rock("drift_rock", rng, (-0.06, 0.06), r=0.1))
    base.export("tile_snow_drift", tiles)

    # Snow path: powder banked to the verges, a trodden lane with bootprints.
    tiles = tile_base("snow_path", "warm_white", "stone_mid_light", profile="soft_recessed_top")
    tiles += kit.snow_billows("snow_path_bank", rng, [
        (-0.5, -0.2, 0.24, (0.85, 1.25)),
        (0.5, 0.26, 0.22, (0.82, 1.22)),
    ], height=0.044)
    lane = [(rng.uniform(-0.06, 0.06), -0.72 + i * 0.29) for i in range(6)]
    tiles += lane_run("snow_path_lane", lane, "ivory_highlight", rng, r=0.28, height=0.028)
    for i, y in enumerate((-0.5, -0.16, 0.2, 0.54)):
        x = -0.1 if i % 2 == 0 else 0.12
        tiles.append(kit.capped_lobe(f"snow_print_{i}", 0.06, (x, y), "stone_mid_light",
                                     rng=rng, height=0.03, seg=6, rings=2,
                                     stretch=(0.72, 1.3), yaw=rng.uniform(-0.2, 0.2)))
    base.export("tile_snow_path", tiles)

    # Frosted stone: crag slabs under creeping powder — every lit face frosts.
    tiles = tile_base("froststone", "stone_mid_light", "stone_shadow")
    slabs = kit.slab_field("froststone_slab", rng, [
        (-0.3, -0.26, 0.36), (0.32, 0.28, 0.32), (0.36, -0.36, 0.22),
    ], mats=["stone_light", "stone_mid_light", "stone_mid"])
    pebbles = [
        kit.capped_lobe("froststone_peb_a", 0.08, (-0.42, 0.44), "stone_light",
                        rng=rng, height=0.042, seg=5, rings=3),
        kit.capped_lobe("froststone_peb_b", 0.06, (-0.08, 0.52), "stone_mid_light",
                        rng=rng, height=0.036, seg=5, rings=2),
    ]
    kit.dust(slabs + pebbles, kit.SNOW_MAT, min_nz=0.42)
    tiles += slabs + pebbles
    tiles += kit.snow_billows("froststone_snow", rng, [
        (-0.5, -0.48, 0.26, (1.15, 0.88)),
        (0.5, 0.48, 0.22, (1.12, 0.85)),
    ], height=0.044)
    base.export("tile_frosted_stone", tiles)

    # Cobblestone: plump grounded setts packed tight, mossy pockets in the gaps.
    tiles = tile_base("cobble", "stone_warm_shadow", "stone_warm_shadow")
    tiles += kit.sett_field("cobble", rng)
    base.export("tile_cobblestone", tiles)

    # Flagstone: broad crag flags floating in lush green joints, moss pockets
    # and gravel washed into the seams.
    tiles = tile_base("flagstone", "grass_secondary", "earth_mid")
    tiles += kit.slab_field("flagstone", rng, [
        (-0.38, -0.38, 0.4), (0.4, -0.4, 0.36), (-0.42, 0.4, 0.36),
        (0.36, 0.4, 0.4), (0.0, -0.02, 0.28),
    ])
    for i, (x, y) in enumerate([(-0.02, 0.42), (0.44, 0.02)]):
        tiles.append(kit.capped_lobe(f"flagstone_moss_{i}", 0.09, (x, y), "moss_bright",
                                     rng=rng, height=0.03, seg=7, rings=3,
                                     stretch=(1.25, 0.85)))
    tiles += kit.scree_patch("flagstone_scree", rng, (0.06, -0.56), count=3,
                             r_range=(0.03, 0.05))
    base.export("tile_flagstone", tiles)

    # Sand: wind-combed dune arcs and a pocket of sun-bleached pebbles.
    tiles = tile_base("sand", "ivory_highlight", "earth_light")
    tiles += kit.dune_ridges("sand_ripple", rng)
    tiles += kit.scree_patch("sand_scree", rng, (-0.48, 0.48), count=3,
                             mats=kit.SAND_PEBBLE_RAMP)
    tiles.append(kit.capped_lobe("sand_stone", 0.07, (0.5, 0.5), "stone_light",
                                 rng=rng, height=0.04, seg=5, rings=2))
    base.export("tile_sand", tiles)

    # Clay: sun-baked terracotta plates over deep red earth.
    tiles = tile_base("clay", "soil_red_shadow", "soil_red_shadow", profile="rounded_corner_slab")
    tiles += kit.slab_field("clay_plate", rng, [
        (-0.38, -0.36, 0.36), (0.38, -0.4, 0.34), (-0.4, 0.38, 0.34),
        (0.36, 0.38, 0.36), (0.0, 0.0, 0.28),
    ], mats=kit.TERRACOTTA_RAMP, height=0.042)
    tiles += kit.scree_patch("clay_scree", rng, (0.54, -0.08), count=2,
                             mats=["terracotta_shadow", "terracotta_primary"])
    base.export("tile_clay", tiles)


# ---------------------------------------------------------------- stone props
def _moss_on(name, r, loc, rng, material="moss_primary"):
    obj = base.lobe(name, r, loc, material, squash=0.3, subdiv=2,
                    stretch=(rng.uniform(1.0, 1.3), rng.uniform(0.75, 0.95)))
    return orient(obj, rng.uniform(0, math.tau))


def build_stone_catalog():
    rng = random.Random(443)

    # Low wall: two courses of grounded crag fieldstones, moss on the tops.
    wall = []
    for i, (x, r) in enumerate([(-0.52, 0.3), (0.02, 0.28), (0.55, 0.29)]):
        wall.append(kit.grounded_lobe(
            f"low_wall_a_{i}", r, (x, rng.uniform(-0.03, 0.03)),
            kit.STONE_RAMP[i % 3], rng=rng, squash=0.62, seg=6, rings=3,
            stretch=(1.12, 0.95)))
    for i, (x, r) in enumerate([(-0.26, 0.26), (0.3, 0.27)]):
        wall.append(kit.grounded_lobe(
            f"low_wall_b_{i}", r, (x, rng.uniform(-0.03, 0.03)),
            kit.STONE_RAMP[(i + 1) % 3], rng=rng, base_z=0.34, squash=0.6, seg=5,
            rings=3, stretch=(1.08, 0.92)))
    kit.dust(wall, "moss_primary", min_nz=0.62, rng=rng, chance=0.4)
    wall += base.move(base.tuft("low_wall_tuft", rng, blades=4, h_range=(0.1, 0.17)), (0.62, 0.26, 0))
    base.export("prop_stone_wall_low", wall)

    # Corner: the same crag courses folded into an L around a keystone.
    corner = []
    for arm, angle in ((0, 0.0), (1, math.pi / 2)):
        stones = []
        for i, (x, r) in enumerate([(0.42, 0.27), (0.82, 0.24)]):
            stones.append(kit.grounded_lobe(
                f"corner_{arm}_{i}", r, (x, rng.uniform(-0.03, 0.03)),
                kit.STONE_RAMP[(arm + i) % 3], rng=rng, squash=0.62, seg=6,
                rings=3, stretch=(1.1, 0.94)))
        stones.append(kit.grounded_lobe(
            f"corner_top_{arm}", 0.21, (0.58, rng.uniform(-0.02, 0.02)),
            kit.STONE_RAMP[(arm + 2) % 3], rng=rng, base_z=0.3, squash=0.58,
            seg=5, rings=3))
        base.rot_z(stones, angle)
        corner += stones
    corner.append(kit.grounded_lobe("corner_key", 0.29, (0.04, 0.04),
                                    "stone_light", rng=rng, squash=0.66, seg=6, rings=3))
    corner.append(kit.grounded_lobe("corner_key_top", 0.22, (0.03, 0.05),
                                    "stone_mid_light", rng=rng, base_z=0.36, squash=0.6,
                                    seg=5, rings=3))
    kit.dust(corner, "moss_primary", min_nz=0.62, rng=rng, chance=0.35)
    base.export("prop_stone_wall_corner", corner)

    # Pillar: a soft classical column — plinth, belly-curved shaft, capital.
    pillar = [
        slab("pillar_plinth", 0.34, 0.14, (0, 0, 0.07), "stone_mid_light", rng,
             verts=12, wobble=0.05, bevel=0.03),
        lathe("pillar_shaft", [
            (0.12, 0.27), (0.2, 0.235), (0.45, 0.225), (0.7, 0.215),
            (0.92, 0.2), (1.04, 0.23),
        ], (0, 0, 0), "stone_light", verts=14, rng=rng, wobble=0.012),
        torus("pillar_neck", 0.225, 0.035, (0, 0, 1.05), "stone_mid_light", 16, 8),
        slab("pillar_cap", 0.32, 0.13, (0, 0, 1.15), "stone_light", rng,
             verts=12, wobble=0.05, bevel=0.03),
    ]
    pillar[1].rotation_euler.z = rng.uniform(0, math.tau)
    base.export("prop_stone_pillar", pillar)

    # Well: two crag courses, mossy rim, leaning posts, gabled roof, bucket.
    well = []
    for i in range(10):
        angle = math.tau * i / 10
        well.append(kit.grounded_lobe(
            f"well_stone_{i}", rng.uniform(0.19, 0.23),
            (math.cos(angle) * 0.47, math.sin(angle) * 0.47),
            kit.STONE_RAMP[i % 3], rng=rng, squash=0.66, seg=6, rings=3))
    for i in range(8):
        angle = math.tau * (i + 0.5) / 8
        well.append(kit.grounded_lobe(
            f"well_stone_b_{i}", rng.uniform(0.16, 0.19),
            (math.cos(angle) * 0.44, math.sin(angle) * 0.44),
            kit.STONE_RAMP[(i + 1) % 3], rng=rng, base_z=0.27, squash=0.62,
            seg=5, rings=3))
    kit.dust(well, "moss_primary", min_nz=0.6, rng=rng, chance=0.3)
    well.append(slab("well_water", 0.33, 0.03, (0, 0, 0.32), "water_shallow", rng,
                     verts=14, wobble=0.06, bevel=0.006))
    well.append(cone_between("well_post_l", (-0.66, 0, 0.0), (-0.55, 0, 1.28), 0.075, 0.058, "wood_primary", 10))
    well.append(cone_between("well_post_r", (0.66, 0, 0.0), (0.55, 0, 1.28), 0.075, 0.058, "wood_primary", 10))
    beam = base.rcyl("well_spindle", 0.055, 1.16, (0, 0, 1.06), "wood_dark", verts=10, bevel=0.01)
    beam.rotation_euler.y = math.pi / 2
    well.append(beam)
    for side in (-1, 1):
        panel = wonk_box(f"well_roof_{side}", (1.3, 0.5, 0.05), (0, side * 0.21, 1.42),
                         "wood_light" if side > 0 else "wood_gold", rng, 0.012, bevel=0.014, segments=2)
        well.append(orient(panel, (-side * 0.72, 0.0, 0.0)))
    ridge = base.rcyl("well_ridge", 0.045, 1.34, (0, 0, 1.52), "wood_dark", verts=8, bevel=0.008)
    ridge.rotation_euler.y = math.pi / 2
    well.append(ridge)
    well.append(base.rcyl("well_rope", 0.016, 0.3, (0.1, 0, 0.93), "cream_fabric", verts=8, bevel=0.003))
    well.append(lathe("well_bucket", [(0.0, 0.07), (0.02, 0.09), (0.16, 0.105)],
                      (0.1, 0, 0.64), "wood_light", verts=10, rng=rng, wobble=0.02))
    base.export("prop_stone_well", well)

    # Bench: one pillowy slab on two rounded stone feet.
    bench = [
        wonk_box("stone_bench_seat", (1.3, 0.52, 0.2), (0, 0, 0.5), "stone_light", rng,
                 0.02, bevel=0.07, segments=3),
        slab("stone_bench_leg_l", 0.21, 0.42, (-0.42, 0, 0.21), "stone_mid_light", rng,
             verts=10, stretch=(1.0, 1.25), wobble=0.06, bevel=0.03),
        slab("stone_bench_leg_r", 0.21, 0.42, (0.42, 0, 0.21), "stone_mid_light", rng,
             verts=10, stretch=(1.0, 1.25), wobble=0.06, bevel=0.03),
        _moss_on("stone_bench_moss", 0.09, (-0.52, 0.14, 0.6), rng, "moss_bright"),
    ]
    base.export("prop_stone_bench", bench)

    # Birdbath: scalloped bowl on a bellied stem — plus a visiting dove.
    birdbath = [
        slab("birdbath_base", 0.3, 0.12, (0, 0, 0.06), "stone_mid", rng, verts=12, wobble=0.05, bevel=0.028),
        lathe("birdbath_stem", [(0.1, 0.19), (0.24, 0.125), (0.52, 0.105), (0.72, 0.13)],
              (0, 0, 0), "stone_mid_light", verts=12, rng=rng, wobble=0.015),
        lathe("birdbath_bowl", [(0.7, 0.16), (0.78, 0.38), (0.86, 0.43), (0.9, 0.4), (0.9, 0.4)],
              (0, 0, 0), "stone_light", verts=14, rng=rng, wobble=0.02),
        slab("birdbath_water", 0.32, 0.025, (0, 0, 0.88), "water_shallow", rng,
             verts=14, wobble=0.04, bevel=0.005),
    ]
    birdbath += _dove("birdbath_dove", (0.3, 0.12, 0.9), 2.4)
    base.export("prop_birdbath", birdbath)


def _dove(prefix, loc, yaw):
    body = base.uv_sphere(f"{prefix}_body", 0.078, (0, -0.01, 0.062), "warm_white",
                          segments=16, rings=10, squash=0.85, stretch=(0.78, 1.25))
    head = base.uv_sphere(f"{prefix}_head", 0.048, (0, 0.088, 0.125), "warm_white",
                          segments=14, rings=8)
    beak = cone_between(f"{prefix}_beak", (0, 0.12, 0.12), (0, 0.17, 0.112), 0.017, 0.003,
                        "terracotta_orange", 8)
    tail = base.lobe(f"{prefix}_tail", 0.052, (0, -0.11, 0.075), "warm_white",
                     squash=0.4, stretch=(0.72, 1.45))
    tail.rotation_euler.x = 0.42
    objs = [body, head, beak, tail]
    base.rot_z(objs, yaw)
    return base.move(objs, loc)


# ---------------------------------------------------------------- garden props
def build_garden_catalog():
    rng = random.Random(977)

    # Watering can: chubby bellied body, generous loop handle, wide rose.
    watering = [
        lathe("watering_can_body", [
            (0.0, 0.27), (0.05, 0.31), (0.28, 0.33), (0.5, 0.27), (0.56, 0.235),
        ], (0, 0, 0), "soft_sage_gray", verts=16, rng=rng, wobble=0.012),
        torus("watering_can_lip", 0.235, 0.022, (0, 0, 0.56), "stone_light", 16, 7),
    ]
    handle = torus("watering_can_handle", 0.3, 0.045, (-0.1, 0, 0.56), "soft_sage_gray", 20, 8)
    handle.rotation_euler.x = math.pi / 2
    handle.rotation_euler.z = -0.15
    watering.append(handle)
    watering.append(cone_between("watering_can_spout", (0.22, 0, 0.28), (0.68, 0, 0.62), 0.1, 0.055,
                                 "soft_sage_gray", 12))
    rose = lathe("watering_can_rose", [(0.0, 0.055), (0.06, 0.1), (0.09, 0.12)],
                 (0, 0, 0), "stone_light", verts=12, rng=rng, wobble=0.02)
    rose.location = Vector((0.7, 0, 0.6))
    base.orient_local_z(rose, (0.75, 0, 0.55))
    watering.append(rose)
    base.export("prop_watering_can", watering)

    # Barrel: coopered belly, sunken dark bands, pale lid.
    barrel = [
        lathe("barrel_body", [
            (0.0, 0.29), (0.1, 0.335), (0.37, 0.37), (0.64, 0.335), (0.74, 0.29),
        ], (0, 0, 0), "wood_primary", verts=14, rng=rng, wobble=0.01),
        torus("barrel_band_low", 0.342, 0.02, (0, 0, 0.14), "stone_deep_shadow", 16, 7),
        torus("barrel_band_high", 0.346, 0.02, (0, 0, 0.6), "stone_deep_shadow", 16, 7),
        slab("barrel_lid", 0.27, 0.035, (0, 0, 0.745), "wood_light", rng, verts=14, wobble=0.03, bevel=0.01),
    ]
    base.export("prop_barrel", barrel)

    # Crate: softly wonked slats around leaning corner posts.
    crate = [wonk_box("crate_core", (0.68, 0.6, 0.52), (0, 0, 0.28), "earth_shadow", rng, 0.012, bevel=0.02, segments=2)]
    for i, z in enumerate((0.13, 0.3, 0.47)):
        for side in (-1, 1):
            plank = wonk_box(f"crate_slat_{i}_{side}", (0.6, 0.075, 0.115),
                             (rng.uniform(-0.015, 0.015), side * 0.32, z),
                             "wood_light" if (i + side) % 2 else "wood_gold", rng, 0.008,
                             bevel=0.018, segments=2)
            crate.append(orient(plank, rng.uniform(-0.03, 0.03)))
        for side in (-1, 1):
            plank = wonk_box(f"crate_slat_side_{i}_{side}", (0.075, 0.56, 0.115),
                             (side * 0.36, rng.uniform(-0.015, 0.015), z),
                             "wood_light" if (i + side) % 2 else "wood_primary", rng, 0.008,
                             bevel=0.018, segments=2)
            crate.append(orient(plank, rng.uniform(-0.03, 0.03)))
    for x in (-0.31, 0.31):
        for y in (-0.27, 0.27):
            post = wonk_box(f"crate_post_{x}_{y}", (0.095, 0.095, 0.6), (x, y, 0.3),
                            "wood_primary", rng, 0.01, bevel=0.016, segments=2)
            crate.append(orient(post, (y * 0.06, -x * 0.07, 0.0)))
    base.export("prop_crate", crate)

    # Wheelbarrow: pillowy tray, curving handles, one fat wheel.
    tray = wonk_box("barrow_tray", (0.8, 0.72, 0.28), (0, 0.06, 0.48), "wood_light", rng,
                    0.018, bevel=0.09, segments=3)
    orient(tray, (-0.06, 0.0, 0.0))
    barrow = [
        tray,
        wonk_box("barrow_soil", (0.56, 0.5, 0.07), (0, 0.06, 0.585), "earth_mid", rng, 0.014, bevel=0.02, segments=2),
    ]
    for x in (-0.25, 0.25):
        barrow.append(base.rod_between(f"barrow_handle_{x}", (x, -0.78, 0.32), (x * 0.9, 0.2, 0.5),
                                       0.042, "wood_primary", 10))
        barrow.append(base.rod_between(f"barrow_leg_{x}", (x, -0.42, 0.0), (x, -0.3, 0.4),
                                       0.038, "wood_deep", 8))
    wheel = torus("barrow_wheel", 0.21, 0.07, (0, 0.68, 0.23), "stone_deep_shadow", 16, 8)
    wheel.rotation_euler.y = math.pi / 2
    barrow.append(wheel)
    hub = base.rcyl("barrow_hub", 0.08, 0.17, (0, 0.68, 0.23), "wood_gold", verts=10, bevel=0.014)
    hub.rotation_euler.y = math.pi / 2
    barrow.append(hub)
    base.export("prop_wheelbarrow", barrow)

    # Log pile: uneven stack with pale cut ends, moss and one red mushroom.
    logs = []
    for row, count in enumerate((4, 3, 2)):
        for i in range(count):
            r = rng.uniform(0.115, 0.145)
            length = rng.uniform(0.62, 0.76)
            x = (i - (count - 1) / 2) * 0.33 + rng.uniform(-0.02, 0.02)
            z = 0.13 + row * 0.21
            body = base.rcyl(f"log_{row}_{i}", r, length, (x, rng.uniform(-0.03, 0.03), z),
                             "wood_primary" if (i + row) % 2 else "wood_brown",
                             verts=11, bevel=0.02, segments=2)
            body.rotation_euler = Euler((math.pi / 2, rng.uniform(-0.05, 0.05), 0))
            logs.append(body)
            cut = base.rcyl(f"log_end_{row}_{i}", r * 0.8, 0.025, (x, length / 2 + 0.005, z),
                            "wood_highlight", verts=11, bevel=0.005)
            cut.rotation_euler.x = math.pi / 2
            logs.append(cut)
    logs.append(_moss_on("log_moss", 0.1, (-0.3, 0.05, 0.47), rng))
    logs.append(base.rcyl("log_mush_stem", 0.028, 0.07, (0.28, -0.02, 0.6), "warm_white", verts=8, bevel=0.005))
    logs.append(base.lobe("log_mush_cap", 0.062, (0.28, -0.02, 0.65), "mushroom_red", squash=0.62))
    base.export("prop_log_pile", logs)

    # Wooden arch: leaning tapered posts under a true round arc, with a vine.
    arch = [
        cone_between("wood_arch_post_l", (-0.62, 0, 0), (-0.56, 0, 1.18), 0.085, 0.065, "wood_primary", 10),
        cone_between("wood_arch_post_r", (0.62, 0, 0), (0.56, 0, 1.18), 0.085, 0.065, "wood_primary", 10),
    ]
    arc_pts = []
    for i in range(7):
        t = math.pi * i / 6
        arc_pts.append((-math.cos(t) * 0.57, 0, 1.16 + math.sin(t) * 0.52))
    for i in range(6):
        arch.append(base.rod_between(f"wood_arch_arc_{i}", arc_pts[i], arc_pts[i + 1], 0.06,
                                     "wood_light" if i % 2 else "wood_gold", 9))
    vine_rng = random.Random(31)
    for i in range(8):
        t = i / 7.0
        z = 0.25 + t * 1.15
        x = -0.6 + 0.06 * t + vine_rng.uniform(-0.03, 0.03)
        leaf = base.leaf_plate(f"arch_leaf_{i}", 0.055, 0.14, (x, vine_rng.uniform(-0.05, 0.05), z),
                               "leaf_bright" if i % 3 else "leaf_medium", bend=0.03, thickness=0.012)
        base.orient_local_z(leaf, (vine_rng.uniform(-0.7, -0.2), vine_rng.uniform(-0.6, 0.6), 0.55))
        arch.append(leaf)
    base.export("prop_wooden_arch", arch)

    # Milk churn: hand-raised body with a knobbed lid and loop handles.
    churn = [
        lathe("churn_body", [
            (0.0, 0.21), (0.05, 0.26), (0.3, 0.29), (0.52, 0.22), (0.62, 0.155),
            (0.72, 0.165), (0.78, 0.19),
        ], (0, 0, 0), "stone_mid_light", verts=14, rng=rng, wobble=0.012),
        slab("churn_lid", 0.2, 0.05, (0, 0, 0.8), "stone_mid", rng, verts=14, wobble=0.03, bevel=0.014),
        base.uv_sphere("churn_knob", 0.045, (0, 0, 0.85), "stone_mid", segments=14, rings=8),
    ]
    for side in (-1, 1):
        ring = torus(f"churn_handle_{side}", 0.075, 0.022, (side * 0.27, 0, 0.5), "stone_shadow", 12, 6)
        ring.rotation_euler.y = math.pi / 2 + side * 0.5
        churn.append(ring)
    base.export("prop_milk_churn", churn)

    # Trellis: slender wonked lattice half-swallowed by a climbing rose.
    trellis = [
        wonk_box("trellis_post_l", (0.085, 0.085, 1.24), (-0.48, 0, 0.62), "wood_primary", rng, 0.012, bevel=0.014, segments=2),
        wonk_box("trellis_post_r", (0.085, 0.085, 1.24), (0.48, 0, 0.62), "wood_primary", rng, 0.012, bevel=0.014, segments=2),
        wonk_box("trellis_top", (1.12, 0.1, 0.1), (0, 0, 1.22), "wood_light", rng, 0.012, bevel=0.016, segments=2),
    ]
    for x in (-0.3, 0.0, 0.3):
        lath = wonk_box(f"trellis_v_{x}", (0.042, 0.06, 0.94), (x, 0, 0.66), "wood_gold", rng, 0.008, bevel=0.007, segments=1)
        trellis.append(orient(lath, (0.0, rng.uniform(-0.02, 0.02), 0.0)))
    for z in (0.34, 0.64, 0.94):
        lath = wonk_box(f"trellis_h_{z}", (0.9, 0.06, 0.042), (0, 0, z), "wood_gold", rng, 0.008, bevel=0.007, segments=1)
        trellis.append(orient(lath, (rng.uniform(-0.02, 0.02), 0.0, 0.0)))
    vine_rng = random.Random(67)
    for i in range(10):
        t = i / 9.0
        x = -0.42 + t * 0.75 + vine_rng.uniform(-0.06, 0.06)
        z = 0.3 + t * 0.85 + vine_rng.uniform(-0.05, 0.05)
        leaf = base.leaf_plate(f"trellis_leaf_{i}", 0.052, 0.13, (x, vine_rng.uniform(-0.05, 0.03), z),
                               "leaf_bright" if i % 3 else "leaf_medium", bend=0.028, thickness=0.011)
        base.orient_local_z(leaf, (vine_rng.uniform(-0.5, 0.5), vine_rng.uniform(-0.8, -0.3), 0.5))
        trellis.append(leaf)
    for i, (x, z) in enumerate([(-0.28, 0.5), (0.08, 0.86), (0.3, 1.06)]):
        trellis.append(base.lobe(f"trellis_bloom_{i}", 0.05, (x, -0.06, z), "petal_pink",
                                 squash=0.7, stretch=(1.1, 1.1)))
        trellis.append(base.lobe(f"trellis_bloom_c_{i}", 0.022, (x, -0.1, z), "flower_yellow", squash=0.7))
    base.export("prop_garden_trellis", trellis)

    # Snowman: three plump spheres, twig arms, a wrapped scarf and top hat.
    snowman = [
        base.uv_sphere("snowman_base", 0.44, (0, 0, 0.38), "warm_white", segments=24, rings=14, squash=0.88),
        base.uv_sphere("snowman_body", 0.32, (0, 0, 0.9), "warm_white", segments=24, rings=14, squash=0.94),
        base.uv_sphere("snowman_head", 0.25, (0, 0, 1.32), "warm_white", segments=24, rings=14),
        base.uv_sphere("snowman_eye_l", 0.032, (-0.08, 0.225, 1.38), "warm_near_black", segments=10, rings=8),
        base.uv_sphere("snowman_eye_r", 0.032, (0.08, 0.225, 1.38), "warm_near_black", segments=10, rings=8),
    ]
    snowman.append(cone_between("snowman_carrot", (0, 0.22, 1.33), (0, 0.5, 1.3), 0.055, 0.008, "terracotta_orange", 10))
    for side in (-1, 1):
        snowman.append(base.rod_between(f"snowman_arm_{side}", (side * 0.28, 0, 0.96),
                                        (side * 0.68, 0.08, 1.22), 0.024, "wood_dark", 8))
        snowman.append(base.rod_between(f"snowman_twig_{side}", (side * 0.58, 0.06, 1.16),
                                        (side * 0.72, 0.16, 1.3), 0.014, "wood_dark", 6))
    for i, z in enumerate((0.82, 0.96)):
        snowman.append(base.uv_sphere(f"snowman_button_{i}", 0.026, (0, 0.305 - i * 0.02, z),
                                      "warm_near_black", segments=10, rings=8))
    scarf = torus("snowman_scarf", 0.21, 0.055, (0, 0, 1.1), "burnt_red", 16, 8)
    scarf.scale = Vector((1.0, 1.0, 0.72))
    snowman.append(scarf)
    tail = wonk_box("snowman_scarf_tail", (0.1, 0.05, 0.26), (0.16, 0.19, 0.95), "burnt_red",
                    random.Random(7), 0.012, bevel=0.016, segments=2)
    snowman.append(orient(tail, (0.15, 0.2, 0.3)))
    hat_rng = random.Random(8)
    brim = slab("snowman_hat_brim", 0.26, 0.05, (0, 0, 1.51), "warm_near_black", hat_rng,
                verts=14, wobble=0.03, bevel=0.012)
    brim.rotation_euler = Euler((0.06, -0.05, 0))
    crown = lathe("snowman_hat", [(0.0, 0.17), (0.16, 0.155), (0.26, 0.165)], (0, 0, 1.52),
                  "warm_near_black", verts=14, rng=hat_rng, wobble=0.015)
    crown.rotation_euler = Euler((0.06, -0.05, 0))
    snowman += [brim, crown]
    base.export("prop_snowman", snowman)


# ---------------------------------------------------------------- water wheel
def build_water_wheel():
    rng = random.Random(83)
    fixed = []
    for side in (-1, 1):
        pier = wonk_box(f"water_wheel_pier_{side}", (0.26, 0.44, 0.84), (side * 0.64, 0, 0.42),
                        "stone_mid_light", rng, 0.02, bevel=0.05, segments=3)
        fixed.append(pier)
        fixed.append(kit.grounded_lobe(
            f"water_wheel_foot_{side}", 0.17, (side * 0.66, 0.24),
            "stone_light" if side > 0 else "stone_mid_light", rng=rng,
            squash=0.6, seg=6, rings=3))
    kit.dust(fixed, "moss_primary", min_nz=0.66, rng=rng, chance=0.3)
    axle = base.rcyl("water_wheel_axle_fixed", 0.1, 1.5, (0, 0, 0.78), "wood_dark", verts=12, bevel=0.014)
    axle.rotation_euler.y = math.pi / 2
    fixed.append(axle)

    rotor = bpy.data.objects.new("WaterWheelRotor", None)
    bpy.context.collection.objects.link(rotor)
    rotor.location = Vector((0, 0, 0.78))
    spinning = []

    for y in (-0.16, 0.16):
        ring = torus(f"wheel_rim_{y}", 0.52, 0.07, (0, y, 0), "wood_primary", 22, 8)
        ring.rotation_euler.x = math.pi / 2
        spinning.append(ring)
    hub = base.rcyl("wheel_hub", 0.15, 0.46, (0, 0, 0), "wood_light", verts=12, bevel=0.025, segments=2)
    hub.rotation_euler.x = math.pi / 2
    spinning.append(hub)

    for i in range(8):
        angle = math.tau * i / 8
        endpoint = (math.cos(angle) * 0.5, 0, math.sin(angle) * 0.5)
        spinning.append(base.rod_between(f"wheel_spoke_{i}", (0, 0, 0), endpoint, 0.036, "wood_gold", 9))
        paddle = wonk_box(
            f"wheel_paddle_{i}",
            (0.16, 0.44, 0.3),
            (math.cos(angle) * 0.6, 0, math.sin(angle) * 0.6),
            "wood_light" if i % 2 else "wood_gold",
            rng, 0.01, bevel=0.03, segments=2,
        )
        spinning.append(orient(paddle, (0.0, -angle, 0.0)))

    for obj in spinning:
        obj.parent = rotor
    base.export("prop_water_wheel", fixed + [rotor] + spinning)


def main():
    base.clear_scene()
    build_tiles()
    build_stone_catalog()
    build_garden_catalog()
    build_water_wheel()
    print("SUMA CATALOG EXPANSION COMPLETE")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
