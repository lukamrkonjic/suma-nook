#!/usr/bin/env python3
"""Suma Nook surface kit — a port of Imota's procedural rock & snow systems,
extended into tile-surface generators for the diorama tiles.

Provenance (studied from C:/Dev/imota-idle, scripts/render/prop_meshes.gd and
scripts/render/terrain*):
  - `_facet_sphere` — rock lobes are LOW-SEGMENT spheres (6 radial segments,
    ~3 rings), never smooth pebbles: the sparse topology gives readable crag
    facets at any size.
  - `_rock_cluster` + `_BOULDER_VARIANTS` — a rock is a hand-authored cluster:
    one main lobe plus asymmetric satellites, each entry
    (radius, off_x, off_y, height_scale, spread_scale).  Alternating warm
    stone tints per lobe give tonal variety inside a single rock.
  - the grounding rule — every lobe's centre sits at exactly its own
    half-height, so the whole cluster rests flat on the ground plane and
    nothing ever floats or sinks.  This is load-bearing for the "sits in the
    world" feel and is applied to every pebble, clod, sett and slab here.
  - snow — warm paper snow (Imota #EEE5CE, Suma's warm_white F6EED6), never
    pure white, and snow lives on the LIT/TOP surfaces: Imota frosts the toon
    light band; baked assets get the same read by assigning the snow material
    to up-facing faces (face-normal split), since the key light is overhead.
    The same split with moss makes weathered stone.

All generators keep their output inside the tile relief budget (z in
[0, RELIEF_MAX]) unless noted, so tile_visual_factory's cover-fade classifier
keeps working.  Object origins carry position (verts stay local): these meshes
are safe to rotate/move after creation, unlike base.rbox/lobe/uv_sphere.
"""

import math
import random

import bpy
from mathutils import Vector

import build_gg_assets as base

RELIEF_MAX = 0.048

# Warm tint ramps (Imota's shadow/base/light palette triples, on Suma keys).
STONE_RAMP = ["stone_light", "stone_mid_light", "stone_mid"]
STONE_WARM_RAMP = ["stone_light", "stone_warm_shadow", "stone_mid_light"]
EARTH_RAMP = ["earth_light", "earth_primary", "earth_mid"]
SAND_PEBBLE_RAMP = ["stone_light", "ivory_highlight", "stone_mid_light"]
TERRACOTTA_RAMP = ["terracotta_light", "terracotta_primary", "terracotta_shadow"]
SNOW_MAT = "warm_white"
SNOW_CREST_MAT = "water_foam"

# Imota's `_BOULDER_VARIANTS`, ported verbatim: authored asymmetric layouts
# (radius, off_x, off_y, height_scale, spread_scale) per lobe.
BOULDER_VARIANTS = [
    [(0.62, 0.0, 0.0, 0.74, 1.06), (0.40, 0.52, 0.12, 0.60, 1.18),
     (0.30, -0.40, -0.30, 0.58, 1.00), (0.22, 0.18, -0.46, 0.52, 1.12)],
    [(0.56, 0.10, 0.0, 0.86, 0.96), (0.46, -0.34, 0.22, 0.66, 1.12),
     (0.27, 0.44, -0.20, 0.56, 1.02)],
    [(0.68, 0.0, 0.05, 0.62, 1.22), (0.34, 0.40, 0.34, 0.52, 1.06),
     (0.30, -0.46, -0.10, 0.58, 1.00), (0.20, -0.10, 0.50, 0.48, 1.00)],
]


def crag_lobe(name, r, loc, material, rng=None, seg=6, rings=3, squash=0.74,
              stretch=(1.0, 1.0), yaw=None, jitter=0.035):
    """One faceted stone lobe (Imota `_facet_sphere`): a low-segment sphere,
    flat-shaded so the sparse topology reads as crag facets.  Verts stay local
    (origin at `loc`), so the object is safe to move/rotate afterwards."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=rings,
                                         radius=r, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    angle = yaw
    if angle is None:
        angle = rng.uniform(0, math.tau) if rng is not None else 0.0
    c, s = math.cos(angle), math.sin(angle)
    for v in obj.data.vertices:
        if rng is not None and jitter > 0.0:
            v.co += Vector((rng.uniform(-jitter, jitter) * r,
                            rng.uniform(-jitter, jitter) * r,
                            rng.uniform(-jitter, jitter) * r * 0.6))
        x, y = v.co.x, v.co.y
        v.co.x = (x * c - y * s) * stretch[0]
        v.co.y = (x * s + y * c) * stretch[1]
        v.co.z *= squash
    obj.data.materials.append(base.mat(material))
    bpy.ops.object.shade_flat()
    return obj


def grounded_lobe(name, r, xy, material, rng=None, base_z=0.0, sink=0.02, **kwargs):
    """A crag lobe resting exactly on `base_z` (Imota's grounding rule: centre
    at its own half-height).  `sink` tucks the base in slightly for seating."""
    squash = kwargs.pop("squash", 0.74)
    half = r * squash
    loc = (xy[0], xy[1], base_z + half * (1.0 - sink))
    return crag_lobe(name, r, loc, material, rng=rng, squash=squash, **kwargs)


def capped_lobe(name, r, xy, material, rng=None, height=RELIEF_MAX, base_z=0.0, **kwargs):
    """A grounded crag lobe whose total height is exactly `height` — the tile
    relief workhorse (setts, pebbles, clods all stay inside the fade budget)."""
    squash = height / (2.0 * r)
    return grounded_lobe(name, r, xy, material, rng=rng, base_z=base_z,
                         sink=0.0, squash=squash, **kwargs)


def rock_cluster(prefix, mats, rng, scale=1.0, variant=None, at=(0.0, 0.0),
                 base_z=0.0, seg_main=6, seg_side=5):
    """Imota `_rock_cluster`: one authored asymmetric layout, every lobe
    grounded, tints alternating across `mats`."""
    layout = BOULDER_VARIANTS[(variant if variant is not None else rng.randrange(3))
                              % len(BOULDER_VARIANTS)]
    objs = []
    for i, (r, ox, oy, sy, sxz) in enumerate(layout):
        objs.append(grounded_lobe(
            f"{prefix}_lobe{i}", r * scale,
            (at[0] + ox * scale, at[1] + oy * scale),
            mats[i % len(mats)], rng=rng, base_z=base_z,
            seg=seg_main if i == 0 else seg_side,
            rings=3, squash=sy * 0.8, stretch=(sxz, sxz),
        ))
    return objs


def dust(objs, material=SNOW_MAT, min_nz=0.6, rng=None, chance=1.0):
    """Imota's snow trick, baked: the cover material claims every face whose
    normal points up past `min_nz` — lit/top surfaces frost over while flanks
    keep their stone.  Works for snow and, with moss, for weathered stone.

    `chance` selects per OBJECT (a stone is either capped or bare) — deciding
    per face on these chunky facets produced pinwheel patchwork, never drifts."""
    for obj in objs if isinstance(objs, (list, tuple)) else [objs]:
        if rng is not None and rng.random() > chance:
            continue
        mesh = obj.data
        index = -1
        for i, slot in enumerate(mesh.materials):
            if slot is not None and slot.name == material:
                index = i
                break
        if index < 0:
            mesh.materials.append(base.mat(material))
            index = len(mesh.materials) - 1
        for poly in mesh.polygons:
            if poly.normal.z >= min_nz:
                poly.material_index = index
    return objs


# ------------------------------------------------------------ tile surfaces
def gravel_field(prefix, rng, mats=None, area=0.7, cell=0.17, density=0.85,
                 r_range=(0.05, 0.085), height=0.044, base_z=0.0):
    """Packed grounded pebbles on a jittered grid — gravel, scree, path metal."""
    mats = mats or STONE_RAMP
    objs = []
    steps = max(2, int(round(area * 2.0 / cell)))
    i = 0
    for gx in range(steps):
        for gy in range(steps):
            if rng.random() > density:
                continue
            x = -area + (gx + 0.5) * (area * 2.0 / steps) + rng.uniform(-cell, cell) * 0.3
            y = -area + (gy + 0.5) * (area * 2.0 / steps) + rng.uniform(-cell, cell) * 0.3
            r = rng.uniform(*r_range)
            objs.append(capped_lobe(
                f"{prefix}_{i}", r, (x, y), mats[i % len(mats)], rng=rng,
                height=min(height, RELIEF_MAX) * rng.uniform(0.75, 1.0),
                base_z=base_z, seg=rng.choice((5, 6)), rings=3,
                stretch=(rng.uniform(0.85, 1.2), rng.uniform(0.85, 1.2)),
            ))
            i += 1
    return objs


def scree_patch(prefix, rng, at, count=4, mats=None, r_range=(0.035, 0.06), base_z=0.0):
    """A pocket of small grounded stones — path edges, wall feet, dirt accents."""
    mats = mats or STONE_RAMP
    objs = []
    for i in range(count):
        a = rng.uniform(0, math.tau)
        d = rng.uniform(0.0, 0.09) + i * 0.02
        objs.append(capped_lobe(
            f"{prefix}_{i}", rng.uniform(*r_range),
            (at[0] + math.cos(a) * d, at[1] + math.sin(a) * d),
            mats[i % len(mats)], rng=rng,
            height=rng.uniform(0.024, 0.04), base_z=base_z, seg=5, rings=2,
        ))
    return objs


def clod_field(prefix, rng, mats=None, count=14, area=0.66, r_range=(0.05, 0.095),
               height=(0.03, 0.046), base_z=0.0):
    """Turned-earth clods: small plump lobes in warm earth tints — kept narrow
    so the relief budget still lets them read as raised lumps, not flat chips."""
    mats = mats or EARTH_RAMP
    objs = []
    for i in range(count):
        objs.append(capped_lobe(
            f"{prefix}_{i}", rng.uniform(*r_range),
            (rng.uniform(-area, area), rng.uniform(-area, area)),
            mats[i % len(mats)], rng=rng,
            height=rng.uniform(*height), base_z=base_z,
            seg=rng.choice((6, 7)), rings=3,
            stretch=(rng.uniform(0.9, 1.25), rng.uniform(0.8, 1.05)),
        ))
    return objs


def sett_field(prefix, rng, mats=None, cells=5, span=0.64, height=RELIEF_MAX,
               moss=0.1, base_z=0.0):
    """Cobble setts: a tight near-grid of plump grounded domes (rounder than
    crag stones — 8 segments — and packed until they kiss) with the odd moss
    pocket.  The Imota rock language shrunk to street scale."""
    mats = mats or STONE_RAMP + ["ivory_highlight"]
    objs = []
    pitch = span * 2.0 / cells
    i = 0
    for row in range(cells):
        for col in range(cells):
            x = -span + (col + 0.5) * pitch + rng.uniform(-0.018, 0.018) + (0.028 if row % 2 else -0.018)
            y = -span + (row + 0.5) * pitch + rng.uniform(-0.018, 0.018)
            if rng.random() < moss:
                objs.append(capped_lobe(
                    f"{prefix}_moss_{i}", pitch * 0.4, (x, y), "moss_bright",
                    rng=rng, height=0.026, base_z=base_z, seg=7, rings=3,
                ))
                i += 1
                continue
            objs.append(capped_lobe(
                f"{prefix}_{i}", pitch * rng.uniform(0.56, 0.62), (x, y),
                mats[i % len(mats)], rng=rng, height=height * rng.uniform(0.9, 1.0),
                base_z=base_z, seg=8, rings=4,
                stretch=(rng.uniform(0.94, 1.1), rng.uniform(0.94, 1.1)),
            ))
            i += 1
    return objs


def slab_field(prefix, rng, specs, mats=None, height=RELIEF_MAX - 0.006, base_z=0.0):
    """Broad organic paving slabs: hard-squashed 7/8-segment crags whose sparse
    outlines read as hand-cut flags.  `specs` = [(x, y, r), ...]."""
    mats = mats or ["stone_light", "ivory_highlight", "stone_mid_light"]
    objs = []
    for i, (x, y, r) in enumerate(specs):
        objs.append(capped_lobe(
            f"{prefix}_{i}", r, (x, y), mats[i % len(mats)], rng=rng,
            height=height * rng.uniform(0.9, 1.0), base_z=base_z,
            seg=rng.choice((7, 8)), rings=3,
            stretch=(rng.uniform(0.94, 1.1), rng.uniform(0.85, 1.0)),
        ))
    return objs


def dune_ridges(prefix, rng, material="warm_white", base_z=0.0):
    """Wind-combed sand: three long soft dune billows sweeping the tile on a
    shared diagonal, plump like banked snow rather than scattered grains."""
    objs = []
    specs = [
        (-0.3, 0.32, 0.22, 2.2), (0.08, -0.04, 0.24, 2.6), (0.44, -0.42, 0.18, 2.0),
    ]
    for i, (x, y, r, run) in enumerate(specs):
        objs.append(capped_lobe(
            f"{prefix}_{i}", r, (x, y), material, rng=rng,
            height=0.032, base_z=base_z, seg=9, rings=4,
            stretch=(run * rng.uniform(0.92, 1.05), 0.5), yaw=-0.72,
            jitter=0.02,
        ))
    return objs


def snow_billows(prefix, rng, spots, height=0.046, material=SNOW_MAT,
                 crest=None, base_z=0.0):
    """Soft banked powder: wide overlapping lobes (higher segment count than
    stone — snow reads pillowy, not craggy).  Optional bright crests ride the
    tops of the largest billows.  `spots` = [(x, y, r, stretch), ...]."""
    objs = []
    for i, (x, y, r, st) in enumerate(spots):
        yaw = rng.uniform(0, math.tau)
        objs.append(capped_lobe(
            f"{prefix}_{i}", r, (x, y), material, rng=rng,
            height=height * rng.uniform(0.86, 1.0), base_z=base_z,
            seg=9, rings=4, stretch=st, yaw=yaw, jitter=0.02,
        ))
        if crest is not None and r >= 0.26:
            objs.append(capped_lobe(
                f"{prefix}_crest_{i}", r * 0.5, (x, y), crest, rng=rng,
                height=height, base_z=base_z, seg=8, rings=3,
                stretch=(st[0] * 0.82, st[1] * 0.78), yaw=yaw, jitter=0.02,
            ))
    return objs


def snow_bound_rock(prefix, rng, at, r=0.11, mats=None, base_z=0.0):
    """A crag pebble breaking through snow, its top faces frosted — the ported
    light-band trick in one object."""
    mats = mats or STONE_RAMP
    rock = capped_lobe(prefix, r, at, mats[rng.randrange(len(mats))], rng=rng,
                       height=min(RELIEF_MAX, r * 0.55), base_z=base_z,
                       seg=6, rings=3)
    dust(rock, SNOW_MAT, min_nz=0.5, rng=rng)
    return rock
