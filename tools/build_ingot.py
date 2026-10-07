"""Render a transparent ingot inventory icon from the workshop model palette.

blender --background --python tools/build_ingot.py -- [iron|copper]
"""
import sys
from pathlib import Path
import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import PALETTE, ROOT, reset_scene, material, mix, prism_y, export

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
METAL = args[0] if args else 'iron'
# Copper matches the copper deposit's seams (tools/build_deposit.py) and ore icon.
COLORS = {
    'iron': PALETTE['steel'],
    'copper': mix(PALETTE['terracotta'], PALETTE['amber'], .48),
}
NAME = METAL + '_ingot'
LABEL = METAL.capitalize() + ' ingot'

reset_scene()
metal = material(LABEL, COLORS[METAL])
prism_y(LABEL, [(-.32, 0), (.32, 0), (.24, .24), (-.24, .24)], -.65, .65, metal)
export(NAME, folder='assets/models/resources', join_label=LABEL)
scene = bpy.context.scene
scene.render.engine = 'CYCLES'
scene.cycles.samples = 32
scene.render.resolution_x = 256
scene.render.resolution_y = 256
scene.render.resolution_percentage = 100
scene.render.film_transparent = True
scene.render.image_settings.file_format = 'PNG'
scene.render.image_settings.color_mode = 'RGBA'
scene.world.color = (.3, .3, .3)
scene.view_settings.view_transform = 'Standard'
for name, location, energy, size in [('Key', (-3, -4, 6), 500, 4), ('Fill', (4, 1, 4), 250, 3)]:
    light = bpy.data.lights.new(name, 'AREA')
    light.energy = energy
    light.shape = 'DISK'
    light.size = size
    obj = bpy.data.objects.new(name, light)
    scene.collection.objects.link(obj)
    obj.location = location
    obj.rotation_euler = (Vector((0, 0, .12)) - obj.location).to_track_quat('-Z', 'Y').to_euler()
camera = bpy.data.objects.new('Icon camera', bpy.data.cameras.new('Icon camera'))
scene.collection.objects.link(camera)
camera.location = (2.5, -3.5, 3)
camera.rotation_euler = (Vector((0, 0, .12)) - camera.location).to_track_quat('-Z', 'Y').to_euler()
camera.data.type = 'ORTHO'
camera.data.ortho_scale = 1.75
scene.camera = camera
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art/blender' / (NAME + '.blend')))
scene.render.filepath = str(ROOT / 'assets/icons' / (NAME + '.png'))
bpy.ops.render.render(write_still=True)
