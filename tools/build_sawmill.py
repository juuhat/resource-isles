"""Blender --background --python tools/build_sawmill.py: model, source and preview.

Sawmill, workbench style (docs/building-style-palette.md): no roof; the work itself is the
building. Its signature is one huge circular blade standing up through a long saw bench, face
to the camera, with the teal motor that drives it at the bench's left end and a broad stack of
finished planks on the right.

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile, front toward -Y). Everything
stands in the back of the tile, leaving an open work yard with the robot's work spot 0.30 tiles
forward of centre, facing the blade.
"""
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, box, cylinder, beam, saw_blade, marker,
                         export, render_preview)

reset_scene()

wood = material('Timber', PALETTE['timber'])
plank = material('Planks', PALETTE['plank'])
end = material('Cut wood', PALETTE['cut_wood'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
teal = material('Teal', PALETTE['teal'])
amber = material('Amber', PALETTE['amber'])

T = TILE

# Long saw bench across the back of the yard: a thick plank top on four stout legs.
TABLE_Z = .42
BENCH_X0, BENCH_X1, BENCH_Y = -.56, .22, .26
box('Saw bench', ((BENCH_X0 + BENCH_X1) / 2, BENCH_Y, TABLE_Z - .04), (BENCH_X1 - BENCH_X0, .34, .08), plank)
for x in [BENCH_X0 + .06, BENCH_X1 - .06]:
    for y in [BENCH_Y - .12, BENCH_Y + .12]:
        box('Bench leg', (x, y, (TABLE_Z - .08) / 2), (.08, .08, TABLE_Z - .08), wood)
    beam('Leg rail', (x, BENCH_Y - .12, .12), (x, BENCH_Y + .12, .12), .05, wood)
box('Board being cut', (-.02, BENCH_Y, TABLE_Z + .02), (.40, .14, .04), end)

# The blade: big enough to tower over the bench, turned face-on to the yard. saw_blade builds
# in the YZ plane (axle along X), so build it at the mirrored spot and turn it a quarter
# around Z: the axle then runs along Y.
BX, BY, BZ, BR = -.14, BENCH_Y, .50, .42
blade = saw_blade('Saw blade', BY - .025, BY + .025, -BX, BZ, BR, BR * .8, 14, steel)
blade.rotation_euler.z = math.pi / 2
cylinder('Blade hub', (BX, BY - .05, BZ), (BX, BY + .05, BZ), .10, dark)
cylinder('Hub cap', (BX, BY - .065, BZ), (BX, BY - .05, BZ), .05, end)
cylinder('Blade axle', (BX, BY, BZ), (BX, BY + .22, BZ), .04, dark)

# Teal motor on the bench's left end, belted to the blade axle behind it.
MX = -.47
box('Saw motor', (MX, BENCH_Y + .04, TABLE_Z + .14), (.18, .26, .28), teal)
box('Power light', (MX, BENCH_Y - .04, TABLE_Z + .30), (.07, .07, .05), amber)
beam('Drive belt', (MX + .06, BENCH_Y + .20, TABLE_Z + .16), (BX, BY + .20, BZ), .04, dark)

# Output: finished planks on the right, laid crosswise so the stack reads as lumber, each
# layer on dark spacer battens.
for layer in range(4):
    z = .03 + layer * .075
    for y in [.18, .30, .42]:
        box('Finished plank', (.43, y, z), (.34, .10, .05), end)
    for x in [.31, .55]:
        box('Spacer', (x, .30, z + .035), (.03, .36, .02), dark)

# Layout metadata for the game: the solid footprint and where the robot works from.
marker('Footprint', (0, .26, .5), (.30 * T, .225 * T, .5))
marker('WorkSpot', (0, -.30 * T, 0))

export('sawmill', join_label='Sawmill')
render_preview('sawmill', target_z=.4, ortho_scale=3.0, true_tile=True)
