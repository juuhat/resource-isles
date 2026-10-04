"""Blender --background --python tools/build_logger_camp.py.

Stationary forestry cutter: articulated iron boom, horizontal circular saw head,
timber pedestal and shared hand-PTO generator. True tile scale, front toward -Y.
HarvesterArmPivot keeps the hydraulic assembly together for a bounded powered
sweep. ForestBladePivot spins the horizontal blade independently of the arm.
"""
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from mathutils import Vector
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, box, cylinder, beam,
                         log, marker, export, render_preview)
from build_shared_generator import build_shared_generator

reset_scene()
wood = material('Timber', PALETTE['timber'])
end = material('Cut wood', PALETTE['cut_wood'])
plank = material('Planks', PALETTE['plank'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
teal = material('Teal', PALETTE['teal'])
cream = material('Cream', PALETTE['cream'])
amber = material('Amber', PALETTE['amber'])
WORK_Y = -.30 * TILE
BASE = Vector((.32, .48, .30))

# Broad sleepers and a small raised pedestal, rather than a terrain platform.
for x in [BASE.x-.20, BASE.x+.20]:
    box('Pedestal sleeper', (x, BASE.y, .055), (.14, .60, .11), wood)
box('Pedestal cross tie', (BASE.x, BASE.y, .15), (.58, .40, .12), wood)
cylinder('Fixed slew bearing', (BASE.x, BASE.y, .21), BASE, .26, dark, 12)
arm = marker('HarvesterArmPivot', BASE)


def moving(obj, parent=arm):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world
    return obj


def joint(name, point, radius):
    p = Vector(point)
    moving(cylinder(name+' cover', p+Vector((0, -.105, 0)),
                    p+Vector((0, .105, 0)), radius, teal))
    moving(cylinder(name+' pin', p+Vector((0, -.125, 0)),
                    p+Vector((0, -.108, 0)), radius*.52, steel))


def piston(name, a, b):
    a, b = Vector(a), Vector(b)
    mid = a.lerp(b, .58)
    moving(cylinder(name+' barrel', a, mid, .042, dark))
    moving(cylinder(name+' rod', mid, b, .021, steel))
    for p in [a, b]:
        moving(cylinder(name+' clevis', p-Vector((0, .04, 0)),
                        p+Vector((0, .04, 0)), .047, teal))


# Recognizable bent boom: tall shoulder, high elbow, short downward forearm.
shoulder = Vector((.32, .48, .53))
elbow = Vector((-.02, .48, 1.22))
wrist = Vector((-.63, .23, .72))
moving(cylinder('Rotating turret', BASE, BASE+Vector((0, 0, .12)), .225, teal, 12))
moving(box('Boom foot', (.32, .48, .44), (.25, .24, .20), teal))
moving(beam('Main boom', shoulder, elbow, .17, dark))
moving(beam('Outer boom', elbow, wrist, .13, dark))
joint('Shoulder', shoulder, .14)
joint('Elbow', elbow, .13)
joint('Wrist', wrist, .095)
piston('Lift piston', (.51, .35, .44), (.11, .35, .99))
piston('Reach piston', (.05, .50, 1.25), (-.51, .30, .86))

# Low horizontal felling blade cuts across trunks as the boom sweeps.
HX, HY = wrist.x, wrist.y
moving(box('Saw drive housing', (HX, HY, .59), (.20, .19, .16), teal))
moving(box('Head front cover', (HX, HY-.103, .59), (.13, .022, .08), cream))
moving(box('Head status light', (HX+.074, HY-.115, .59), (.025, .016, .055), amber))
moving(cylinder('Saw spindle', (HX, HY, .415), (HX, HY, .52), .038, steel))
blade_pivot = moving(marker('ForestBladePivot', (HX, HY, .42)))
n = 32
verts = []
for z in [.408, .432]:
    for i in range(n):
        angle = math.tau*i/n
        r = .255 if i % 2 == 0 else .215
        verts.append((HX+r*math.cos(angle), HY+r*math.sin(angle), z))
faces = [tuple(reversed(range(n))), tuple(range(n, 2*n))]
faces += [(i, (i+1)%n, (i+1)%n+n, i+n) for i in range(n)]
mesh = bpy.data.meshes.new('Horizontal felling saw mesh')
mesh.from_pydata(verts, [], faces)
mesh.update()
blade = bpy.data.objects.new('Forest cutting blade', mesh)
bpy.context.collection.objects.link(blade)
mesh.materials.append(steel)
moving(blade, blade_pivot)
moving(cylinder('Blade hub', (HX, HY, .432), (HX, HY, .465), .066, dark), blade_pivot)
# One broad inset drive spoke makes the spinning face readable from the game camera.
moving(box('Blade drive spoke', (HX+.125, HY, .435), (.15, .025, .005), dark), blade_pivot)

# Crosswise harvested logs, two below and one above, behind the working head.
for y, z in [(.61, .105), (.83, .105), (.72, .285)]:
    log('Harvested log', -.29, y, z, .74, .105, wood, end, plank, sides=7, axis='X')
for x in [-.69, .12]:
    box('Log rack sleeper', (x, .72, .025), (.08, .47, .05), wood)

# Same operator and hand docking as the quarry/sawmill.
GEN = (.2175, WORK_Y+.20+.265, .15)
build_shared_generator(GEN)
for x in [GEN[0]-.18, GEN[0]+.18]:
    box('Generator sleeper', (x, GEN[1]+.08, .045), (.11, .58, .09), wood)
    box('Generator cradle', (x, GEN[1], .12), (.14, .34, .06), wood)
box('Hydraulic pump', (.32, .26, .29), (.23, .16, .18), teal)
cylinder('Pump shaft', (.32, .045, .40), (.32, .25, .40), .035, steel)
# Two coarse hoses run from the pump to the stationary slew bearing.
for x in [.40, .47]:
    cylinder('Hydraulic supply', (x, .27, .34), (x, .43, .25), .018, dark, 6)

marker('Footprint', (-.10, .27, .67), (.79, .67, .67))
marker('WorkSpot', (0, WORK_Y, 0))

# Merge moving meshes by material too, preserving the one swivel pivot.
for mat in [wood, end, plank, dark, steel, teal, cream, amber]:
    parts = [o for o in bpy.context.scene.objects if o.type == 'MESH'
             and o.parent == arm and o.data.materials[0] == mat]
    if not parts:
        continue
    bpy.ops.object.select_all(action='DESELECT')
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    if len(parts) > 1:
        bpy.ops.object.join()
    bpy.context.object.name = 'Harvester '+mat.name

# Keep imported bounds aligned with the pivot's axes, rather than the first
# diagonal boom segment's axes after joining.
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.context.scene.objects:
    if obj.type == 'MESH':
        obj.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

export('logger_camp', join_label='Logger camp')
render_preview('logger_camp', target_z=.55, ortho_scale=3.2, true_tile=True)
