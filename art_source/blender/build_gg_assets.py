#!/usr/bin/env python3
"""Suma Nook clean-room asset builder — quiet tiles and authored decorations.

Runs headless under Blender 5.x:
  /Applications/Blender.app/Contents/MacOS/Blender --background --factory-startup \
      --python art_source/blender/build_gg_assets.py

Exports GLBs to assets/3d/reworked/ (which AssetLibrary searches FIRST, so
every rebuilt id overrides the legacy asset with zero code changes).

Modeling standards (docs/visual_rework/ASSET_AUDIT.md):
  - hard surfaces: restrained one-segment chamfers, deliberate planes,
    weighted normals, no razor edges or inflated pill-shaped boxes;
  - curved objects: 10-16 radial segments on pots/posts, faceted silhouettes;
  - pines: 3-5 overlapping scalloped tiers with sparse drooping leaf plates;
  - bushes: one coherent low-poly mass with a restrained leaf shell;
  - flowers: thick stems, broad leaves, 5-6 shaped petals, visible center;
  - grass: 3-7 broad tapered curved blades, grouped, never scattered noise;
  - composition: bare tile by default; at most one functional or hero motif.

Deterministic (fixed seeds). 1 unit = 1 m; tile = 1.70 m; land top z=0.
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

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

TILE = 1.70
# Garden Galaxy's audited ordinary ground collider is 1.0 x 0.5 x 1.0,
# centred at y=-0.25. Keep its confirmed half-metre vertical stacking step
# while retaining enough horizontal room for Suma Nook's existing props.
BLOCK_DEPTH = 0.50
WATER_SURFACE_Y = -0.14     # matches the contiguous water renderer
WATER_FLOOR_Y = -0.36

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
    "grass_highlight": "ADC15B",
    "grass_primary": "8DA84A",
    "grass_secondary": "769142",
    "grass_shade": "567A2C",
    "grass_sunlit": "A3B852",
    "grass_vivid_accent": "6E963A",
    "hair_deep": "382419",
    "hair_light": "76533B",
    "hair_primary": "543826",
    "ivory_highlight": "E2D7BF",
    "sand_top": "E6CD88",
    "leaf_bright": "8FB058",
    "leaf_medium": "708A4E",
    "leaf_olive": "5B7343",
    "leaf_soft_sage": "98AE82",
    "magic": "A77A2C",
    "moss_bright": "80A14F",
    "moss_primary": "668747",
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
    "grass": "8DA84A",  # legacy semantic name
    "hair": "543826",  # legacy semantic name
    "metal": "5C5B55",  # legacy semantic name
    "moss": "668747",  # legacy semantic name
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
    # The reference read is matte but not chalky: broad highlights still carry
    # the bevels and low-poly planes. Runtime material rebinding mirrors these
    # values through data/material_styles.json.
    bsdf.inputs["Roughness"].default_value = 0.78
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


def rbox(name, size, loc, material, bevel_frac=0.028, segments=1, flat=False, bevel=None):
    """Soft-chamfered box with a restrained, authored hard-surface profile."""
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
    """Faceted organic mass with a controlled, readable low-poly silhouette."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=max(1, min(3, subdiv)), radius=r, location=loc)
    obj = bpy.context.active_object
    obj.name = name
    obj.scale = Vector((stretch[0], stretch[1], squash))
    bpy.ops.object.transform_apply(scale=True)
    obj.data.materials.append(mat(material))
    bpy.ops.object.shade_flat()
    return obj


def leaf_plate(name, width, height, loc, material, bend=0.0, thickness=None):
    """Low-poly tapered leaf/blade. Local +Z points from the base to the tip."""
    thick = thickness if thickness is not None else max(0.012, width * 0.18)
    rings = [
        (0.00, width * 0.30, 0.0),
        (0.34, width, bend * 0.12),
        (0.72, width * 0.72, bend * 0.48),
        (1.00, width * 0.08, bend),
    ]
    verts = []
    for z01, half_w, shift in rings:
        for y in (-thick, thick):
            verts.append((-half_w, y, z01 * height + shift))
            verts.append((half_w, y, z01 * height + shift))
    faces = []
    for ring in range(len(rings) - 1):
        a = ring * 4
        b = (ring + 1) * 4
        faces += [
            (a, a + 1, b + 1, b),
            (a + 2, b + 2, b + 3, a + 3),
            (a, b, b + 2, a + 2),
            (a + 1, a + 3, b + 3, b + 1),
        ]
    faces += [(0, 2, 3, 1), (len(verts) - 4, len(verts) - 3, len(verts) - 1, len(verts) - 2)]
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = Vector(loc)
    return _finish(obj, material, min(width * 0.08, 0.008), segments=1, flat=True, weighted=False)


def orient_local_z(obj, direction):
    obj.rotation_mode = "QUATERNION"
    obj.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(Vector(direction).normalized())
    return obj


def pine_tier(name, r, height, loc, material, rng, lobes=7):
    """Scalloped, faceted conifer tier with a pointed teardrop profile."""
    sides = 12
    phase = rng.uniform(0, math.tau)
    ring_spec = [
        (-0.10, 0.52),
        (0.10, 1.00),
        (0.48, 0.70),
        (0.78, 0.35),
        (1.00, 0.035),
    ]
    verts = []
    for ring_index, (z01, radius_scale) in enumerate(ring_spec):
        for i in range(sides):
            ang = math.tau * i / sides
            scallop = 1.0 + 0.09 * math.sin(ang * lobes + phase)
            droop = -0.09 * height if ring_index == 0 and i % 2 == 0 else 0.0
            verts.append((
                math.cos(ang) * r * radius_scale * scallop,
                math.sin(ang) * r * radius_scale * scallop,
                z01 * height + droop,
            ))
    faces = []
    for ring in range(len(ring_spec) - 1):
        for i in range(sides):
            n = (i + 1) % sides
            faces.append((ring * sides + i, ring * sides + n,
                          (ring + 1) * sides + n, (ring + 1) * sides + i))
    faces.append(tuple(reversed(tuple(range(sides)))))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = Vector(loc)
    obj.data.materials.append(mat(material))
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_flat()
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
    # Deliberate planes are more important than inflated bevels on natural
    # stone. Keep enough topology for the silhouette, then leave it faceted.
    obj.data.materials.append(mat(material))
    bpy.ops.object.shade_flat()
    return obj


def blade(name, w, h, loc, material, rng, lean=0.35):
    """Broad, bent, low-poly grass blade that reads as a leaf, not a spike."""
    ang = rng.uniform(0, 6.28)
    dx, dy = math.cos(ang) * lean * h, math.sin(ang) * lean * h
    obj = leaf_plate(name, w, h, loc, material, bend=math.hypot(dx, dy), thickness=w * 0.13)
    obj.rotation_euler = Euler((0, 0, ang))
    return obj


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
# Tile shells come from the TileGeometryProfile system (tile_profiles.py):
# exact slot fill (footprint exactly TILE, top plane at 0, depth to -0.50),
# genuinely planar flat-shaded tops, thin turf skins, and per-tile silhouette
# profiles instead of one universal rounded cap. See the module docstring for
# the profile catalogue and design rules.
def tile_block(prefix, top_mat, side_mat, profile="micro_bevel_square"):
    """Land block shell in the requested geometry profile."""
    import tile_profiles
    return tile_profiles.build_shell(prefix, top_mat, side_mat, profile, mat)


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

    # Ordinary tiles stay quiet. Readable objects belong in the placeable
    # decoration layer; even palette variants contain no baked scatter.
    t = tile_block("grass", "grass_primary", "earth_mid")
    export("tile_grass", t)

    t = tile_block("gf", "grass_sunlit", "earth_mid")
    export("tile_grass_flower", t)

    # Flat soil ground. Planters and flowers are independent placeables.
    t = tile_block("gar", "soil_orange", "earth_mid")
    export("tile_garden", t)

    # A continuous stone surface: path identity comes from colour, not raised
    # pavers. Any future seams must be carved below the z=0 surface.
    t = tile_block("path", "stone_light", "stone_warm_shadow")
    export("tile_path", t)

    # Courtyard variation is carried by its flat cap colour, not raised trim.
    # Courtyard is a crafted patio: an architectural plinth, not soft ground.
    t = tile_block("co", "stone_light", "stone_mid", profile="stepped_platform")
    export("tile_courtyard", t)

    # Pond edge: sloped sandy shore into readable shallow water.
    t = []
    t.append(rbox("gp_body", (TILE, TILE, 0.2), (0, 0, -BLOCK_DEPTH + 0.1), "earth_mid", bevel=0.02, flat=True))
    rim = 0.34
    # Rims fill the slot exactly — the old +0.02 overhang poked into neighbours.
    for i, (x, y, w, d) in enumerate([(0, -TILE / 2 + rim / 2, TILE, rim), (0, TILE / 2 - rim / 2, TILE, rim),
                                      (-TILE / 2 + rim / 2, 0, rim, TILE), (TILE / 2 - rim / 2, 0, rim, TILE)]):
        t.append(rbox(f"gp_rim{i}", (w, d, BLOCK_DEPTH), (x, y, -BLOCK_DEPTH / 2), "earth_mid", bevel=0.02, flat=True))
        t.append(rbox(f"gp_cap{i}", (w, d, 0.13), (x, y, -0.065), "grass_primary", bevel=0.024, segments=1))
    # sloped sand shore ring — tucked inside the basin, meeting the floor
    shore = TILE * 0.22
    shore_span = TILE - rim * 1.75
    for i, (x, y, yaw) in enumerate([(0, -shore, 0), (0, shore, math.pi), (-shore, 0, -math.pi / 2), (shore, 0, math.pi / 2)]):
        panel = rbox(f"gp_slope{i}", (shore_span, 0.25, 0.05), (x, y, -0.39), "uw_sand_light", bevel=0.01, flat=True)
        panel.rotation_euler = Euler((-0.62 if yaw in (0.0,) else 0.62 if yaw == math.pi else 0.0, 0, 0))
        if yaw not in (0.0, math.pi):
            panel.rotation_euler = Euler((0, 0.62 if x > 0 else -0.62, 0))
        t.append(panel)
    basin_size = TILE - rim * 1.8
    t.append(rbox("gp_floor", (basin_size, basin_size, 0.07), (0, 0, -0.43), "uw_sand_light", bevel=0.012, flat=True))
    water = rbox("WaterSurface", (TILE - rim * 1.45, TILE - rim * 1.45, 0.03), (0, 0, -0.2), "water", bevel=0.0)
    t.append(water)
    export("tile_grass_pond_edge", t)

    # Stone family
    t = tile_block("sc", "stone_mid_light", "stone_mid")
    export("tile_stone_clearing", t)

    t = tile_block("sm", "moss_primary", "stone_mid")
    export("tile_stone_mossy", t)

    # Ruins and crystals are decorations, not raised tile geometry.
    # Foundation stone reads as a true, exact cube.
    t = tile_block("sr", "stone_mid_light", "stone_mid", profile="hard_square")
    export("tile_stone_ruin", t)

    t = tile_block("scr", "stone_mid_light", "stone_mid")
    export("tile_stone_crystal", t)

    # The old road follows the same flat-surface contract.
    t = tile_block("road", "stone_mid_light", "stone_mid")
    export("tile_stone_road", t)

    # Grove rewards are flat palette variants. Trees are independent
    # placeables, so moving a tile never carries a baked-in tree.
    for asset_id, top_mat in [
        ("tile_grove_mature", "grass_sunlit"),
        ("tile_grove_birch", "leaf_soft_sage"),
        ("tile_grove_mossy", "moss_primary"),
        ("tile_grove_autumn", "earthy_olive"),
        ("tile_grove_flowering", "grass_highlight"),
    ]:
        export(asset_id, tile_block("grove_ground", top_mat, "earth_mid"))

    # Open-water sand floor tile (surface comes from the water renderer).
    # Dish-shaped: shallow near tile edges, deep toward the center, so the
    # depth-absorption gradient reads shallow-to-turquoise-to-deep.
    t = []
    # The bed fills the slot exactly, like every land body: inset beds left
    # dark grid gaps between water cells, visible through the surface.
    floor = rbox("wf_bed", (TILE, TILE, 0.14), (0, 0, WATER_FLOOR_Y - 0.07), "uw_sand_light", bevel=0.0, flat=True)
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
            v.co.z -= 0.25 * max(0.0, 1.0 - dist / (TILE * 0.62)) ** 1.4
            v.co.z += rng.uniform(-0.012, 0.02)
    t.append(floor)
    t.append(rbox("wf_body", (TILE, TILE, 0.14),
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
    objs = [rcyl(f"{prefix}_trunk", 0.105, trunk_h, (0, 0, trunk_h / 2),
                 "wood_brown", verts=10, r2=0.075, bevel=0.008, segments=1, flat=True)]
    base = trunk_h * 0.75
    span = height - base
    radius = 0.32 + height * 0.14
    for i in range(tiers):
        z01 = i / max(tiers - 1, 1)
        tier_mat = light if i == tiers - 1 else mid if i > 0 else deep
        r = radius * (1.0 - 0.58 * z01) * rng.uniform(0.94, 1.06)
        th = span / tiers * 1.75
        tier = pine_tier(f"{prefix}_tier{i}", r, th,
                         (rng.uniform(-0.04, 0.04), rng.uniform(-0.04, 0.04), base + span * z01 * 0.82 + th * 0.28),
                         tier_mat, rng)
        objs.append(tier)
        # Overlapping drooping leaf plates soften the tier into a leafy,
        # scalloped silhouette. They are part of the hero tree, not tile noise.
        leaf_z = base + span * z01 * 0.82 + th * 0.22
        for j in range(7):
            a = math.tau * j / 7 + rng.uniform(-0.12, 0.12)
            start = Vector((math.cos(a) * r * 0.5, math.sin(a) * r * 0.5, leaf_z))
            leaf = leaf_plate(f"{prefix}_tier{i}_leaf{j}", r * 0.22, r * 0.5,
                              start, tier_mat, bend=r * 0.08, thickness=r * 0.022)
            orient_local_z(leaf, (math.cos(a) * 0.85, math.sin(a) * 0.85, -0.5))
            objs.append(leaf)
    return objs


def _bush(prefix, rng, r=0.42, material="leaf_medium", lobes=5, accent="leaf_bright"):
    # One coherent crown plus a sparse authored leaf shell. This keeps the
    # object readable as a single large decal instead of a pile of balls.
    objs = [lobe(f"{prefix}_mass", r, (0, 0, r * 0.68), material,
                 squash=0.78, subdiv=2, stretch=(1.05, 0.92))]
    leaf_count = max(14, lobes * 3)
    for i in range(leaf_count):
        a = math.tau * i / leaf_count + rng.uniform(-0.22, 0.22)
        z = r * rng.uniform(0.24, 1.02)
        radial = r * rng.uniform(0.56, 0.82)
        start = Vector((math.cos(a) * radial, math.sin(a) * radial, z))
        # Leaves climb along the crown instead of pointing out like spikes.
        direction = Vector((math.cos(a) * 0.24, math.sin(a) * 0.24, 0.9))
        leaf = leaf_plate(f"{prefix}_leaf{i}", r * 0.24, r * rng.uniform(0.38, 0.48),
                          start, accent if i % 4 == 0 else material,
                          bend=r * 0.08, thickness=r * 0.022)
        orient_local_z(leaf, direction)
        leaf.rotation_quaternion = (
            leaf.rotation_quaternion
            @ Euler((0, 0, rng.uniform(-0.45, 0.45))).to_quaternion()
        )
        objs.append(leaf)
    return objs


def _leafy_tree(prefix, rng, trunk_mat="wood_brown", leaf_mat="leaf_bright"):
    trunk = rcyl(f"{prefix}_trunk", 0.105, 0.9, (0, 0, 0.45), trunk_mat,
                  verts=10, r2=0.07, bevel=0.008, segments=1, flat=True)
    tip = rng.uniform(-0.06, 0.06)
    for v in trunk.data.vertices:
        z01 = max(0.0, v.co.z / 0.9 + 0.5)
        v.co.x += tip * z01
    objs = [trunk]
    branch_l = rod_between(f"{prefix}_branch_l", (tip, 0, 0.58), (-0.28, 0.02, 0.94), 0.045, trunk_mat, verts=8)
    branch_r = rod_between(f"{prefix}_branch_r", (tip, 0, 0.67), (0.29, -0.02, 1.02), 0.04, trunk_mat, verts=8)
    objs += [branch_l, branch_r]
    crown_specs = [
        (Vector((tip, 0, 1.18)), 0.46),
        (Vector((tip + 0.28, -0.02, 1.03)), 0.30),
        (Vector((tip - 0.26, 0.03, 0.98)), 0.28),
    ]
    for i, (center, radius) in enumerate(crown_specs):
        crown = _bush(f"{prefix}_c{i}", rng, radius, leaf_mat, lobes=4,
                      accent="leaf_soft_sage" if leaf_mat == "leaf_bright" else leaf_mat)
        objs += move(crown, center)
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

    # Bench: separate planks, splayed supports and an open silhouette.
    bench = []
    for side in (-1, 1):
        for front in (-1, 1):
            leg = rbox(f"bench_leg_{side}_{front}", (0.12, 0.12, 0.34),
                       (side * 0.43, front * 0.14, 0.17), "wood_deep",
                       bevel=0.009, segments=1)
            leg.rotation_euler = Euler((front * 0.09, side * -0.08, 0))
            bench.append(leg)
    for i, y in enumerate((-0.15, 0.0, 0.15)):
        bench.append(rbox(f"bench_seat_{i}", (1.12, 0.125, 0.085),
                          (0, y, 0.34), "wood_light" if i != 1 else "wood_gold",
                          bevel=0.012, segments=1))
    for side in (-1, 1):
        support = rbox(f"bench_back_support_{side}", (0.09, 0.08, 0.53),
                       (side * 0.43, 0.18, 0.55), "wood_deep",
                       bevel=0.008, segments=1)
        support.rotation_euler = Euler((-0.14, 0, 0))
        bench.append(support)
    for i, z in enumerate((0.58, 0.74)):
        back = rbox(f"bench_back_{i}", (1.1, 0.08, 0.13),
                    (0, 0.215, z), "wood_light" if i else "wood_gold",
                    bevel=0.012, segments=1)
        back.rotation_euler = Euler((-0.14, 0, 0))
        bench.append(back)
    export("prop_bench", bench)

    stool = [rbox("stool_top", (0.48, 0.42, 0.09), (0, 0, 0.39),
                  "wood_light", bevel=0.014, segments=1)]
    for x in (-0.17, 0.17):
        for y in (-0.14, 0.14):
            leg = rbox(f"stool_leg_{x}_{y}", (0.085, 0.085, 0.36),
                       (x, y, 0.18), "wood_deep", bevel=0.007, segments=1)
            leg.rotation_euler = Euler((y * 0.35, -x * 0.3, 0))
            stool.append(leg)
    export("prop_stool", stool)

    table = [rcyl("table_top", 0.46, 0.085, (0, 0, 0.54), "wood_light",
                  verts=12, bevel=0.012, segments=1, flat=True)]
    for i in range(3):
        a = math.tau * i / 3 + 0.35
        start = Vector((math.cos(a) * 0.12, math.sin(a) * 0.12, 0.49))
        end = Vector((math.cos(a) * 0.27, math.sin(a) * 0.27, 0.04))
        table.append(rod_between(f"table_leg_{i}", start, end, 0.055, "wood_deep", verts=8))
    table.append(rcyl("table_brace", 0.15, 0.07, (0, 0, 0.22),
                       "wood_gold", verts=10, bevel=0.007, segments=1, flat=True))
    export("prop_table", table)

    # Dock: individual rounded planks, soft posts, board variation.
    dock = []
    for i in range(5):
        dock.append(rbox(f"dock_plank{i}", (0.88, 0.34, 0.09),
                         (rng.uniform(-0.015, 0.015), -0.72 + i * 0.37, 0.1 + rng.uniform(-0.006, 0.006)),
                         "wood_light" if i % 2 else "wood_gold", bevel=0.012, segments=1))
    for i, (x, y) in enumerate([(-0.4, -0.8), (0.4, -0.8), (-0.4, 0.8), (0.4, 0.8)]):
        dock.append(rcyl(f"dock_pile{i}", 0.085, 0.62, (x, y, -0.14),
                          "wood_brown", verts=10, bevel=0.007, segments=1, flat=True))
    export("prop_dock", dock)

    # Ferry delivery dock (matches DeliveryPoint marker layout).
    fdock = []
    for i in range(4):
        fdock.append(rbox(f"fdock_plank{i}", (1.05, 0.36, 0.11),
                          (rng.uniform(-0.012, 0.012), 0.72 + i * 0.38, 0.085 + rng.uniform(-0.005, 0.005)),
                          "wood_light" if i % 2 else "wood_gold", bevel=0.012, segments=1))
    for side in (-1.0, 1.0):
        fdock.append(rcyl(f"fdock_post{side > 0}", 0.09, 0.74,
                           (side * 0.45, 1.52, 0.3), "wood_brown",
                           verts=10, bevel=0.007, segments=1, flat=True))
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
        rbox("chest_base", (0.66, 0.44, 0.3), (0, 0, 0.15),
             "wood_gold", bevel=0.014, segments=1),
        rbox("chest_foot_l", (0.12, 0.4, 0.08), (-0.25, 0, 0.04),
             "wood_deep", bevel=0.007, segments=1),
        rbox("chest_foot_r", (0.12, 0.4, 0.08), (0.25, 0, 0.04),
             "wood_deep", bevel=0.007, segments=1),
    ]
    lid = rcyl("chest_lid", 0.22, 0.67, (0, 0, 0.32), "wood_brown",
                verts=10, bevel=0.008, segments=1, flat=True)
    lid.rotation_euler = Euler((0, 1.5708, 0))
    lid.scale = Vector((1.0, 1.0, 0.62))
    bpy.ops.object.transform_apply(scale=True)
    chest.append(lid)
    for x in (-0.22, 0.22):
        chest.append(rbox(f"chest_band_{x}", (0.075, 0.46, 0.41),
                          (x, 0, 0.23), "stone_deep_shadow",
                          bevel=0.006, segments=1))
    chest.append(rbox("chest_clasp", (0.12, 0.06, 0.14), (0, -0.23, 0.27),
                      "gold_primary", bevel=0.006, segments=1))
    export("prop_chest", chest)

    lantern = [
        rcyl("lant_base", 0.16, 0.07, (0, 0, 0.035), "warm_near_black",
             verts=10, bevel=0.008, segments=1, flat=True),
        rcyl("lant_pole", 0.052, 0.92, (0, 0, 0.5), "warm_near_black",
             verts=10, r2=0.043, bevel=0.006, segments=1, flat=True),
        rbox("lant_floor", (0.26, 0.26, 0.055), (0, 0, 1.0),
             "warm_near_black", bevel=0.008, segments=1),
    ]
    for x in (-0.105, 0.105):
        for y in (-0.105, 0.105):
            lantern.append(rbox(f"lant_frame_{x}_{y}", (0.025, 0.025, 0.29),
                                (x, y, 1.17), "warm_near_black",
                                bevel=0.004, segments=1))
    glow = rcyl("GlowCore", 0.085, 0.22, (0, 0, 1.15), "fire_core",
                 verts=8, r2=0.045, bevel=0.006, segments=1, flat=True)
    lantern.append(glow)
    lantern += [
        rcyl("lant_roof", 0.21, 0.11, (0, 0, 1.37), "warm_near_black",
             verts=4, r2=0.09, bevel=0.007, segments=1, flat=True),
        rcyl("lant_finial", 0.04, 0.09, (0, 0, 1.47), "warm_near_black",
             verts=8, r2=0.01, bevel=0.004, segments=1, flat=True),
    ]
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
        rcyl("pot_body", 0.21, 0.3, (0, 0, 0.15), "terracotta_light",
             verts=12, r2=0.145, bevel=0.009, segments=1, flat=True),
        rcyl("pot_lip", 0.245, 0.075, (0, 0, 0.32), "terracotta_primary",
             verts=12, bevel=0.009, segments=1, flat=True),
        rcyl("pot_soil", 0.185, 0.025, (0, 0, 0.348), "soil_orange",
             verts=12, bevel=0.003, segments=1, flat=True),
    ]
    for i in range(7):
        a = math.tau * i / 7
        leaf = leaf_plate(f"pot_leaf_{i}", 0.055, 0.2, (0, 0, 0.35),
                          "leaf_bright" if i % 3 else "leaf_soft_sage",
                          bend=0.035, thickness=0.012)
        orient_local_z(leaf, (math.cos(a) * 0.82, math.sin(a) * 0.82, 0.56))
        pot.append(leaf)
    export("prop_pot", pot)

    planter = [
        rbox("pl_box", (0.72, 0.36, 0.28), (0, 0, 0.14), "wood_gold", bevel=0.012, segments=1),
        rbox("pl_soil", (0.62, 0.27, 0.05), (0, 0, 0.26), "soil_orange", bevel=0.008, flat=True),
        rbox("pl_foot_l", (0.12, 0.3, 0.1), (-0.24, 0, 0.05), "wood_deep", bevel=0.006, segments=1),
        rbox("pl_foot_r", (0.12, 0.3, 0.1), (0.24, 0, 0.05), "wood_deep", bevel=0.006, segments=1),
    ]
    planter += move(petal_flower("plf", rng, "petal_white", stem_h=0.2), (-0.12, 0, 0.27))
    planter += move(petal_flower("plf2", rng, "petal_pink", stem_h=0.24), (0.14, 0.02, 0.27))
    export("prop_planter", planter)

    fence = []
    for side in (-1, 1):
        fence.append(rbox(f"fence_post_{side}", (0.13, 0.13, 0.62),
                          (side * 0.78, 0, 0.31), "wood_brown",
                          bevel=0.008, segments=1))
        fence.append(rcyl(f"fence_cap_{side}", 0.105, 0.16,
                          (side * 0.78, 0, 0.7), "wood_gold",
                          verts=4, r2=0.0, bevel=0.004, segments=1, flat=True))
    for i, z in enumerate((0.22, 0.46)):
        rail = rbox(f"fence_rail_{i}", (1.62, 0.07, 0.105), (0, 0, z),
                    "wood_light" if i else "wood_gold",
                    bevel=0.008, segments=1)
        rail.rotation_euler = Euler((0, 0, -0.035 if i else 0.028))
        fence.append(rail)
    export("prop_fence", fence)

    gate = [
        rbox("gate_post1", (0.14, 0.14, 0.82), (-0.58, 0, 0.41), "wood_brown", bevel=0.008, segments=1),
        rbox("gate_post2", (0.14, 0.14, 0.82), (0.58, 0, 0.41), "wood_brown", bevel=0.008, segments=1),
        rbox("gate_top", (1.32, 0.09, 0.11), (0, 0, 0.78), "wood_light", bevel=0.009, segments=1),
    ]
    for i, x in enumerate((-0.36, -0.12, 0.12, 0.36)):
        gate.append(rbox(f"gate_picket_{i}", (0.09, 0.065, 0.52),
                         (x, 0, 0.32), "wood_gold" if i % 2 else "wood_light",
                         bevel=0.006, segments=1))
    brace = rbox("gate_brace", (0.92, 0.07, 0.09), (0, -0.01, 0.34),
                 "wood_deep", bevel=0.006, segments=1)
    brace.rotation_euler = Euler((0, -0.45, 0))
    gate.append(brace)
    export("prop_gate", gate)

    sign = [
        rbox("sign_pole", (0.1, 0.1, 0.86), (0, 0, 0.43), "wood_brown", bevel=0.007, segments=1),
        rbox("sign_board", (0.68, 0.075, 0.3), (0.1, 0, 0.73), "wood_light", bevel=0.012, segments=1),
        rbox("sign_trim", (0.74, 0.025, 0.055), (0.1, -0.05, 0.83), "wood_gold", bevel=0.005, segments=1),
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

    # prop_shelter is an authored imported asset with its own focused,
    # reproducible processor. Do not overwrite it with the old blockout here;
    # see process_stylized_pyramid_tent.py.

    marker = [rcyl("fmk_pole", 0.055, 0.62, (0, 0, 0.31), "wood_light", verts=18, bevel=0.01),
              lobe("fmk_buoy", 0.1, (0, 0, 0.68), "coral", squash=0.92)]
    export("prop_fishing_marker", marker)

    arch = []
    for side in (-1, 1):
        for level in range(4):
            z = 0.16 + level * 0.31
            arch.append(rbox(f"arch_{side}_{level}", (0.31, 0.32, 0.29),
                             (side * (0.58 + (0.02 if level % 2 else -0.01)), 0, z),
                             "stone_light" if level % 2 else "stone_mid_light",
                             bevel=0.014, segments=1))
    for i, x in enumerate((-0.48, -0.16, 0.16, 0.48)):
        arch.append(rbox(f"arch_top_{i}", (0.38, 0.34, 0.3),
                         (x, 0, 1.37 + (0.06 if abs(x) < 0.2 else 0.0)),
                         "stone_light" if i % 2 else "stone_mid_light",
                         bevel=0.014, segments=1))
    export("prop_ruin_arch", arch)

    r3 = random.Random(163)
    wall = []
    block_specs = [
        (-0.56, 0.0, 0.17, 0.56, 0.31),
        (0.0, 0.01, 0.16, 0.52, 0.29),
        (0.54, -0.01, 0.18, 0.54, 0.33),
        (-0.34, 0.0, 0.47, 0.63, 0.27),
        (0.34, 0.01, 0.46, 0.61, 0.29),
    ]
    for i, (x, y, z, width, height) in enumerate(block_specs):
        wall.append(rbox(f"wall_block_{i}", (width, 0.32, height),
                         (x, y, z), "stone_light" if i % 2 else "stone_mid_light",
                         bevel=0.014, segments=1))
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
    if "--terrain-only" in sys.argv:
        print("GG TERRAIN BUILD COMPLETE")
        return
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
