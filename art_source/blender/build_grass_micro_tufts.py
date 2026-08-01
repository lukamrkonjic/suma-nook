#!/usr/bin/env python3
"""Build Suma's micro-tuft grass library — the dense living carpet.

These are NOT plants, and the vocabulary is deliberate:

    moss cushion      a low rounded dome that meets the ground plumply
    plush nub         the smallest unit of the carpet, barely a shape
    soft grass lobe   one cushion inside a merged multi-lobe module

Every earlier grass pass in this repo failed the same way: it modelled
recognisable botany. Leaves radiating from a point make a rosette; tapered
slabs make a star; anything with a vertical axis makes a spike. All three read
as *objects scattered on* the ground rather than *ground that is alive*, and no
amount of proportion tuning fixes that because the failure is in the
silhouette. So the primitive here is a half-ellipsoid, not a blade: a form with
no tip, no radial origin and no visible centre. Hundreds of them at 4-10 cm
across stop reading as individuals and start reading as one surface, which is
the entire point of the layer.

WHY HALF-ELLIPSOIDS AND NOT SLABS. `build_carpet_tufts.py` builds the *decorated*
layer — larger scalloped masses that sit on top and carry the composition. This
file builds the layer underneath it, which must survive being tiled at very high
density. At that density a silhouette with any straight edge or any point starts
to strobe, because the eye locks onto the repeated feature. A dome has neither.

TOPOLOGY IS FIXED, CHEAP AND ROUND BY CONSTRUCTION. A lobe is a stack of rings
closed by a single apex, so its triangle count is exactly

    sides * (2 * intermediate_rings + 1)

and its roundness comes from the ring profile alone. There is NO subdivision
modifier and NO bevel modifier anywhere in this file, by requirement and by
preference: at this scale a subdivided nub costs ten times the triangles to
gain silhouette detail that is under one screen pixel. The underside is left
open on purpose — it is the ground-contact face, it is never visible, and at a
12-20 triangle budget a cap the player cannot see is a third of the mesh.

UNITS ARE LIVE METRES. Suma's logical cell is 1.35 m (data/tuning.json::tile_size)
while the art catalogue was authored against a 1.70 m footprint, so every linear
figure quoted in the brief was scaled by 1.35 / 1.70 = 0.794 before being written
into MODULES below. The numbers in this file are already live metres; do not
scale them again.

VERTEX COLOURS ARE LOAD-BEARING — the runtime shader reads them and there is no
second source for this data:

    COLOR.r  wind weight   0.0 on the planted underside and lower perimeter,
                           0.25-0.55 through the middle, 0.65-1.0 over the upper
                           rounded surface.
    COLOR.g  top-light     0.25 lower, 0.55 middle, 0.75-1.0 upper.
    COLOR.b  reserved, written as 0.0 so a future channel cannot inherit noise.

The dense/flexible distinction is NOT baked into COLOR.r. Both kinds carry the
full authored band and the runtime scales them by a per-kind wind multiplier,
which keeps the attribute a pure "how far is this vertex from being planted"
measure rather than two incompatible encodings sharing one channel.

The exporter only keeps a colour attribute that a material actually reads
(export_vertex_color="MATERIAL"), so the Color Attribute node is wired straight
into Base Color. That makes the material preview show the encoding rather than
green, which is intended: it is a free debug view, and the runtime replaces the
material anyway.

THE BUILD-TIME GATE IS NOT OPTIONAL. An earlier grass rebuild in this repo
shipped columns three times because nothing checked the output, so every mesh is
measured against its triangle band, its dimension band, its contact plane and
its vertex-colour ranges, and the exported GLB is then re-read from disk and
checked again. A mesh that fails prints PROBLEM lines and is counted in the
report; it does not fail silently.

Run from the repository root:

    C:/Software/Blender/blender.exe --background --factory-startup \
        --python art_source/blender/build_grass_micro_tufts.py
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

import bpy

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "world" / "grass" / "meshes"
RES_PREFIX = "res://world/grass/meshes"

# The catalogue was authored on a 1.70 m footprint; Suma's live cell is 1.35 m.
CATALOG_CELL = 1.70
LIVE_CELL = 1.35
LIVE_SCALE = LIVE_CELL / CATALOG_CELL  # 0.794

MATERIAL_NAME = "grass_micro_tuft"
COLOR_ATTRIBUTE = "Color"
# Viewport-only tone. The exported Base Color is the vertex-colour encoding, so
# this exists purely so the mesh is not magenta while being authored in Blender.
PREVIEW_TONE = (0.30, 0.48, 0.16, 1.0)


# --------------------------------------------------------------------------
# Ring profiles
# --------------------------------------------------------------------------
#
# (v, radius_factor, height_factor, wind, light)
#
# `v` is only a label for readability; the geometry is driven by the radius and
# height factors. The widest ring deliberately sits ABOVE the ground ring, so the
# cushion tucks in where it meets the terrain instead of meeting it at a hard
# rim. That tuck is what hides the open underside from a low camera and what
# makes the form read as growing out of the ground rather than resting on it.
#
# The wind values step across the authored bands and never land in the 0.55-0.65
# gap between "middle" and "upper", so every vertex is unambiguously in one band.

LOW_CUSHION = [
    (0.00, 0.82, 0.00, 0.00, 0.25),
    (0.50, 1.00, 0.58, 0.42, 0.55),
    (1.00, 0.00, 1.00, 0.80, 0.88),
]

# The flexible layer is the only one that visibly moves, so it gets one more ring
# — the extra loop is what lets the shader bend it as a curve instead of a hinge.
DEEP_CUSHION = [
    (0.00, 0.80, 0.00, 0.00, 0.25),
    (0.34, 1.00, 0.40, 0.38, 0.55),
    (0.72, 0.74, 0.80, 0.72, 0.80),
    (1.00, 0.00, 1.00, 0.96, 1.00),
]


def material():
    """One shared material carrying the Color Attribute node.

    The node has to exist and has to reach the output, or the glTF exporter
    drops COLOR_0 entirely under export_vertex_color="MATERIAL" and the runtime
    shader silently loses both wind and top-light.
    """
    existing = bpy.data.materials.get(MATERIAL_NAME)
    if existing is not None:
        return existing
    result = bpy.data.materials.new(name=MATERIAL_NAME)
    result.use_nodes = True
    tree = result.node_tree
    shader = tree.nodes["Principled BSDF"]
    attribute = tree.nodes.new("ShaderNodeVertexColor")
    attribute.layer_name = COLOR_ATTRIBUTE
    # Wired straight in. A Mix node in between makes the exporter emit a second,
    # ambiguous COLOR_1 set, which is worse than a debug-coloured preview.
    tree.links.new(attribute.outputs["Color"], shader.inputs["Base Color"])
    shader.inputs["Roughness"].default_value = 0.96
    shader.inputs["Metallic"].default_value = 0.0
    if "Specular IOR Level" in shader.inputs:
        shader.inputs["Specular IOR Level"].default_value = 0.08
    result.diffuse_color = PREVIEW_TONE
    return result


class Builder:
    def __init__(self):
        self.verts = []
        self.colours = []
        self.faces = []

    def add(self, point, colour):
        self.verts.append(point)
        self.colours.append(colour)
        return len(self.verts) - 1

    def face(self, indices):
        if len(indices) >= 3:
            self.faces.append(tuple(indices))


def cushion_lobe(builder, centre, radius_x, radius_y, height, sides, profile,
                 skew=0.0, phase_deg=0.0, lean=(0.0, 0.0), ring_offset_deg=0.0,
                 wind_scale=1.0):
    """One low rounded cushion: a ring stack closed by a single apex.

    `skew` bends the footprint into a bean by modulating the radius with one
    cosine of the ring angle. That is the cheapest possible asymmetry — it costs
    zero extra vertices — and it matters because a perfectly radial dome repeated
    a thousand times reads as a manufactured bead. `lean` slides the apex
    sideways so the crown is not centred over the footprint, which breaks the
    remaining symmetry in the shaded highlight rather than in the outline.

    Faces wind counter-clockwise seen from outside, so normals point away from
    the lobe axis and the dome is not inside-out.
    """
    phase = math.radians(phase_deg)
    ring_offset = math.radians(ring_offset_deg)

    def shape(angle):
        return 1.0 + skew * math.cos(angle - phase)

    rings = []
    apex = None
    for _v, radius_factor, height_factor, wind, light in profile:
        colour = (min(wind * wind_scale, 1.0), light, 0.0, 1.0)
        z = height * height_factor
        if radius_factor <= 1e-6:
            # The crown is a single vertex. A ring here would need a cap fan the
            # triangle budget cannot pay for, and at 5 cm across the difference
            # is invisible under smooth shading.
            apex = builder.add(
                (centre[0] + lean[0], centre[1] + lean[1], z), colour
            )
            continue
        ids = []
        for index in range(sides):
            angle = ring_offset + math.tau * index / sides
            reach = shape(angle) * radius_factor
            # The apex offset is blended in with height so the lobe leans as a
            # whole instead of shearing only at the top.
            slide_x = lean[0] * height_factor
            slide_y = lean[1] * height_factor
            ids.append(builder.add((
                centre[0] + math.cos(angle) * radius_x * reach + slide_x,
                centre[1] + math.sin(angle) * radius_y * reach + slide_y,
                z,
            ), colour))
        rings.append(ids)

    for index in range(len(rings) - 1):
        lower, upper = rings[index], rings[index + 1]
        for step in range(sides):
            nxt = (step + 1) % sides
            builder.face((lower[step], lower[nxt], upper[nxt], upper[step]))
    if apex is not None and rings:
        top = rings[-1]
        for step in range(sides):
            builder.face((top[step], top[(step + 1) % sides], apex))
    return sides * (2 * max(len(rings) - 1, 0) + (1 if apex is not None else 0))


# --------------------------------------------------------------------------
# The five modules
# --------------------------------------------------------------------------
#
# Each lobe is authored explicitly as a dict so the intent of every number stays
# readable. Lobes in a multi-lobe module OVERLAP by roughly a third of their
# footprints — merged, not arranged — because two cushions that merely touch read
# as two objects while two that interpenetrate read as one mass with a dip in it.

MODULES = [
    ("grass_micro_round", "dense", [
        dict(centre=(0.0000, 0.0000), radius_x=0.0280, radius_y=0.0259,
             height=0.0210, sides=6, profile=LOW_CUSHION,
             skew=0.09, phase_deg=40.0, lean=(0.0030, 0.0016)),
    ]),

    ("grass_micro_double", "dense", [
        dict(centre=(-0.0180, 0.0020), radius_x=0.0205, radius_y=0.0215,
             height=0.0250, sides=5, profile=LOW_CUSHION,
             skew=0.08, phase_deg=15.0, lean=(-0.0022, 0.0014)),
        dict(centre=(0.0165, -0.0035), radius_x=0.0180, radius_y=0.0190,
             height=0.0208, sides=5, profile=LOW_CUSHION,
             skew=0.08, phase_deg=200.0, lean=(0.0020, -0.0012),
             ring_offset_deg=36.0),
    ]),

    ("grass_micro_triple", "dense", [
        dict(centre=(-0.0130, 0.0060), radius_x=0.0245, radius_y=0.0230,
             height=0.0310, sides=6, profile=LOW_CUSHION,
             skew=0.09, phase_deg=30.0, lean=(-0.0026, 0.0018)),
        dict(centre=(0.0175, -0.0025), radius_x=0.0215, radius_y=0.0200,
             height=0.0262, sides=5, profile=LOW_CUSHION,
             skew=0.08, phase_deg=190.0, lean=(0.0024, -0.0010),
             ring_offset_deg=36.0),
        # The third lobe is a filler that closes the gap between the other two.
        # It is smaller and lower on purpose: three equal lobes make a clover.
        dict(centre=(0.0025, -0.0180), radius_x=0.0155, radius_y=0.0150,
             height=0.0205, sides=4, profile=LOW_CUSHION,
             skew=0.07, phase_deg=95.0, lean=(0.0008, -0.0016),
             ring_offset_deg=45.0),
    ]),

    ("grass_flexible_soft", "flexible", [
        dict(centre=(0.0000, 0.0000), radius_x=0.0460, radius_y=0.0377,
             height=0.0500, sides=8, profile=DEEP_CUSHION,
             skew=0.07, phase_deg=25.0, lean=(0.0060, -0.0030)),
    ]),

    ("grass_flexible_accent", "flexible", [
        dict(centre=(-0.0095, 0.0035), radius_x=0.0430, radius_y=0.0355,
             height=0.0620, sides=8, profile=DEEP_CUSHION,
             skew=0.08, phase_deg=310.0, lean=(-0.0070, 0.0038),
             ring_offset_deg=22.5),
        # A shouldered second cushion is what makes this one "characterful":
        # it breaks the dome into a two-headed mass without adding height.
        # Its wind is scaled down because a lobe this low physically cannot
        # travel as far as the crown above it.
        dict(centre=(0.0290, -0.0110), radius_x=0.0230, radius_y=0.0205,
             height=0.0295, sides=6, profile=LOW_CUSHION,
             skew=0.09, phase_deg=140.0, lean=(0.0026, -0.0018),
             wind_scale=0.55),
    ]),
]


# --------------------------------------------------------------------------
# Bands enforced at build time
# --------------------------------------------------------------------------
#
# (triangle_min, triangle_max, width_min, width_max, height_min, height_max)

BANDS = {
    "grass_micro_round": (12, 20, 0.044, 0.068, 0.014, 0.028),
    "grass_micro_double": (20, 32, 0.056, 0.087, 0.017, 0.033),
    "grass_micro_triple": (28, 48, 0.064, 0.103, 0.022, 0.040),
    "grass_flexible_soft": (30, 70, 0.064, 0.119, 0.036, 0.067),
    "grass_flexible_accent": (30, 70, 0.064, 0.119, 0.036, 0.067),
}

# A cushion may be oval but never a sliver: depth has to stay within this
# fraction of width or the module stops reading as a dome from overhead.
ASPECT_BAND = (0.55, 1.05)
CONTACT_EPSILON = 1e-6
# Wind band edges from the brief. Nothing may land in the 0.55-0.65 gap.
WIND_MIDDLE_MAX = 0.55
WIND_UPPER_MIN = 0.65
LIGHT_LOWER_MAX = 0.30
LIGHT_UPPER_MIN = 0.75


def build_module(name, lobes):
    builder = Builder()
    predicted = 0
    for lobe in lobes:
        predicted += cushion_lobe(builder, **lobe)

    # Recentre on the footprint and drop the contact ring exactly onto z=0. The
    # runtime places these by their ground point, so an origin anywhere else
    # shows up as tufts floating or sunk once terrain height varies.
    xs = [v[0] for v in builder.verts]
    ys = [v[1] for v in builder.verts]
    zs = [v[2] for v in builder.verts]
    shift_x = (max(xs) + min(xs)) * 0.5
    shift_y = (max(ys) + min(ys)) * 0.5
    shift_z = min(zs)
    builder.verts = [
        (x - shift_x, y - shift_y, z - shift_z) for x, y, z in builder.verts
    ]

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(builder.verts, [], builder.faces)
    mesh.validate(verbose=False)
    mesh.materials.append(material())
    for polygon in mesh.polygons:
        polygon.material_index = 0
        # Smooth everywhere. There is no sharp feature on a cushion, and this is
        # the whole softening budget — no bevel, no subdivision.
        polygon.use_smooth = True

    attribute = mesh.color_attributes.new(
        name=COLOR_ATTRIBUTE, type="FLOAT_COLOR", domain="POINT"
    )
    for index, colour in enumerate(builder.colours):
        attribute.data[index].color = colour
    mesh.color_attributes.active_color_index = 0
    mesh.color_attributes.render_color_index = 0
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    return obj, predicted


def measure(obj, lobes, predicted):
    mesh = obj.data
    mesh.calc_loop_triangles()
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    width = max(xs) - min(xs)
    depth = max(ys) - min(ys)
    height = max(zs) - min(zs)

    colour = mesh.color_attributes[COLOR_ATTRIBUTE]
    winds = [colour.data[i].color[0] for i in range(len(mesh.vertices))]
    lights = [colour.data[i].color[1] for i in range(len(mesh.vertices))]

    contact = [i for i, v in enumerate(mesh.vertices) if v.co.z <= CONTACT_EPSILON]
    contact_x = sum(mesh.vertices[i].co.x for i in contact) / max(len(contact), 1)
    contact_y = sum(mesh.vertices[i].co.y for i in contact) / max(len(contact), 1)

    return {
        "triangles": len(mesh.loop_triangles),
        "predicted_triangles": predicted,
        "vertices": len(mesh.vertices),
        "lobes": lobes,
        "width": round(width, 4),
        "depth": round(depth, 4),
        "height": round(height, 4),
        "aspect": round(depth / max(width, 1e-6), 3),
        "min_z": round(min(zs), 6),
        "contact_vertices": len(contact),
        "contact_offset": round(math.hypot(contact_x, contact_y), 5),
        "wind_range": [round(min(winds), 3), round(max(winds), 3)],
        "light_range": [round(min(lights), 3), round(max(lights), 3)],
        "contact_wind_max": round(max([winds[i] for i in contact], default=1.0), 4),
        "contact_light_max": round(max([lights[i] for i in contact], default=1.0), 4),
        "wind_in_gap": sum(
            1 for w in winds if WIND_MIDDLE_MAX < w < WIND_UPPER_MIN
        ),
    }


def gate(name, record, problems):
    tri_min, tri_max, width_min, width_max, height_min, height_max = BANDS[name]

    if not tri_min <= record["triangles"] <= tri_max:
        problems.append("%s: %d triangles is outside the %d-%d band"
                        % (name, record["triangles"], tri_min, tri_max))
    if record["triangles"] != record["predicted_triangles"]:
        problems.append("%s: %d triangles does not match the %d the topology "
                        "should produce — a face was dropped as degenerate"
                        % (name, record["triangles"], record["predicted_triangles"]))
    if not width_min <= record["width"] <= width_max:
        problems.append("%s: %.4f m wide is outside the %.3f-%.3f band"
                        % (name, record["width"], width_min, width_max))
    if not height_min <= record["height"] <= height_max:
        problems.append("%s: %.4f m tall is outside the %.3f-%.3f band"
                        % (name, record["height"], height_min, height_max))
    if not ASPECT_BAND[0] <= record["aspect"] <= ASPECT_BAND[1]:
        problems.append("%s: depth/width %.3f is outside the %.2f-%.2f band "
                        "(%.4f x %.4f) — it reads as a sliver, not a cushion"
                        % (name, record["aspect"], ASPECT_BAND[0], ASPECT_BAND[1],
                           record["width"], record["depth"]))

    # Contact plane. A lobe that floats leaves a visible shadow gap and a lobe
    # that sinks loses its tuck, so this is exact rather than approximate.
    if abs(record["min_z"]) > CONTACT_EPSILON:
        problems.append("%s: contact plane is at z=%.6f, not z=0"
                        % (name, record["min_z"]))
    if record["contact_vertices"] < 3:
        problems.append("%s: only %d vertices touch z=0 — that is a point of "
                        "contact, not a planted base"
                        % (name, record["contact_vertices"]))
    if record["contact_offset"] > record["width"] * 0.18:
        problems.append("%s: ground-contact centre is %.4f m off the origin, "
                        "past the %.4f m allowance"
                        % (name, record["contact_offset"], record["width"] * 0.18))

    # Vertex colours. These are the runtime's only source for wind and top-light,
    # so a silent drift here is invisible in Blender and catastrophic in engine.
    wind_low, wind_high = record["wind_range"]
    light_low, light_high = record["light_range"]
    if wind_low > 0.001:
        problems.append("%s: lowest wind weight is %.3f — nothing is planted"
                        % (name, wind_low))
    if wind_high < WIND_UPPER_MIN:
        problems.append("%s: highest wind weight is %.3f, below the %.2f the "
                        "upper surface must reach" % (name, wind_high, WIND_UPPER_MIN))
    if record["contact_wind_max"] > 0.001:
        problems.append("%s: a ground-contact vertex carries wind %.3f — the "
                        "tuft will slide out of the terrain"
                        % (name, record["contact_wind_max"]))
    if record["wind_in_gap"]:
        problems.append("%s: %d vertices sit in the undefined %.2f-%.2f wind gap"
                        % (name, record["wind_in_gap"], WIND_MIDDLE_MAX,
                           WIND_UPPER_MIN))
    if light_low > LIGHT_LOWER_MAX:
        problems.append("%s: lowest top-light is %.3f, above the %.2f floor"
                        % (name, light_low, LIGHT_LOWER_MAX))
    if light_high < LIGHT_UPPER_MIN:
        problems.append("%s: highest top-light is %.3f, below the %.2f the "
                        "upper surface must reach" % (name, light_high, LIGHT_UPPER_MIN))
    if record["contact_light_max"] > LIGHT_LOWER_MAX:
        problems.append("%s: a ground-contact vertex carries top-light %.3f"
                        % (name, record["contact_light_max"]))


def export(obj, name):
    OUT.mkdir(parents=True, exist_ok=True)
    for other in bpy.context.scene.objects:
        other.select_set(other is obj)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=str(OUT / ("%s.glb" % name)),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_cameras=False,
        export_lights=False,
        export_materials="EXPORT",
        # MATERIAL keeps exactly the attribute the material reads. Verified
        # against the written file below rather than trusted.
        export_vertex_color="MATERIAL",
        export_normals=True,
        export_texcoords=False,
        export_tangents=False,
    )


def read_glb(path):
    """Re-read the written GLB so the gate checks the shipped bytes.

    Measuring the Blender mesh proves what was modelled, not what was exported.
    The attribute this whole file exists to deliver is dropped by an exporter
    flag, not by a modelling mistake, so it has to be verified after the fact.
    """
    data = path.read_bytes()
    offset = 12
    chunks = {}
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        chunks[kind] = data[offset:offset + length]
        offset += length
    document = json.loads(chunks[0x4E4F534A].decode("utf-8"))
    binary = chunks.get(0x004E4942, b"")

    def accessor(index):
        spec = document["accessors"][index]
        view = document["bufferViews"][spec["bufferView"]]
        counts = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[spec["type"]]
        code = {5120: "b", 5121: "B", 5122: "h", 5123: "H",
                5125: "I", 5126: "f"}[spec["componentType"]]
        size = struct.calcsize(code)
        stride = view.get("byteStride") or size * counts
        base = view.get("byteOffset", 0) + spec.get("byteOffset", 0)
        maximum = float((1 << (8 * size)) - 1) if spec.get("normalized") else 1.0
        out = []
        for index_value in range(spec["count"]):
            values = struct.unpack_from(
                "<" + code * counts, binary, base + index_value * stride
            )
            out.append(tuple(v / maximum for v in values)
                       if spec.get("normalized") else values)
        return out

    primitive = document["meshes"][0]["primitives"][0]
    result = {
        "attributes": sorted(primitive["attributes"].keys()),
        "images": len(document.get("images", [])),
        "cameras": len(document.get("cameras", [])),
        "nodes": len(document.get("nodes", [])),
        "triangles": len(accessor(primitive["indices"])) // 3,
    }
    if "COLOR_0" in primitive["attributes"]:
        colours = accessor(primitive["attributes"]["COLOR_0"])
        positions = accessor(primitive["attributes"]["POSITION"])
        result["colour_count"] = len(colours)
        result["wind_range"] = [min(c[0] for c in colours),
                                max(c[0] for c in colours)]
        result["light_range"] = [min(c[1] for c in colours),
                                 max(c[1] for c in colours)]
        # glTF is Y-up after export_yup, so the contact plane is y=0 here.
        grounded = [c for c, p in zip(colours, positions) if abs(p[1]) <= 1e-5]
        result["contact_vertices"] = len(grounded)
        result["contact_wind_max"] = max((c[0] for c in grounded), default=1.0)
    # A node with a non-identity transform means the mesh was not built at the
    # origin with applied transforms, which breaks instanced placement.
    node = document["nodes"][0]
    result["node_scale"] = node.get("scale", [1.0, 1.0, 1.0])
    result["node_translation"] = node.get("translation", [0.0, 0.0, 0.0])
    result["node_rotation"] = node.get("rotation", [0.0, 0.0, 0.0, 1.0])
    return result


def gate_glb(name, record, exported, problems):
    if "COLOR_0" not in exported["attributes"]:
        problems.append("%s: the exported GLB has no COLOR_0 — the vertex "
                        "colours were dropped and the shader has no wind data"
                        % name)
    elif exported["colour_count"] != record["vertices"]:
        problems.append("%s: GLB carries %d colours for %d vertices"
                        % (name, exported["colour_count"], record["vertices"]))
    if any(key.startswith("COLOR_") and key != "COLOR_0"
           for key in exported["attributes"]):
        problems.append("%s: the GLB carries more than one colour set (%s) — "
                        "the runtime would read an ambiguous one"
                        % (name, ", ".join(exported["attributes"])))
    if exported["triangles"] != record["triangles"]:
        problems.append("%s: GLB has %d triangles but the mesh measured %d"
                        % (name, exported["triangles"], record["triangles"]))
    # Read once. Reaching for the key again inside the message body crashes the
    # whole build on the one failure this gate exists to catch — a dropped
    # COLOR_0 leaves no contact_wind_max to report.
    contact_wind = exported.get("contact_wind_max")
    if contact_wind is not None and contact_wind > 0.001:
        problems.append("%s: GLB ground-contact wind is %.3f, not 0"
                        % (name, contact_wind))
    if exported["images"] or exported["cameras"]:
        problems.append("%s: GLB carries %d images and %d cameras; it must "
                        "carry neither"
                        % (name, exported["images"], exported["cameras"]))
    if exported["nodes"] != 1:
        problems.append("%s: GLB has %d nodes, expected exactly 1"
                        % (name, exported["nodes"]))
    if [round(v, 6) for v in exported["node_scale"]] != [1.0, 1.0, 1.0]:
        problems.append("%s: GLB node scale is %s, not 1,1,1"
                        % (name, exported["node_scale"]))
    if any(abs(v) > 1e-6 for v in exported["node_translation"]):
        problems.append("%s: GLB node is translated to %s"
                        % (name, exported["node_translation"]))


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    OUT.mkdir(parents=True, exist_ok=True)
    records = []
    problems = []

    for name, kind, lobes in MODULES:
        obj, predicted = build_module(name, lobes)
        record = measure(obj, len(lobes), predicted)
        export(obj, name)
        exported = read_glb(OUT / ("%s.glb" % name))

        gate(name, record, problems)
        gate_glb(name, record, exported, problems)

        record.update(
            id=name,
            kind=kind,
            path="%s/%s.glb" % (RES_PREFIX, name),
            glb_attributes=exported["attributes"],
            glb_triangles=exported["triangles"],
        )
        # The manifest contract leads with the keys the runtime reads.
        ordered = {key: record[key] for key in
                   ("id", "path", "kind", "triangles", "width", "depth", "height")}
        ordered.update({k: v for k, v in record.items() if k not in ordered})
        records.append(ordered)
        bpy.data.objects.remove(obj, do_unlink=True)

    report = {
        "modules": records,
        "total_triangles": sum(r["triangles"] for r in records),
        "problems": problems,
        "live_scale": round(LIVE_SCALE, 4),
        "cell_size": LIVE_CELL,
        "bands": {name: list(band) for name, band in BANDS.items()},
        "vertex_colour_contract": {
            "r": "wind weight: planted 0.0, middle 0.25-0.55, upper 0.65-1.0",
            "g": "top-light: lower 0.25, middle 0.55, upper 0.75-1.0",
            "b": "reserved, always 0.0",
        },
    }
    (OUT / "micro_tuft_report.json").write_text(
        json.dumps(report, indent=2), encoding="utf-8"
    )

    for record in records:
        print("%-22s %-8s tris=%2d/%-2d verts=%2d  %.4fw %.4fd %.4fh  "
              "aspect=%.2f  wind=%.2f-%.2f light=%.2f-%.2f  contact=%d@z%.6f"
              % (record["id"], record["kind"], record["triangles"],
                 record["glb_triangles"], record["vertices"],
                 record["width"], record["depth"], record["height"],
                 record["aspect"],
                 record["wind_range"][0], record["wind_range"][1],
                 record["light_range"][0], record["light_range"][1],
                 record["contact_vertices"], record["min_z"]))
    for line in problems:
        print("PROBLEM %s" % line)
    print("MICRO TUFTS: %d modules, %d problems, %d tris total, out=%s"
          % (len(records), len(problems), report["total_triangles"], OUT))


if __name__ == "__main__":
    main()
