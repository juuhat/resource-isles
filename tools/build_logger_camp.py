"""Blender --background --python tools/build_logger_camp.py: powered felling axe.

At true tile scale, front toward -Y: a standing pine with a felling notch cut into its front, and
a powered axe arm that swings sideways into the notch. The arm turns on a vertical iron shaft in
a timber gallows, so the swing is flat on the ground plane and the axe head's broad face looks up
at the camera. The shared hand-PTO generator belts to a cross shaft and a gearbox at the shaft's
foot. Felled trunks lie crosswise behind the machine and a fresh stump stands at the yard's edge.

AxeHelvePivot holds the shaft, helve, brace and head, authored in the strike pose: an idle camp
rests with its axe in the notch, the woodcutter's icon. The game's chop swings it STRIKE_DEGREES
back and into the notch again. AxePulleyPivot spins with the drive.
"""
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bmesh
import bpy
from mathutils import Vector
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, finish, box, cylinder, beam,
                         log, marker, export, render_preview)
from build_shared_generator import build_shared_generator

reset_scene()
wood = material('Timber', PALETTE['timber'])
end = material('Cut wood', PALETTE['cut_wood'])
plank = material('Planks', PALETTE['plank'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
pine = material('Pine', PALETTE['pine'])
WORK_Y = -.30 * TILE
MX, MY = -.08, .28        # vertical shaft the arm swings on
HZ = .30                  # height of the helve and of the cut
HX = -.54                 # axe head, in the strike pose
BIT_Y = MY + .21          # axe bit edge, in the strike pose
R = .17                   # trunk radius (to a face: the octagon is turned flat to the front)
BITE = .06                # how far the bit sinks past the trunk's face
TX, TY = HX, BIT_Y - BITE + R
STRIKE_DEGREES = 40       # keep in step with IslandRenderer's chop


def moving(obj, pivot):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = pivot
    obj.matrix_world = world
    return obj


def slab(name, outline, offset, mat):
    """Flat polygon (3D points, in order) extruded by offset."""
    n = len(outline)
    verts = [tuple(p) for p in outline] + [tuple(Vector(p) + Vector(offset)) for p in outline]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, i + n, (i + 1) % n + n, (i + 1) % n) for i in range(n)]
    mesh = bpy.data.meshes.new(name + ' mesh')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat)


def cone(name, z, radius, height, mat):
    bpy.ops.mesh.primitive_cone_add(vertices=8, radius1=radius, radius2=0, depth=height,
                                    location=(TX, TY, z + height / 2))
    obj = bpy.context.object
    obj.rotation_euler.z = math.pi / 8
    return finish(obj, name, mat)


# The tree being felled: a trunk with a pale notch at the cut, and a pine crown.
corner = R / math.cos(math.pi / 8)
trunk = cylinder('Trunk', (TX, TY, 0), (TX, TY, .62), corner, wood, 8)
trunk.rotation_euler.z = math.pi / 8
flare = cylinder('Root flare', (TX, TY, 0), (TX, TY, .07), corner + .04, wood, 8)
flare.rotation_euler.z = math.pi / 8
front = TY - R
mouth = [(TX - .3, front - .05, HZ - .04), (TX - .3, front - .05, HZ + .17), (TX - .3, front + .12, HZ - .04)]
notch = slab('Notch', mouth, (.6, 0, 0), end)
for part in [trunk, flare]:
    cut = part.modifiers.new('Felling notch', 'BOOLEAN')
    cut.operation = 'DIFFERENCE'
    cut.object = notch
    cut.material_mode = 'TRANSFER'
    bpy.context.view_layer.objects.active = part
    bpy.ops.object.modifier_apply(modifier=cut.name)
bpy.data.objects.remove(notch)
for z, radius, height in [(.50, .33, .40), (.72, .26, .36), (.92, .18, .32)]:
    cone('Pine crown', z, radius, height, pine)
# Chips knocked out of the notch.
for x, y, turn in [(-.36, .14, .4), (-.62, .10, -.6), (-.47, .02, 1.1)]:
    chip = box('Wood chip', (x, y, .015), (.07, .04, .03), end)
    chip.rotation_euler.z = turn

# Gallows: a sill, a back post and a cap arm carrying the shaft's bearings.
box('Gallows sill', (MX, MY + .06, .045), (.20, .34, .09), wood)
box('Gallows post', (MX, MY + .16, .40), (.10, .10, .70), wood)
box('Post end', (MX, MY + .16, .765), (.10, .10, .03), end)
box('Cap arm', (MX, MY + .06, .70), (.10, .30, .08), wood)
box('Top bearing', (MX, MY, .65), (.12, .12, .07), dark)
box('Shaft gearbox', (MX, MY, .14), (.17, .17, .14), dark)

# Shaft, helve, brace and axe head in the strike pose, the bit in the notch.
helve = marker('AxeHelvePivot', (MX, MY, HZ))
moving(cylinder('Swing shaft', (MX, MY, .21), (MX, MY, .615), .035, steel), helve)
moving(box('Shaft collar', (MX, MY, HZ), (.11, .11, .11), dark), helve)
moving(beam('Helve', (MX, MY, HZ), (HX - .09, MY, HZ), .075, wood), helve)
moving(beam('Helve brace', (MX, MY, .56), (MX - .27, MY, HZ + .03), .05, wood), helve)
moving(box('Helve band', (HX - .08, MY, HZ), (.035, .09, .09), dark), helve)
# Seen from above: a cheek around the helve flaring to a wide steel bit.
cheek = [(HX - .06, MY - .065), (HX + .06, MY - .065), (HX + .06, MY + .06), (HX + .12, BIT_Y - .05),
         (HX - .12, BIT_Y - .05), (HX - .06, MY + .06)]
moving(slab('Axe head', [(x, y, HZ - .035) for x, y in cheek], (0, 0, .07), dark), helve)
bit = [(HX - .12, BIT_Y - .05), (HX + .12, BIT_Y - .05), (HX + .135, BIT_Y), (HX - .135, BIT_Y)]
moving(slab('Axe bit', [(x, y, HZ - .022) for x, y in bit], (0, 0, .044), steel), helve)

# Socket .2175 right, .20 forward and .40 high from the robot's WorkSpot.
GEN = (.2175, WORK_Y + .20 + .265, .15)
build_shared_generator(GEN)
for x in [GEN[0] - .18, GEN[0] + .18]:
    box('Generator sleeper', (x, GEN[1] + .08, .045), (.11, .58, .09), wood)
    box('Generator cradle', (x, GEN[1], .12), (.14, .34, .06), wood)

# Flywheel belts back to a pulley on a cross shaft that runs into the gearbox.
FX, SZ, PR = GEN[0] + .375, .14, .10
pulley = marker('AxePulleyPivot', (FX, MY, SZ))
moving(cylinder('Drive pulley', (FX - .03, MY, SZ), (FX + .03, MY, SZ), PR, dark), pulley)
moving(cylinder('Pulley hub', (FX + .03, MY, SZ), (FX + .05, MY, SZ), .045, end), pulley)
moving(beam('Pulley spoke', (FX + .033, MY, SZ), (FX + .033, MY, SZ + PR*.85), .022, steel), pulley)
cylinder('Cross shaft', (MX, MY, SZ), (FX, MY, SZ), .03, steel)
box('Shaft bearing', (.44, MY, SZ), (.10, .10, .10), dark)
box('Bearing block', (.44, MY, (SZ - .05)/2), (.12, .12, SZ - .05), wood)
fy, fz, fr = GEN[1] + .015, GEN[2] + .25, .22
dy, dz = MY - fy, SZ - fz
base = math.atan2(dz, dy)
spread = math.acos((fr - PR)/math.hypot(dy, dz))
for side in [-1, 1]:
    ny, nz = math.cos(base + side*spread), math.sin(base + side*spread)
    beam('Drive belt', (FX, fy + fr*ny, fz + fr*nz), (FX, MY + PR*ny, SZ + PR*nz), .035, dark)

# The harvest: felled trunks crosswise behind the machine, and the stump of the last tree.
for y, z in [(.62, .095), (.80, .095), (.71, .26)]:
    log('Felled trunk', .24, y, z, .70, .095, wood, end, plank, sides=7, axis='X')
cylinder('Stump', (-.78, -.12, 0), (-.78, -.12, .13), .13, wood, 8)
cylinder('Stump cut', (-.78, -.12, .13), (-.78, -.12, .135), .11, end, 8)
cylinder('Stump heartwood', (-.78, -.12, .135), (-.78, -.12, .138), .04, plank, 8)

marker('Footprint', (-.15, .40, .62), (.75, .55, .62))
marker('WorkSpot', (0, WORK_Y, 0))

# Merge moving meshes per material under each pivot, keeping the pivots themselves.
for pivot in [helve, pulley]:
    for mat in [wood, end, plank, dark, steel]:
        parts = [o for o in bpy.context.scene.objects if o.type == 'MESH'
                 and o.parent == pivot and o.data.materials[0] == mat]
        if not parts:
            continue
        bpy.ops.object.select_all(action='DESELECT')
        for obj in parts:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        if len(parts) > 1:
            bpy.ops.object.join()
        bpy.context.object.name = pivot.name.removesuffix('Pivot') + ' ' + mat.name

# Keep imported bounds aligned with the pivots' axes rather than a joined beam's. Only meshes:
# the pivots' own placement must survive into the export.
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.context.scene.objects:
    if obj.type == 'MESH':
        obj.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

export('logger_camp', join_label='Logger camp')
render_preview('logger_camp', target_z=.55, ortho_scale=3.2, true_tile=True)
