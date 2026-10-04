"""Blender --background --python tools/build_sawmill.py: model, source and preview.

Sawmill, workbench style (docs/building-style-palette.md), after the hand-PTO concept
(art/concepts/player-building-hand-pto-v2-neutral.png): a heavy open timber frame on ground
sills, tall rear posts with slanted tops, and the signature huge upright blade standing face
to the camera, carried on an iron arm. The shared PTO generator (tools/build_shared_generator.py)
sits on a timber cradle at the front right of the yard; its flywheel belts up to a cross shaft
that drives the blade through a small gearbox. A squared beam rides the bench into the blade,
finished boards wait on the bench behind it and raw logs lie on the ground at the left.

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile, front toward -Y). The robot's
work spot is 0.30 tiles forward of centre, facing the blade. The generator's socket is placed
where the robot's right forearm meets it when held level from the elbow: 0.2175 units to the
robot's right (+X, since it faces +Y), 0.40 above the ground, just ahead of its hand.

Moving parts stay separate under pivots for the game to spin while the building is powered:
SawBladePivot (blade, axle along Blender Y / Godot local Z) and the generator's FlywheelPivot
and SocketRotor. Everything else is merged per material.
"""
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, box, cylinder, beam, log, saw_blade,
                         prism_y, marker, export, render_preview)
from build_shared_generator import build_shared_generator

reset_scene()

wood = material('Timber', PALETTE['timber'])
plank = material('Planks', PALETTE['plank'])
end = material('Cut wood', PALETTE['cut_wood'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])

T = TILE
WORK_Y = -.30 * T


def parent_to(obj, pivot):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = pivot
    obj.matrix_world = world
    return obj


def post(name, x, y, z0, z1, size=.10, slant=.05):
    """Square timber post with its top cut on a slant, high side toward the outside (sign of x),
    as on the concept's frame."""
    h = size / 2
    lo, hi = (z1 - slant, z1) if x < 0 else (z1, z1 - slant)
    return prism_y(name, [(x - h, z0), (x + h, z0), (x + h, hi), (x - h, lo)], y - h, y + h, wood)


# --- Timber frame ---------------------------------------------------------------------------
X0, X1 = -.66, .42          # bench ends
YF, YB = .16, .60           # front and back post lines
TOP = .50                   # bench top

# Ground sills run past the posts at both ends, with cross sleepers on top of their ends.
for y in [YF, YB]:
    box('Ground sill', ((X0 + X1) / 2 - .02, y, .04), (X1 - X0 + .20, .11, .08), wood)
for x in [X0 - .03, X1 + .03]:
    box('Cross sleeper', (x, (YF + YB) / 2, .11), (.09, YB - YF + .16, .06), wood)

# Posts: short at the front so nothing crosses in front of the blade, tall at the back.
for x in [X0 + .05, X1 - .05]:
    post('Front post', x, YF, .08, TOP + .10)
    post('Rear post', x, YB, .08, 1.0)
    beam('End rail', (x, YF, .24), (x, YB, .24), .07, wood)
for y in [YF, YB]:
    box('Long rail', ((X0 + X1) / 2, y, TOP - .08), (X1 - X0 - .10, .08, .08), wood)
    box('Low rail', ((X0 + X1) / 2, y, .20), (X1 - X0 - .10, .07, .07), wood)
box('Bench top', ((X0 + X1) / 2, (YF + YB) / 2, TOP - .03), (X1 - X0 + .04, YB - YF + .12, .06), plank)

# --- Blade, arm and drive -------------------------------------------------------------------
BX, BY, BZ, BR = .0, .38, .70, .46
blade_pivot = marker('SawBladePivot', (BX, BY, BZ))
# saw_blade builds in the YZ plane (axle along X): build it at the mirrored spot and turn it a
# quarter around Z, so the axle runs along Y and the blade faces the yard.
blade = saw_blade('Saw blade', BY - .022, BY + .022, -BX, BZ, BR, BR * .82, 14, steel)
blade.rotation_euler.z = math.pi / 2
for part in [blade,
             cylinder('Blade hub', (BX, BY - .05, BZ), (BX, BY + .05, BZ), .095, dark),
             cylinder('Hub cap', (BX, BY - .065, BZ), (BX, BY - .05, BZ), .05, end)]:
    parent_to(part, blade_pivot)

# Iron arm from the right rear post down to the gearbox behind the blade.
GEAR_Y = .50
cylinder('Blade axle', (BX, BY + .05, BZ), (BX, GEAR_Y, BZ), .035, steel)
box('Gearbox', (BX, GEAR_Y + .01, BZ), (.15, .10, .15), dark)
beam('Saw arm', (X1 - .08, YB - .02, .94), (BX + .05, GEAR_Y + .02, BZ + .05), .075, dark)

# The shared generator on a cradle, socket toward the work spot under the robot's right hand.
GEN = (.2175, WORK_Y + .20 + .265, .15)  # root such that DockPoint is .20 ahead of the robot
gen = build_shared_generator(GEN)
for x in [GEN[0] - .18, GEN[0] + .18]:
    box('Cradle sleeper', (x, GEN[1] + .10, .045), (.10, .62, .09), wood)
    box('Cradle block', (x, GEN[1], .12), (.13, .34, .06), wood)
box('Cradle tie', (GEN[0], YF - .06, .13), (.50, .08, .08), wood)

# Flywheel (generator output, axle along X) belted to a pulley on a cross shaft that runs into
# the gearbox. The belt runs in the flywheel's plane, outside the bench's right end.
FX = GEN[0] + .375
fly = (GEN[1] + .015, GEN[2] + .25, .22)   # (y, z, radius) of the flywheel rim
pul = (GEAR_Y, BZ, .11)
cylinder('Cross shaft', (BX + .07, GEAR_Y, BZ), (FX + .045, GEAR_Y, BZ), .03, steel)
cylinder('Pulley', (FX - .03, GEAR_Y, BZ), (FX + .03, GEAR_Y, BZ), pul[2], dark)
cylinder('Pulley hub', (FX + .03, GEAR_Y, BZ), (FX + .045, GEAR_Y, BZ), .04, steel)
dy, dz = pul[0] - fly[0], pul[1] - fly[1]
base, spread = math.atan2(dz, dy), math.acos((fly[2] - pul[2]) / math.hypot(dy, dz))
for side in [1, -1]:
    n = (math.cos(base + side * spread), math.sin(base + side * spread))
    a = (FX, fly[0] + fly[2] * n[0], fly[1] + fly[2] * n[1])
    b = (FX, pul[0] + pul[2] * n[0], pul[1] + pul[2] * n[1])
    beam('Drive belt', a, b, .045, dark)

# --- Stock ----------------------------------------------------------------------------------
# A squared beam riding the bench into the blade, and finished boards stacked behind it.
box('Beam being cut', ((X0 + .02 + BX - BR + .04) / 2, BY, TOP + .05), (BX - BR + .04 - X0 - .02, .15, .10), end)
for layer in range(2):
    for x in [-.50, -.22]:
        box('Finished board', (x, .56, TOP + .025 + layer * .05), (.26, .12, .045), end)
# Raw logs on the ground at the front left, lying crosswise so their long sides show.
heart = material('Heartwood', PALETTE['plank'])
for x, y, z in [(-.58, -.16, .075), (-.58, .00, .075), (-.58, -.08, .20)]:
    log('Log', x, y, z, .44, .075, wood, end, heart, axis='X')

# Layout metadata for the game: the solid footprint and where the robot works from.
marker('Footprint', (-.13, .14, .5), (.70, .54, .5))
marker('WorkSpot', (0, WORK_Y, 0))

export('sawmill', join_label='Sawmill')
render_preview('sawmill', target_z=.4, ortho_scale=3.0, true_tile=True)
