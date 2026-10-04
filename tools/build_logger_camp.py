"""Blender --background --python tools/build_logger_camp.py: powered chopping axe.

A trip hammer at true tile scale, front toward -Y: a timber helve on a fulcrum carries a broad
axe head over a chopping block, so the machine works its own wood wherever it stands. The
shared hand-PTO generator belts up to a cross shaft and right-angle gearbox (as the quarry's
drill), turning a two-wiper cam that lifts the helve by its tappet.

AxeHelvePivot holds the helve and head, authored RAISED (the top of the stroke, where an idle
camp rests); the game's chop drops it STRIKE_DEGREES onto the round. AxeCamPivot and
AxePulleyPivot spin. One wiper is authored just releasing the tappet, the moment the drop begins.
"""
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, box, cylinder, beam,
                         log, prism_y, marker, export, render_preview)
from build_shared_generator import build_shared_generator

reset_scene()
wood = material('Timber', PALETTE['timber'])
end = material('Cut wood', PALETTE['cut_wood'])
plank = material('Planks', PALETTE['plank'])
dark = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
WORK_Y = -.30 * TILE
AY = .36                  # plane the helve swings in
BX = -.30                 # chopping block and axe head
PX, PZ = -.76, .80        # fulcrum pin
STRIKE_DEGREES = 26       # keep in step with IslandRenderer's chop
CY, CR = AY - .09, .15    # cam plane, in front of the helve, and wiper reach
RELEASE_DEGREES = 100     # wiper angle (from +X toward +Z) as it lets the tappet go
TAPPET_X, TAPPET_W = -.55, .07


def moving(obj, pivot):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = pivot
    obj.matrix_world = world
    return obj


def raised(x, z):
    """Where a point authored in the strike pose sits once the helve is lifted."""
    a = math.radians(STRIKE_DEGREES)
    dx, dz = x - PX, z - PZ
    return PX + dx*math.cos(a) - dz*math.sin(a), PZ + dx*math.sin(a) + dz*math.cos(a)


# Chopping block: a broad stump with a round stood on end, split by the last blow.
cylinder('Chopping block', (BX, AY, 0), (BX, AY, .22), .19, wood, 8)
cylinder('Block top', (BX, AY, .22), (BX, AY, .225), .165, end, 8)
cylinder('Round bark', (BX, AY, .225), (BX, AY, .44), .13, wood, 8)
cylinder('Round cut end', (BX, AY, .44), (BX, AY, .452), .11, end, 8)
cylinder('Round heartwood', (BX, AY, .452), (BX, AY, .456), .04, plank, 8)
box('Split seam', (BX, AY, .4545), (.20, .014, .006), dark)

# Fulcrum: two posts on a sill.
box('Fulcrum sill', (PX, AY, .045), (.17, .44, .09), wood)
for y in [AY - .11, AY + .11]:
    box('Fulcrum post', (PX, y, .45), (.10, .07, .82), wood)
    box('Post end', (PX, y, .875), (.10, .07, .03), end)

# Helve and axe head, authored in the strike pose (bit in the round), then lifted.
helve = marker('AxeHelvePivot', (PX, AY, PZ))
moving(beam('Helve', (-.92, AY, PZ), (-.14, AY, PZ), .075, wood), helve)
moving(cylinder('Fulcrum pin', (PX, AY - .16, PZ), (PX, AY + .16, PZ), .03, steel), helve)
for x in [-.90, -.16]:
    moving(box('Helve band', (x, AY, PZ), (.035, .09, .09), dark), helve)
tappet_bottom = PZ - .0375 - .05
moving(box('Cam tappet', (TAPPET_X, CY + .02, tappet_bottom + .025), (TAPPET_W, .11, .05), dark), helve)
# Broad face toward the camera: a cheek around the helve flaring to a wide steel bit.
cheek = [(BX - .06, PZ + .065), (BX + .06, PZ + .065), (BX + .06, PZ - .06), (BX + .13, .56),
         (BX - .13, .56), (BX - .06, PZ - .06)]
moving(prism_y('Axe head', cheek, AY - .05, AY + .05, dark), helve)
bit = [(BX - .13, .56), (BX + .13, .56), (BX + .15, .45), (BX - .15, .45)]
moving(prism_y('Axe bit', bit, AY - .03, AY + .03, steel), helve)
helve.rotation_euler.y = -math.radians(STRIKE_DEGREES)

# Two-wiper cam, placed so a wiper tip is at the tappet's trailing edge in the raised pose.
release_x, release_z = raised(TAPPET_X - TAPPET_W/2, tappet_bottom)
r = math.radians(RELEASE_DEGREES)
CX, CZ = release_x - CR*math.cos(r), release_z - CR*math.sin(r)
cam = marker('AxeCamPivot', (CX, CY, CZ))
moving(cylinder('Cam hub', (CX, CY - .03, CZ), (CX, CY + .03, CZ), .045, dark, 8), cam)
for degrees in [RELEASE_DEGREES, RELEASE_DEGREES + 180]:
    a = math.radians(degrees)
    tip = (CX + (CR - .022)*math.cos(a), CY, CZ + (CR - .022)*math.sin(a))
    moving(beam('Cam wiper', (CX, CY, CZ), tip, .04, dark), cam)
    moving(cylinder('Wiper roller', (tip[0], CY - .03, tip[2]), (tip[0], CY + .03, tip[2]), .022, steel, 6), cam)

# Socket .2175 right, .20 forward and .40 high from the robot's WorkSpot.
GEN = (.2175, WORK_Y + .20 + .265, .15)
build_shared_generator(GEN)
for x in [GEN[0] - .18, GEN[0] + .18]:
    box('Generator sleeper', (x, GEN[1] + .08, .045), (.11, .58, .09), wood)
    box('Generator cradle', (x, GEN[1], .12), (.14, .34, .06), wood)

# Flywheel belts back to a cross shaft behind the helve, then a gearbox turns the cam shaft.
FX, SY, PR = GEN[0] + .375, .64, .10
pulley = marker('AxePulleyPivot', (FX, SY, CZ))
moving(cylinder('Drive pulley', (FX - .03, SY, CZ), (FX + .03, SY, CZ), PR, dark), pulley)
moving(cylinder('Pulley hub', (FX + .03, SY, CZ), (FX + .05, SY, CZ), .045, end), pulley)
moving(beam('Pulley spoke', (FX + .033, SY, CZ), (FX + .033, SY, CZ + PR*.85), .022, steel), pulley)
cylinder('Cross shaft', (CX, SY, CZ), (FX, SY, CZ), .03, steel)
cylinder('Cam shaft', (CX, CY, CZ), (CX, SY, CZ), .03, steel)
box('Cam gearbox', (CX, SY, CZ), (.15, .15, .14), dark)
box('Shaft bearing', (.46, SY, CZ), (.12, .12, .12), dark)
for x in [CX, .46]:
    box('Shaft post', (x, SY, (CZ - .07)/2), (.09, .09, CZ - .07), wood)
fy, fz, fr = GEN[1] + .015, GEN[2] + .25, .22
dy, dz = SY - fy, CZ - fz
base = math.atan2(dz, dy)
spread = math.acos((fr - PR)/math.hypot(dy, dz))
for side in [-1, 1]:
    ny, nz = math.cos(base + side*spread), math.sin(base + side*spread)
    beam('Drive belt', (FX, fy + fr*ny, fz + fr*nz), (FX, SY + PR*ny, CZ + PR*nz), .035, dark)

# Firewood: split halves by the block, and a crosswise log pile behind the machine.
for x, y, turn in [(-.54, .06, .5), (-.18, .10, -.3)]:
    piece = prism_y('Split half', [(-.09, 0), (.09, 0), (.065, .07), (0, .09), (-.065, .07)],
                    -.10, .10, end)
    piece.location = (x, y, 0)
    piece.rotation_euler.z = turn
for y, z in [(.80, .095), (.98, .095), (.89, .26)]:
    log('Harvested log', -.28, y, z, .70, .095, wood, end, plank, sides=7, axis='X')

marker('Footprint', (-.13, .27, .67), (.79, .70, .67))
marker('WorkSpot', (0, WORK_Y, 0))

# Merge moving meshes per material under each pivot, keeping the pivots themselves.
for pivot in [helve, cam, pulley]:
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
# the helve pivot's own lift must survive into the export.
bpy.ops.object.select_all(action='DESELECT')
for obj in bpy.context.scene.objects:
    if obj.type == 'MESH':
        obj.select_set(True)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

export('logger_camp', join_label='Logger camp')
render_preview('logger_camp', target_z=.55, ortho_scale=3.2, true_tile=True)
