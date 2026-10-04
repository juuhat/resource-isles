"""Blender --background --python tools/build_burner_generator.py: model, source and preview.

Burner generator, workbench style (docs/building-style-palette.md): no roof; the machine is the
building. Its signature is a compact vertical furnace, a stone firebox with a glowing mouth
turned to the yard, an iron boiler drum on top and a tall chimney, read from across the map.
Steam piped from the boiler drives the teal dynamo on the right; the split firewood it burns is
stacked on the left.

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile, front toward -Y). Everything
stands in the back of the tile, leaving an open work yard with the robot's work spot 0.30 tiles
forward of centre, facing the firebox.
"""
import sys
from pathlib import Path

import bpy

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, box, cylinder, beam, log, marker,
                         export, render_preview)

reset_scene()

wood = material('Timber', PALETTE['timber'])
end = material('Cut wood', PALETTE['cut_wood'])
plank = material('Planks', PALETTE['plank'])
stone = material('Stone', PALETTE['stone'])
stone_dark = material('Dark stone', PALETTE['stone_dark'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
shaft = material('Firebox', PALETTE['shaft'])
teal = material('Teal', PALETTE['teal'])
amber = material('Amber', PALETTE['amber'])

T = TILE

# Stone firebox, the furnace's base: a squat block with a darker capstone slab. Its front face
# is at FRONT_Y, the furnace mouth on it facing the yard.
FX, FY, FIRE_H = -.08, .32, .44
FIRE_W, FIRE_D = .46, .48
FRONT_Y = FY - FIRE_D / 2
box('Firebox', (FX, FY, FIRE_H / 2), (FIRE_W, FIRE_D, FIRE_H), stone)
box('Capstone', (FX, FY, FIRE_H + .025), (FIRE_W + .06, FIRE_D + .06, .05), stone_dark)

# The mouth: an iron frame around a dark opening with the fire glowing low inside.
MOUTH_Z = .18
box('Mouth frame', (FX, FRONT_Y - .012, MOUTH_Z), (.32, .03, .26), dark)
box('Mouth', (FX, FRONT_Y - .03, MOUTH_Z), (.24, .01, .18), shaft)
box('Fire', (FX, FRONT_Y - .036, MOUTH_Z - .03), (.20, .01, .11), amber)
box('Ash door', (FX, FRONT_Y - .012, .045), (.22, .03, .05), dark)

# Boiler drum standing on the firebox, banded in steel, with a lid and the chimney rising
# from its back half — the tallest thing on the tile.
DRUM_R, DRUM_Z0, DRUM_Z1 = .19, FIRE_H + .05, .86
cylinder('Boiler drum', (FX, FY, DRUM_Z0), (FX, FY, DRUM_Z1), DRUM_R, dark)
for z in [DRUM_Z0 + .07, DRUM_Z1 - .07]:
    cylinder('Drum band', (FX, FY, z - .02), (FX, FY, z + .02), DRUM_R + .012, steel)
cylinder('Drum lid', (FX, FY, DRUM_Z1), (FX, FY, DRUM_Z1 + .04), DRUM_R * .8, steel)
CX, CY, CHIMNEY_TOP = FX, FY + .05, 1.19
cylinder('Chimney', (CX, CY, DRUM_Z1), (CX, CY, CHIMNEY_TOP), .075, dark)
cylinder('Chimney cap', (CX, CY, CHIMNEY_TOP - .04), (CX, CY, CHIMNEY_TOP + .01), .10, steel)
cylinder('Flue', (CX, CY, CHIMNEY_TOP + .01), (CX, CY, CHIMNEY_TOP + .014), .06, shaft)

# Teal dynamo on the right: a fat drum lying along X on an iron cradle, fed by a steam pipe
# from the boiler, with the amber power light on its top.
GX0, GX1, GY, GZ, GR = .22, .52, .32, .23, .17
GX = (GX0 + GX1) / 2
for x in [GX0 + .06, GX1 - .06]:
    box('Dynamo cradle', (x, GY, .05), (.06, .30, .10), dark)
cylinder('Dynamo', (GX0, GY, GZ), (GX1, GY, GZ), GR, teal)
for x0, x1 in [(GX0 - .02, GX0), (GX1, GX1 + .02)]:
    cylinder('Dynamo end cap', (x0, GY, GZ), (x1, GY, GZ), GR * .7, dark)
PIPE_Z = .70
cylinder('Steam pipe', (FX + DRUM_R - .02, FY, PIPE_Z), (GX0 + .06, GY, PIPE_Z), .04, steel)
cylinder('Steam pipe', (GX0 + .06, GY, PIPE_Z + .04), (GX0 + .06, GY, GZ + GR - .02), .04, steel)
box('Pipe elbow', (GX0 + .06, GY, PIPE_Z), (.10, .10, .10), dark)
box('Power light', (GX1 - .08, GY, GZ + GR + .02), (.08, .08, .05), amber)

# Fuel on the left: split firewood stacked three-two-one, lying crosswise so the long sides
# read, on two timber rails.
LOG_R, LOG_LEN, LOG_X = .055, .26, -.47
for x in [LOG_X - .08, LOG_X + .08]:
    beam('Woodpile rail', (x, .16, .02), (x, .56, .02), .04, wood)
for row, ys in enumerate([[.22, .36, .50], [.29, .43], [.36]]):
    for y in ys:
        log('Firewood', LOG_X, y, .04 + LOG_R + row * LOG_R * 1.75, LOG_LEN, LOG_R, wood, end, plank,
            sides=6, axis='X')

# Layout metadata for the game: the solid footprint and where the robot works from.
marker('Footprint', (0, .26, .5), (.30 * T, .225 * T, .5))
marker('WorkSpot', (0, -.30 * T, 0))

# Width and height in tiles, for the definition's visual_size_tiles and the scale table.
bpy.context.view_layer.update()
corners = [o.matrix_world @ v.co for o in bpy.context.scene.objects if o.type == 'MESH'
           for v in o.data.vertices]
size = [max(c[i] for c in corners) - min(c[i] for c in corners) for i in range(3)]
print('BURNER_GENERATOR width=%.3f tiles height=%.3f tiles' % (max(size[0], size[1]) / T, size[2] / T))

export('burner_generator', join_label='Burner generator')
render_preview('burner_generator', target_z=.5, ortho_scale=3.0, true_tile=True)
