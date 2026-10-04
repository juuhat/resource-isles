"""Blender --background --python tools/build_quarry.py: stone drill quarry.

Timber drill frame, spiral bit and shared hand-PTO generator at true tile scale.
The front yard and socket alignment match the sawmill.
"""
import math
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, box, cylinder, beam,
                         block, marker, export, render_preview)
from build_shared_generator import build_shared_generator

reset_scene()
random.seed(11)
wood = material('Timber', PALETTE['timber'])
end = material('Cut wood', PALETTE['cut_wood'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
stone = material('Stone', PALETTE['stone'])
cut = material('Cut stone', PALETTE['stone_cut'])
WORK_Y = -.30 * TILE
DX, DY = -.28, .34


def moving(obj, pivot):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = pivot
    obj.matrix_world = world
    return obj


# Square uprights and ground sills, leaving the drill face open.
for x in [-.66, .10]:
    box('Ground sill', (x, .33, .045), (.16, .83, .09), wood)
    box('Drill upright', (x, .46, .66), (.14, .14, 1.20), wood)
    box('Post end', (x, .46, 1.265), (.14, .14, .03), end)
    beam('Rear frame brace', (x, .68, .12), (x, .46, .85), .07, wood)
box('Drill crosshead', (DX, DY, 1.22), (.96, .22, .16), wood)
box('Rear tie', (DX, .55, .20), (.76, .09, .10), wood)

# Broad worked block directly beneath the bit, divided by a cut seam.
for x in [DX - .145, DX + .145]:
    box('Stone being drilled', (x, DY, .165), (.282, .46, .33), stone)
cylinder('Bore shadow', (DX, DY, .329), (DX, DY, .333), .069, dark, 12)

# Vertical spindle, chunky collars and a true three-turn helical cutting flight.
drill = marker('DrillPivot', (DX, DY, .75))
moving(cylinder('Drill spindle', (DX, DY, .34), (DX, DY, 1.36), .042, steel), drill)
for z, radius, depth in [(.91, .12, .14), (1.075, .085, .12)]:
    moving(cylinder('Spindle collar', (DX, DY, z-depth/2),
                    (DX, DY, z+depth/2), radius, dark), drill)
moving(cylinder('Top spindle cap', (DX, DY, 1.34), (DX, DY, 1.38), .075, dark), drill)
verts, faces = [], []
steps = 72
for i in range(steps + 1):
    t = i / steps
    angle = t * math.tau * 3
    z = .35 + t * .48
    radius = .052 + t * .045
    for r, dz in [(.038, -.012), (radius, -.012), (radius, .012), (.038, .012)]:
        verts.append((DX + r*math.cos(angle), DY + r*math.sin(angle), z + dz))
for i in range(steps):
    for j in range(4):
        a, b = i*4+j, i*4+(j+1)%4
        faces.append((a, b, b+4, a+4))
faces.extend([(3, 2, 1, 0), tuple(steps*4+j for j in range(4))])
mesh = bpy.data.meshes.new('Spiral cutting flight mesh')
mesh.from_pydata(verts, [], faces)
mesh.update()
flight = bpy.data.objects.new('Spiral cutting flight', mesh)
bpy.context.collection.objects.link(flight)
mesh.materials.append(dark)
moving(flight, drill)

# Socket .2175 right, .20 forward and .40 high from the robot's WorkSpot.
GEN = (.2175, WORK_Y + .20 + .265, .15)
build_shared_generator(GEN)
for x in [GEN[0]-.18, GEN[0]+.18]:
    box('Generator sleeper', (x, GEN[1]+.08, .045), (.11, .58, .09), wood)
    box('Generator cradle', (x, GEN[1], .12), (.14, .34, .06), wood)

# Flywheel belts to a cross shaft and right-angle gearbox above the drill.
FX, PY, PZ, PR = GEN[0]+.375, DY, 1.075, .105
pulley = marker('DrillPulleyPivot', (FX, PY, PZ))
moving(cylinder('Drive pulley', (FX-.03, PY, PZ), (FX+.03, PY, PZ), PR, dark), pulley)
moving(cylinder('Pulley hub', (FX+.03, PY, PZ), (FX+.05, PY, PZ), .045, end), pulley)
moving(beam('Pulley spoke', (FX+.033, PY, PZ), (FX+.033, PY, PZ+PR*.85), .022, steel), pulley)
cylinder('Cross shaft', (DX, PY, PZ), (FX, PY, PZ), .032, steel)
box('Drill gearbox', (DX, PY, PZ), (.17, .17, .14), dark)
box('Shaft bearing', (.10, PY, PZ), (.14, .13, .13), dark)
beam('Pulley support', (.10, .46, .98), (FX, PY, 1.0), .065, wood)
fy, fz, fr = GEN[1]+.015, GEN[2]+.25, .22
dy, dz = PY-fy, PZ-fz
base = math.atan2(dz, dy)
spread = math.acos((fr-PR)/math.hypot(dy, dz))
for side in [-1, 1]:
    ny, nz = math.cos(base+side*spread), math.sin(base+side*spread)
    beam('Drive belt', (FX, fy+fr*ny, fz+fr*nz),
         (FX, PY+PR*ny, PZ+PR*nz), .035, dark)

# Compact raw and finished stock groups clear of the front yard.
for loc, size in [((-.78, .12, 0), (.27, .29, .25)),
                  ((-.79, .40, 0), (.25, .27, .34)),
                  ((-.65, .67, 0), (.27, .25, .20))]:
    block('Raw stone', loc, size, stone)
for x in [-.33, -.07]:
    box('Finished stone', (x, .77, .11), (.24, .23, .22), cut)

marker('Footprint', (-.12, .34, .69), (.80, .56, .69))
marker('WorkSpot', (0, WORK_Y, 0))
export('quarry', join_label='Quarry')
render_preview('quarry', target_z=.50, ortho_scale=3.1, true_tile=True)
