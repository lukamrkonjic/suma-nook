"""Fit, skin, and export the supplied cowboy vest for Suma's current player.

The source remains untouched under ``art_source/imported``. This script fits
the garment over the player's evaluated rest-pose surface, smooths its jagged
silhouette, transfers vertex-group weights with Blender's nearest-face
interpolation, binds it to the exact player armature, and exports a wardrobe
bundle containing:

- ``CowboyVest``: the independently switchable skinned garment;
- ``BodyExposedForCowboyVest``: the same skinned player body with only the
  polygons concealed by the vest removed.

At runtime both meshes are rebound to the already-active player Skeleton3D, so
there is still only one live skeleton.
"""

from __future__ import annotations

import hashlib
import json
import math
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[2]
SOURCE = (
    ROOT
    / "art_source"
    / "imported"
    / "cowboy_vest"
    / "cowboy_vest_source.glb"
)
PLAYER = ROOT / "assets" / "3d" / "reworked" / "suma_player.glb"
OUTPUT = ROOT / "assets" / "3d" / "reworked" / "cowboy_vest.glb"
WORK_DIR = ROOT / "art_source" / "blender" / "cowboy_vest"
BLEND = WORK_DIR / "cowboy_vest.blend"
REST_FRONT = WORK_DIR / "cowboy_vest_rest_front.png"
REST_BACK = WORK_DIR / "cowboy_vest_rest_back.png"
IDLE_DEFORM = WORK_DIR / "cowboy_vest_idle_deform.png"
REPORT = WORK_DIR / "process_report.json"

EXPECTED_SOURCE_SHA256 = (
    "145180369651319798d510b38a01a8127a9f97aecb4abd12ac38f3041cdac024"
)

# Fit established against the evaluated visual rest pose, not the raw bind
# vertices. Blender axes are Z-up after glTF import.
FIT_SCALE = Vector((0.56, 0.50, 0.40))
FIT_LOCATION = Vector((0.0, -0.015, 0.0))
SUBDIVISION_LEVELS = 1
SMOOTH_ANGLE_RADIANS = math.radians(55.0)
SHOULDER_CLEARANCE_MIN_HEIGHT = 0.060
SHOULDER_CLEARANCE_MIN_WIDTH = 0.105
SHOULDER_NORMAL_OFFSET = 0.010
SHOULDER_LATERAL_OVERLAP = 0.008

# Body triangles centered inside this back-torso region are omitted from the
# equipped-body clone.  Restricting removal to the back half prevents the broad
# shirt surface from breaking through the vest, while the front, armholes,
# sleeves, hem, and open center remain the untouched canonical body.
COVERAGE_HEIGHT_MIN = -0.160
COVERAGE_HEIGHT_MAX = 0.115
COVERAGE_HALF_WIDTH = 0.230
COVERAGE_BACK_Y = 0.020


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stats(mesh_object: bpy.types.Object) -> dict:
    mesh_object.data.calc_loop_triangles()
    return {
        "vertices": len(mesh_object.data.vertices),
        "polygons": len(mesh_object.data.polygons),
        "triangles": len(mesh_object.data.loop_triangles),
        "materials": [
            material.name
            for material in mesh_object.data.materials
            if material is not None
        ],
        "uv_layers": [layer.name for layer in mesh_object.data.uv_layers],
        "vertex_groups": len(mesh_object.vertex_groups),
    }


def import_new_mesh(path: Path) -> bpy.types.Object:
    existing = set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    meshes = [
        obj
        for obj in bpy.context.scene.objects
        if obj not in existing and obj.type == "MESH"
    ]
    if not meshes:
        raise RuntimeError(f"No mesh found in {path}")
    return max(meshes, key=lambda obj: len(obj.data.polygons))


def activate_only(obj: bpy.types.Object) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def smooth_garment(vest: bpy.types.Object) -> None:
    activate_only(vest)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.00001, use_unselected=False)
    bpy.ops.mesh.normals_make_consistent(inside=False)
    bpy.ops.object.mode_set(mode="OBJECT")

    subdivision = vest.modifiers.new("SilhouetteSubdivision", "SUBSURF")
    subdivision.subdivision_type = "CATMULL_CLARK"
    subdivision.levels = SUBDIVISION_LEVELS
    subdivision.render_levels = SUBDIVISION_LEVELS
    subdivision.show_only_control_edges = True
    bpy.ops.object.modifier_apply(modifier=subdivision.name)
    bpy.ops.object.shade_smooth_by_angle(
        angle=SMOOTH_ANGLE_RADIANS,
        keep_sharp_edges=True,
    )

    for material in vest.data.materials:
        if material is None or not material.use_nodes:
            continue
        principled = next(
            (
                node
                for node in material.node_tree.nodes
                if node.type == "BSDF_PRINCIPLED"
            ),
            None,
        )
        if principled is not None:
            principled.inputs["Roughness"].default_value = max(
                0.78,
                principled.inputs["Roughness"].default_value,
            )


def add_shoulder_clearance(vest: bpy.types.Object) -> int:
    """Lift the yoke over the body's shoulder silhouette without widening the torso."""
    vest.data.update()
    adjusted = 0
    for vertex in vest.data.vertices:
        horizontal = abs(vertex.co.x)
        if (
            vertex.co.z < SHOULDER_CLEARANCE_MIN_HEIGHT
            or horizontal < SHOULDER_CLEARANCE_MIN_WIDTH
        ):
            continue
        height_factor = min(
            1.0,
            (vertex.co.z - SHOULDER_CLEARANCE_MIN_HEIGHT) / 0.080,
        )
        width_factor = min(
            1.0,
            (horizontal - SHOULDER_CLEARANCE_MIN_WIDTH) / 0.090,
        )
        influence = max(0.0, height_factor * width_factor)
        if influence <= 0.0:
            continue
        vertex.co += vertex.normal * SHOULDER_NORMAL_OFFSET * influence
        vertex.co.x += (
            math.copysign(SHOULDER_LATERAL_OVERLAP, vertex.co.x)
            * influence
        )
        adjusted += 1
    vest.data.update()
    return adjusted


def evaluated_rest_reference(
    body: bpy.types.Object,
) -> bpy.types.Object:
    reference = body.copy()
    reference.data = body.data.copy()
    reference.name = "WeightTransferReference"
    reference.data.name = "WeightTransferReferenceMesh"
    bpy.context.scene.collection.objects.link(reference)
    activate_only(reference)
    armature_modifier = next(
        modifier
        for modifier in reference.modifiers
        if modifier.type == "ARMATURE"
    )
    bpy.ops.object.modifier_apply(modifier=armature_modifier.name)
    world = reference.matrix_world.copy()
    reference.parent = None
    reference.matrix_world = world
    reference.hide_render = True
    reference.hide_set(True)
    return reference


def transfer_weights(
    body_reference: bpy.types.Object,
    vest: bpy.types.Object,
    armature: bpy.types.Object,
) -> dict:
    for group in body_reference.vertex_groups:
        vest.vertex_groups.new(name=group.name)

    activate_only(vest)
    transfer = vest.modifiers.new("BodyWeightTransfer", "DATA_TRANSFER")
    transfer.object = body_reference
    transfer.use_vert_data = True
    transfer.data_types_verts = {"VGROUP_WEIGHTS"}
    transfer.vert_mapping = "POLYINTERP_NEAREST"
    transfer.layers_vgroup_select_src = "ALL"
    transfer.layers_vgroup_select_dst = "NAME"
    transfer.mix_mode = "REPLACE"
    bpy.ops.object.modifier_apply(modifier=transfer.name)

    bpy.ops.object.vertex_group_clean(
        group_select_mode="ALL",
        limit=0.0001,
        keep_single=True,
    )
    bpy.ops.object.vertex_group_limit_total(
        group_select_mode="ALL",
        limit=4,
    )
    bpy.ops.object.vertex_group_normalize_all(
        group_select_mode="ALL",
        lock_active=False,
    )

    weight_totals = [
        sum(group.weight for group in vertex.groups)
        for vertex in vest.data.vertices
    ]
    unweighted = sum(total <= 0.00001 for total in weight_totals)
    if unweighted:
        raise RuntimeError(f"Weight transfer left {unweighted} vest vertices unweighted")

    vest.parent = armature
    vest.matrix_parent_inverse = armature.matrix_world.inverted()
    armature_modifier = vest.modifiers.new("PlayerArmature", "ARMATURE")
    armature_modifier.object = armature
    armature_modifier.use_vertex_groups = True
    return {
        "unweighted_vertices": unweighted,
        "minimum_weight_total": min(weight_totals),
        "maximum_weight_total": max(weight_totals),
        "maximum_influences": max(
            len(vertex.groups) for vertex in vest.data.vertices
        ),
    }


def make_exposed_body(
    body: bpy.types.Object,
    armature: bpy.types.Object,
) -> tuple[bpy.types.Object, list[int]]:
    exposed = body.copy()
    exposed.data = body.data.copy()
    exposed.name = "BodyExposedForCowboyVest"
    exposed.data.name = "BodyExposedForCowboyVestMesh"
    bpy.context.scene.collection.objects.link(exposed)

    depsgraph = bpy.context.evaluated_depsgraph_get()
    evaluated_object = body.evaluated_get(depsgraph)
    evaluated_mesh = evaluated_object.to_mesh()
    if len(evaluated_mesh.polygons) != len(body.data.polygons):
        evaluated_object.to_mesh_clear()
        raise RuntimeError("Armature evaluation unexpectedly changed body topology")

    hidden_faces = []
    for polygon in evaluated_mesh.polygons:
        points = [
            body.matrix_world @ evaluated_mesh.vertices[index].co
            for index in polygon.vertices
        ]
        center = sum(points, Vector()) / len(points)
        safely_covered = (
            COVERAGE_HEIGHT_MIN <= center.z <= COVERAGE_HEIGHT_MAX
            and abs(center.x) <= COVERAGE_HALF_WIDTH
            and center.y >= COVERAGE_BACK_Y
        )
        if safely_covered:
            hidden_faces.append(polygon.index)
    evaluated_object.to_mesh_clear()

    activate_only(exposed)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    hidden_set = set(hidden_faces)
    for polygon in exposed.data.polygons:
        polygon.select = polygon.index in hidden_set
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.delete(type="VERT")
    bpy.ops.object.mode_set(mode="OBJECT")

    if not hidden_faces:
        raise RuntimeError("Coverage mask did not remove any body faces")
    if not any(modifier.type == "ARMATURE" for modifier in exposed.modifiers):
        modifier = exposed.modifiers.new("PlayerArmature", "ARMATURE")
        modifier.object = armature
    return exposed, hidden_faces


def add_review_stage() -> tuple[bpy.types.Object, list[bpy.types.Object]]:
    center = Vector((0.0, 0.0, -0.08))
    bpy.ops.object.camera_add(location=(1.10, -1.80, 0.65))
    camera = bpy.context.object
    camera.name = "ReviewCamera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = 1.05
    camera.rotation_euler = (
        center - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    bpy.context.scene.camera = camera

    lights = []
    for name, location, energy, size in [
        ("ReviewKey", (1.5, -1.5, 2.0), 800.0, 2.5),
        ("ReviewFill", (-1.0, 0.8, 1.0), 350.0, 2.5),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.name = name
        light.data.energy = energy
        light.data.size = size
        light.rotation_euler = (
            center - light.location
        ).to_track_quat("-Z", "Y").to_euler()
        lights.append(light)

    world = bpy.data.worlds.new("CowboyVestReviewWorld")
    bpy.context.scene.world = world
    world.color = (0.04, 0.04, 0.04)
    return camera, lights


def render(path: Path) -> None:
    scene = bpy.context.scene
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def main() -> None:
    if not SOURCE.is_file() or not PLAYER.is_file():
        raise FileNotFoundError("Cowboy vest source or current player GLB is missing")
    source_hash = sha256(SOURCE)
    if source_hash != EXPECTED_SOURCE_SHA256:
        raise RuntimeError(
            f"Cowboy vest source changed: expected {EXPECTED_SOURCE_SHA256}, "
            f"found {source_hash}"
        )

    WORK_DIR.mkdir(parents=True, exist_ok=True)
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(PLAYER))

    armature = next(
        obj for obj in bpy.context.scene.objects if obj.type == "ARMATURE"
    )
    body = max(
        (obj for obj in bpy.context.scene.objects if obj.type == "MESH"),
        key=lambda obj: len(obj.data.polygons),
    )
    armature.data.pose_position = "REST"
    bpy.context.scene.frame_set(0)
    bpy.context.view_layer.update()

    vest = import_new_mesh(SOURCE)
    before = stats(vest)
    world = vest.matrix_world.copy()
    vest.parent = None
    vest.matrix_world = world
    vest.scale = FIT_SCALE
    vest.location = FIT_LOCATION
    vest.name = "CowboyVest"
    vest.data.name = "CowboyVestMesh"
    activate_only(vest)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    smooth_garment(vest)
    shoulder_vertices = add_shoulder_clearance(vest)

    body_reference = evaluated_rest_reference(body)
    weight_report = transfer_weights(body_reference, vest, armature)
    exposed_body, hidden_faces = make_exposed_body(body, armature)

    bpy.ops.object.select_all(action="DESELECT")
    for obj in [armature, vest, exposed_body]:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = armature
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT),
        export_format="GLB",
        use_selection=True,
        export_yup=True,
        export_animations=False,
        export_skins=True,
        export_def_bones=True,
        export_materials="EXPORT",
        export_tangents=True,
        export_lights=False,
        export_cameras=False,
    )

    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(BLEND))

    body.hide_render = True
    body_reference.hide_render = True
    camera, _lights = add_review_stage()
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = 700
    scene.render.resolution_y = 700
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"

    armature.data.pose_position = "REST"
    bpy.context.view_layer.update()
    render(REST_FRONT)

    camera.location = Vector((-1.10, 1.80, 0.65))
    camera.rotation_euler = (
        Vector((0.0, 0.0, -0.08)) - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    render(REST_BACK)

    armature.data.pose_position = "POSE"
    bpy.context.scene.frame_set(48)
    camera.location = Vector((1.10, -1.80, 0.65))
    camera.rotation_euler = (
        Vector((0.0, 0.0, 0.02)) - camera.location
    ).to_track_quat("-Z", "Y").to_euler()
    camera.data.ortho_scale = 1.25
    render(IDLE_DEFORM)

    report = {
        "source": str(SOURCE.relative_to(ROOT)),
        "source_sha256": source_hash,
        "player_reference": str(PLAYER.relative_to(ROOT)),
        "output": str(OUTPUT.relative_to(ROOT)),
        "output_sha256": sha256(OUTPUT),
        "blend": str(BLEND.relative_to(ROOT)),
        "fit": {
            "scale": list(FIT_SCALE),
            "location_blender": list(FIT_LOCATION),
            "shoulder_clearance": {
                "adjusted_vertices": shoulder_vertices,
                "minimum_height": SHOULDER_CLEARANCE_MIN_HEIGHT,
                "minimum_half_width": SHOULDER_CLEARANCE_MIN_WIDTH,
                "normal_offset": SHOULDER_NORMAL_OFFSET,
                "lateral_overlap": SHOULDER_LATERAL_OVERLAP,
            },
        },
        "weight_transfer": {
            "mapping": "POLYINTERP_NEAREST",
            **weight_report,
        },
        "body_coverage": {
            "hidden_face_count": len(hidden_faces),
            "height": [COVERAGE_HEIGHT_MIN, COVERAGE_HEIGHT_MAX],
            "half_width": COVERAGE_HALF_WIDTH,
            "back_y": COVERAGE_BACK_Y,
            "selection": "polygon centers inside back-torso bounds",
        },
        "before": before,
        "after": stats(vest),
        "exposed_body": stats(exposed_body),
        "previews": [
            str(REST_FRONT.relative_to(ROOT)),
            str(REST_BACK.relative_to(ROOT)),
            str(IDLE_DEFORM.relative_to(ROOT)),
        ],
    }
    REPORT.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print("COWBOY_VEST_PROCESS_REPORT=" + json.dumps(report))


if __name__ == "__main__":
    main()
