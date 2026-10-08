"""Blender --background --python tools/build_boat_icon.py: transparent boat action icon.

The salvage skiff (tools/build_salvage_skiff.py), imported from its exported model and rendered
with the copper ore icon's camera and lighting, for the Pilot boat and Disembark actions. The
command bar crosses the icon out for Disembark (ActionBar's cancel overlay).
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import ROOT, reset_scene

CAMERA_SWING = 15  # degrees counter-clockwise (seen from above) from the copper icon's camera
MARGIN = .09  # each side, of the icon's width (docs/icons-and-2d-art.md: 8-12%)

reset_scene()
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/models/boats/salvage_skiff.glb'))
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.world.color = (.25, .25, .25)
# The copper icon's camera, swung round the boat so its bow points to the viewer's right, where it
# reads by its bow plate and stern drive.
swing = math.radians(CAMERA_SWING)
camera = Vector((-2.2, -3.5, 4.2))
camera.xy = (camera.x * math.cos(swing) - camera.y * math.sin(swing), camera.x * math.sin(swing) + camera.y * math.cos(swing))
bpy.ops.object.camera_add(location=camera)
scene.camera = bpy.context.object
scene.camera.rotation_euler = (Vector((0, 0, 0)) - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera.data.type = 'ORTHO'
# Frame the boat's bounds as the camera sees them, centred, with the icon guide's margin.
bpy.context.view_layer.update()
to_view = scene.camera.matrix_world.inverted()
points = [to_view @ (obj.matrix_world @ v.co) for obj in scene.objects if obj.type == 'MESH' for v in obj.data.vertices]
low = Vector((min(p.x for p in points), min(p.y for p in points)))
high = Vector((max(p.x for p in points), max(p.y for p in points)))
size = max(high.x - low.x, high.y - low.y) / (1 - 2 * MARGIN)
scene.camera.data.ortho_scale = size
scene.camera.data.shift_x = (low.x + high.x) / 2 / size
scene.camera.data.shift_y = (low.y + high.y) / 2 / size
for loc, energy, size in [((-3, -4, 7), 650, 5), ((4, -1, 4), 400, 4)]:
    bpy.ops.object.light_add(type='AREA', location=loc)
    light = bpy.context.object
    light.data.energy = energy
    light.data.size = size
    light.rotation_euler = (Vector((0, 0, .3)) - light.location).to_track_quat('-Z', 'Y').to_euler()
scene.view_settings.view_transform = 'AgX'
scene.render.resolution_x = scene.render.resolution_y = 256
scene.render.resolution_percentage = 100
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.render.filepath = str(ROOT / 'assets/icons/boat.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art/blender/boat_icon.blend'))
bpy.ops.render.render(write_still=True)
