#!/usr/bin/env python3
"""TileGeometryProfile system — profile-driven tile shells.

Replaces the old universal rounded shell (one thick beveled cap + inset body
for every tile) with a small set of deliberate low-poly profiles, following
the reference's design principles WITHOUT copying its assets:

  - a tile fills EXACTLY one grid slot: side walls on the grid boundary,
    footprint exactly TILE, top plane exactly z = 0, depth exactly -0.50;
  - tops are genuinely planar (no domes, no vertex jitter, no subdivision);
  - normals are split: flat shading everywhere, so the top reads as one clean
    face and side walls read as walls — softness comes from the lighting,
    never from melted geometry;
  - connected terrain reaches the grid boundary at the walkable plane, so
    equal neighbours meet as one unbroken surface instead of two back-to-back
    chamfers forming a dark V-groove;
  - bevels are reserved for profiles whose individual edges are intentional;
  - the top material skin is thin (a turf line, not a frosting band);
  - material identity comes from the PROFILE SILHOUETTE (edge-flush terrain
    vs soft recess vs slab vs plinth), not from colour alone.

Every profile is expressed as an outline (optionally rounded corners) plus a
short ring path for the cap edge, so the whole family is one tiny builder.
Shells keep the `<prefix>_body` / `<prefix>_cap` naming contract used by the
runtime classifier and the slot-fill test in tests/test_runner.gd.

Profile summary (dims in metres; TILE = 1.70):
  hard_square          exact cube edge — pedestals, foundations, clean stone
  micro_bevel_square   edge-flush planar cap — the DEFAULT terrain profile
                       (legacy id retained for content-data compatibility)
  soft_recessed_top    rim at 0, one 4% slope to a planar top at -0.035 —
                       reserved for genuinely soft material (snow, soil beds)
  rounded_corner_slab  straight edges, 3% rounded CORNERS only, flat top
  stepped_platform     hard block + one 1.5%-inset cap step — plinths, patios
Constructed tiles (planks, bridges) and the merged water surface are authored
elsewhere; organic materials are shallow overlays on one of the crisp bases.
"""

import math

import bpy

TILE = 1.70
HALF = TILE / 2.0
DEPTH = 0.50

# Cap ring paths: (extra_inset, z), ending in a planar plateau at the last
# ring. "BOT" is replaced by the profile's cap thickness (the thin material
# skin). `outline_inset` shifts the whole cap inward (the plinth step).
PROFILES = {
    # skin_wraps_sides: whether the top material wraps the cap's outer wall.
    # Terrain (hard/micro) keeps a hard top-to-earth boundary. The ordinary
    # micro profile is deliberately edge-flush: beveling every cell creates
    # two back-to-back chamfers and therefore a false recessed grid between
    # equal neighbours. Snow wraps (the soft material folds over the lip);
    # slab and plinth caps are one crafted material by design.
    "hard_square": {
        "radius": 0.0,
        "turf": 0.055,
        "cap": [(0.0, "BOT"), (0.0, 0.0)],
        "skin_wraps_sides": False,
    },
    "micro_bevel_square": {
        "radius": 0.0,
        "turf": 0.055,
        "cap": [(0.0, "BOT"), (0.0, 0.0)],
        "skin_wraps_sides": False,
    },
    "soft_recessed_top": {
        "radius": 0.0,
        "turf": 0.07,
        "cap": [(0.0, "BOT"), (0.0, 0.0), (0.07, -0.035)],
        "skin_wraps_sides": True,
    },
    "rounded_corner_slab": {
        "radius": 0.055,
        "turf": 0.055,
        "cap": [(0.0, "BOT"), (0.0, -0.017), (0.017, 0.0)],
        "skin_wraps_sides": True,
    },
    "stepped_platform": {
        "radius": 0.0,
        "turf": 0.04,
        "cap": [(0.0, "BOT"), (0.0, -0.01), (0.01, 0.0)],
        "outline_inset": 0.025,
        "skin_wraps_sides": True,
    },
}


def _outline(radius, inset, segs=3):
    """CCW rounded-rect outline. Point count depends only on whether the
    profile has rounded corners, so stacked rings always pair up."""
    h = HALF - inset
    if radius <= 1e-6:
        return [(h, -h), (h, h), (-h, h), (-h, -h)]
    r = min(max(0.0015, radius - inset), h - 1e-4)
    pts = []
    corners = [
        (h - r, -(h - r), -math.pi / 2.0),
        (h - r, h - r, 0.0),
        (-(h - r), h - r, math.pi / 2.0),
        (-(h - r), -(h - r), math.pi),
    ]
    for cx, cy, a0 in corners:
        for i in range(segs + 1):
            a = a0 + (math.pi / 2.0) * i / segs
            pts.append((cx + math.cos(a) * r, cy + math.sin(a) * r))
    return pts


def _build_ring_object(name, radius, rings, material, wall_material=None):
    """Extrude an outline through `rings` [(inset, z), ...], closing the
    bottom and the top plateau. Flat-shaded: every face keeps its own planar
    normal, which is what keeps tops crisp under the light.

    With `wall_material`, steep faces (outer walls, bottom) take that second
    material while up-facing faces (top plane, chamfer, slope) keep the first
    — the thin-turf split that stops stacked tiles exposing a bright band."""
    verts = []
    starts = []
    n = 0
    for inset, z in rings:
        pts = _outline(radius, inset)
        n = len(pts)
        starts.append(len(verts))
        verts += [(p[0], p[1], z) for p in pts]
    faces = []
    for k in range(len(rings) - 1):
        a0 = starts[k]
        b0 = starts[k + 1]
        for i in range(n):
            j = (i + 1) % n
            faces.append((a0 + i, a0 + j, b0 + j, b0 + i))
    faces.append(tuple(reversed(tuple(range(n)))))
    top0 = starts[-1]
    faces.append(tuple(range(top0, top0 + n)))
    mesh = bpy.data.meshes.new(name + "_mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    obj.data.materials.append(material)
    if wall_material is not None:
        obj.data.materials.append(wall_material)
        for poly in obj.data.polygons:
            # Reference construction: the top material WRAPS over the bevel —
            # the chamfer catches light in the same material as the top — and
            # the side material starts only below it. Only true vertical walls
            # and the bottom take the wall material. Stacked tiles never show
            # any of this: the cover swap replaces the whole cap with the
            # side-material infill lid.
            if poly.normal.z <= 0.35:
                poly.material_index = 1
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.shade_flat()
    return obj


def build_shell(prefix, top_mat_name, side_mat_name, profile_id, mat_fn):
    """The one entry point: a [body, cap] pair for the requested profile.
    `mat_fn` is the build script's palette material factory (base.mat)."""
    profile = PROFILES[profile_id]
    turf = profile["turf"]
    outline_inset = profile.get("outline_inset", 0.0)
    cap_rings = [
        (outline_inset + inset, -turf if z == "BOT" else z)
        for (inset, z) in profile["cap"]
    ]
    body = _build_ring_object(
        f"{prefix}_body", profile["radius"],
        [(0.0, -DEPTH), (0.0, -turf)], mat_fn(side_mat_name))
    wall_material = None if profile.get("skin_wraps_sides", True) else mat_fn(side_mat_name)
    cap = _build_ring_object(
        f"{prefix}_cap", profile["radius"], cap_rings, mat_fn(top_mat_name),
        wall_material)
    return [body, cap]
