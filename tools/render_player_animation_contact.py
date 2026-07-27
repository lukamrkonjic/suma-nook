"""Render a neutral contact sheet source sequence for animation timing review.

Usage:
  blender --background --python tools/render_player_animation_contact.py -- \
    input.glb output_directory 12
"""

import math
import os
import sys

import bpy
from mathutils import Vector


def look_at(camera, target):
    direction = target - camera.location
    camera.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def visual_bounds():
    points = []
    for obj in bpy.context.scene.objects:
        if obj.type != "MESH":
            continue
        points.extend(obj.matrix_world @ Vector(corner) for corner in obj.bound_box)
    minimum = Vector((min(point.x for point in points), min(point.y for point in points), min(point.z for point in points)))
    maximum = Vector((max(point.x for point in points), max(point.y for point in points), max(point.z for point in points)))
    return minimum, maximum


argv = sys.argv[sys.argv.index("--") + 1 :]
source_path = os.path.abspath(argv[0])
output_directory = os.path.abspath(argv[1])
sample_count = max(3, int(argv[2]) if len(argv) > 2 else 12)
os.makedirs(output_directory, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=source_path)
scene = bpy.context.scene
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 420
scene.render.resolution_y = 420
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
if scene.world is None:
    scene.world = bpy.data.worlds.new("ContactWorld")
scene.world.color = (0.18, 0.20, 0.23)

minimum, maximum = visual_bounds()
center = (minimum + maximum) * 0.5
height = max(0.1, maximum.z - minimum.z)

camera_data = bpy.data.cameras.new("ContactCamera")
camera = bpy.data.objects.new("ContactCamera", camera_data)
scene.collection.objects.link(camera)
scene.camera = camera
camera.data.type = "ORTHO"
camera.data.ortho_scale = height * 1.45
camera.location = center + Vector((height * 1.4, -height * 2.2, height * 0.75))
look_at(camera, center + Vector((0.0, 0.0, height * 0.02)))

key = bpy.data.lights.new("Key", "AREA")
key.energy = 700
key.shape = "DISK"
key.size = height * 4.0
key_obj = bpy.data.objects.new("Key", key)
scene.collection.objects.link(key_obj)
key_obj.location = center + Vector((-height * 2.0, -height * 2.0, height * 3.0))

fill = bpy.data.lights.new("Fill", "AREA")
fill.energy = 350
fill.size = height * 3.0
fill_obj = bpy.data.objects.new("Fill", fill)
scene.collection.objects.link(fill_obj)
fill_obj.location = center + Vector((height * 2.0, height, height * 2.0))

start = scene.frame_start
end = scene.frame_end
for sample_index in range(sample_count):
    ratio = sample_index / float(sample_count - 1)
    frame = round(start + (end - start) * ratio)
    scene.frame_set(frame)
    scene.render.filepath = os.path.join(
        output_directory,
        f"{sample_index:02d}_frame_{frame:04d}.png",
    )
    bpy.ops.render.render(write_still=True)
    print(f"CONTACT_RENDER frame={frame} path={scene.render.filepath}")
