"""Blender --background --python tools/build_copper_icon.py: transparent copper ore icon.

A simplified chunk using the deposit's copper and green mineral materials.
"""
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import ROOT, PALETTE, reset_scene, material, mix, block

reset_scene()
ore = material('Copper ore', mix(PALETTE['terracotta'], PALETTE['amber'], .48))
mineral = material('Green copper mineral', mix(PALETTE['teal'], PALETTE['pine'], .35))
block('Copper chunk', (0, 0, 0), (.8, .65, .6), ore,
      cuts=[((0, -.22, .3), (.2, -.8, .4))], cut_mat=mineral)
block('Copper chip', (.42, -.18, 0), (.30, .28, .24), ore)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 40
scene.cycles.use_denoising = True
scene.render.film_transparent = True
scene.world.color = (.25, .25, .25)
bpy.ops.object.camera_add(location=(-2.2, -3.5, 3.0))
scene.camera = bpy.context.object
scene.camera.rotation_euler = (Vector((.1, 0, .27)) - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera.data.type = 'ORTHO'
scene.camera.data.ortho_scale = 1.5
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
scene.render.filepath = str(ROOT / 'assets/icons/copper_ore.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art/blender/copper_ore_icon.blend'))
bpy.ops.render.render(write_still=True)
