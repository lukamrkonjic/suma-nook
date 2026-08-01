"""Leaf-based grass clumps for Suma's carpet.

    blender --background --python art_source/blender/build_grass_leaves.py

Replaces the rounded micro-cushions. Those were geometrically correct and read
on screen as pebbles scattered over a lawn: because a cushion is convex and
opaque, every instance held its own silhouette and the field never closed up.
Leaves interleave — a blade from one clump lies across its neighbour — so the
same instance count reads as one continuous mass instead of as countable blobs.

WHAT A LEAF IS HERE

A tapering ribbon of five stations, arcing over from a planted base to a single
tip vertex: 7 triangles. Cheap on purpose. The carpet's richness has to come
from many small overlapping blades, not from detail inside any one of them, and
at this size no viewer will ever resolve a single leaf's outline.

NORMALS ARE AUTHORED, NOT COMPUTED

Every vertex normal points mostly UP, tilted slightly along the leaf's own
direction, regardless of which way its faces point. Face normals on a thin
ribbon give each blade its own hard light-and-dark, which is what makes stylised
foliage read as a heap of litter. Biasing to up-plus-a-little makes a clump
shade as one soft dome, and a field of clumps as one soft surface. This is also
why the runtime shader draws these with cull_disabled and does NOT flip the
normal for back faces: both sides of a blade are meant to be lit the same.

VERTEX COLOUR CONTRACT (unchanged, the runtime depends on it)

    COLOR.r  wind weight  0.0 at the planted base, rising to the tip.
    COLOR.g  top-light    0.25 low, up to 1.0 at the tip.
    COLOR.b  reserved, written 0.0.
"""

import json
import math
import pathlib
import struct
import sys

import bpy

# Anchored to THIS FILE, never to the working directory. bpy.path.abspath("//")
# resolves to the cwd when Blender runs headless with no .blend loaded, so the
# obvious spelling writes the GLBs to a different tree depending on where the
# command was launched from — silently, while reporting success.
OUT = (pathlib.Path(__file__).resolve().parent.parent.parent
       / "world" / "grass" / "meshes")
RES_PREFIX = "res://world/grass/meshes"

MATERIAL_NAME = "grass_leaf"
COLOR_ATTRIBUTE = "Color"
PREVIEW_TONE = (0.30, 0.48, 0.16, 1.0)

# Stations along a leaf: (t, width factor).
#
# This is a PADDLE, not a blade: narrow where it joins the clump, widest just
# past the middle, then closing to a rounded tip. Two earlier shapes were
# rejected on sight — convex cushions read as scattered balls, and a linear
# taper to a point read as straw. The difference is entirely in this table. A
# leaf that carries most of its width through the outer half presents a broad
# soft silhouette from the gameplay camera, which is what makes a clump read as
# one chunky form instead of as a bundle of separate strands.
STATIONS = [
    (0.00, 0.42),
    (0.22, 0.80),
    (0.50, 1.00),
    (0.76, 0.94),
    (0.92, 0.66),
    (1.00, 0.00),
]

# How far the normal leans away from straight up, along the leaf's direction.
# Small: this is a softening bias, and pushing it further starts to reintroduce
# the per-blade shading it exists to suppress.
NORMAL_LEAN = 0.30

CONTACT_EPSILON = 1e-4


def material():
    """Shared material carrying the Color Attribute node.

    It must reach the output or the glTF exporter drops COLOR_0 under
    export_vertex_color="MATERIAL", and the runtime silently loses both the wind
    mask and the top-light with no error anywhere.
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
        self.faces = []
        self.colours = []
        self.normals = []

    def add(self, position, colour, normal):
        self.verts.append(position)
        self.colours.append(colour)
        self.normals.append(normal)
        return len(self.verts) - 1


def leaf(builder, origin, yaw, length, width, tilt, arc):
    """One blade. Returns the triangle count it contributed.

    The spine is integrated rather than expressed in closed form: the angle from
    vertical grows along the blade, so stepping it and accumulating gives a curve
    that leaves the ground vertical-ish and lies over near the tip. A blade that
    leaves the ground already leaning reads as flattened or trampled.
    """
    direction = (math.cos(yaw), math.sin(yaw))
    across = (-math.sin(yaw), math.cos(yaw))
    normal = _unit((direction[0] * NORMAL_LEAN, direction[1] * NORMAL_LEAN, 1.0))

    spine = []
    steps = 24
    x = 0.0
    z = 0.0
    for step in range(steps + 1):
        t = step / steps
        # Quadratic in t so the bend is gentle at the base and strongest near
        # the tip, which is how a real blade droops under its own weight.
        angle = tilt + arc * t * t
        if step > 0:
            ds = length / steps
            x += math.sin(angle) * ds
            z += math.cos(angle) * ds
        spine.append((t, x, z))

    def sample(t):
        for index in range(len(spine) - 1):
            if spine[index][0] <= t <= spine[index + 1][0]:
                a = spine[index]
                b = spine[index + 1]
                span = b[0] - a[0]
                k = 0.0 if span <= 0.0 else (t - a[0]) / span
                return (a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k)
        return (spine[-1][1], spine[-1][2])

    rings = []
    for t, width_factor in STATIONS:
        along, height = sample(t)
        centre = (
            origin[0] + direction[0] * along,
            origin[1] + direction[1] * along,
            origin[2] + height,
        )
        # Wind rises faster than linearly: the top third of a blade is what the
        # eye reads as movement, and a linear ramp makes the whole blade shear.
        wind = min(1.0, (t ** 1.35) * 1.05)
        if t <= 0.0:
            wind = 0.0
        light = 0.25 + 0.75 * (t ** 0.85)
        colour = (wind, light, 0.0, 1.0)
        half = width * width_factor * 0.5
        if width_factor <= 0.0:
            rings.append([builder.add(centre, colour, normal)])
            continue
        rings.append([
            builder.add(
                (centre[0] - across[0] * half, centre[1] - across[1] * half, centre[2]),
                colour, normal),
            builder.add(
                (centre[0] + across[0] * half, centre[1] + across[1] * half, centre[2]),
                colour, normal),
        ])

    triangles = 0
    for index in range(len(rings) - 1):
        lower = rings[index]
        upper = rings[index + 1]
        if len(upper) == 1:
            builder.faces.append((lower[0], lower[1], upper[0]))
            triangles += 1
        else:
            builder.faces.append((lower[0], lower[1], upper[1], upper[0]))
            triangles += 2
    return triangles


def _unit(vector):
    length = math.sqrt(sum(component * component for component in vector))
    if length <= 0.0:
        return (0.0, 0.0, 1.0)
    return tuple(component / length for component in vector)


def clump(name, spec):
    """A rosette of blades.

    Yaws are spread evenly and then jittered. Evenly spaced alone produces a
    little starburst that repeats visibly once thousands are on screen; jitter
    alone lets blades bunch and leave a bald sector. Both together give a clump
    that covers its own footprint without looking constructed.
    """
    builder = Builder()
    count = spec["leaves"]
    triangles = 0
    for index in range(count):
        fraction = index / count
        yaw = fraction * math.tau + _wobble(index, 11) * spec["yaw_jitter"]
        length = spec["length"][0] + (spec["length"][1] - spec["length"][0]) * _wobble01(index, 23)
        tilt = spec["tilt"][0] + (spec["tilt"][1] - spec["tilt"][0]) * _wobble01(index, 37)
        arc = spec["arc"][0] + (spec["arc"][1] - spec["arc"][0]) * _wobble01(index, 41)
        radius = spec["base_radius"] * _wobble01(index, 53)
        origin = (math.cos(yaw) * radius, math.sin(yaw) * radius, 0.0)
        triangles += leaf(builder, origin, yaw, length, spec["width"], tilt, arc)

    xs = [v[0] for v in builder.verts]
    ys = [v[1] for v in builder.verts]
    zs = [v[2] for v in builder.verts]
    shift = ((max(xs) + min(xs)) * 0.5, (max(ys) + min(ys)) * 0.5, min(zs))
    builder.verts = [
        (x - shift[0], y - shift[1], z - shift[2]) for x, y, z in builder.verts
    ]

    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(builder.verts, [], builder.faces)
    mesh.validate(verbose=False)
    mesh.materials.append(material())
    for polygon in mesh.polygons:
        polygon.material_index = 0
        polygon.use_smooth = True

    attribute = mesh.color_attributes.new(
        name=COLOR_ATTRIBUTE, type="FLOAT_COLOR", domain="POINT"
    )
    for index, colour in enumerate(builder.colours):
        attribute.data[index].color = colour
    mesh.color_attributes.active_color_index = 0
    mesh.color_attributes.render_color_index = 0

    # The authored up-biased normals, which is the whole softening strategy.
    mesh.normals_split_custom_set_from_vertices(builder.normals)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    bpy.context.view_layer.objects.active = obj
    return obj, triangles


def _wobble(index, salt):
    """Deterministic -1..1. Seeded numerically so a rebuild is byte-identical."""
    value = math.sin(index * 12.9898 + salt * 78.233) * 43758.5453
    return (value - math.floor(value)) * 2.0 - 1.0


def _wobble01(index, salt):
    return _wobble(index, salt) * 0.5 + 0.5


# Width is roughly a THIRD of length here, against a tenth in the rejected straw
# pass. Combined with high tilt — leaves leaving the base at 40-60° from
# vertical rather than near-upright — each clump splays into a low rounded
# rosette. That splay is what produces a soft blobby mass at gameplay distance
# while every individual piece stays a recognisable leaf up close.
SPECS = {
    # Dense carpet. Three sizes so the field mixes small, medium and large
    # forms instead of repeating one silhouette across thousands of instances.
    "grass_leaf_small": {
        "kind": "dense", "leaves": 4, "width": 0.030, "base_radius": 0.008,
        "length": (0.042, 0.066), "tilt": (0.62, 1.02), "arc": (0.42, 0.80),
        "yaw_jitter": 0.58,
    },
    "grass_leaf_medium": {
        "kind": "dense", "leaves": 5, "width": 0.044, "base_radius": 0.011,
        "length": (0.066, 0.098), "tilt": (0.58, 0.98), "arc": (0.46, 0.88),
        "yaw_jitter": 0.54,
    },
    "grass_leaf_large": {
        "kind": "dense", "leaves": 6, "width": 0.058, "base_radius": 0.015,
        "length": (0.092, 0.140), "tilt": (0.54, 0.94), "arc": (0.50, 0.96),
        "yaw_jitter": 0.50,
    },
    # Flexible layer: taller and standing more upright, so it breaks the
    # carpet's silhouette and is the part the wind visibly moves.
    "grass_leaf_tall": {
        "kind": "flexible", "leaves": 5, "width": 0.050, "base_radius": 0.013,
        "length": (0.125, 0.175), "tilt": (0.34, 0.68), "arc": (0.62, 1.10),
        "yaw_jitter": 0.56,
    },
    "grass_leaf_accent": {
        "kind": "flexible", "leaves": 4, "width": 0.046, "base_radius": 0.011,
        "length": (0.150, 0.205), "tilt": (0.28, 0.60), "arc": (0.70, 1.22),
        "yaw_jitter": 0.62,
    },
}


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
        export_vertex_color="MATERIAL",
        export_normals=True,
        export_texcoords=False,
        export_tangents=False,
    )


def read_glb(path):
    """Re-read the written bytes.

    Measuring the Blender mesh proves what was modelled, not what shipped, and
    the attribute this file exists to deliver is lost to an exporter flag rather
    than to a modelling mistake.
    """
    data = path.read_bytes()
    offset = 12
    chunks = {}
    while offset < len(data):
        length, kind = struct.unpack_from("<I4s", data, offset)
        body = data[offset + 8:offset + 8 + length]
        chunks[kind.decode().strip()] = body
        offset += 8 + length
    document = json.loads(chunks["JSON"].decode("utf-8"))
    primitive = document["meshes"][0]["primitives"][0]
    return {
        "attributes": sorted(primitive["attributes"].keys()),
        "triangles": document["accessors"][primitive["indices"]]["count"] // 3,
    }


def measure(obj, triangles):
    mesh = obj.data
    mesh.calc_loop_triangles()
    xs = [v.co.x for v in mesh.vertices]
    ys = [v.co.y for v in mesh.vertices]
    zs = [v.co.z for v in mesh.vertices]
    colour = mesh.color_attributes[COLOR_ATTRIBUTE]
    winds = [colour.data[i].color[0] for i in range(len(mesh.vertices))]
    contact = [i for i, v in enumerate(mesh.vertices) if v.co.z <= CONTACT_EPSILON]
    return {
        "triangles": len(mesh.loop_triangles),
        "predicted_triangles": triangles,
        "vertices": len(mesh.vertices),
        "width": round(max(xs) - min(xs), 4),
        "depth": round(max(ys) - min(ys), 4),
        "height": round(max(zs) - min(zs), 4),
        "min_z": round(min(zs), 6),
        "contact_vertices": len(contact),
        "contact_wind_max": round(max((winds[i] for i in contact), default=0.0), 4),
        "wind_range": [round(min(winds), 3), round(max(winds), 3)],
    }


def gate(name, spec, record, problems):
    """Build-time checks for the failures that are invisible in a screenshot.

    A blade whose base can move detaches from the ground and skates; a mesh
    exported without COLOR_0 loses wind entirely and looks merely stiff. Both
    survive a casual look at a still image, so they are asserted here instead.
    """
    if record["contact_wind_max"] > 0.001:
        problems.append("%s: a ground-contact vertex carries wind weight %.3f — "
                        "its base will slide" % (name, record["contact_wind_max"]))
    if record["min_z"] < -CONTACT_EPSILON:
        problems.append("%s: geometry below z=0 (%.5f)" % (name, record["min_z"]))
    if record["wind_range"][1] < 0.9:
        problems.append("%s: no vertex reaches wind weight 0.9" % name)
    if "COLOR_0" not in record["glb_attributes"]:
        problems.append("%s: exported GLB has no COLOR_0 — wind and top-light "
                        "are gone" % name)
    if record["triangles"] != record["glb_triangles"]:
        problems.append("%s: modelled %d triangles, exported %d"
                        % (name, record["triangles"], record["glb_triangles"]))
    span = max(record["width"], record["depth"])
    band = {"dense": (0.07, 0.34), "flexible": (0.16, 0.52)}[spec["kind"]]
    if not band[0] <= span <= band[1]:
        problems.append("%s: span %.3f m outside the %s band %s"
                        % (name, span, spec["kind"], band))


def main():
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    records = []
    problems = []
    for name, spec in SPECS.items():
        obj, triangles = clump(name, spec)
        export(obj, name)
        record = measure(obj, triangles)
        exported = read_glb(OUT / ("%s.glb" % name))
        record["glb_attributes"] = exported["attributes"]
        record["glb_triangles"] = exported["triangles"]
        record["id"] = name
        record["kind"] = spec["kind"]
        record["path"] = "%s/%s.glb" % (RES_PREFIX, name)
        gate(name, spec, record, problems)
        records.append(record)
        bpy.data.objects.remove(obj, do_unlink=True)

    report = {"modules": records, "problems": problems}
    (OUT / "leaf_report.json").write_text(json.dumps(report, indent=1))
    for record in records:
        print("%-20s %3d tris  %.3f x %.3f x %.3f m"
              % (record["id"], record["triangles"], record["width"],
                 record["depth"], record["height"]))
    print("TOTAL %d triangles across %d modules"
          % (sum(r["triangles"] for r in records), len(records)))
    if problems:
        for problem in problems:
            print("PROBLEM: %s" % problem)
        sys.exit(1)
    print("GATE PASSED")


main()
