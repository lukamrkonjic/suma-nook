#!/usr/bin/env python3
"""Narrow Modly GLB import → smooth → export → re-import experiment.

This script is intentionally self-contained in tests/modly_blender_smoothing.
It does not read or alter Suma Nook's asset registries or production pipeline.
"""

import hashlib
import json
import math
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Vector


ANGLE_DEGREES = 40.0
RENDER_SIZE = 900
HELPER_PREFIX = "TEST_"


def json_vector(value):
    return [round(float(component), 6) for component in value]


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in (
        bpy.data.meshes,
        bpy.data.curves,
        bpy.data.armatures,
        bpy.data.materials,
        bpy.data.images,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for datablock in list(collection):
            if datablock.users == 0:
                collection.remove(datablock)


def scene_asset_objects():
    return [
        obj for obj in bpy.context.scene.objects
        if not obj.name.startswith(HELPER_PREFIX)
    ]


def mesh_objects(objects):
    return [obj for obj in objects if obj.type == "MESH" and obj.data is not None]


def world_bounds(objects):
    corners = []
    for obj in mesh_objects(objects):
        corners.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    if not corners:
        return Vector((-0.5, -0.5, 0.0)), Vector((0.5, 0.5, 1.0))
    low = Vector(tuple(min(point[index] for point in corners) for index in range(3)))
    high = Vector(tuple(max(point[index] for point in corners) for index in range(3)))
    return low, high


def hierarchy_record(obj):
    return {
        "name": obj.name,
        "type": obj.type,
        "children": [hierarchy_record(child) for child in obj.children],
    }


def connected_component_count(mesh):
    vertex_count = len(mesh.vertices)
    if vertex_count == 0:
        return 0, 0
    parent = list(range(vertex_count))
    used = [False] * vertex_count

    def find(index):
        while parent[index] != index:
            parent[index] = parent[parent[index]]
            index = parent[index]
        return index

    def union(left, right):
        root_left = find(left)
        root_right = find(right)
        if root_left != root_right:
            parent[root_right] = root_left

    for edge in mesh.edges:
        left, right = edge.vertices
        used[left] = True
        used[right] = True
        union(left, right)
    for polygon in mesh.polygons:
        vertices = polygon.vertices
        if not vertices:
            continue
        first = vertices[0]
        used[first] = True
        for vertex in vertices[1:]:
            used[vertex] = True
            union(first, vertex)
    roots = {find(index) for index, is_used in enumerate(used) if is_used}
    isolated = sum(1 for is_used in used if not is_used)
    return len(roots) + isolated, isolated


def edge_topology(mesh):
    bm = bmesh.new()
    bm.from_mesh(mesh)
    non_manifold = sum(1 for edge in bm.edges if not edge.is_manifold)
    boundary = sum(1 for edge in bm.edges if edge.is_boundary)
    wire = sum(1 for edge in bm.edges if edge.is_wire)
    bm.free()
    return non_manifold, boundary, wire


def normal_health(mesh):
    invalid = 0
    total = 0
    try:
        normals = mesh.corner_normals
    except AttributeError:
        normals = mesh.vertex_normals
    for item in normals:
        vector = item.vector
        total += 1
        if (
            vector.length_squared < 1e-12
            or not all(math.isfinite(component) for component in vector)
        ):
            invalid += 1
    return total, invalid


def texture_records(material):
    records = []
    if material is None or not material.use_nodes or material.node_tree is None:
        return records
    for node in material.node_tree.nodes:
        if node.type != "TEX_IMAGE":
            continue
        image = node.image
        if image is None:
            records.append({"node": node.name, "missing_image": True})
            continue
        resolved = Path(bpy.path.abspath(image.filepath)) if image.filepath else None
        records.append({
            "node": node.name,
            "image": image.name,
            "size": [int(image.size[0]), int(image.size[1])],
            "packed": bool(image.packed_file),
            "filepath": image.filepath,
            "external_file_exists": bool(resolved and resolved.exists()),
            "colorspace": image.colorspace_settings.name,
        })
    return records


def inspect_asset(label, source_path):
    objects = scene_asset_objects()
    meshes = mesh_objects(objects)
    low, high = world_bounds(objects)
    dimensions = high - low
    mesh_reports = []
    total_vertices = total_edges = total_faces = total_triangles = 0
    total_components = total_non_manifold = total_invalid_normals = 0
    total_smooth_faces = 0
    material_names = set()
    texture_count = 0
    duplicate_signatures = {}

    for obj in meshes:
        mesh = obj.data
        mesh.calc_loop_triangles()
        components, isolated = connected_component_count(mesh)
        non_manifold, boundary, wire = edge_topology(mesh)
        normal_count, invalid_normals = normal_health(mesh)
        smooth_faces = sum(1 for polygon in mesh.polygons if polygon.use_smooth)
        materials = []
        for slot in obj.material_slots:
            material = slot.material
            if material is None:
                materials.append({"missing": True})
                continue
            material_names.add(material.name)
            textures = texture_records(material)
            texture_count += len(textures)
            materials.append({
                "name": material.name,
                "use_nodes": bool(material.use_nodes),
                "alpha": round(float(material.diffuse_color[3]), 6),
                "surface_render_method": getattr(
                    material,
                    "surface_render_method",
                    getattr(material, "blend_method", "OPAQUE"),
                ),
                "textures": textures,
            })
        signature = (
            len(mesh.vertices),
            len(mesh.edges),
            len(mesh.polygons),
            tuple(round(value, 5) for row in obj.matrix_world for value in row),
        )
        duplicate_signatures.setdefault(str(signature), []).append(obj.name)
        report = {
            "object": obj.name,
            "mesh": mesh.name,
            "vertices": len(mesh.vertices),
            "edges": len(mesh.edges),
            "faces": len(mesh.polygons),
            "triangles": len(mesh.loop_triangles),
            "connected_components": components,
            "isolated_vertices": isolated,
            "non_manifold_edges": non_manifold,
            "boundary_edges": boundary,
            "wire_edges": wire,
            "normal_samples": normal_count,
            "invalid_normals": invalid_normals,
            "smooth_faces": smooth_faces,
            "material_slots": materials,
            "location": json_vector(obj.location),
            "rotation_degrees": json_vector(
                tuple(math.degrees(value) for value in obj.rotation_euler)
            ),
            "scale": json_vector(obj.scale),
            "dimensions": json_vector(obj.dimensions),
        }
        mesh_reports.append(report)
        total_vertices += report["vertices"]
        total_edges += report["edges"]
        total_faces += report["faces"]
        total_triangles += report["triangles"]
        total_components += components
        total_non_manifold += non_manifold
        total_invalid_normals += invalid_normals
        total_smooth_faces += smooth_faces

    roots = [obj for obj in objects if obj.parent is None]
    duplicate_groups = [
        names for names in duplicate_signatures.values() if len(names) > 1
    ]
    extreme_scale_objects = [
        obj.name for obj in objects
        if any(abs(value) < 0.01 or abs(value) > 100.0 for value in obj.scale)
    ]
    origins_far_from_geometry = []
    diagonal = max(dimensions.length, 1e-6)
    bounds_center = (low + high) * 0.5
    for obj in meshes:
        if (obj.matrix_world.translation - bounds_center).length > diagonal * 2.0:
            origins_far_from_geometry.append(obj.name)

    return {
        "label": label,
        "source": str(source_path),
        "object_count": len(objects),
        "mesh_object_count": len(meshes),
        "empty_count": sum(1 for obj in objects if obj.type == "EMPTY"),
        "armature_count": sum(1 for obj in objects if obj.type == "ARMATURE"),
        "material_count": len(material_names),
        "texture_node_count": texture_count,
        "bounds_min": json_vector(low),
        "bounds_max": json_vector(high),
        "dimensions": json_vector(dimensions),
        "origin_to_ground_delta": round(abs(float(low.z)), 6),
        "totals": {
            "vertices": total_vertices,
            "edges": total_edges,
            "faces": total_faces,
            "triangles": total_triangles,
            "connected_components": total_components,
            "non_manifold_edges": total_non_manifold,
            "invalid_normals": total_invalid_normals,
            "smooth_faces": total_smooth_faces,
        },
        "extreme_scale_objects": extreme_scale_objects,
        "origins_far_from_geometry": origins_far_from_geometry,
        "exact_duplicate_object_groups": duplicate_groups,
        "hierarchy": [hierarchy_record(root) for root in roots],
        "meshes": mesh_reports,
    }


def make_material(name, color, roughness):
    material = bpy.data.materials.new(name)
    material.diffuse_color = (*color, 1.0)
    material.use_nodes = True
    bsdf = material.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return material


def look_at(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat("-Z", "Y").to_euler()


def setup_render(objects):
    low, high = world_bounds(objects)
    dimensions = high - low
    center = (low + high) * 0.5
    max_dimension = max(max(dimensions), 0.5)

    ground_material = make_material(
        HELPER_PREFIX + "GroundMaterial", (0.32, 0.32, 0.32), 0.95
    )
    bpy.ops.mesh.primitive_plane_add(
        size=max_dimension * 5.0,
        location=(center.x, center.y, low.z - max_dimension * 0.003),
    )
    ground = bpy.context.object
    ground.name = HELPER_PREFIX + "Ground"
    ground.data.materials.append(ground_material)

    target = Vector((center.x, center.y, low.z + dimensions.z * 0.48))
    direction = Vector((1.55, -1.8, 1.18)).normalized()
    camera_distance = max_dimension * 4.2
    bpy.ops.object.camera_add(location=target + direction * camera_distance)
    camera = bpy.context.object
    camera.name = HELPER_PREFIX + "Camera"
    camera.data.type = "ORTHO"
    camera.data.ortho_scale = max(
        dimensions.z * 1.24,
        max(dimensions.x, dimensions.y) * 1.75,
        1.0,
    )
    camera.data.lens = 50
    look_at(camera, target)
    bpy.context.scene.camera = camera

    bpy.ops.object.light_add(
        type="AREA",
        location=target + Vector((-1.8, -2.3, 3.6)).normalized() * max_dimension * 3.2,
    )
    key = bpy.context.object
    key.name = HELPER_PREFIX + "Key"
    key.data.energy = 900.0
    key.data.shape = "DISK"
    key.data.size = max_dimension * 2.2
    look_at(key, target)

    bpy.ops.object.light_add(
        type="AREA",
        location=target + Vector((2.4, 1.3, 2.0)).normalized() * max_dimension * 2.8,
    )
    fill = bpy.context.object
    fill.name = HELPER_PREFIX + "Fill"
    fill.data.energy = 500.0
    fill.data.size = max_dimension * 2.4
    look_at(fill, target)

    world = bpy.context.scene.world
    world.use_nodes = True
    background = world.node_tree.nodes["Background"]
    background.inputs["Color"].default_value = (0.22, 0.22, 0.22, 1.0)
    background.inputs["Strength"].default_value = 0.7

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x = RENDER_SIZE
    scene.render.resolution_y = RENDER_SIZE
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.look = "AgX - Medium High Contrast"
    return [ground, camera, key, fill]


def render(path):
    scene = bpy.context.scene
    scene.render.filepath = str(path)
    bpy.ops.render.render(write_still=True)


def remove_helpers():
    helpers = [
        obj for obj in bpy.context.scene.objects
        if obj.name.startswith(HELPER_PREFIX)
    ]
    bpy.ops.object.select_all(action="DESELECT")
    for obj in helpers:
        obj.select_set(True)
    if helpers:
        bpy.context.view_layer.objects.active = helpers[0]
        bpy.ops.object.delete(use_global=False)


def apply_conservative_smoothing(objects):
    meshes = mesh_objects(objects)
    bpy.ops.object.select_all(action="DESELECT")
    for obj in meshes:
        obj.select_set(True)
    if not meshes:
        return {"operator": "none", "result": ["NO_MESHES"], "normals_recalculated": []}
    bpy.context.view_layer.objects.active = meshes[0]
    result = bpy.ops.object.shade_smooth_by_angle(
        angle=math.radians(ANGLE_DEGREES),
        keep_sharp_edges=True,
    )
    recalculated = []
    for obj in meshes:
        _, invalid = normal_health(obj.data)
        if invalid == 0:
            continue
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()
        recalculated.append(obj.name)
    return {
        "operator": "bpy.ops.object.shade_smooth_by_angle",
        "angle_degrees": ANGLE_DEGREES,
        "keep_sharp_edges": True,
        "result": sorted(result),
        "normals_recalculated": recalculated,
    }


def select_for_export(objects):
    bpy.ops.object.select_all(action="DESELECT")
    selectable = [obj for obj in objects if obj.name in bpy.context.scene.objects]
    for obj in selectable:
        obj.select_set(True)
    if selectable:
        bpy.context.view_layer.objects.active = selectable[0]
    return selectable


def export_glb(path, objects):
    selected = select_for_export(objects)
    bpy.ops.export_scene.gltf(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=False,
        export_yup=True,
        export_extras=True,
    )
    return len(selected)


def create_comparison(before_path, after_path, output_path):
    try:
        import numpy as np
    except ImportError:
        return False
    before = bpy.data.images.load(str(before_path), check_existing=False)
    after = bpy.data.images.load(str(after_path), check_existing=False)
    width, height = before.size
    before_pixels = np.array(before.pixels[:], dtype=np.float32).reshape((height, width, 4))
    after_pixels = np.array(after.pixels[:], dtype=np.float32).reshape((height, width, 4))
    divider = np.full((height, 8, 4), (0.12, 0.12, 0.12, 1.0), dtype=np.float32)
    combined_pixels = np.concatenate((before_pixels, divider, after_pixels), axis=1)
    combined = bpy.data.images.new(
        output_path.stem,
        width=combined_pixels.shape[1],
        height=height,
        alpha=True,
        float_buffer=False,
    )
    combined.pixels.foreach_set(combined_pixels.ravel())
    combined.filepath_raw = str(output_path)
    combined.file_format = "PNG"
    combined.save()
    bpy.data.images.remove(before)
    bpy.data.images.remove(after)
    bpy.data.images.remove(combined)
    return True


def pixel_difference(path_a, path_b):
    try:
        import numpy as np
    except ImportError:
        return None
    image_a = bpy.data.images.load(str(path_a), check_existing=False)
    image_b = bpy.data.images.load(str(path_b), check_existing=False)
    if tuple(image_a.size) != tuple(image_b.size):
        return None
    pixels_a = np.array(image_a.pixels[:], dtype=np.float32)
    pixels_b = np.array(image_b.pixels[:], dtype=np.float32)
    difference = np.abs(pixels_a - pixels_b)
    result = {
        "mean_absolute_difference": round(float(difference.mean()), 8),
        "maximum_absolute_difference": round(float(difference.max()), 8),
    }
    bpy.data.images.remove(image_a)
    bpy.data.images.remove(image_b)
    return result


def validation_summary(before, after, reimported, after_render, reimport_render):
    before_totals = before["totals"]
    after_totals = after["totals"]
    reimported_totals = reimported["totals"]
    bounds_delta = max(
        abs(left - right)
        for left, right in zip(after["dimensions"], reimported["dimensions"])
    )
    return {
        "polygon_count_preserved_by_smoothing": (
            before_totals["triangles"] == after_totals["triangles"]
        ),
        "polygon_count_preserved_by_export": (
            after_totals["triangles"] == reimported_totals["triangles"]
        ),
        "mesh_count_preserved": (
            after["mesh_object_count"] == reimported["mesh_object_count"]
        ),
        "material_count_preserved": (
            after["material_count"] == reimported["material_count"]
        ),
        "texture_assignments_preserved": (
            after["texture_node_count"] == reimported["texture_node_count"]
        ),
        "maximum_dimension_delta": round(bounds_delta, 8),
        "scale_orientation_bounds_preserved": bounds_delta < 0.0001,
        "smoothed_faces_after_export": reimported_totals["smooth_faces"],
        "smoothing_survived_export": reimported_totals["smooth_faces"] > 0,
        "render_pixel_difference": pixel_difference(after_render, reimport_render),
    }


def process_asset(root, name):
    source = root / "source_copies" / f"{name}_original.glb"
    before_render = root / "renders" / f"{name}_before.png"
    after_render = root / "renders" / f"{name}_after.png"
    comparison_render = root / "renders" / f"{name}_comparison.png"
    reimport_render = root / "renders" / f"{name}_reimport.png"
    export_path = root / "exports" / f"{name}_smooth_test.glb"
    blend_path = root / "blender_scenes" / f"{name}_smooth_test.blend"

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(source))
    imported_objects = scene_asset_objects()
    before = inspect_asset("original_import", source)

    setup_render(imported_objects)
    render(before_render)
    smoothing = apply_conservative_smoothing(imported_objects)
    render(after_render)
    create_comparison(before_render, after_render, comparison_render)
    remove_helpers()

    after = inspect_asset("after_smoothing", source)
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    selected_count = export_glb(export_path, imported_objects)

    clear_scene()
    bpy.ops.import_scene.gltf(filepath=str(export_path))
    reimported_objects = scene_asset_objects()
    reimported = inspect_asset("fresh_reimport", export_path)
    setup_render(reimported_objects)
    render(reimport_render)
    remove_helpers()

    return {
        "asset": name,
        "working_copy": str(source),
        "working_copy_bytes": source.stat().st_size,
        "working_copy_sha256": sha256(source),
        "before_render": str(before_render),
        "after_render": str(after_render),
        "comparison_render": str(comparison_render),
        "exported_glb": str(export_path),
        "exported_glb_bytes": export_path.stat().st_size,
        "exported_glb_sha256": sha256(export_path),
        "reimport_render": str(reimport_render),
        "blend_scene": str(blend_path),
        "exported_selected_object_count": selected_count,
        "smoothing": smoothing,
        "original_import": before,
        "after_smoothing": after,
        "fresh_reimport": reimported,
        "validation": validation_summary(
            before, after, reimported, after_render, reimport_render
        ),
    }


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if len(argv) != 1:
        raise SystemExit(
            "usage: blender --background --python run_smoothing_test.py -- <experiment_dir>"
        )
    root = Path(argv[0]).resolve()
    for subdirectory in ("renders", "exports", "reports", "blender_scenes"):
        (root / subdirectory).mkdir(parents=True, exist_ok=True)
    report = {
        "experiment": "Modly Blender conservative smoothing",
        "blender_version": bpy.app.version_string,
        "angle_degrees": ANGLE_DEGREES,
        "assets": [],
    }
    for name in ("tree1", "tree2"):
        print(f"[modly-test] processing {name}")
        report["assets"].append(process_asset(root, name))
    report_path = root / "reports" / "inspection_report.json"
    report_path.write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"[modly-test] report {report_path}")
    print("MODLY SMOOTHING TEST COMPLETE")


if __name__ == "__main__":
    main()
