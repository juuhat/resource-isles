"""Blender --background --python tools/build_logger_camp.py: model, source and preview.

Logger camp, v3 design (docs/building-style-palette.md, art/style/logger-camp-v3-low-poly.png):
a two-bay lean-to with a single-slope terracotta roof, a teal powered winch in the left bay, a
short log stack in the right bay and an oversized axe against the right front post. No saw: that
belongs to the sawmill.

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile, front toward -Y). The solid
structure is 0.60 x 0.45 tiles, set 0.13 tiles toward the back, leaving the front of the tile
as an open work yard with the robot's work spot 0.30 tiles forward of centre.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, box, cylinder, beam, log, marker,
                         export, render_preview)

reset_scene()

wood = material('Timber', PALETTE['timber'])
end = material('Cut wood', PALETTE['cut_wood'])
plank = material('Planks', PALETTE['plank'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
teal = material('Teal', PALETTE['teal'])
roof_mat = material('Terracotta', PALETTE['terracotta'])
amber = material('Amber', PALETTE['amber'])

T = TILE
FRONT_Y, BACK_Y = -.12, .62  # post rows
POST_X = [-.53, 0, .53]       # three posts per row: two bays
FRONT_TOP = 1.3               # roof underside over the front posts
PITCH = math.radians(24)      # single slope, falling toward the back


def roof_z(y):
    """Height of the roof underside at depth y."""
    return FRONT_TOP - (y - FRONT_Y) * math.tan(PITCH)


# Lean-to frame: stout square posts, a header beam under each roof edge, and three rafters
# whose ends show under the eaves. Plank back walls close each bay, so it reads as a shelter
# rather than a table on legs.
for y in [FRONT_Y, BACK_Y]:
    for x in POST_X:
        h = roof_z(y)
        box('Timber post', (x, y, h / 2), (.15, .15, h), wood)
    beam('Header beam', (-.62, y, roof_z(y) - .06), (.62, y, roof_z(y) - .06), .12, wood)
wall_h = roof_z(BACK_Y) - .12
for x in [-.265, .265]:
    box('Back wall', (x, BACK_Y + .02, wall_h / 2), (.40, .05, wall_h), plank)
EAVE_FRONT, EAVE_BACK = -.32, .74
for x in POST_X:
    beam('Rafter', (x, EAVE_FRONT, roof_z(EAVE_FRONT) - .04), (x, EAVE_BACK, roof_z(EAVE_BACK) - .04), .08, plank)

# One broad roof plane resting on the rafters, framed by timber edge boards and a centre
# batten so its pitch and roof-ness read from above.
THICK = .09
mid = (EAVE_FRONT + EAVE_BACK) / 2
roof = box('Roof', (0, mid, roof_z(mid) + THICK / 2 / math.cos(PITCH)),
           (1.32, (EAVE_BACK - EAVE_FRONT) / math.cos(PITCH), THICK), roof_mat)
roof.rotation_euler.x = -PITCH
top = THICK / math.cos(PITCH) + .03
for x in [-.63, 0, .63]:
    beam('Roof batten', (x, EAVE_FRONT, roof_z(EAVE_FRONT) + top), (x, EAVE_BACK, roof_z(EAVE_BACK) + top), .07, wood)

# Right bay: three short six-sided logs, ends toward the yard, kept between the post rows.
LOG_R, LOG_LEN, LOG_Y = .13, .58, .24
for x, z in [(.40, LOG_R), (.14, LOG_R), (.27, LOG_R * 2.7)]:
    log('Stacked log', x, LOG_Y, z, LOG_LEN, LOG_R, wood, end, plank, sides=6)

# Left bay, in clear view: the powered winch that drags felled trunks in. Teal cheeks carry
# an iron drum wound with cable; a motor housing sits behind with its amber power light, and
# a broad crank handle sticks out to the side.
WX, WY, WZ = -.27, .22, .30
box('Winch skid', (WX, WY, .03), (.44, .34, .06), dark)
for x in [WX - .18, WX + .18]:
    box('Winch cheek', (x, WY, .23), (.07, .30, .40), teal)
cylinder('Winch drum', (WX - .15, WY, WZ), (WX + .15, WY, WZ), .11, dark)
cylinder('Wound cable', (WX - .10, WY, WZ), (WX + .10, WY, WZ), .118, steel)
box('Winch motor', (WX, .45, .15), (.30, .18, .26), teal)
box('Power light', (WX, .45, .30), (.08, .08, .04), amber)
cylinder('Crank axle', (WX - .215, WY, WZ), (WX - .29, WY, WZ), .03, dark)
beam('Crank arm', (WX - .29, WY, WZ + .02), (WX - .29, WY - .04, WZ - .17), .05, dark)
cylinder('Crank grip', (WX - .27, WY - .04, WZ - .17), (WX - .37, WY - .04, WZ - .17), .032, end)

# Oversized axe leaning back against the right front post, its blade over the log stack and
# inside the footprint. Built upright at the origin, then tilted onto the post.
axe = [
    cylinder('Axe handle', (0, 0, 0), (0, 0, 1.0), .04, end),
    box('Axe head', (-.02, 0, .88), (.14, .08, .15), dark),
    box('Axe blade', (-.19, 0, .88), (.22, .04, .18), steel),
]
for v in axe[2].data.vertices:
    if v.co.x < 0:
        v.co.z *= 1.6  # flared cutting edge
lean = Matrix.Translation((.50, -.29, .005)) @ Matrix.Rotation(math.radians(-6), 4, 'X') \
    @ Matrix.Rotation(math.radians(-4), 4, 'Y')
bpy.context.view_layer.update()  # refresh matrix_world from the parts' fresh rotations
for part in axe:
    part.matrix_world = lean @ part.matrix_world

# Layout metadata for the game: the solid footprint and where the robot works from.
marker('Footprint', (0, .26, .75), (.30 * T, .225 * T, .75))
marker('WorkSpot', (0, -.30 * T, 0))

export('logger_camp', join_label='Logger camp')
render_preview('logger_camp', target_z=.5, ortho_scale=3.0, true_tile=True)
