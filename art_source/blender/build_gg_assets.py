#!/usr/bin/env python3
"""Garden Galaxy rework asset builder — rounded, beveled, authored geometry.

Runs headless under Blender 5.x:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python art_source/blender/build_gg_assets.py

Exports GLBs to assets/3d/reworked/ (which AssetLibrary searches FIRST, so
every rebuilt id overrides the legacy asset with zero code changes).

Modeling standards (docs/visual_rework/ASSET_AUDIT.md):
  - hard surfaces: bevel 3-6% of smallest visible dimension, 2-3 segments,
    weighted normals, no razor edges, no default-cube look;
  - curved objects: 12-16 radial segments on pots/posts, rounded silhouettes;
  - pines: 3-5 overlapping lobed tiers, no straight cones, no near-black;
  - bushes: 3-7 overlapping rounded masses;
  - flowers: thick stems, broad leaves, 5-6 shaped petals, visible center;
  - grass: 3-7 broad tapered curved blades, grouped, never scattered noise;
  - composition: <= ~3 authored clusters per tile, 65-75% quiet surface.

Deterministic (fixed seeds). 1 unit = 1 m; tile = 2.0 m; land top z=0.
"""

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "assets" / "3d" / "reworked"
OUT.mkdir(parents=True, exist_ok=True)

TILE = 2.0
BLOCK_DEPTH = 0.56          # visible side ~0.28 of tile width
WATER_SURFACE_Y = -0.14     # matches the contiguous water renderer
WATER_FLOOR_Y = -0.42       # ~0.14 tile widths below the surface

# ---------------------------------------------------------------- palette
# Mirrors assets/palettes/gg_material_palette.tres — keep in sync.
def srgb(hexcode):
    h = hexcode.lstrip("#")
    lin = []
    for i in (0, 2, 4):
        c = int(h[i:i + 2], 16) / 255.0
        lin.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*lin, 1.0)


PALETTE = {
    "background_cream_01": "E4E0D0",
    "background_cream_02": "DFDACA",
    "background_cream_03": "D9D4C4",
    "brown_fabric": "845739",
    "burnt_red": "A94A35",
    "coral": "C96558",
    "cream_fabric": "DDD0B6",
    "crystal": "9ED7D8",
    "dark_fabric": "5B3E2E",
    "deep_grass": "3F5A28",
    "earth_deep": "65412D",
    "earth_light": "BA7B4A",
    "earth_mid": "955F3B",
    "earth_primary": "A86D42",
    "earth_shadow": "7D5236",
    "earthy_olive": "6B6F2F",
    "fire_core": "FFF4CC",
    "fire_orange": "D98B22",
    "fire_red": "B84A2A",
    "fire_yellow": "F2D84A",
    "gold_deep": "BF8E18",
    "gold_highlight": "EAD24A",
    "gold_primary": "DDB626",
    "grass_highlight": "B8CC46",
    "grass_primary": "98B53A",
    "grass_secondary": "7FA134",
    "grass_shade": "567A2C",
    "grass_sunlit": "AFC53D",
    "grass_vivid_accent": "74A82A",
    "hair_deep": "382419",
    "hair_light": "76533B",
    "hair_primary": "543826",
    "ivory_highlight": "E2D7BF",
    "leaf_bright": "8FB058",
    "leaf_medium": "708A4E",
    "leaf_olive": "5B7343",
    "leaf_soft_sage": "98AE82",
    "magic": "A77A2C",
    "moss_bright": "89B03E",
    "moss_primary": "6D9536",
    "mustard_fabric": "B88F41",
    "olive_shadow": "4D6732",
    "pine_deep": "2D4122",
    "pine_light": "6E9440",
    "pine_medium": "50722F",
    "pine_shadow": "3E582A",
    "skin_light": "E0B06C",
    "skin_mid": "C58757",
    "skin_shadow": "967363",
    "smoke": "C4BAA7",
    "soft_coral": "D98A82",
    "soft_sage_gray": "7E8F84",
    "soil_deep": "5E2E17",
    "soil_deepest": "472114",
    "soil_orange": "965722",
    "soil_red_shadow": "7A3D19",
    "stone_deep_shadow": "5C5B55",
    "stone_light": "CFC6B8",
    "stone_mid": "AAA497",
    "stone_mid_light": "BDB5A8",
    "stone_shadow": "7F7C72",
    "stone_warm_shadow": "948C80",
    "terracotta_light": "C9875B",
    "terracotta_orange": "C76D1C",
    "terracotta_primary": "B86E40",
    "terracotta_shadow": "954B1B",
    "uw_flora_dark": "2F6A4D",
    "uw_flora_deep": "1F4C3D",
    "uw_flora_light": "74B27A",
    "uw_flora_mid": "4E8D60",
    "uw_rock_light": "8F9E9D",
    "uw_rock_mid": "738789",
    "uw_rock_shadow": "586A6D",
    "uw_sand_light": "DDD9CD",
    "uw_sand_shadow": "C5C7BE",
    "warm_near_black": "2C1E17",
    "warm_white": "F6EED6",
    "warm_yellow": "E6B34C",
    "water_abyss": "173C50",
    "water_caustic": "A7D7D2",
    "water_deep": "245369",
    "water_deep_mid": "366E81",
    "water_foam": "E3F1EE",
    "water_mid": "478F9E",
    "water_shallow": "73BFC3",
    "water_shallow_highlight": "8FCFD0",
    "water_turquoise": "59AEB8",
    "wood_brown": "6C4A35",
    "wood_dark": "3D2A20",
    "wood_deep": "52382A",
    "wood_gold": "B98237",
    "wood_highlight": "DAB55F",
    "wood_light": "C99849",
    "wood_primary": "A76D2D",
    "wood_warm_shadow": "875324",
    "dark_stone": "7F7C72",  # legacy semantic name
    "eyes": "382419",  # legacy semantic name
    "fabric": "A94A35",  # legacy semantic name
    "fabric_accent": "B88F41",  # legacy semantic name
    "flower_yellow": "DDB626",  # legacy semantic name
    "gold": "DDB626",  # legacy semantic name
    "grass": "98B53A",  # legacy semantic name
    "hair": "543826",  # legacy semantic name
    "metal": "5C5B55",  # legacy semantic name
    "moss": "6D9536",  # legacy semantic name
    "mushroom_red": "C96558",  # legacy semantic name
    "pale_stone": "CFC6B8",  # legacy semantic name
    "petal_pink": "D98A82",  # legacy semantic name
    "petal_red": "C96558",  # legacy semantic name
    "petal_white": "F6EED6",  # legacy semantic name
    "skin": "E0B06C",  # legacy semantic name
    "soil": "965722",  # legacy semantic name
    "terracotta": "C9875B",  # legacy semantic name
    "water": "59AEB8",  # legacy semantic name
    "wood": "A76D2D",  # legacy semantic name
    "calib_gray": "9E9E9E",
}

EMISSIVE = {"fire_core": 6.0, "fire_yellow": 3.0, "fire_orange": 2.2, "magic": 2.5, "crystal": 1.2}
_mats = {}


def mat(name):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = srgb(PALETTE[name])
    bsdf.inputs["Roughness"].default_value = 0.88
    bsdf.inputs["Metallic"].default_value = 0.0
    if name in EMISSIVE:
        bsdf.inputs["Emission Color"].default_value = srgb(PALETTE[name])
        bsdf.inputs["Emission Strength"].default_value = EMISSIVE[name]
    _mats[name] = m
    return m


# ---------------------------------------------------------------- finishing
def _finish(obj, material, bevel=0.0, segments=2, smooth_angle=40.0, flat=False, weighted=True):
    obj.data.materials.append(mat(material))
    if bevel > 0.0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = segments
        mod.angle_limit = math.radians(38)
        if weighted and not flat:
            wn = obj.modifiers.new("wnormal", "WEIGHTED_NORMAL")
            wn.keep_sharp = True
            wn.weight = 50
    if flat:
        bpy.ops.object.shade_flat()
    else:
        try:
            bpy.ops.object.shade_auto_smooth(angle=math.radians(smooth_angle))
        except Exception:
            bpy.ops.object.shade_smooth()
    return obj


def rbox(name, size, loc, material, bevel_frac=0.045, segments=2, flat=False, bevel=None):
    """Rounded box: bevel defaults to a fraction of the smallest dimension."""
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector(size)
    bpy.ops.object.transform_apply(scale=True)
    width = bevel if bevel is not None else max(0.008, min(size) * bevel_frac)
    return _finish(obj, material, width, segments, flat=flat)


def rcyl(name, r, depth, loc, material, verts=18, bevel_frac=0.06, r2=None, segments=3, flat=False, bevel=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    width = bevel if bevel is not None else max(0.006, min(r, depth) * bevel_frac)
    return _finish(obj, material, width, segments, flat=flat)


def uv_sphere(name, r, loc, material, segments=28, rings=16, squash=1.0,
              stretch=(1.0, 1.0), smooth_angle=180.0):
    """High-resolution rounded volume. UV spheres give a far cleaner silhouette
    than low-subdivision icospheres at the same triangle budget, which is what
    kills the faceted look on heads, bushes and foliage."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=rings,
                                         radius=r, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector((stretch[0], stretch[1], squash))
    bpy.ops.object.transform_apply(scale=True)
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat(material))
    return obj


def lobe(name, r, loc, material, squash=0.86, subdiv=2, stretch=(1.0, 1.0)):
    """Rounded foliage/organic mass. `subdiv` is kept for call compatibility and
    mapped onto UV-sphere resolution; every lobe is fully smooth-shaded."""
    seg = {1: 20, 2: 28, 3: 36}.get(subdiv, 28)
    return uv_sphere(name, r, loc, material, segments=seg, rings=max(10, seg // 2),
                     squash=squash, stretch=stretch)


def pine_tier(name, r, height, loc, material, rng, lobes=7):
    """One broad foliage mass of a pine: a high-resolution rounded dome with a
    gently scalloped, drooping lower rim and a softened tip. No cone, no
    horizontal tier break, no octagonal cross-section."""
    bpy.ops.mesh.primitive_uv_sphere_add(segments=32, ring_count=18, radius=1.0,
                                         location=loc)
    obj = bpy.context.active_object
    obj.name = name
    phase = rng.uniform(0, 6.28)
    phase2 = rng.uniform(0, 6.28)
    for v in obj.data.vertices:
        z01 = (v.co.z + 1.0) * 0.5                     # 0 bottom .. 1 top
        # Smooth ogive taper: full width low down, easing to a soft point.
        taper = math.sin((1.0 - z01) * math.pi * 0.5) ** 0.7
        ang = math.atan2(v.co.y, v.co.x)
        # Two scallop harmonics so the outline never repeats mechanically.
        scallop = (1.0
                   + 0.085 * math.sin(ang * lobes + phase) * (1.0 - z01)
                   + 0.045 * math.sin(ang * (lobes * 2 + 1) + phase2) * (1.0 - z01))
        v.co.x *= r * taper * scallop
        v.co.y *= r * taper * scallop
        # Skirt droops outward and down at the rim instead of cutting flat.
        droop = max(0.0, 0.32 - z01) * 1.4
        v.co.z = (v.co.z * 0.5 + 0.5) * height - droop * height * 0.28
    bpy.ops.object.shade_smooth()
    obj.data.materials.append(mat(material))
    return obj


def rock(name, r, loc, material, rng, squash=0.78):
    """Designed rock: controlled asymmetry, readable top plane, soft facets.
    Subdivision 2 keeps a rounded outer silhouette while the bevel + moderate
    smoothing angle preserve deliberate planes (no tetrahedron look)."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=2, radius=r, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    sx, sy = rng.uniform(0.8, 1.25), rng.uniform(0.8, 1.2)
    for v in obj.data.vertices:
        v.co.x *= sx * (1.0 + rng.uniform(-0.08, 0.08))
        v.co.y *= sy * (1.0 + rng.uniform(-0.08, 0.08))
        v.co.z *= squash
        if v.co.z > r * squash * 0.55:      # flattened top plane
            v.co.z = r * squash * 0.55 + (v.co.z - r * squash * 0.55) * 0.35
    obj.rotation_euler = Euler((0, 0, rng.uniform(0, 6.28)))
    _finish(obj, material, r * 0.1, segments=2, smooth_angle=46.0)
    return obj


def blade(name, w, h, loc, material, rng, lean=0.35):
    """Broad tapered grass blade with a rounded tip. Deliberately chunky: thin
    spikes alias badly at the isometric gameplay distance, so every blade stays
    several screen pixels wide and keeps volume all the way up."""
    bpy.ops.mesh.primitive_cone_add(vertices=12, radius1=w, radius2=w * 0.42,
                                    depth=h, location=(loc[0], loc[1], loc[2] + h / 2))
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector((1.0, 0.62, 1.0))
    bpy.ops.object.transform_apply(scale=True)
    ang = rng.uniform(0, 6.28)
    dx, dy = math.cos(ang) * lean * h, math.sin(ang) * lean * h
    for v in obj.data.vertices:
        z01 = max(0.0, min(1.0, v.co.z / max(h, 1e-5) + 0.5))
        v.co.x += dx * z01 * z01
        v.co.y += dy * z01 * z01
    obj.rotation_euler = Euler((0, 0, rng.uniform(0, 6.28)))
    # Bevel rounds the tip and the base rim so the blade never ends in a
    # one-pixel point.
    return _finish(obj, material, w * 0.34, segments=2, smooth_angle=70.0)


def petal_flower(prefix, rng, petal_mat="petal_pink", petals=5, stem_h=None):
    """Thick stem, broad leaves, shaped petals around a visible center."""
    objs = []
    h = stem_h if stem_h else rng.uniform(0.26, 0.34)
    stem = rcyl(f"{prefix}_stem", 0.038, h, (0, 0, h / 2), "leaf_bright", verts=14, bevel=0.008)
    tip = rng.uniform(0.03, 0.05)
    for v in stem.data.vertices:
        z01 = max(0.0, v.co.z / max(h, 1e-5) + 0.5)
        v.co.x += tip * z01 * z01
    objs.append(stem)
    for i in range(2):
        leaf = lobe(f"{prefix}_leaf{i}", 0.075, (0, 0, h * rng.uniform(0.25, 0.45)), "leaf_bright", squash=0.22, stretch=(1.6, 0.7))
        leaf.rotation_euler = Euler((rng.uniform(-0.25, -0.05), 0, rng.uniform(0, 6.28)))
        objs.append(leaf)
    cx = tip
    for i in range(petals):
        a = i * (6.283 / petals) + rng.uniform(-0.1, 0.1)
        p = lobe(f"{prefix}_petal{i}", 0.055, (cx + math.cos(a) * 0.072, math.sin(a) * 0.072, h + 0.028), petal_mat, squash=0.34, stretch=(1.35, 0.85))
        p.rotation_euler = Euler((0, -0.22, a))
        objs.append(p)
    objs.append(lobe(f"{prefix}_center", 0.036, (cx, 0, h + 0.045), "flower_yellow", squash=0.6))
    return objs


def tuft(prefix, rng, blades=5, material="moss_bright", w=0.072, h_range=(0.16, 0.3)):
    objs = []
    for i in range(blades):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.015, 0.06)
        objs.append(blade(f"{prefix}_b{i}", w, rng.uniform(*h_range),
                          (math.cos(a) * d, math.sin(a) * d, 0), material, rng))
    return objs


def move(objs, offset):
    for o in objs:
        o.location = Vector(o.location) + Vector(offset)
    return objs


def rot_z(objs, angle):
    for o in objs:
        o.rotation_euler = Euler((o.rotation_euler.x, o.rotation_euler.y, o.rotation_euler.z + angle))
        o.location = Vector((
            o.location.x * math.cos(angle) - o.location.y * math.sin(angle),
            o.location.x * math.sin(angle) + o.location.y * math.cos(angle),
            o.location.z,
        ))
    return objs


def export(asset_id, objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    out = OUT / f"{asset_id}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out), use_selection=True, export_apply=True, export_yup=True,
        export_animations=False, export_skins=False, export_lights=False, export_cameras=False,
    )
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    print(f"[asset] {out.relative_to(ROOT)}")


# ---------------------------------------------------------------- terrain
def tile_block(prefix, top_mat, side_mat):
    """Rounded-edge land block: shallow warm side, chunky soft top cap."""
    # Cap is exactly one tile wide: an oversized cap overlaps its neighbour and
    # z-fights. Rounded vertical corners + a 3-segment bevel turn the join into
    # a soft shoulder instead of a razor edge or a dark crack.
    body = rbox(f"{prefix}_body", (TILE - 0.004, TILE - 0.004, BLOCK_DEPTH - 0.1),
                (0, 0, -(BLOCK_DEPTH + 0.1) / 2), side_mat, bevel=0.045, segments=3)
    cap = rbox(f"{prefix}_cap", (TILE, TILE, 0.16), (0, 0, -0.07),
               top_mat, bevel=0.05, segments=3)
    return [body, cap]


def grass_cluster(prefix, rng, kind="tuft"):
    """One authored detail cluster (tuft group / rock pair / flower trio)."""
    if kind == "tuft":
        objs = tuft(f"{prefix}_t0", rng, blades=rng.randint(4, 6))
        objs += move(tuft(f"{prefix}_t1", rng, blades=3, h_range=(0.1, 0.18)), (rng.uniform(0.14, 0.22), rng.uniform(-0.1, 0.1), 0))
        return objs
    if kind == "rocks":
        objs = [rock(f"{prefix}_r0", rng.uniform(0.1, 0.14), (0, 0, 0.05), "stone_light", rng)]
        objs.append(rock(f"{prefix}_r1", rng.uniform(0.055, 0.08), (rng.uniform(0.16, 0.22), rng.uniform(-0.08, 0.08), 0.03), "stone_mid", rng))
        return objs
    objs = []
    mats = ["petal_pink", "petal_white", "flower_yellow"]
    for i in range(3):
        objs += move(petal_flower(f"{prefix}_f{i}", rng, mats[i % 3]),
                     (math.cos(i * 2.1) * 0.16, math.sin(i * 2.1) * 0.16, 0))
    return objs


def build_terrain():
    rng = random.Random(101)

    # Meadow: one tuft cluster near a corner + one rock pair near the opposite
    # edge; ~70% of the top stays quiet.
    t = tile_block("grass", "grass_primary", "earth_mid")
    t += move(grass_cluster("g_tc", rng, "tuft"), (-0.58, -0.5, 0.01))
    t += move(grass_cluster("g_rk", rng, "rocks"), (0.62, 0.55, 0.01))
    export("tile_grass", t)

    t = tile_block("gf", "grass_primary", "earth_mid")
    t += move(grass_cluster("gf_fl", rng, "flowers"), (-0.35, 0.3, 0.01))
    t += move(grass_cluster("gf_tf", rng, "tuft"), (0.6, -0.55, 0.01))
    export("tile_grass_flower", t)

    # Garden bed
    t = tile_block("gar", "grass_sunlit", "earth_mid")
    t.append(rbox("gar_bed", (1.15, 1.15, 0.18), (0.15, 0.15, 0.09), "wood_gold", bevel=0.03, segments=3))
    t.append(rbox("gar_fill", (0.95, 0.95, 0.1), (0.15, 0.15, 0.15), "soil_orange", bevel=0.018, flat=True))
    t += move(grass_cluster("gar_fl", rng, "flowers"), (0.15, 0.15, 0.2))
    export("tile_garden", t)

    # Paving: varied warm-ivory slabs, narrow warm seams, soft height steps.
    t = tile_block("pa", "stone_warm_shadow", "stone_mid")
    slabs = [
        ((-0.5, -0.5), (0.94, 0.94)), ((0.52, -0.62), (0.86, 0.68)),
        ((0.52, 0.28), (0.86, 0.98)), ((-0.5, 0.52), (0.94, 0.9)),
    ]
    for i, ((sx, sy), (w, d)) in enumerate(slabs):
        t.append(rbox(f"pa_slab{i}", (w, d, 0.08),
                      (sx, sy, 0.03 + rng.uniform(-0.005, 0.005)),
                      "stone_light" if i != 2 else "stone_mid_light", bevel=0.035, segments=3))
    export("tile_path", t)

    t = tile_block("co", "stone_light", "stone_mid")
    t.append(rbox("co_center", (0.92, 0.92, 0.055), (0, 0, 0.026), "terracotta_light", bevel=0.024, segments=3))
    for i, (x, y, w, d) in enumerate([(0, 0.73, 1.72, 0.3), (0, -0.73, 1.72, 0.3), (0.73, 0, 0.3, 1.16), (-0.73, 0, 0.3, 1.16)]):
        t.append(rbox(f"co_ring{i}", (w, d, 0.045), (x, y, 0.02), "terracotta_primary", bevel=0.018, segments=2))
    export("tile_courtyard", t)

    # Pond edge: sloped sandy shore into readable shallow water.
    t = []
    t.append(rbox("gp_body", (TILE, TILE, 0.2), (0, 0, -BLOCK_DEPTH + 0.1), "earth_mid", bevel=0.02, flat=True))
    rim = 0.4
    for i, (x, y, w, d) in enumerate([(0, -TILE / 2 + rim / 2, TILE + 0.02, rim), (0, TILE / 2 - rim / 2, TILE + 0.02, rim),
                                      (-TILE / 2 + rim / 2, 0, rim, TILE + 0.02), (TILE / 2 - rim / 2, 0, rim, TILE + 0.02)]):
        t.append(rbox(f"gp_rim{i}", (w, d, BLOCK_DEPTH), (x, y, -BLOCK_DEPTH / 2), "earth_mid", bevel=0.02, flat=True))
        t.append(rbox(f"gp_cap{i}", (w, d, 0.16), (x, y, -0.07), "grass_primary", bevel=0.06, segments=3))
    # sloped sand shore ring — tucked inside the basin, meeting the floor
    for i, (x, y, yaw) in enumerate([(0, -0.47, 0), (0, 0.47, math.pi), (-0.47, 0, -math.pi / 2), (0.47, 0, math.pi / 2)]):
        panel = rbox(f"gp_slope{i}", (1.02, 0.3, 0.05), (x, y, -0.36), "uw_sand_light", bevel=0.01, flat=True)
        panel.rotation_euler = Euler((-0.62 if yaw in (0.0,) else 0.62 if yaw == math.pi else 0.0, 0, 0))
        if yaw not in (0.0, math.pi):
            panel.rotation_euler = Euler((0, 0.62 if x > 0 else -0.62, 0))
        t.append(panel)
    t.append(rbox("gp_floor", (1.15, 1.15, 0.07), (0, 0, -0.46), "uw_sand_light", bevel=0.012, flat=True))
    water = rbox("WaterSurface", (TILE - 0.5, TILE - 0.5, 0.03), (0, 0, -0.2), "water", bevel=0.0)
    t.append(water)
    t += move(tuft("gp_reed", rng, 4, "leaf_bright", w=0.03, h_range=(0.3, 0.5)), (-0.68, -0.68, 0))
    t.append(rock("gp_rock", 0.12, (0.66, 0.72, 0.05), "stone_light", rng))
    export("tile_grass_pond_edge", t)

    # Stone family
    t = tile_block("sc", "stone_mid_light", "stone_mid")
    t.append(rock("sc_r0", 0.24, (-0.35, -0.3, 0.09), "stone_light", rng))
    t.append(rock("sc_r1", 0.15, (0.05, -0.05, 0.06), "stone_mid_light", rng))
    t.append(rock("sc_r2", 0.09, (0.42, 0.5, 0.04), "stone_mid", rng))
    export("tile_stone_clearing", t)

    t = tile_block("sm", "moss_primary", "stone_mid")
    t.append(rock("sm_r0", 0.26, (-0.4, 0.35, 0.1), "stone_shadow", rng))
    t.append(rock("sm_r1", 0.16, (-0.05, 0.55, 0.06), "stone_mid_light", rng))
    t += move(_mushrooms("smm", rng), (0.55, -0.5, 0))
    export("tile_stone_mossy", t)

    t = tile_block("sr", "stone_mid_light", "stone_mid")
    t.append(rbox("sr_found1", (1.1, 0.26, 0.36), (0, 0.5, 0.18), "stone_light", bevel=0.035, segments=3))
    t.append(rbox("sr_found2", (0.26, 0.9, 0.28), (0.55, -0.2, 0.14), "stone_light", bevel=0.035, segments=3))
    t.append(rock("sr_r0", 0.18, (-0.5, -0.45, 0.07), "stone_light", rng))
    export("tile_stone_ruin", t)

    t = tile_block("scr", "stone_mid_light", "stone_mid")
    for i in range(3):
        h = rng.uniform(0.35, 0.7)
        c = rcyl(f"scr_c{i}", rng.uniform(0.09, 0.15), h, (rng.uniform(-0.45, 0.45), rng.uniform(-0.45, 0.45), h / 2), "crystal", verts=6, bevel=0.01, flat=True)
        c.rotation_euler = Euler((rng.uniform(-0.15, 0.15), rng.uniform(-0.15, 0.15), rng.uniform(0, 3.14)))
        t.append(c)
    export("tile_stone_crystal", t)

    t = tile_block("ro", "stone_mid_light", "stone_mid")
    for i, (x, y) in enumerate([(-0.55, -0.3), (0.0, -0.28), (0.55, -0.32), (-0.28, 0.32), (0.28, 0.3)]):
        t.append(rbox(f"ro_s{i}", (0.5, 0.52, 0.055), (x + rng.uniform(-0.02, 0.02), y, 0.026), "stone_light", bevel=0.024, segments=3))
    t += move(tuft("rot", rng, 3, "moss_primary"), (0.6, -0.7, 0.01))
    export("tile_stone_road", t)

    # Groves — one tree + one bush + one tuft, asymmetric triangle composition.
    def grove(asset_id, seed, tree_fn):
        r = random.Random(seed)
        g = tile_block(asset_id, "grass_sunlit", "earth_mid")
        g += move(tree_fn(r), (0.45, 0.42, 0))
        g += move(_bush(f"{asset_id}_b", r, 0.3, lobes=4), (-0.55, 0.42, 0))
        g += move(tuft(f"{asset_id}_t", r, 4), (-0.4, -0.62, 0.01))
        export(asset_id, g)

    grove("tile_grove_mature", 121, lambda r: _pine("gm", r, 1.95, 4))
    grove("tile_grove_birch", 122, lambda r: _leafy_tree("gb", r, trunk_mat="warm_white", leaf_mat="leaf_bright"))
    grove("tile_grove_mossy", 123, lambda r: _pine("gms", r, 1.5, 3, light="moss_bright", mid="moss_primary", deep="grass_shade"))
    grove("tile_grove_autumn", 124, lambda r: _leafy_tree("ga", r, leaf_mat="terracotta_orange"))
    grove("tile_grove_flowering", 125, lambda r: _leafy_tree("gfl", r, leaf_mat="soft_coral"))

    # Open-water sand floor tile (surface comes from the water renderer).
    # Dish-shaped: shallow near tile edges, deep toward the center, so the
    # depth-absorption gradient reads shallow-to-turquoise-to-deep.
    t = []
    floor = rbox("wf_bed", (TILE - 0.03, TILE - 0.03, 0.14), (0, 0, WATER_FLOOR_Y - 0.07), "uw_sand_light", bevel=0.02)
    bpy.ops.object.select_all(action="DESELECT")
    floor.select_set(True)
    bpy.context.view_layer.objects.active = floor
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.subdivide(number_cuts=5)
    bpy.ops.object.mode_set(mode="OBJECT")
    for v in floor.data.vertices:
        if v.co.z > WATER_FLOOR_Y - 0.06:
            dist = math.hypot(v.co.x, v.co.y)
            v.co.z -= 0.42 * max(0.0, 1.0 - dist / 1.25) ** 1.4
            v.co.z += rng.uniform(-0.012, 0.02)
    t.append(floor)
    t.append(rbox("wf_body", (TILE - 0.03, TILE - 0.03, 0.14),
                  (0, 0, WATER_FLOOR_Y - 0.14), "uw_sand_shadow", bevel=0.015, flat=True))
    export("tile_water_floor", t)


def _mushrooms(prefix, rng):
    objs = []
    for i, r in enumerate([0.1, 0.07]):
        sh = rng.uniform(0.09, 0.14)
        objs.append(rcyl(f"{prefix}_s{i}", r * 0.38, sh, (i * 0.16, i * 0.07, sh / 2), "warm_white", verts=10, bevel=0.008))
        objs.append(lobe(f"{prefix}_c{i}", r, (i * 0.16, i * 0.07, sh + r * 0.28), "mushroom_red", squash=0.6))
    return objs


# ---------------------------------------------------------------- vegetation
def _pine(prefix, rng, height=1.7, tiers=4, light="pine_light", mid="pine_medium", deep="pine_shadow"):
    trunk_h = height * 0.24
    objs = [rcyl(f"{prefix}_trunk", 0.105, trunk_h, (0, 0, trunk_h / 2), "wood_brown", verts=18, r2=0.08, bevel=0.014)]
    base = trunk_h * 0.75
    span = height - base
    radius = 0.32 + height * 0.14
    for i in range(tiers):
        z01 = i / max(tiers - 1, 1)
        tier_mat = light if i == tiers - 1 else mid
        r = radius * (1.0 - 0.58 * z01) * rng.uniform(0.94, 1.06)
        th = span / tiers * 1.75
        tier = pine_tier(f"{prefix}_tier{i}", r, th,
                         (rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), base + span * z01 * 0.82 + th * 0.28),
                         tier_mat, rng)
        objs.append(tier)
    return objs


def _bush(prefix, rng, r=0.42, material="leaf_medium", lobes=5, accent="leaf_bright"):
    objs = []
    for i in range(lobes):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.0, r * 0.55)
        rr = r * rng.uniform(0.55, 0.95)
        m = accent if i == lobes - 1 else material
        objs.append(lobe(f"{prefix}_l{i}", rr, (math.cos(a) * d, math.sin(a) * d, rr * 0.7), m,
                         squash=rng.uniform(0.78, 0.9)))
    return objs


def _leafy_tree(prefix, rng, trunk_mat="wood_brown", leaf_mat="leaf_bright"):
    trunk = rcyl(f"{prefix}_trunk", 0.105, 0.9, (0, 0, 0.45), trunk_mat, verts=18, r2=0.075, bevel=0.014)
    tip = rng.uniform(-0.06, 0.06)
    for v in trunk.data.vertices:
        z01 = max(0.0, v.co.z / 0.9 + 0.5)
        v.co.x += tip * z01
    objs = [trunk]
    objs.append(lobe(f"{prefix}_crown", 0.5, (tip, 0, 1.16), leaf_mat, squash=0.82))
    objs.append(lobe(f"{prefix}_crown2", 0.34, (tip + rng.uniform(0.15, 0.3), rng.uniform(-0.2, 0.2), 1.0), leaf_mat, squash=0.8))
    objs.append(lobe(f"{prefix}_crown3", 0.28, (tip - rng.uniform(0.15, 0.28), rng.uniform(-0.2, 0.2), 0.95), leaf_mat, squash=0.8))
    return objs


def build_vegetation():
    export("prop_pine_young", _pine("pyg", random.Random(141), 1.25, 3))
    export("prop_pine_a", _pine("pna", random.Random(142), 1.8, 4))
    export("prop_pine_b", _pine("pnb", random.Random(143), 2.35, 5))
    export("prop_bush_a", _bush("bsa", random.Random(144), 0.45, "leaf_medium", 5))
    export("prop_bush_b", _bush("bsb", random.Random(145), 0.34, "leaf_bright", 4, accent="leaf_soft_sage"))
    export("prop_bush_c", _bush("bsc", random.Random(146), 0.5, "leaf_olive", 6, accent="leaf_medium"))
    rng = random.Random(147)
    export("prop_flowers_pink", petal_flower("fpk", rng, "petal_pink") + move(petal_flower("fpk2", rng, "petal_pink", stem_h=0.24), (0.17, 0.1, 0)))
    export("prop_flowers_white", petal_flower("fwh", rng, "petal_white") + move(petal_flower("fwh2", rng, "petal_white", stem_h=0.22), (0.15, -0.12, 0)))
    export("prop_flowers_red", petal_flower("fre", rng, "petal_red"))
    export("prop_grass_tuft", tuft("tft", random.Random(148), 6))
    export("prop_mushrooms", _mushrooms("msh", random.Random(149)))
    r = random.Random(150)
    export("prop_rock_cluster", [rock("rkc_a", 0.28, (0, 0, 0.11), "stone_light", r),
                                 rock("rkc_b", 0.16, (0.34, 0.16, 0.06), "stone_mid_light", r),
                                 rock("rkc_c", 0.09, (0.18, -0.24, 0.04), "stone_mid", r)])
    reeds = []
    rr = random.Random(151)
    for i in range(5):
        x, y = rr.uniform(-0.16, 0.16), rr.uniform(-0.16, 0.16)
        h = rr.uniform(0.42, 0.64)
        reeds.append(rcyl(f"rds_s{i}", 0.03, h, (x, y, h / 2), "leaf_bright", verts=14, bevel=0.006))
        reeds.append(rcyl(f"rds_h{i}", 0.046, 0.14, (x, y, h + 0.06), "wood_brown", verts=16, bevel=0.01))
    export("prop_reeds", reeds)
    stump = [rcyl("stump", 0.24, 0.3, (0, 0, 0.15), "wood_brown", verts=14, bevel=0.03, segments=3)]
    stump.append(rcyl("stump_top", 0.2, 0.035, (0, 0, 0.315), "wood_light", verts=14, bevel=0.008))
    export("prop_stump", stump)
    lg = rcyl("log", 0.15, 0.9, (0, 0, 0.15), "wood_brown", verts=12, bevel=0.02, segments=3)
    lg.rotation_euler = Euler((0, 1.5708, 0.4))
    export("prop_log", [lg, lobe("log_moss", 0.13, (0.1, 0.05, 0.24), "moss_primary", squash=0.5)])


# ---------------------------------------------------------------- props
def build_props():
    rng = random.Random(161)

    # Bench: chunky rounded seat, soft legs, gently angled back.
    bench = [
        rbox("bench_leg1", (0.14, 0.36, 0.26), (-0.42, 0, 0.13), "wood_deep", bevel=0.02, segments=3),
        rbox("bench_leg2", (0.14, 0.36, 0.26), (0.42, 0, 0.13), "wood_deep", bevel=0.02, segments=3),
        rbox("bench_seat", (1.1, 0.44, 0.1), (0, 0, 0.31), "wood_light", bevel=0.028, segments=3),
    ]
    back = rbox("bench_back", (1.1, 0.09, 0.34), (0, -0.19, 0.55), "wood_light", bevel=0.026, segments=3)
    back.rotation_euler = Euler((0.12, 0, 0))
    bench.append(back)
    export("prop_bench", bench)

    stool = [rcyl("stool_top", 0.2, 0.09, (0, 0, 0.3), "wood_light", verts=14, bevel=0.028, segments=3),
             rcyl("stool_leg", 0.13, 0.26, (0, 0, 0.13), "wood_deep", verts=12, bevel=0.015)]
    export("prop_stool", stool)

    table = [rcyl("table_top", 0.42, 0.08, (0, 0, 0.5), "wood_light", verts=16, bevel=0.03, segments=3),
             rcyl("table_leg", 0.09, 0.47, (0, 0, 0.24), "wood_deep", verts=12, bevel=0.012),
             rcyl("table_base", 0.2, 0.07, (0, 0, 0.035), "wood_deep", verts=14, bevel=0.015)]
    export("prop_table", table)

    # Dock: individual rounded planks, soft posts, board variation.
    dock = []
    for i in range(5):
        dock.append(rbox(f"dock_plank{i}", (0.88, 0.34, 0.09),
                         (rng.uniform(-0.015, 0.015), -0.72 + i * 0.37, 0.1 + rng.uniform(-0.006, 0.006)),
                         "wood_light" if i % 2 else "wood_gold", bevel=0.024, segments=3))
    for i, (x, y) in enumerate([(-0.4, -0.8), (0.4, -0.8), (-0.4, 0.8), (0.4, 0.8)]):
        dock.append(rcyl(f"dock_pile{i}", 0.085, 0.62, (x, y, -0.14), "wood_brown", verts=18, bevel=0.016))
    export("prop_dock", dock)

    # Ferry delivery dock (matches DeliveryPoint marker layout).
    fdock = []
    for i in range(4):
        fdock.append(rbox(f"fdock_plank{i}", (1.05, 0.36, 0.11),
                          (rng.uniform(-0.012, 0.012), 0.72 + i * 0.38, 0.085 + rng.uniform(-0.005, 0.005)),
                          "wood_light" if i % 2 else "wood_gold", bevel=0.026, segments=3))
    for side in (-1.0, 1.0):
        fdock.append(rcyl(f"fdock_post{side > 0}", 0.09, 0.74, (side * 0.45, 1.52, 0.3), "wood_brown", verts=18, bevel=0.016))
    export("prop_dock_ferry", fdock)

    # Present: rounded parcel, ribbon, soft bow.
    present = [
        rbox("present_box", (0.46, 0.4, 0.32), (0, 0, 0.16), "warm_white", bevel=0.028, segments=3),
        rbox("present_ribbon_x", (0.1, 0.41, 0.335), (0, 0, 0.163), "coral", bevel=0.014, segments=2),
        rbox("present_ribbon_z", (0.47, 0.1, 0.335), (0, 0, 0.163), "coral", bevel=0.014, segments=2),
        lobe("present_bow_l", 0.06, (-0.055, 0, 0.36), "coral", squash=0.7, stretch=(1.2, 0.8)),
        lobe("present_bow_r", 0.06, (0.055, 0, 0.36), "coral", squash=0.7, stretch=(1.2, 0.8)),
        lobe("present_bow_c", 0.035, (0, 0, 0.365), "burnt_red", squash=0.8),
    ]
    export("prop_present", present)

    chest = [
        rbox("chest_base", (0.62, 0.42, 0.3), (0, 0, 0.15), "wood_gold", bevel=0.03, segments=3),
    ]
    lid = rcyl("chest_lid", 0.21, 0.64, (0, 0, 0.31), "wood_brown", verts=14, bevel=0.02, segments=2)
    lid.rotation_euler = Euler((0, 1.5708, 0))
    lid.scale = Vector((1.0, 1.0, 0.62))
    bpy.ops.object.transform_apply(scale=True)
    chest.append(lid)
    chest.append(rbox("chest_band", (0.65, 0.1, 0.3), (0, 0, 0.17), "stone_deep_shadow", bevel=0.014))
    chest.append(rbox("chest_clasp", (0.1, 0.06, 0.12), (0, -0.22, 0.28), "gold_primary", bevel=0.012))
    export("prop_chest", chest)

    lantern = [
        rcyl("lant_base", 0.15, 0.08, (0, 0, 0.04), "warm_near_black", verts=22, bevel=0.018, segments=3),
        rcyl("lant_pole", 0.055, 1.02, (0, 0, 0.56), "warm_near_black", verts=18, r2=0.046, bevel=0.012),
        rcyl("lant_collar", 0.078, 0.05, (0, 0, 1.04), "warm_near_black", verts=18, bevel=0.012),
        rbox("lant_cage", (0.22, 0.22, 0.26), (0, 0, 1.2), "warm_near_black", bevel=0.022, segments=3),
        rbox("lant_glow", (0.155, 0.155, 0.19), (0, 0, 1.2), "fire_core", bevel=0.012),
        rcyl("lant_cap", 0.19, 0.1, (0, 0, 1.37), "warm_near_black", verts=20, r2=0.075, bevel=0.02, segments=3),
        lobe("lant_finial", 0.036, (0, 0, 1.44), "warm_near_black", squash=1.0),
    ]
    lantern[4].name = "GlowCore"
    export("prop_lantern", lantern)

    card = [
        rbox("card_body", (0.56, 0.44, 0.4), (0, 0, 0.2), "wood_light", bevel=0.02, segments=3),
        rbox("card_inner", (0.48, 0.36, 0.03), (0, 0, 0.3), "wood_brown", bevel=0.006, flat=True),
    ]
    for name, size, pos, rot in [
        ("card_flap_l", (0.26, 0.42, 0.028), (-0.26, 0, 0.44), (0, -0.55, 0)),
        ("card_flap_r", (0.26, 0.42, 0.028), (0.26, 0, 0.44), (0, 0.55, 0)),
        ("card_flap_f", (0.5, 0.2, 0.028), (0, -0.23, 0.43), (0.7, 0, 0)),
    ]:
        f = rbox(name, size, pos, "wood_light", bevel=0.01)
        f.rotation_euler = Euler(rot)
        card.append(f)
    export("prop_cardboard_box", card)

    pot = [
        rcyl("pot_body", 0.2, 0.3, (0, 0, 0.15), "terracotta_light", verts=24, r2=0.155, bevel=0.022, segments=3),
        rcyl("pot_lip", 0.24, 0.085, (0, 0, 0.33), "terracotta_primary", verts=24, bevel=0.028, segments=3),
        rcyl("pot_soil", 0.175, 0.03, (0, 0, 0.35), "soil_orange", verts=24, bevel=0.006, flat=True),
        lobe("pot_plant", 0.15, (0, 0, 0.48), "leaf_bright", squash=0.88),
    ]
    export("prop_pot", pot)

    planter = [
        rbox("pl_box", (0.72, 0.36, 0.28), (0, 0, 0.14), "wood_gold", bevel=0.026, segments=3),
        rbox("pl_soil", (0.62, 0.27, 0.05), (0, 0, 0.26), "soil_orange", bevel=0.008, flat=True),
    ]
    planter += move(petal_flower("plf", rng, "petal_white", stem_h=0.2), (-0.12, 0, 0.27))
    planter += move(petal_flower("plf2", rng, "petal_pink", stem_h=0.24), (0.14, 0.02, 0.27))
    export("prop_planter", planter)

    fence = [
        rcyl("fence_post1", 0.085, 0.54, (-0.8, 0, 0.27), "wood_brown", verts=18, bevel=0.016),
        rcyl("fence_post2", 0.085, 0.54, (0.8, 0, 0.27), "wood_brown", verts=18, bevel=0.016),
        rbox("fence_rail1", (1.72, 0.065, 0.1), (0, 0, 0.4), "wood_light", bevel=0.018, segments=3),
        rbox("fence_rail2", (1.72, 0.065, 0.1), (0, 0, 0.19), "wood_light", bevel=0.018, segments=3),
    ]
    export("prop_fence", fence)

    gate = [
        rcyl("gate_post1", 0.09, 0.74, (-0.55, 0, 0.37), "wood_brown", verts=12, bevel=0.016),
        rcyl("gate_post2", 0.09, 0.74, (0.55, 0, 0.37), "wood_brown", verts=12, bevel=0.016),
        rbox("gate_top", (1.32, 0.09, 0.11), (0, 0, 0.74), "wood_light", bevel=0.02, segments=3),
        rbox("gate_door", (0.92, 0.06, 0.44), (0, 0, 0.31), "wood_gold", bevel=0.016, segments=3),
    ]
    export("prop_gate", gate)

    sign = [
        rcyl("sign_pole", 0.062, 0.82, (0, 0, 0.41), "wood_brown", verts=18, bevel=0.012),
        rbox("sign_board", (0.62, 0.07, 0.32), (0, 0, 0.74), "wood_light", bevel=0.02, segments=3),
    ]
    export("prop_sign", sign)

    camp = []
    r2 = random.Random(162)
    for i in range(6):
        a = i * 1.047
        camp.append(rock(f"camp_rock{i}", 0.1, (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.045), "stone_mid_light", r2))
    for i in range(3):
        lg = rcyl(f"camp_log{i}", 0.055, 0.48, (0, 0, 0.1), "wood_deep", verts=10, bevel=0.01)
        lg.rotation_euler = Euler((0, 1.32, i * 2.1))
        camp.append(lg)
    flame_outer = rcyl("FlameOuter", 0.18, 0.48, (0, 0, 0.3), "fire_orange", verts=10, r2=0.02, bevel=0.02)
    flame_core = rcyl("FlameCore", 0.11, 0.32, (0, 0, 0.26), "fire_yellow", verts=9, r2=0.015, bevel=0.015)
    camp += [flame_outer, flame_core]
    export("prop_campfire", camp)

    shelter = [
        rbox("sh_floor", (1.7, 1.5, 0.11), (0, 0, 0.055), "wood_gold", bevel=0.026, segments=3),
        rbox("sh_wall_l", (0.11, 1.4, 1.0), (-0.8, -0.05, 0.6), "wood_light", bevel=0.02, segments=3),
        rbox("sh_wall_r", (0.11, 1.4, 1.0), (0.8, -0.05, 0.6), "wood_light", bevel=0.02, segments=3),
        rbox("sh_wall_b", (1.7, 0.11, 1.0), (0, -0.7, 0.6), "wood_light", bevel=0.02, segments=3),
    ]
    half_w, pitch = 1.06, 0.62
    ridge_z = 1.1 + half_w * math.sin(pitch)
    for side, name in ((-1, "sh_roof_l"), (1, "sh_roof_r")):
        panel = rbox(name, (half_w, 1.74, 0.1),
                     (side * half_w / 2 * math.cos(pitch), 0.03, ridge_z - half_w / 2 * math.sin(pitch)),
                     "terracotta_light", bevel=0.026, segments=3)
        panel.rotation_euler = Euler((0, side * pitch, 0))
        shelter.append(panel)
    shelter.append(rbox("sh_ridge", (0.17, 1.78, 0.13), (0, 0.03, ridge_z + 0.02), "wood_deep", bevel=0.026, segments=3))
    export("prop_shelter", shelter)

    marker = [rcyl("fmk_pole", 0.055, 0.62, (0, 0, 0.31), "wood_light", verts=18, bevel=0.01),
              lobe("fmk_buoy", 0.1, (0, 0, 0.68), "coral", squash=0.92)]
    export("prop_fishing_marker", marker)

    arch = [
        rcyl("arch_col1", 0.13, 1.3, (-0.62, 0, 0.65), "stone_light", verts=14, bevel=0.02, segments=3),
        rcyl("arch_col2", 0.13, 1.3, (0.62, 0, 0.65), "stone_light", verts=14, bevel=0.02, segments=3),
        rbox("arch_top", (1.62, 0.24, 0.24), (0, 0, 1.43), "stone_light", bevel=0.03, segments=3),
        rbox("arch_key", (0.26, 0.26, 0.32), (0, 0, 1.49), "stone_mid_light", bevel=0.024, segments=3),
    ]
    export("prop_ruin_arch", arch)

    r3 = random.Random(163)
    wall = [rbox("wall_body", (1.7, 0.32, 0.55), (0, 0, 0.275), "stone_light", bevel=0.035, segments=3),
            rock("wall_r0", 0.13, (-0.5, 0.0, 0.6), "stone_mid_light", r3),
            rock("wall_r1", 0.1, (0.4, 0.05, 0.58), "stone_light", r3)]
    export("prop_stone_wall", wall)

    export("calib_sphere", [lobe("calib_sphere", 0.42, (0, 0, 0.42), "calib_gray", squash=1.0, subdiv=3)])
    export("calib_cube", [rbox("calib_cube", (0.7, 0.7, 0.7), (0, 0, 0.35), "calib_gray", bevel=0.026, segments=3)])


# ---------------------------------------------------------------- character
def ellipsoid(name, radii, loc, material, segments=32, rings=18):
    """Smooth non-spherical volume with explicit width, depth and height."""
    return uv_sphere(name, 1.0, loc, material, segments=segments, rings=rings,
                     squash=radii[2], stretch=(radii[0], radii[1]))


def rod_between(name, start, end, radius, material, verts=14):
    """Capsule-ish rod between two points; used for the smiling mouth."""
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = rcyl(name, radius, direction.length, (a + b) * 0.5, material,
               verts=verts, bevel=radius * 0.45, segments=2)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    return obj


def build_character():
    """Keeper proxy rebuilt for smoothness. Geometry, proportions and pivots
    match the previous proxy exactly so player_visual.gd keeps working — every
    part name, mount offset and gameplay scale is preserved. What changed is
    resolution: UV spheres at 32x18 instead of low-subdivision icospheres, so
    the head, hands and hair read as rounded rather than faceted."""
    objs = []
    # Legs and shoes
    objs.append(rcyl("LegL", 0.055, 0.28, (-0.082, 0.012, 0.18), "wood_deep", verts=18, bevel=0.014))
    objs.append(rcyl("LegR", 0.055, 0.28, (0.082, 0.012, 0.18), "wood_deep", verts=18, bevel=0.014))
    objs.append(ellipsoid("ShoeL", (0.078, 0.105, 0.052), (-0.082, 0.04, 0.055), "wood_deep"))
    objs.append(ellipsoid("ShoeR", (0.078, 0.105, 0.052), (0.082, 0.04, 0.055), "wood_deep"))
    # Torso, belt, collar
    objs.append(rcyl("Torso", 0.19, 0.4, (0, 0, 0.49), "burnt_red", verts=28, r2=0.17, bevel=0.05, segments=3))
    objs.append(rcyl("Belt", 0.177, 0.035, (0, 0, 0.32), "mustard_fabric", verts=28, bevel=0.012))
    objs.append(rcyl("Collar", 0.125, 0.035, (0, -0.01, 0.7), "mustard_fabric", verts=24, bevel=0.012))
    # Arms and hands
    arm_l = rcyl("ArmL", 0.047, 0.35, (-0.22, 0, 0.49), "burnt_red", verts=18, r2=0.04, bevel=0.014)
    arm_l.rotation_euler = Euler((0, 0.16, 0))
    arm_r = rcyl("ArmR", 0.047, 0.35, (0.22, 0, 0.49), "burnt_red", verts=18, r2=0.04, bevel=0.014)
    arm_r.rotation_euler = Euler((0, -0.16, 0))
    objs += [arm_l, arm_r]
    objs.append(uv_sphere("HandL", 0.064, (-0.25, -0.008, 0.32), "skin_light"))
    objs.append(uv_sphere("HandR", 0.064, (0.25, -0.008, 0.32), "skin_light"))
    # Head and face
    objs.append(ellipsoid("Head", (0.31, 0.275, 0.29), (0, 0, 1.03), "skin_light", segments=40, rings=24))
    objs.append(ellipsoid("EarL", (0.055, 0.04, 0.07), (-0.295, 0.0, 1.03), "skin_light"))
    objs.append(ellipsoid("EarR", (0.055, 0.04, 0.07), (0.295, 0.0, 1.03), "skin_light"))
    objs.append(ellipsoid("EyeL", (0.04, 0.022, 0.054), (-0.105, 0.265, 1.08), "hair_deep"))
    objs.append(ellipsoid("EyeR", (0.04, 0.022, 0.054), (0.105, 0.265, 1.08), "hair_deep"))
    objs.append(ellipsoid("EyeHighlightL", (0.011, 0.006, 0.014), (-0.116, 0.287, 1.1), "warm_white", segments=16, rings=10))
    objs.append(ellipsoid("EyeHighlightR", (0.011, 0.006, 0.014), (0.094, 0.287, 1.1), "warm_white", segments=16, rings=10))
    objs.append(ellipsoid("Nose", (0.018, 0.018, 0.022), (0, 0.279, 1.025), "skin_light", segments=20, rings=12))
    objs.append(ellipsoid("CheekL", (0.03, 0.012, 0.015), (-0.18, 0.263, 1.015), "soft_coral", segments=20, rings=12))
    objs.append(ellipsoid("CheekR", (0.03, 0.012, 0.015), (0.18, 0.263, 1.015), "soft_coral", segments=20, rings=12))
    objs.append(rod_between("MouthL", (-0.043, 0.274, 0.98), (0, 0.282, 0.965), 0.011, "hair_deep"))
    objs.append(rod_between("MouthR", (0, 0.282, 0.965), (0.043, 0.274, 0.98), 0.011, "hair_deep"))
    # Hair: rounded overlapping masses, no angular helmet dome.
    h0 = ellipsoid("Hair00", (0.32, 0.285, 0.205), (0, -0.02, 1.17), "hair_primary", segments=40, rings=24)
    h0_l = ellipsoid("Hair00_bangL", (0.075, 0.05, 0.055), (-0.085, 0.263, 1.205), "hair_primary", segments=24, rings=14)
    h0_r = ellipsoid("Hair00_bangR", (0.07, 0.05, 0.052), (0.075, 0.266, 1.21), "hair_primary", segments=24, rings=14)
    h1 = ellipsoid("Hair01", (0.315, 0.28, 0.175), (0, -0.02, 1.19), "hair_primary", segments=40, rings=24)
    h1_tuft = ellipsoid("Hair01_tuft", (0.072, 0.05, 0.05), (-0.055, 0.255, 1.235), "hair_primary", segments=24, rings=14)
    h2 = ellipsoid("Hair02", (0.32, 0.285, 0.19), (0, -0.02, 1.18), "hair_primary", segments=40, rings=24)
    bun = ellipsoid("Hair02_bun", (0.09, 0.085, 0.105), (0, -0.17, 1.385), "hair_primary", segments=28, rings=16)
    h3 = ellipsoid("Hair03", (0.325, 0.29, 0.25), (0, -0.035, 1.14), "hair_primary", segments=40, rings=24)
    h3b = ellipsoid("Hair03_fall", (0.245, 0.19, 0.29), (0, -0.13, 0.95), "hair_primary", segments=32, rings=20)
    objs += [h0, h0_l, h0_r, h1, h1_tuft, h2, bun, h3, h3b]
    export("character_proxy", objs)


# ---------------------------------------------------------------- underwater
def build_underwater():
    # Eelgrass — tall thin curved blades, three variants.
    for variant, seed, blades, h in [("a", 171, 7, (0.28, 0.5)), ("b", 172, 5, (0.2, 0.36)), ("c", 173, 9, (0.3, 0.55))]:
        rng = random.Random(seed)
        objs = []
        for i in range(blades):
            a = rng.uniform(0, 6.28)
            d = rng.uniform(0.02, 0.12)
            m = ["uw_flora_light", "uw_flora_mid", "uw_flora_mid"][i % 3]
            objs.append(blade(f"eel{variant}_{i}", 0.042, rng.uniform(*h),
                              (math.cos(a) * d, math.sin(a) * d, 0), m, rng, lean=0.5))
        export(f"prop_uw_eelgrass_{variant}", objs)

    # Broad-leaf aquatic plants.
    for variant, seed, leaves in [("a", 175, 4), ("b", 176, 6)]:
        rng = random.Random(seed)
        objs = []
        for i in range(leaves):
            a = i * (6.283 / leaves) + rng.uniform(-0.2, 0.2)
            leaf = lobe(f"bl{variant}_{i}", 0.11, (math.cos(a) * 0.07, math.sin(a) * 0.07, 0.12 + rng.uniform(0, 0.05)),
                        "uw_flora_mid" if i % 2 else "uw_flora_light", squash=0.2, stretch=(1.8, 0.7))
            leaf.rotation_euler = Euler((0, -0.5 - rng.uniform(0, 0.25), a))
            objs.append(leaf)
        objs.append(lobe(f"bl{variant}_base", 0.06, (0, 0, 0.05), "uw_flora_dark", squash=0.7))
        export(f"prop_uw_broadleaf_{variant}", objs)

    # Reeds that break the surface.
    for variant, seed, count in [("a", 178, 5), ("b", 179, 3)]:
        rng = random.Random(seed)
        objs = []
        for i in range(count):
            x, y = rng.uniform(-0.14, 0.14), rng.uniform(-0.14, 0.14)
            h = rng.uniform(0.5, 0.75)
            objs.append(rcyl(f"uwr{variant}_s{i}", 0.032, h, (x, y, h / 2), "uw_flora_mid", verts=14, bevel=0.006))
            objs.append(rcyl(f"uwr{variant}_h{i}", 0.048, 0.13, (x, y, h + 0.055), "wood_brown", verts=16, bevel=0.01))
        export(f"prop_uw_reeds_{variant}", objs)

    # Lily pads with one bloom.
    for variant, seed, pads in [("a", 181, 3), ("b", 182, 2)]:
        rng = random.Random(seed)
        objs = []
        for i in range(pads):
            x, y = rng.uniform(-0.3, 0.3), rng.uniform(-0.3, 0.3)
            pad = rcyl(f"lily{variant}_p{i}", rng.uniform(0.1, 0.16), 0.025, (x, y, 0.012), "uw_flora_light", verts=14, bevel=0.006)
            pad.rotation_euler = Euler((0, 0, rng.uniform(0, 6.28)))
            objs.append(pad)
        if variant == "a":
            objs += move(petal_flower("lilyf", rng, "petal_pink", stem_h=0.05), (0.1, 0.05, 0.02))
        export(f"prop_lily_{variant}", objs)

    # Submerged rock arrangements.
    for variant, seed, spec in [
        ("a", 184, [(0.2, "uw_rock_light"), (0.12, "uw_rock_mid")]),
        ("b", 185, [(0.26, "uw_rock_mid"), (0.14, "uw_rock_shadow"), (0.08, "uw_rock_light")]),
        ("c", 186, [(0.16, "uw_rock_light"), (0.1, "uw_rock_mid"), (0.07, "uw_rock_mid")]),
    ]:
        rng = random.Random(seed)
        objs = []
        for i, (r, m) in enumerate(spec):
            objs.append(rock(f"uwrk{variant}_{i}", r, (i * 0.24 - 0.15, rng.uniform(-0.1, 0.1), r * 0.35), m, rng, squash=0.7))
        export(f"prop_uw_rocks_{variant}", objs)


# ---------------------------------------------------------------- run
def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete()
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def main():
    clear_scene()
    build_terrain()
    build_vegetation()
    build_props()
    build_character()
    build_underwater()
    print("GG ASSET BUILD COMPLETE")


if __name__ == "__main__":
    try:
        main()
    except Exception:
        import traceback
        traceback.print_exc()
        sys.exit(1)
