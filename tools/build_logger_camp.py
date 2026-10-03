"""Blender --background --python tools/build_logger_camp.py: model, source and preview.

Logger camp, workbench style (docs/building-style-palette.md): no roof; the work itself is the
building. Its signature is a giant axe sunk in a chopping stump, read from across the map, with
a pile of felled logs behind it and the teal powered winch that drags trunks in.

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile, front toward -Y). Everything
stands in the back of the tile, leaving an open work yard with the robot's work spot 0.30 tiles
forward of centre, facing the stump.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, box, cylinder, log, marker,
                         export, render_preview)

reset_scene()

wood = material('Timber', PALETTE['timber'])
end = material('Cut wood', PALETTE['cut_wood'])
plank = material('Planks', PALETTE['plank'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
teal = material('Teal', PALETTE['teal'])
amber = material('Amber', PALETTE['amber'])

T = TILE

# Chopping stump, front left: a fat eight-sided round with a pale cut top and heartwood ring.
SX, SY, STUMP_H, STUMP_R = -.24, -.02, .32, .21
cylinder('Stump', (SX, SY, 0), (SX, SY, STUMP_H), STUMP_R, wood)
cylinder('Stump top', (SX, SY, STUMP_H), (SX, SY, STUMP_H + .015), STUMP_R * .88, end)
cylinder('Stump heart', (SX, SY, STUMP_H + .015), (SX, SY, STUMP_H + .02), STUMP_R * .3, plank)

# The giant axe, blade sunk in the stump and the handle rising back and to the right — the
# camp's silhouette. Built lying along +X with the head at the origin, then tipped up and
# turned onto the stump.
axe = [
    cylinder('Axe handle', (0, 0, 0), (1.0, 0, 0), .045, end),
    box('Axe head', (0, 0, 0), (.15, .11, .17), dark),
    box('Axe blade', (0, 0, -.20), (.20, .05, .26), steel),
]
for v in axe[2].data.vertices:
    if v.co.z < 0:
        v.co.x *= 1.6  # flared cutting edge, buried in the wood
place = Matrix.Translation((SX, SY, STUMP_H + .14)) @ Matrix.Rotation(math.radians(25), 4, 'Z') \
    @ Matrix.Rotation(math.radians(-35), 4, 'Y')
bpy.context.view_layer.update()  # refresh matrix_world from the parts' fresh rotations
for part in axe:
    part.matrix_world = place @ part.matrix_world

# Felled logs behind, lying crosswise so the pile reads by its long sides, stacked
# three-two-one with pale cut ends at the sides.
LOG_R, LOG_LEN, LOG_X = .11, .72, -.18
for row, ys in enumerate([[.30, .50, .70], [.40, .60], [.50]]):
    for y in ys:
        log('Felled log', LOG_X, y, LOG_R + row * LOG_R * 1.75, LOG_LEN, LOG_R, wood, end, plank, sides=6, axis='X')

# Teal powered winch on the right, its drum facing the yard and an amber power light on top.
WX, WY = .40, .36
box('Winch housing', (WX, WY, .19), (.26, .26, .38), teal)
box('Power light', (WX, WY, .40), (.08, .08, .05), amber)
cylinder('Winch drum', (WX - .13, WY - .20, .17), (WX + .13, WY - .20, .17), .10, dark)
cylinder('Wound cable', (WX - .09, WY - .20, .17), (WX + .09, WY - .20, .17), .108, steel)
for x in [WX - .13, WX + .13]:
    box('Drum cheek', (x, WY - .16, .14), (.04, .18, .28), teal)

# Layout metadata for the game: the solid footprint and where the robot works from.
marker('Footprint', (0, .26, .5), (.30 * T, .225 * T, .5))
marker('WorkSpot', (0, -.30 * T, 0))

export('logger_camp', join_label='Logger camp')
render_preview('logger_camp', target_z=.4, ortho_scale=3.0, true_tile=True)
