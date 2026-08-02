#!/usr/bin/env python3
"""Suma Nook Tier A/B asset builder.

Runs headless under Blender 5.x:
  /Applications/Blender.app/Contents/MacOS/Blender --background --python art_source/procedural/build_assets.py

Deterministic (fixed seeds). Writes GLBs to assets/3d/final/ (Tier A/B) and
assets/3d/proxies/ (Tier C stand-ins). One shared palette; semantic material
names; bottom-center pivots; 1 unit = 1 m; tile = 2.0 m; land block top z=0,
bottom z=-0.9 (Blender Z-up; glTF exports Y-up).
"""

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Euler, Vector

ROOT = Path(__file__).resolve().parents[2]
OUT_FINAL = ROOT / "assets" / "3d" / "final"
OUT_PROXY = ROOT / "assets" / "3d" / "proxies"
OUT_FINAL.mkdir(parents=True, exist_ok=True)
OUT_PROXY.mkdir(parents=True, exist_ok=True)

TILE = 2.0
# Visible terrain side depth ~0.30 of one tile width — top surfaces dominate,
# side walls stay a warm supporting band.
BLOCK_DEPTH = 0.60

# Offline preview values only. Exported material NAMES are semantic; runtime
# colors always rebind through assets/palettes/gg_material_palette.tres.
# Raw unlit albedos; the DirectionalLight3D creates light and shade — no baked
# sunlight, no orientation tint, no screen-space color grading.
def srgb(hexcode: str) -> tuple:
    h = hexcode.lstrip("#")
    lin = []
    for i in (0, 2, 4):
        c = int(h[i : i + 2], 16) / 255.0
        lin.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return (*lin, 1.0)


PALETTE = {
    "grass": srgb("AEBB32"),
    "grass_lush": srgb("C0C83D"),
    "grass_tuft": srgb("9EAC2D"),
    "moss": srgb("879528"),
    "dark_foliage": srgb("4B5B23"),
    "bright_foliage": srgb("8FA33A"),
    "foliage_medium": srgb("687A2B"),
    "foliage_deep": srgb("39451F"),
    "pine_light": srgb("73842E"),
    "pine_medium": srgb("586923"),
    "pine_dark": srgb("3F4D20"),
    "soil": srgb("A65C22"),
    "soil_side": srgb("98501E"),
    "dark_soil": srgb("763B18"),
    "wood": srgb("B87532"),
    "wood_light": srgb("D09A48"),
    "wood_mid": srgb("8F5B28"),
    "dark_wood": srgb("654127"),
    "pale_stone": srgb("D4CBBD"),
    "stone_mid": srgb("BEB3A4"),
    "dark_stone": srgb("9A9186"),
    "stone_highlight": srgb("E8E1D6"),
    "terracotta": srgb("D27C3A"),
    "terracotta_light": srgb("DE8B49"),
    "terracotta_dark": srgb("87451F"),
    "water": srgb("89A59D"),
    "water_light": srgb("A2B9B1"),
    "water_deep": srgb("718D86"),
    "water_foam": srgb("D0DED7"),
    "cardboard": srgb("D09A48"),
    "gold": srgb("DEB42D"),
    "fabric": srgb("B5563B"),
    "fabric_accent": srgb("E0C173"),
    "metal": srgb("756E65"),
    "warm_charcoal": srgb("3C3631"),
    "warm_gray": srgb("AAA197"),
    "warm_white": srgb("F1ECE2"),
    "calib_gray": srgb("9E9E9E"),
    "skin": srgb("E8B88A"),
    "hair": srgb("5A3A22"),
    "eyes": srgb("2A2521"),
    "petal_pink": srgb("DC829B"),
    "petal_white": srgb("F1ECE2"),
    "petal_red": srgb("C95C3E"),
    "flower_yellow": srgb("DEB42D"),
    "mushroom_red": srgb("C95C3E"),
    "crystal": srgb("8FD0C7"),
    "fire_core": srgb("FFD12A"),
    "fire_outer": srgb("E96F10"),
    "smoke": srgb("D9D4C4"),
    "magic": srgb("E8A33C"),
}

EMISSIVE = {"fire_core": 6.0, "fire_outer": 3.0, "magic": 2.5, "crystal": 1.2}
_mats = {}


def mat(name: str):
    if name in _mats:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    bsdf = m.node_tree.nodes["Principled BSDF"]
    color = PALETTE[name]
    bsdf.inputs["Base Color"].default_value = color
    bsdf.inputs["Roughness"].default_value = 0.35 if name in ("gold", "metal") else 0.93
    bsdf.inputs["Metallic"].default_value = 0.85 if name in ("gold", "metal") else 0.0
    if name in EMISSIVE:
        bsdf.inputs["Emission Color"].default_value = color
        bsdf.inputs["Emission Strength"].default_value = EMISSIVE[name]
    if name == "water":
        m.blend_method = "BLEND"
        bsdf.inputs["Alpha"].default_value = 0.8
        bsdf.inputs["Roughness"].default_value = 0.15
    if name == "crystal":
        m.blend_method = "BLEND"
        bsdf.inputs["Alpha"].default_value = 0.9
        bsdf.inputs["Roughness"].default_value = 0.25
    _mats[name] = m
    return m


def _finish(obj, material, bevel=0.0, smooth_angle=35.0, flat=False):
    obj.data.materials.append(mat(material))
    if bevel > 0.0:
        mod = obj.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.angle_limit = math.radians(40)
        if not flat:
            # Weighted normals keep the big faces optically flat while the bevel
            # ring carries one broad soft highlight — the toy-like edge glint.
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


def box(name, size, loc, material, bevel=0.03, flat=False):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector(size)
    bpy.ops.object.transform_apply(scale=True)
    return _finish(obj, material, bevel, flat=flat)


def cyl(name, r, depth, loc, material, verts=14, bevel=0.02, r2=None, flat=False):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(vertices=verts, radius=r, depth=depth, location=loc)
    else:
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=r2, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, material, bevel, flat=flat)


def rod_between(name, start, end, radius, material, verts=10, bevel=0.0):
    """Cylinder aligned between two points; useful for tiny face strokes."""
    a = Vector(start)
    b = Vector(end)
    direction = b - a
    obj = cyl(name, radius, direction.length, (a + b) * 0.5, material, verts=verts, bevel=bevel)
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(direction.normalized())
    return obj


def cone(name, r, depth, loc, material, verts=10, bevel=0.015, flat=False):
    bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r, radius2=0.0, depth=depth, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    return _finish(obj, material, bevel, flat=flat)


def blob(name, r, loc, material, squash=0.85, subdiv=2, jitter=0.0, rng=None, flat=False):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=r, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector((1.0, 1.0, squash))
    bpy.ops.object.transform_apply(scale=True)
    if jitter > 0.0 and rng is not None:
        for v in obj.data.vertices:
            v.co += Vector((rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter)))
    return _finish(obj, material, 0.0, flat=flat)


def ellipsoid(name, radii, loc, material, subdiv=2, flat=False):
    """Smooth non-spherical volume with explicit width, depth, and height."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=1.0, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector(radii)
    bpy.ops.object.transform_apply(scale=True)
    return _finish(obj, material, 0.0, flat=flat)


def rock(name, r, loc, material, rng, squash=0.8):
    return blob(name, r, loc, material, squash=squash, subdiv=1, jitter=r * 0.22, rng=rng, flat=True)


def export(asset_id, objs, proxy=False):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    out = (OUT_PROXY if proxy else OUT_FINAL) / f"{asset_id}.glb"
    bpy.ops.export_scene.gltf(
        filepath=str(out),
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_animations=False,
        export_skins=False,
        export_lights=False,
        export_cameras=False,
    )
    for o in objs:
        bpy.data.objects.remove(o, do_unlink=True)
    print(f"[asset] {out.relative_to(ROOT)}")


# ---------------------------------------------------------------- vegetation

def make_pine(prefix, rng, height=1.7, tiers=3, foliage=None, tilt=0.04):
    """Stacked soft-shaded tiers, light at the crown to readable dark-green at
    the base — never near-black; the sun does the shading."""
    objs = [cyl(f"{prefix}_trunk", 0.11, 0.5, (0, 0, 0.25), "wood_mid", verts=10, bevel=0.02)]
    base = 0.42
    step = (height - base) / tiers
    radius = 0.58
    for i in range(tiers):
        if foliage:
            tier_mat = foliage
        elif i == 0:
            tier_mat = "pine_dark"
        elif i == tiers - 1:
            tier_mat = "pine_light"
        else:
            tier_mat = "pine_medium"
        c = cone(
            f"{prefix}_tier{i}",
            radius * (1.0 - i * 0.26),
            step * 1.55,
            (rng.uniform(-0.03, 0.03), rng.uniform(-0.03, 0.03), base + step * i + step * 0.55),
            tier_mat,
            verts=10,
            bevel=0.03,
        )
        c.rotation_euler = Euler((rng.uniform(-tilt, tilt), rng.uniform(-tilt, tilt), rng.uniform(0, 6.28)))
        objs.append(c)
    return objs


def make_bush(prefix, rng, r=0.42, material="foliage_medium", lobes=3):
    objs = []
    for i in range(lobes):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.0, r * 0.5)
        rr = r * rng.uniform(0.66, 0.95)
        objs.append(
            blob(f"{prefix}_lobe{i}", rr, (math.cos(a) * d, math.sin(a) * d, rr * 0.72), material, squash=0.84, jitter=rr * 0.04, rng=rng)
        )
    return objs


def make_flower(prefix, rng, petal="petal_pink", stems=3):
    objs = []
    for i in range(stems):
        x, y = rng.uniform(-0.16, 0.16), rng.uniform(-0.16, 0.16)
        h = rng.uniform(0.22, 0.34)
        objs.append(cyl(f"{prefix}_stem{i}", 0.022, h, (x, y, h / 2), "bright_foliage", verts=6, bevel=0.0))
        objs.append(blob(f"{prefix}_head{i}", 0.085, (x, y, h + 0.05), petal, squash=0.66, subdiv=1, flat=True))
        objs.append(blob(f"{prefix}_eye{i}", 0.032, (x, y, h + 0.095), "flower_yellow", squash=0.7, subdiv=1, flat=True))
    objs.append(blob(f"{prefix}_leafmound", 0.16, (0, 0, 0.07), "bright_foliage", squash=0.5, subdiv=1, jitter=0.02, rng=rng, flat=True))
    return objs


def make_tuft(prefix, rng, blades=4, material="grass_tuft"):
    objs = []
    for i in range(blades):
        a = rng.uniform(0, 6.28)
        d = rng.uniform(0.02, 0.07)
        h = rng.uniform(0.14, 0.24)
        c = cone(f"{prefix}_blade{i}", 0.035, h, (math.cos(a) * d, math.sin(a) * d, h / 2), material, verts=5, bevel=0.0, flat=True)
        c.rotation_euler = Euler((rng.uniform(-0.25, 0.25), rng.uniform(-0.25, 0.25), 0))
        objs.append(c)
    return objs


def make_mushroom(prefix, rng, cap="mushroom_red", r=0.11):
    stem_h = rng.uniform(0.1, 0.16)
    objs = [cyl(f"{prefix}_stem", r * 0.42, stem_h, (0, 0, stem_h / 2), "petal_white", verts=8)]
    c = blob(f"{prefix}_cap", r, (0, 0, stem_h + r * 0.3), cap, squash=0.62, subdiv=2)
    objs.append(c)
    return objs


def make_reeds(prefix, rng, count=5):
    objs = []
    for i in range(count):
        x, y = rng.uniform(-0.16, 0.16), rng.uniform(-0.16, 0.16)
        h = rng.uniform(0.4, 0.62)
        objs.append(cyl(f"{prefix}_stalk{i}", 0.02, h, (x, y, h / 2), "bright_foliage", verts=6, bevel=0.0))
        objs.append(cyl(f"{prefix}_head{i}", 0.038, 0.13, (x, y, h + 0.06), "wood", verts=6, bevel=0.0))
    return objs


# ---------------------------------------------------------------- tiles

def tile_block(prefix, top_mat, side_mat, top_z=0.0):
    """Land block: warm shallow side body + chunky beveled top cap ("brownie
    edge"). Tops stay clean — detail comes from a few authored clusters, never
    procedural noise across the whole surface."""
    body = box(f"{prefix}_body", (TILE, TILE, BLOCK_DEPTH - 0.1), (0, 0, top_z - (BLOCK_DEPTH + 0.1) / 2), side_mat, bevel=0.025, flat=True)
    cap = box(f"{prefix}_cap", (TILE + 0.02, TILE + 0.02, 0.14), (0, 0, top_z - 0.06), top_mat, bevel=0.06)
    return [body, cap]


def scatter_clods(prefix, rng, material="dark_soil", count=7, area=0.85):
    objs = []
    for i in range(count):
        x, y = rng.uniform(-area, area), rng.uniform(-area, area)
        s = rng.uniform(0.05, 0.12)
        r = rock(f"{prefix}_clod{i}", s, (x, y, s * 0.4), material, rng, squash=0.55)
        objs.append(r)
    return objs


def scatter_pebbles(prefix, rng, count=5, material="dark_stone", area=0.85):
    return [
        rock(f"{prefix}_peb{i}", rng.uniform(0.04, 0.09), (rng.uniform(-area, area), rng.uniform(-area, area), 0.02), material, rng, squash=0.6)
        for i in range(count)
    ]


def move(objs, offset):
    for o in objs:
        o.location = Vector(o.location) + Vector(offset)
    return objs


def build_tiles():
    rng = random.Random(11)

    # -------- Home Meadow family: clean tops, 2-6 authored detail clusters.
    t = tile_block("grass", "grass", "soil_side")
    t += scatter_clods("g0", rng, "grass_lush", 3)
    for i in range(3):
        t += move(make_tuft(f"g0t{i}", rng), (rng.uniform(-0.8, 0.8), rng.uniform(-0.8, 0.8), 0))
    export("tile_grass", t)

    t = tile_block("gf", "grass", "soil_side")
    for i in range(3):
        t += move(make_flower(f"gf{i}", rng, petal=("petal_pink", "petal_white", "flower_yellow")[i]), (rng.uniform(-0.66, 0.66), rng.uniform(-0.66, 0.66), 0))
    t += move(make_tuft("gft", rng), (0.7, -0.6, 0))
    export("tile_grass_flower", t)

    # Pond edge: an OPEN basin carved into the block — grass rim, visible inner
    # walls, dark floor, water surface sitting below the land top.
    t = []
    t.append(box("gp_body", (TILE, TILE, 0.22), (0, 0, -BLOCK_DEPTH + 0.11), "soil_side", bevel=0.02, flat=True))
    bw, off = 0.36, 0.14  # rim width; basin center offset
    t.append(box("gp_rim_n", (TILE + 0.02, bw + 0.14 - off, BLOCK_DEPTH), (0, -TILE / 2 + (bw + 0.14 - off) / 2, -BLOCK_DEPTH / 2), "soil_side", bevel=0.02, flat=True))
    t.append(box("gp_rim_s", (TILE + 0.02, bw - 0.14 + off, BLOCK_DEPTH), (0, TILE / 2 - (bw - 0.14 + off) / 2, -BLOCK_DEPTH / 2), "soil_side", bevel=0.02, flat=True))
    t.append(box("gp_rim_w", (bw + 0.14 - off, TILE + 0.02, BLOCK_DEPTH), (-TILE / 2 + (bw + 0.14 - off) / 2, 0, -BLOCK_DEPTH / 2), "soil_side", bevel=0.02, flat=True))
    t.append(box("gp_rim_e", (bw - 0.14 + off, TILE + 0.02, BLOCK_DEPTH), (TILE / 2 - (bw - 0.14 + off) / 2, 0, -BLOCK_DEPTH / 2), "soil_side", bevel=0.02, flat=True))
    # grass caps over the rims
    t.append(box("gp_cap_n", (TILE + 0.02, bw + 0.14 - off, 0.14), (0, -TILE / 2 + (bw + 0.14 - off) / 2, -0.06), "grass", bevel=0.055))
    t.append(box("gp_cap_s", (TILE + 0.02, bw - 0.14 + off, 0.14), (0, TILE / 2 - (bw - 0.14 + off) / 2, -0.06), "grass", bevel=0.055))
    t.append(box("gp_cap_w", (bw + 0.14 - off, TILE + 0.02, 0.14), (-TILE / 2 + (bw + 0.14 - off) / 2, 0, -0.06), "grass", bevel=0.055))
    t.append(box("gp_cap_e", (bw - 0.14 + off, TILE + 0.02, 0.14), (TILE / 2 - (bw - 0.14 + off) / 2, 0, -0.06), "grass", bevel=0.055))
    t.append(box("gp_floor", (TILE - 0.3, TILE - 0.3, 0.07), (off * 0.5, off * 0.5, -0.37), "water_deep", flat=True))
    water = box("gp_water", (TILE - 0.42, TILE - 0.42, 0.045), (off * 0.5, off * 0.5, -0.21), "water", bevel=0.0)
    water.name = "WaterSurface"
    t.append(water)
    t += move(make_reeds("gpr", rng, 3), (-0.72, -0.72, 0))
    for i in range(2):
        t.append(rock(f"gp_rock{i}", rng.uniform(0.09, 0.13), (-0.78 + i * 0.26, 0.8, 0.04), "pale_stone", rng))
    export("tile_grass_pond_edge", t)

    # Paving: full 2×2 slab grid with narrow darker grooves — reads like the
    # reference courtyard stone, not scattered stepping stones.
    t = tile_block("pa", "stone_mid", "stone_mid")
    for i in range(2):
        for j in range(2):
            t.append(
                box(
                    f"pa_slab{i}{j}",
                    (0.94, 0.94, 0.07),
                    (-0.49 + i * 0.98, -0.49 + j * 0.98, 0.028 + rng.uniform(-0.004, 0.004)),
                    "stone_mid" if (i + j) == 1 and rng.random() < 0.35 else "pale_stone",
                    bevel=0.032,
                )
            )
    export("tile_path", t)

    t = tile_block("gar", "grass_lush", "soil_side")
    bed = box("gar_bed", (1.1, 1.1, 0.16), (0.2, 0.2, 0.08), "wood", bevel=0.03)
    fill = box("gar_fill", (0.92, 0.92, 0.1), (0.2, 0.2, 0.14), "soil", bevel=0.02, flat=True)
    t += [bed, fill]
    for i in range(3):
        t += move(make_flower(f"garf{i}", rng, petal=("petal_red", "petal_white", "petal_pink")[i], stems=2), (0.0 + i * 0.24 - 0.1, 0.1 + (i % 2) * 0.24, 0.18))
    export("tile_garden", t)

    t = tile_block("co", "pale_stone", "stone_mid")
    t.append(box("co_center", (0.9, 0.9, 0.05), (0, 0, 0.025), "terracotta", bevel=0.022))
    t.append(box("co_ring", (1.7, 0.28, 0.04), (0, 0.72, 0.02), "terracotta", bevel=0.016))
    t.append(box("co_ring2", (1.7, 0.28, 0.04), (0, -0.72, 0.02), "terracotta", bevel=0.016))
    t.append(box("co_ring3", (0.28, 1.14, 0.04), (0.72, 0, 0.02), "terracotta", bevel=0.016))
    t.append(box("co_ring4", (0.28, 1.14, 0.04), (-0.72, 0, 0.02), "terracotta", bevel=0.016))
    export("tile_courtyard", t)

    # -------- Living Grove family (each carries a grove anchor visual spot)
    def grove(asset_id, seed, tree_fn):
        r = random.Random(seed)
        g = tile_block(asset_id, "grass_lush", "soil_side")
        g += move(tree_fn(r), (0.45, 0.45, 0))
        g += move(make_bush(f"{asset_id}_b", r, 0.3), (-0.6, 0.5, 0))
        g += move(make_tuft(f"{asset_id}_t", r), (-0.5, -0.65, 0))
        g += scatter_pebbles(f"{asset_id}_p", r, 2)
        export(asset_id, g)

    grove("tile_grove_mature", 21, lambda r: make_pine("gm", r, height=1.9, tiers=3))
    grove("tile_grove_birch", 22, lambda r: (
        [cyl("gb_trunk", 0.09, 1.0, (0, 0, 0.5), "petal_white", verts=9)]
        + [blob("gb_leaf", 0.5, (0, 0, 1.25), "bright_foliage", squash=0.8, jitter=0.05, rng=r)]
    ))
    grove("tile_grove_mossy", 23, lambda r: make_pine("gm2", r, height=1.5, tiers=2, foliage="moss"))
    grove("tile_grove_autumn", 24, lambda r: (
        [cyl("ga_trunk", 0.1, 0.8, (0, 0, 0.4), "wood", verts=9)]
        + [blob("ga_leaf", 0.52, (0, 0, 1.1), "terracotta", squash=0.78, jitter=0.06, rng=r)]
    ))
    grove("tile_grove_flowering", 25, lambda r: (
        [cyl("gfl_trunk", 0.1, 0.8, (0, 0, 0.4), "wood", verts=9)]
        + [blob("gfl_leaf", 0.5, (0, 0, 1.1), "petal_pink", squash=0.78, jitter=0.06, rng=r)]
    ))

    # -------- Stonebound family
    t = tile_block("sc", "stone_mid", "stone_mid")
    for i in range(3):
        t.append(rock(f"sc_r{i}", rng.uniform(0.14, 0.26), (rng.uniform(-0.6, 0.6), rng.uniform(-0.6, 0.6), 0.08), "pale_stone", rng))
    t += scatter_pebbles("scp", rng, 4, "pale_stone")
    export("tile_stone_clearing", t)

    t = tile_block("sm", "moss", "stone_mid")
    for i in range(3):
        t.append(rock(f"sm_r{i}", rng.uniform(0.16, 0.3), (rng.uniform(-0.55, 0.55), rng.uniform(-0.55, 0.55), 0.1), "dark_stone", rng))
    t += move(make_mushroom("smm", rng), (0.6, -0.55, 0))
    export("tile_stone_mossy", t)

    t = tile_block("sr", "stone_mid", "stone_mid")
    t.append(box("sr_found1", (1.1, 0.24, 0.34), (0, 0.5, 0.17), "pale_stone", bevel=0.03, flat=True))
    t.append(box("sr_found2", (0.24, 0.9, 0.26), (0.55, -0.2, 0.13), "pale_stone", bevel=0.03, flat=True))
    t.append(rock("sr_r0", 0.2, (-0.5, -0.45, 0.07), "pale_stone", rng))
    t += move(make_tuft("srt", rng, material="moss"), (-0.2, -0.1, 0))
    export("tile_stone_ruin", t)

    t = tile_block("scr", "stone_mid", "stone_mid")
    for i in range(4):
        h = rng.uniform(0.3, 0.75)
        c = cyl(f"scr_c{i}", rng.uniform(0.08, 0.16), h, (rng.uniform(-0.5, 0.5), rng.uniform(-0.5, 0.5), h / 2), "crystal", verts=6, bevel=0.0, flat=True)
        c.rotation_euler = Euler((rng.uniform(-0.2, 0.2), rng.uniform(-0.2, 0.2), rng.uniform(0, 3.14)))
        t.append(c)
    t += scatter_pebbles("scrp", rng, 3, "pale_stone")
    export("tile_stone_crystal", t)

    t = tile_block("ro", "stone_mid", "stone_mid")
    for i in range(3):
        for j in range(2):
            if rng.random() < 0.8:
                t.append(box(f"ro_s{i}{j}", (0.5, 0.5, 0.05), (-0.55 + i * 0.55, -0.3 + j * 0.6, 0.025), "pale_stone", bevel=0.022))
    t += move(make_tuft("rot", rng, material="moss"), (0.6, -0.7, 0))
    export("tile_stone_road", t)


# ---------------------------------------------------------------- props

def build_props():
    rng = random.Random(31)

    export("prop_pine_a", make_pine("pna", random.Random(41), 1.8, 3))
    export("prop_pine_b", make_pine("pnb", random.Random(42), 2.3, 4))
    export("prop_bush_a", make_bush("bsa", random.Random(43), 0.45, "foliage_medium", 3))
    export("prop_bush_b", make_bush("bsb", random.Random(44), 0.36, "bright_foliage", 2))
    export("prop_flowers_pink", make_flower("fpk", random.Random(45), "petal_pink"))
    export("prop_flowers_white", make_flower("fwh", random.Random(46), "petal_white"))
    export("prop_flowers_red", make_flower("fre", random.Random(47), "petal_red", stems=2))
    export("prop_reeds", make_reeds("rds", random.Random(48)))
    export("prop_mushrooms", make_mushroom("msh", random.Random(49)) + move(make_mushroom("msh2", random.Random(50), r=0.08), (0.18, 0.1, 0)))
    export("prop_grass_tuft", make_tuft("tft", random.Random(51), 5))

    r = random.Random(52)
    stump = [cyl("stump", 0.24, 0.3, (0, 0, 0.15), "wood", verts=11)]
    stump.append(cyl("stump_top", 0.2, 0.03, (0, 0, 0.31), "dark_wood", verts=11, bevel=0.0))
    export("prop_stump", stump)

    log_ = [cyl("log", 0.16, 0.9, (0, 0, 0.16), "wood", verts=10)]
    log_[0].rotation_euler = Euler((0, 1.5708, 0.4))
    log_.append(blob("log_moss", 0.14, (0.1, 0.05, 0.26), "moss", squash=0.5, subdiv=1, flat=True))
    export("prop_log", log_)

    rock_c = [rock("rockc_a", 0.3, (0, 0, 0.12), "pale_stone", r), rock("rockc_b", 0.18, (0.3, 0.18, 0.07), "dark_stone", r)]
    export("prop_rock_cluster", rock_c)

    # bench: two leg boxes + seat + low back
    bench = [
        box("bench_leg1", (0.12, 0.34, 0.24), (-0.4, 0, 0.12), "dark_wood"),
        box("bench_leg2", (0.12, 0.34, 0.24), (0.4, 0, 0.12), "dark_wood"),
        box("bench_seat", (1.05, 0.4, 0.08), (0, 0, 0.28), "wood", bevel=0.03),
        box("bench_back", (1.05, 0.07, 0.3), (0, -0.17, 0.5), "wood", bevel=0.025),
    ]
    export("prop_bench", bench)

    stool = [cyl("stool_top", 0.2, 0.08, (0, 0, 0.3), "wood", verts=10, bevel=0.03), cyl("stool_leg", 0.13, 0.27, (0, 0, 0.13), "dark_wood", verts=8)]
    export("prop_stool", stool)

    table = [
        cyl("table_top", 0.42, 0.07, (0, 0, 0.5), "wood", verts=12, bevel=0.03),
        cyl("table_leg", 0.09, 0.48, (0, 0, 0.24), "dark_wood", verts=8),
        cyl("table_base", 0.2, 0.06, (0, 0, 0.03), "dark_wood", verts=10),
    ]
    export("prop_table", table)

    fence = [
        cyl("fence_post1", 0.07, 0.52, (-0.8, 0, 0.26), "dark_wood", verts=7),
        cyl("fence_post2", 0.07, 0.52, (0.8, 0, 0.26), "dark_wood", verts=7),
        box("fence_rail1", (1.7, 0.06, 0.09), (0, 0, 0.38), "wood", bevel=0.02),
        box("fence_rail2", (1.7, 0.06, 0.09), (0, 0, 0.18), "wood", bevel=0.02),
    ]
    export("prop_fence", fence)

    gate = [
        cyl("gate_post1", 0.09, 0.72, (-0.55, 0, 0.36), "dark_wood", verts=8),
        cyl("gate_post2", 0.09, 0.72, (0.55, 0, 0.36), "dark_wood", verts=8),
        box("gate_top", (1.3, 0.08, 0.1), (0, 0, 0.72), "wood", bevel=0.025),
        box("gate_door", (0.9, 0.05, 0.42), (0, 0, 0.3), "wood", bevel=0.02),
    ]
    export("prop_gate", gate)

    # Black metal street lantern — warm charcoal, never pure black, glass core.
    lantern = [
        cyl("lant_base", 0.13, 0.07, (0, 0, 0.035), "warm_charcoal", verts=10, bevel=0.02),
        cyl("lant_pole", 0.042, 1.0, (0, 0, 0.55), "warm_charcoal", verts=9, bevel=0.012),
        cyl("lant_collar", 0.065, 0.05, (0, 0, 1.02), "warm_charcoal", verts=9, bevel=0.012),
        box("lant_cage", (0.21, 0.21, 0.24), (0, 0, 1.18), "warm_charcoal", bevel=0.02),
        box("lant_glow", (0.15, 0.15, 0.18), (0, 0, 1.18), "fire_core", bevel=0.012),
        cone("lant_cap", 0.19, 0.13, (0, 0, 1.37), "warm_charcoal", verts=8, bevel=0.02),
        blob("lant_finial", 0.028, (0, 0, 1.45), "warm_charcoal", subdiv=1),
    ]
    lantern[4].name = "GlowCore"
    export("prop_lantern", lantern)

    # Cardboard box with open flaps — the reference's warm paper-toned crate.
    card = [
        box("card_body", (0.56, 0.44, 0.4), (0, 0, 0.2), "cardboard", bevel=0.016),
        box("card_inner", (0.48, 0.36, 0.03), (0, 0, 0.3), "wood_mid", bevel=0.0, flat=True),
    ]
    flap_l = box("card_flap_l", (0.26, 0.42, 0.025), (-0.25, 0, 0.44), "cardboard", bevel=0.01)
    flap_l.rotation_euler = Euler((0, -0.5, 0))
    flap_r = box("card_flap_r", (0.26, 0.42, 0.025), (0.25, 0, 0.44), "cardboard", bevel=0.01)
    flap_r.rotation_euler = Euler((0, 0.5, 0))
    flap_f = box("card_flap_f", (0.5, 0.2, 0.025), (0, -0.22, 0.43), "cardboard", bevel=0.01)
    flap_f.rotation_euler = Euler((0.65, 0, 0))
    card += [flap_l, flap_r, flap_f]
    export("prop_cardboard_box", card)

    # Neutral calibration solids for the Match Lab — never shipped in gameplay.
    export("calib_sphere", [blob("calib_sphere", 0.42, (0, 0, 0.42), "calib_gray", squash=1.0, subdiv=3)])
    export("calib_cube", [box("calib_cube", (0.7, 0.7, 0.7), (0, 0, 0.35), "calib_gray", bevel=0.024)])

    camp = []
    r2 = random.Random(53)
    for i in range(5):
        a = i * 1.257
        camp.append(rock(f"camp_rock{i}", 0.11, (math.cos(a) * 0.4, math.sin(a) * 0.4, 0.05), "dark_stone", r2))
    for i in range(3):
        lg = cyl(f"camp_log{i}", 0.06, 0.5, (0, 0, 0.1), "dark_wood", verts=7)
        lg.rotation_euler = Euler((0, 1.35, i * 2.1))
        camp.append(lg)
    flame_outer = cone("FlameOuter", 0.19, 0.5, (0, 0, 0.32), "fire_outer", verts=8)
    flame_core = cone("FlameCore", 0.11, 0.34, (0, 0, 0.28), "fire_core", verts=7)
    camp += [flame_outer, flame_core]
    export("prop_campfire", camp)

    shelter = [
        box("sh_floor", (1.7, 1.5, 0.1), (0, 0, 0.05), "wood", bevel=0.03),
        box("sh_wall_l", (0.1, 1.4, 1.0), (-0.8, -0.05, 0.6), "wood", bevel=0.02),
        box("sh_wall_r", (0.1, 1.4, 1.0), (0.8, -0.05, 0.6), "wood", bevel=0.02),
        box("sh_wall_b", (1.7, 0.1, 1.0), (0, -0.7, 0.6), "wood", bevel=0.02),
    ]
    # Roof: both halves pivot about the shared ridge line so they meet cleanly.
    half_w = 1.06
    pitch = 0.62
    ridge_z = 1.1 + half_w * math.sin(pitch)
    for side, name in ((-1, "sh_roof_l"), (1, "sh_roof_r")):
        panel = box(name, (half_w, 1.72, 0.09), (side * half_w / 2 * math.cos(pitch), 0.03, ridge_z - half_w / 2 * math.sin(pitch)), "terracotta", bevel=0.03)
        panel.rotation_euler = Euler((0, side * pitch, 0))
        shelter.append(panel)
    ridge = box("sh_ridge", (0.16, 1.76, 0.12), (0, 0.03, ridge_z + 0.02), "dark_wood", bevel=0.03)
    shelter.append(ridge)
    export("prop_shelter", shelter)

    planter = [
        box("pl_box", (0.7, 0.34, 0.26), (0, 0, 0.13), "wood", bevel=0.03),
        box("pl_soil", (0.6, 0.26, 0.06), (0, 0, 0.24), "soil", bevel=0.0, flat=True),
    ]
    planter += move(make_flower("plf", random.Random(54), "petal_white", 2), (0, 0, 0.24))
    export("prop_planter", planter)

    pot = [
        cyl("pot_body", 0.2, 0.3, (0, 0, 0.15), "terracotta", verts=14, r2=0.16, bevel=0.022),
        cyl("pot_lip", 0.235, 0.08, (0, 0, 0.325), "terracotta_light", verts=14, bevel=0.028),
        cyl("pot_soil", 0.17, 0.03, (0, 0, 0.345), "soil", verts=14, bevel=0.0, flat=True),
    ]
    pot += [blob("pot_plant", 0.14, (0, 0, 0.47), "bright_foliage", squash=0.9, subdiv=1, flat=True)]
    export("prop_pot", pot)

    chest = [
        box("chest_base", (0.62, 0.4, 0.3), (0, 0, 0.15), "wood", bevel=0.035),
        box("chest_lid", (0.64, 0.42, 0.16), (0, 0, 0.36), "dark_wood", bevel=0.05),
        box("chest_band", (0.66, 0.09, 0.32), (0, 0, 0.2), "metal", bevel=0.02),
        box("chest_clasp", (0.1, 0.05, 0.12), (0, -0.21, 0.3), "gold", bevel=0.015),
    ]
    export("prop_chest", chest)

    dock = [
        box("dock_deck", (0.9, 1.8, 0.09), (0, 0, 0.1), "wood", bevel=0.03),
    ]
    for i, (x, y) in enumerate([(-0.38, -0.8), (0.38, -0.8), (-0.38, 0.8), (0.38, 0.8)]):
        dock.append(cyl(f"dock_pile{i}", 0.07, 0.5, (x, y, -0.12), "dark_wood", verts=7))
    export("prop_dock", dock)

    sign = [
        cyl("sign_pole", 0.05, 0.8, (0, 0, 0.4), "dark_wood", verts=7),
        box("sign_board", (0.6, 0.06, 0.3), (0, 0, 0.72), "wood", bevel=0.03),
    ]
    export("prop_sign", sign)

    arch = [
        cyl("arch_col1", 0.12, 1.3, (-0.62, 0, 0.65), "pale_stone", verts=10),
        cyl("arch_col2", 0.12, 1.3, (0.62, 0, 0.65), "pale_stone", verts=10),
        box("arch_top", (1.6, 0.22, 0.22), (0, 0, 1.42), "pale_stone", bevel=0.04),
        box("arch_key", (0.24, 0.24, 0.3), (0, 0, 1.48), "dark_stone", bevel=0.03),
    ]
    export("prop_ruin_arch", arch)

    wall = [
        box("wall_body", (1.7, 0.3, 0.55), (0, 0, 0.275), "pale_stone", bevel=0.04, flat=True),
        rock("wall_r0", 0.14, (-0.5, 0.0, 0.6), "dark_stone", random.Random(55)),
        rock("wall_r1", 0.11, (0.4, 0.05, 0.58), "pale_stone", random.Random(56)),
    ]
    export("prop_stone_wall", wall)

    marker = [
        cyl("fmk_pole", 0.04, 0.6, (0, 0, 0.3), "wood", verts=7),
        blob("fmk_buoy", 0.1, (0, 0, 0.66), "petal_red", squash=0.9, subdiv=1),
    ]
    export("prop_fishing_marker", marker)


# ---------------------------------------------------------------- equipment & effects

def build_equipment():
    rod = [
        cyl("rod_shaft", 0.025, 1.15, (0, 0, 0.575), "wood", verts=7, r2=0.012),
        cyl("rod_grip", 0.035, 0.22, (0, 0, 0.11), "dark_wood", verts=7),
        cyl("rod_reel", 0.045, 0.03, (0.045, 0, 0.3), "metal", verts=8, bevel=0.0),
    ]
    export("equip_fishing_rod", rod)

    bob = [blob("bobber_top", 0.055, (0, 0, 0.05), "petal_red", squash=1.0, subdiv=2), blob("bobber_bot", 0.05, (0, 0, -0.02), "petal_white", squash=0.8, subdiv=2)]
    export("equip_bobber", bob)

    def axe(asset_id, head_mat):
        a = [
            cyl("axe_handle", 0.032, 0.72, (0, 0, 0.36), "wood", verts=7),
            box("axe_head", (0.24, 0.06, 0.16), (0.1, 0, 0.62), head_mat, bevel=0.02),
            box("axe_blade", (0.1, 0.045, 0.2), (0.24, 0, 0.62), head_mat, bevel=0.03),
        ]
        export(asset_id, a)

    axe("equip_axe_basic", "metal")
    axe("equip_axe_fine", "gold")

    sword = [
        box("sw_blade", (0.07, 0.03, 0.62), (0, 0, 0.55), "metal", bevel=0.02),
        box("sw_guard", (0.24, 0.05, 0.05), (0, 0, 0.24), "gold", bevel=0.015),
        cyl("sw_grip", 0.028, 0.18, (0, 0, 0.12), "dark_wood", verts=7),
        blob("sw_pommel", 0.04, (0, 0, 0.015), "gold", subdiv=1),
    ]
    export("equip_sword", sword)

    hood = [blob("hood", 0.24, (0, 0, 0.1), "fabric", squash=0.9, subdiv=2)]
    export("equip_hood", hood)

    cape = [box("cape", (0.42, 0.06, 0.55), (0, 0, -0.25), "bright_foliage", bevel=0.04)]
    cape.append(box("cape_clasp", (0.1, 0.05, 0.06), (0, 0, 0.04), "gold", bevel=0.01))
    export("equip_cape", cape)


def build_effects():
    export("fx_flame_core", [cone("fx_flame_core", 0.1, 0.3, (0, 0, 0.15), "fire_core", verts=7)])
    export("fx_flame_outer", [cone("fx_flame_outer", 0.16, 0.44, (0, 0, 0.22), "fire_outer", verts=8)])
    export("fx_smoke_puff", [blob("fx_smoke", 0.12, (0, 0, 0), "smoke", squash=0.9, subdiv=1, flat=True)])
    ring = cyl("fx_ripple", 0.3, 0.015, (0, 0, 0), "petal_white", verts=20, bevel=0.0)
    export("fx_ripple_ring", [ring])
    export("fx_wood_chip", [box("fx_chip", (0.07, 0.03, 0.05), (0, 0, 0), "wood", bevel=0.008, flat=True)])
    export("fx_leaf", [box("fx_leaf", (0.08, 0.05, 0.015), (0, 0, 0), "bright_foliage", bevel=0.008, flat=True)])
    export("fx_spark", [blob("fx_spark", 0.03, (0, 0, 0), "gold", subdiv=1, flat=True)])


# ---------------------------------------------------------------- character proxy

def build_character():
    """Friendly life-sim keeper, ~1.35 m and just over two heads tall. The
    silhouette is original, soft and toy-like; named pieces let Godot pose and
    recolor the same mesh without a skeletal rig."""
    objs = []
    # Slim legs and compact shoes keep the avatar light rather than plush.
    objs.append(cyl("LegL", 0.055, 0.28, (-0.082, 0.012, 0.18), "dark_wood", verts=10))
    objs.append(cyl("LegR", 0.055, 0.28, (0.082, 0.012, 0.18), "dark_wood", verts=10))
    objs.append(ellipsoid("ShoeL", (0.078, 0.105, 0.052), (-0.082, 0.04, 0.055), "dark_wood", subdiv=2))
    objs.append(ellipsoid("ShoeR", (0.078, 0.105, 0.052), (0.082, 0.04, 0.055), "dark_wood", subdiv=2))
    # A narrow straight shirt gives the head room without making the body fat.
    objs.append(cyl("Torso", 0.19, 0.4, (0, 0, 0.49), "fabric", verts=16, r2=0.17, bevel=0.045))
    objs.append(cyl("Belt", 0.177, 0.035, (0, 0, 0.32), "fabric_accent", verts=16, bevel=0.01))
    objs.append(cyl("Collar", 0.125, 0.035, (0, -0.01, 0.7), "fabric_accent", verts=16, bevel=0.01))
    # Thin tapered arms and restrained hands match the lighter body.
    arm_l = cyl("ArmL", 0.047, 0.35, (-0.22, 0, 0.49), "fabric", verts=10, r2=0.04)
    arm_l.rotation_euler = Euler((0, 0.16, 0))
    arm_r = cyl("ArmR", 0.047, 0.35, (0.22, 0, 0.49), "fabric", verts=10, r2=0.04)
    arm_r.rotation_euler = Euler((0, -0.16, 0))
    objs += [arm_l, arm_r]
    objs.append(blob("HandL", 0.064, (-0.25, -0.008, 0.32), "skin", subdiv=2))
    objs.append(blob("HandR", 0.064, (0.25, -0.008, 0.32), "skin", subdiv=2))
    # A broad but shallow oval head reads graphic from the front and slim in profile.
    objs.append(ellipsoid("Head", (0.31, 0.275, 0.29), (0, 0, 1.03), "skin", subdiv=3))
    objs.append(ellipsoid("EarL", (0.055, 0.04, 0.07), (-0.295, 0.0, 1.03), "skin", subdiv=2))
    objs.append(ellipsoid("EarR", (0.055, 0.04, 0.07), (0.295, 0.0, 1.03), "skin", subdiv=2))
    # Blender +Y becomes the character's Godot -Z forward after glTF import.
    objs.append(ellipsoid("EyeL", (0.04, 0.022, 0.054), (-0.105, 0.265, 1.08), "eyes", subdiv=2))
    objs.append(ellipsoid("EyeR", (0.04, 0.022, 0.054), (0.105, 0.265, 1.08), "eyes", subdiv=2))
    objs.append(ellipsoid("EyeHighlightL", (0.011, 0.006, 0.014), (-0.116, 0.287, 1.1), "petal_white", subdiv=2))
    objs.append(ellipsoid("EyeHighlightR", (0.011, 0.006, 0.014), (0.094, 0.287, 1.1), "petal_white", subdiv=2))
    objs.append(ellipsoid("Nose", (0.018, 0.018, 0.022), (0, 0.279, 1.025), "skin", subdiv=2))
    objs.append(ellipsoid("CheekL", (0.03, 0.012, 0.015), (-0.18, 0.263, 1.015), "petal_pink", subdiv=2))
    objs.append(ellipsoid("CheekR", (0.03, 0.012, 0.015), (0.18, 0.263, 1.015), "petal_pink", subdiv=2))
    objs.append(rod_between("MouthL", (-0.043, 0.274, 0.98), (0, 0.282, 0.965), 0.008, "eyes", verts=8))
    objs.append(rod_between("MouthR", (0, 0.282, 0.965), (0.043, 0.274, 0.98), 0.008, "eyes", verts=8))
    # Hair is built as shallow sculpted caps and flat fringe pieces, not balls.
    h0 = ellipsoid("Hair00", (0.32, 0.285, 0.205), (0, -0.02, 1.17), "hair", subdiv=3)
    h0_l = box("Hair00_bangL", (0.135, 0.055, 0.085), (-0.085, 0.263, 1.205), "hair", bevel=0.035)
    h0_l.rotation_euler = Euler((0, -0.12, -0.12))
    h0_r = box("Hair00_bangR", (0.13, 0.055, 0.08), (0.075, 0.266, 1.21), "hair", bevel=0.035)
    h0_r.rotation_euler = Euler((0, 0.12, 0.12))
    h1 = ellipsoid("Hair01", (0.315, 0.28, 0.175), (0, -0.02, 1.19), "hair", subdiv=3)
    h1_tuft = box("Hair01_tuft", (0.13, 0.055, 0.075), (-0.055, 0.255, 1.235), "hair", bevel=0.03)
    h1_tuft.rotation_euler = Euler((0, -0.1, -0.18))
    h2 = ellipsoid("Hair02", (0.32, 0.285, 0.19), (0, -0.02, 1.18), "hair", subdiv=3)
    bun = ellipsoid("Hair02_bun", (0.09, 0.085, 0.105), (0, -0.17, 1.385), "hair", subdiv=2)
    h3 = ellipsoid("Hair03", (0.325, 0.29, 0.25), (0, -0.035, 1.14), "hair", subdiv=3)
    h3b = ellipsoid("Hair03_fall", (0.245, 0.19, 0.29), (0, -0.13, 0.95), "hair", subdiv=3)
    objs += [h0, h0_l, h0_r, h1, h1_tuft, h2, bun, h3, h3b]
    export("character_proxy", objs, proxy=True)


# ---------------------------------------------------------------- enemies & landmark (Tier B proxies)

def build_enemies():
    r = random.Random(61)
    stalker = [blob("Body", 0.26, (0, 0, 0.3), "dark_foliage", squash=0.95, jitter=0.03, rng=r)]
    for i in range(6):
        a = i * 1.047 + 0.3
        s = cone(f"Spike{i}", 0.06, 0.22, (math.cos(a) * 0.22, math.sin(a) * 0.22, 0.42), "dark_wood", verts=6, flat=True)
        s.rotation_euler = Euler((r.uniform(-0.5, 0.5), r.uniform(-0.5, 0.5), 0))
        stalker.append(s)
    stalker.append(blob("EyeL", 0.035, (-0.08, -0.22, 0.34), "magic", subdiv=1))
    stalker.append(blob("EyeR", 0.035, (0.08, -0.22, 0.34), "magic", subdiv=1))
    export("enemy_thornling_stalker", stalker)

    lobber = [blob("Body", 0.3, (0, 0, 0.32), "moss", squash=0.8, jitter=0.04, rng=r)]
    lobber.append(cyl("Mouth", 0.12, 0.1, (0, -0.24, 0.36), "dark_wood", verts=8, flat=True))
    lobber.append(blob("EyeL", 0.04, (-0.1, -0.24, 0.46), "magic", subdiv=1))
    lobber.append(blob("EyeR", 0.04, (0.1, -0.24, 0.46), "magic", subdiv=1))
    for i in range(3):
        lobber.append(cone(f"Back{i}", 0.07, 0.18, (-0.12 + i * 0.12, 0.2, 0.5), "dark_foliage", verts=6, flat=True))
    export("enemy_thornling_lobber", lobber)

    guardian = [
        box("Hips", (0.42, 0.3, 0.24), (0, 0, 0.5), "dark_wood", bevel=0.05),
        box("Torso", (0.62, 0.4, 0.55), (0, 0, 0.95), "dark_wood", bevel=0.07),
        blob("MossPadL", 0.2, (-0.32, 0, 1.18), "moss", squash=0.7, subdiv=1, flat=True),
        blob("MossPadR", 0.2, (0.32, 0, 1.18), "moss", squash=0.7, subdiv=1, flat=True),
        rock("Pauldron", 0.22, (0.36, 0, 1.3), "pale_stone", r),
        blob("Head", 0.17, (0, -0.05, 1.5), "dark_wood", squash=0.9, subdiv=2),
        blob("EyeL", 0.035, (-0.06, -0.2, 1.52), "magic", subdiv=1),
        blob("EyeR", 0.035, (0.06, -0.2, 1.52), "magic", subdiv=1),
        box("Core", (0.16, 0.1, 0.2), (0, -0.17, 0.98), "magic", bevel=0.02),
        cyl("ArmL", 0.09, 0.6, (-0.42, 0, 0.85), "dark_wood", verts=9),
        cyl("ArmR", 0.09, 0.6, (0.42, 0, 0.85), "dark_wood", verts=9),
        cyl("LegL", 0.11, 0.4, (-0.16, 0, 0.2), "dark_wood", verts=9),
        cyl("LegR", 0.11, 0.4, (0.16, 0, 0.2), "dark_wood", verts=9),
        cyl("Club", 0.07, 0.7, (0.48, -0.1, 0.6), "wood", verts=8, r2=0.11),
    ]
    export("enemy_watchpost_guardian", guardian)


def build_watchpost():
    r = random.Random(71)
    objs = []
    # broken tower: stacked slightly-rotated ring courses, jagged top
    for i in range(5):
        h = 0.55
        c = cyl(f"tower_c{i}", 0.62 - i * 0.03, h, (0.9, 0.9, h / 2 + i * h * 0.96), "pale_stone", verts=10, bevel=0.03, flat=True)
        c.rotation_euler = Euler((0, 0, r.uniform(0, 0.6)))
        objs.append(c)
    top = cyl("tower_broken", 0.5, 0.5, (0.9, 0.9, 2.85), "dark_stone", verts=10, r2=0.28, flat=True)
    top.rotation_euler = Euler((0.12, 0.1, 0))
    objs.append(top)
    # gate arch
    objs.append(cyl("gate_col1", 0.18, 1.5, (-0.9, -0.5, 0.75), "pale_stone", verts=9, flat=True))
    objs.append(cyl("gate_col2", 0.18, 1.15, (-0.9, 0.7, 0.575), "pale_stone", verts=9, flat=True))
    lintel = box("gate_lintel", (0.34, 1.5, 0.3), (-0.9, 0.1, 1.55), "dark_stone", bevel=0.04, flat=True)
    lintel.rotation_euler = Euler((0.12, 0, 0))
    objs.append(lintel)
    # rubble piles + ivy + dead tree
    for i in range(8):
        objs.append(rock(f"rubble{i}", r.uniform(0.12, 0.3), (r.uniform(-1.4, 1.4), r.uniform(-1.4, 1.4), 0.08), "pale_stone" if r.random() < 0.6 else "dark_stone", r))
    for i in range(4):
        objs.append(blob(f"ivy{i}", r.uniform(0.16, 0.3), (r.uniform(-1.2, 1.4), r.uniform(-1.0, 1.4), r.uniform(0.1, 1.6)), "dark_foliage", squash=0.55, subdiv=1, jitter=0.05, rng=r, flat=True))
    trunk = cyl("deadtree", 0.1, 1.4, (-1.3, 1.2, 0.7), "dark_wood", verts=8, r2=0.05)
    trunk.rotation_euler = Euler((0.15, 0.1, 0))
    objs.append(trunk)
    branch = cyl("deadbranch", 0.05, 0.6, (-1.15, 1.25, 1.15), "dark_wood", verts=7, r2=0.02)
    branch.rotation_euler = Euler((0.3, 1.2, 0.4))
    objs.append(branch)
    export("landmark_watchpost", objs)

    # reclaimed dressing: banner + planter + cleaned pedestal (shown post-reclaim)
    objs = [
        cyl("banner_pole", 0.05, 1.7, (0, 0, 0.85), "dark_wood", verts=7),
        box("banner_cloth", (0.42, 0.04, 0.6), (0.0, 0, 1.35), "fabric_accent", bevel=0.02),
        cyl("pedestal", 0.3, 0.4, (0.7, -0.4, 0.2), "pale_stone", verts=10, bevel=0.04),
        blob("pedestal_glow", 0.12, (0.7, -0.4, 0.52), "magic", subdiv=1),
    ]
    export("landmark_watchpost_reclaimed_dressing", objs)


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
    build_tiles()
    build_props()
    build_equipment()
    build_effects()
    build_character()
    build_enemies()
    build_watchpost()
    print("ASSET BUILD COMPLETE")


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # surface real tracebacks in headless logs
        import traceback

        traceback.print_exc()
        sys.exit(1)
