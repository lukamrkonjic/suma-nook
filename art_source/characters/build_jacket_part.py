"""Fit, recolor, and rig the generated cozy jacket onto the canonical mannequin.

Input:  art_source/imported/jacket_default/jacket_source.glb (Meshy, sha-pinned)
Color:  art_source/imported/jacket_default/jacket_color_reference.png
Output: assets/characters/parts/top_jacket_cozy.glb (skinned to GameExportRig)
        art_source/characters/review/jacket_*.png (fit previews)

Run:
    blender --background --factory-startup --python build_jacket_part.py
"""

from __future__ import annotations

import json
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

REPO = Path(r"C:\Dev\suma-nook")
MASTER = REPO / "art_source/characters/suma_character_master.blend"
SOURCE = REPO / "art_source/imported/jacket_default/jacket_source.glb"
GLB_OUT = REPO / "assets/characters/parts/top_jacket_cozy.glb"
REVIEW_DIR = REPO / "art_source/characters/review"
REPORT_OUT = REPO / "art_source/imported/jacket_default/process_report.json"

# Fitting targets in mannequin model space (front = -Y, ground z = -0.435).
COLLAR_TOP_Z = 0.128        # just above the neck base (0.12)
HEM_BOTTOM_Z = -0.128       # upper hips
TORSO_HALF_X = 0.123        # body chest 0.114 + clearance
TORSO_BACK_Y = 0.097        # body back 0.088 + clearance
TORSO_FRONT_Y = 0.107       # body belly front 0.095 + clearance
SLEEVE_END_X = 0.295        # wrist; stub hands (0.27..0.32) peek out
ARM_CENTER_Z = 0.093        # arm bone centerline height
TARGET_TRIANGLES = 3800

# Sampled from the Gemini color reference (sRGB hex).
COLORS = {
    "mustard": (0.910, 0.662, 0.306, 1.0),   # #E8A94E body, pockets, hem
    "cream": (0.949, 0.906, 0.808, 1.0),     # #F2E7CE collar + cuffs
    "walnut": (0.545, 0.420, 0.310, 1.0),    # #8B6B4F buttons
}


def srgb_to_linear(color: tuple) -> tuple:
    def channel(c: float) -> float:
        return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

    return (channel(color[0]), channel(color[1]), channel(color[2]), color[3])


def make_material(name: str, srgb: tuple) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    linear = srgb_to_linear(srgb)
    material.diffuse_color = linear
    material.use_nodes = True
    principled = material.node_tree.nodes.get("Principled BSDF")
    principled.inputs["Base Color"].default_value = linear
    principled.inputs["Roughness"].default_value = 0.72
    principled.inputs["Specular IOR Level"].default_value = 0.15
    return material


def apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)


def triangle_count(obj: bpy.types.Object) -> int:
    return sum(len(p.vertices) - 2 for p in obj.data.polygons)


def import_jacket() -> bpy.types.Object:
    existing = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(SOURCE))
    imported = [
        o for o in bpy.context.scene.objects
        if o not in existing and o.type == "MESH"
    ]
    if len(imported) != 1:
        raise RuntimeError(f"Expected one jacket mesh, found {len(imported)}")
    jacket = imported[0]
    jacket.name = "JacketCozy"
    jacket.data.name = "JacketCozyMesh"
    return jacket


def clay_smooth(jacket: bpy.types.Object) -> None:
    """Keep the generated topology (its buttons, pockets, and collar read
    best crisp) and smooth only the rounded surfaces: the established
    60-degree smooth-by-angle treatment."""
    from math import radians as _radians

    bpy.context.view_layer.objects.active = jacket
    bpy.ops.object.select_all(action="DESELECT")
    jacket.select_set(True)
    bpy.ops.object.shade_smooth_by_angle(angle=_radians(60.0))


def fit_to_mannequin(jacket: bpy.types.Object) -> dict:
    """Scale per-axis onto the torso, then shear the sleeves up so the
    horizontal T-pose arms stay centered inside them."""
    coords = [v.co.copy() for v in jacket.data.vertices]
    min_v = Vector((min(c[i] for c in coords) for i in range(3)))
    max_v = Vector((max(c[i] for c in coords) for i in range(3)))

    # Source torso half-width: widest point of the lower torso (below the
    # sleeve line, z < -0.1 source space, excluding hem splay outliers).
    torso_half_source = max(
        abs(c.x) for c in coords if c.z < -0.15
    )
    scale_x = max(TORSO_HALF_X / torso_half_source, SLEEVE_END_X / max_v.x)
    scale_x = min(scale_x, SLEEVE_END_X / max_v.x * 1.08)
    # The front needs its own clearance: the belly is the body's deepest point.
    scale_y = max(TORSO_BACK_Y / max_v.y, TORSO_FRONT_Y / -min_v.y)
    scale_z = (COLLAR_TOP_Z - HEM_BOTTOM_Z) / (max_v.z - min_v.z)
    matrix = Matrix.Diagonal((scale_x, scale_y, scale_z, 1.0))
    jacket.data.transform(matrix)

    # Vertical placement: hem to target.
    coords = [v.co.copy() for v in jacket.data.vertices]
    min_z = min(c.z for c in coords)
    offset_z = HEM_BOTTOM_Z - min_z
    jacket.data.transform(Matrix.Translation((0.0, 0.0, offset_z)))

    # Sleeve shear: ramp a vertical correction from the armpit outward so the
    # sleeve centerline lands on the arm bone centerline at the cuff.
    coords = [v.co.copy() for v in jacket.data.vertices]
    cuff_x = max(abs(c.x) for c in coords)
    armpit_x = 0.145
    cuff_band = [c.z for c in coords if abs(c.x) > cuff_x - 0.02]
    cuff_center = sum(cuff_band) / len(cuff_band)
    lift = ARM_CENTER_Z - cuff_center
    for vertex in jacket.data.vertices:
        ramp = (abs(vertex.co.x) - armpit_x) / (cuff_x - armpit_x)
        if ramp > 0.0:
            vertex.co.z += lift * min(ramp, 1.0)

    # Flare the hem outward so mid-stride thighs never punch through it.
    hem_top = -0.055
    hem_bottom = HEM_BOTTOM_Z
    for vertex in jacket.data.vertices:
        if vertex.co.z < hem_top and abs(vertex.co.x) < 0.16:
            ramp = min(
                (hem_top - vertex.co.z) / (hem_top - hem_bottom), 1.0
            )
            factor = 1.0 + 0.10 * ramp
            vertex.co.x *= factor
            vertex.co.y *= factor

    jacket.location = (0.0, 0.0, 0.0)
    jacket.rotation_euler = (0.0, 0.0, 0.0)
    jacket.scale = (1.0, 1.0, 1.0)
    return {
        "scale": [round(scale_x, 4), round(scale_y, 4), round(scale_z, 4)],
        "offset_z": round(offset_z, 4),
        "sleeve_lift": round(lift, 4),
        "torso_half_source": round(torso_half_source, 4),
    }


def assign_region_materials(jacket: bpy.types.Object) -> dict:
    """Mustard body, cream collar + cuffs, walnut buttons — matching the
    color reference. Regions are selected geometrically in model space."""
    mustard = make_material("Suma_Jacket_Body", COLORS["mustard"])
    cream = make_material("Suma_Jacket_Trim", COLORS["cream"])
    walnut = make_material("Suma_Jacket_Buttons", COLORS["walnut"])
    jacket.data.materials.clear()
    for material in (mustard, cream, walnut):
        jacket.data.materials.append(material)

    coords = [v.co.copy() for v in jacket.data.vertices]
    cuff_x = max(abs(c.x) for c in coords)
    # Front baseline of the center torso strip, for button detection.
    center_front = [
        c.y for c in coords
        if abs(c.x) < 0.05 and -0.06 < c.z < 0.08 and c.y < 0.0
    ]
    front_baseline = sorted(center_front)[len(center_front) // 2]

    counts = {"body": 0, "trim": 0, "buttons": 0}
    for polygon in jacket.data.polygons:
        center = polygon.center
        neck_radial = (center.x ** 2 + (center.y + 0.01) ** 2) ** 0.5
        index = 0
        if abs(center.x) > cuff_x - 0.055:
            index = 1  # cuffs
        elif (
            center.z > 0.082
            and neck_radial < 0.115
            and (center.y > -0.045 or center.z > 0.105)
        ):
            index = 1  # collar ring: back and sides only, no chest cream
        if (
            abs(center.x) < 0.034
            and -0.05 < center.z < 0.06
            and center.y < front_baseline - 0.014
        ):
            index = 2  # buttons protrude clearly past the lapel line
        polygon.material_index = index
        counts[("body", "trim", "buttons")[index]] += 1
    return counts


def _fill_missing_weights(
    jacket: bpy.types.Object, body: bpy.types.Object
) -> int:
    """Vertices the face-interpolated transfer missed keep zero total weight.
    Blender leaves such vertices at their authored position, so the problem is
    invisible in previews — but Godot collapses them toward the origin and the
    garment explodes once posed. Copy weights from the nearest body vertex."""
    from mathutils import kdtree

    tree = kdtree.KDTree(len(body.data.vertices))
    for index, vertex in enumerate(body.data.vertices):
        tree.insert(vertex.co, index)
    tree.balance()
    body_group_names = {g.index: g.name for g in body.vertex_groups}
    jacket_groups = {g.name: g for g in jacket.vertex_groups}
    filled = 0
    for vertex in jacket.data.vertices:
        if sum(entry.weight for entry in vertex.groups) >= 0.05:
            continue
        _location, nearest, _distance = tree.find(vertex.co)
        for entry in body.data.vertices[nearest].groups:
            name = body_group_names[entry.group]
            group = jacket_groups.get(name)
            if group is None:
                group = jacket.vertex_groups.new(name=name)
                jacket_groups[name] = group
            group.add([vertex.index], entry.weight, "REPLACE")
        filled += 1
    return filled


def transfer_weights(jacket: bpy.types.Object) -> int:
    body = bpy.data.objects.get("PlayerMaleBody")
    rig = bpy.data.objects.get("GameExportRig")
    if body is None or rig is None:
        raise RuntimeError("Master file is missing PlayerMaleBody/GameExportRig")
    # The master file keeps the idle action applied; Data Transfer samples the
    # EVALUATED body, and against the lifted idle pose the legs sit at sleeve
    # height — the garment would inherit leg/foot weights. Sample at rest.
    rig.data.pose_position = "REST"
    bpy.context.view_layer.update()
    transfer = jacket.modifiers.new("CopyBodyWeights", "DATA_TRANSFER")
    transfer.object = body
    transfer.use_vert_data = True
    transfer.data_types_verts = {"VGROUP_WEIGHTS"}
    transfer.vert_mapping = "POLYINTERP_NEAREST"
    transfer.layers_vgroup_select_src = "ALL"
    transfer.layers_vgroup_select_dst = "NAME"
    bpy.context.view_layer.objects.active = jacket
    bpy.ops.object.datalayout_transfer(modifier=transfer.name)
    apply_modifier(jacket, transfer)
    filled = _fill_missing_weights(jacket, body)

    # Per-vertex nearest-face sampling leaves sharp weight discontinuities
    # (visible as spikes and lumps once posed). Smooth the weights so the
    # garment deforms like one piece of fabric, then limit + normalize so
    # glTF's four-influence export can never underweight a vertex.
    bpy.context.view_layer.objects.active = jacket
    bpy.ops.object.select_all(action="DESELECT")
    jacket.select_set(True)
    bpy.ops.object.mode_set(mode="WEIGHT_PAINT")
    bpy.ops.object.vertex_group_smooth(
        group_select_mode="ALL", factor=0.5, repeat=4, expand=0.15
    )
    bpy.ops.object.mode_set(mode="OBJECT")

    # A jacket hangs from the torso: leg and foot influences make the hem
    # ride the stride and let thighs punch through. Strip them entirely and
    # renormalize onto the remaining torso/arm bones.
    for group in list(jacket.vertex_groups):
        if any(
            part in group.name
            for part in ("UpLeg", "LeftLeg", "RightLeg", "Foot", "ToeBase")
        ):
            jacket.vertex_groups.remove(group)

    # Guard: a vertex whose only influences were legs would now be weightless
    # and collapse to the origin in Godot. Anchor any such vertex to the hips.
    hips_group = jacket.vertex_groups.get("mixamorigHips")
    if hips_group is None:
        hips_group = jacket.vertex_groups.new(name="mixamorigHips")
    for vertex in jacket.data.vertices:
        if sum(entry.weight for entry in vertex.groups) < 0.001:
            hips_group.add([vertex.index], 1.0, "REPLACE")

    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)

    armature = jacket.modifiers.new("GameExportRig", "ARMATURE")
    armature.object = rig
    # The glTF exporter requires the armature to be the mesh's object parent;
    # a bare armature modifier exports the skin in the wrong space.
    jacket.parent = rig
    jacket.matrix_parent_inverse = rig.matrix_world.inverted()
    return filled


def export_jacket(jacket: bpy.types.Object) -> None:
    rig = bpy.data.objects["GameExportRig"]
    rig.data.pose_position = "REST"
    bpy.ops.object.select_all(action="DESELECT")
    jacket.select_set(True)
    rig.select_set(True)
    bpy.context.view_layer.objects.active = rig
    GLB_OUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.export_scene.gltf(
        filepath=str(GLB_OUT),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_animations=False,
        export_skins=True,
        export_morph=False,
        export_yup=True,
    )


def render_previews(jacket: bpy.types.Object) -> None:
    scene = bpy.context.scene
    rig = bpy.data.objects["GameExportRig"]
    rig.data.pose_position = "REST"
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 900
    scene.render.resolution_y = 900
    scene.render.image_settings.file_format = "PNG"
    REVIEW_DIR.mkdir(parents=True, exist_ok=True)
    views = {
        "jacket_front": "CAM_FRONT_ORTHO",
        "jacket_three_quarter": "CAM_THREE_QUARTER",
        "jacket_side": "CAM_SIDE_ORTHO",
        "jacket_game": "CAM_GAME_APPROX",
    }
    for file_stem, camera_name in views.items():
        camera = bpy.data.objects.get(camera_name)
        if camera is None:
            continue
        scene.camera = camera
        scene.render.filepath = str(REVIEW_DIR / f"{file_stem}.png")
        bpy.ops.render.render(write_still=True)


def main() -> None:
    bpy.ops.wm.open_mainfile(filepath=str(MASTER))
    # Reference and helper objects stay out of the renders.
    for collection_name in ("REFERENCE_ONLY", "EXPORT_HELPERS"):
        collection = bpy.data.collections.get(collection_name)
        if collection is not None:
            for obj in collection.objects:
                obj.hide_render = True

    jacket = import_jacket()
    clay_smooth(jacket)
    fit = fit_to_mannequin(jacket)
    regions = assign_region_materials(jacket)
    filled = transfer_weights(jacket)

    report = {
        "weights_filled_by_nearest_vertex": filled,
        "source_sha256": "E78D2DF851B8A1F29FB59FB35969826434A1680D71B29FCB6879D0CA10353B33",
        "fit": fit,
        "material_faces": regions,
        "triangles": triangle_count(jacket),
        "vertices": len(jacket.data.vertices),
        "glb": str(GLB_OUT.relative_to(REPO)),
    }
    export_jacket(jacket)
    render_previews(jacket)
    REPORT_OUT.write_text(json.dumps(report, indent=2))
    print("JACKET_PART_BUILT", json.dumps(report))


if __name__ == "__main__":
    main()
