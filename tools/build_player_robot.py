"""Build the salvage robot, its looping clips, editable source, and studio previews.

Blender --background --python tools/build_player_robot.py
Mechanical pivot rig: rigid parts, no deforming skin or texture dependency.
Blender front -Y exports as Godot +Z; native standing height is 1.20 to the head top, with
the antenna rising to 1.445 above that (the game scales by the 1.20 body height).
Clips: Idle, Walk, Run (the bounding trot the game plays while moving), the harvesting swings Chop
(axe) and Mine (pickaxe), Build (wrench taps on a construction site), and Operate (the hand-PTO
docking pose, forearm level into a building's generator socket, HeldPTO spinning). The axe, pickaxe and wrench from tools/build_robot_tools.py sit in the
robot's right hand as HeldAxe, HeldPickaxe and HeldWrench; the game shows the one a clip needs and
hides the others.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import ROOT, PALETTE, mix, reset_scene, material, box, cylinder, prism_y, render_preview
from build_robot_tools import build_axe, build_pickaxe, build_wrench

reset_scene()
cream = material('Robot shell cream', PALETTE['cream'])
teal = material('Robot workshop teal', PALETTE['teal'])
dark = material('Robot joint iron', PALETTE['iron'])
visor = material('Robot visor', PALETTE['shaft'])
amber = material('Robot amber signals', PALETTE['amber'])
steel = material('Robot tool steel', PALETTE['steel'])
timber = material('Robot salvage strap', PALETTE['timber'])
# The antenna tip is the robot's one self-lit part, so the player stands out from above.
beacon = material('Robot antenna beacon', mix(PALETTE['amber'], PALETTE['terracotta'], .35))
beacon.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value = (*PALETTE['amber'], 1)
beacon.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = .5


def pivot(name, position, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = position
    if parent:
        obj.parent = parent
        obj.location = Vector(position) - parent.matrix_world.translation
    bpy.context.view_layer.update()
    return obj


def attach(obj, parent):
    bpy.context.view_layer.update()
    transform = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = transform
    return obj


def block(name, loc, size, mat, parent):
    return attach(box(name, loc, size, mat), parent)


def rod(name, a, b, radius, mat, parent):
    return attach(cylinder(name, a, b, radius, mat), parent)


def shell(name, center, width, depth, height, cut, mat, parent):
    x, y, z = center
    w, h = width / 2, height / 2
    profile = [(x-w+cut, z-h), (x+w-cut, z-h), (x+w, z-h+cut),
               (x+w, z+h-cut), (x+w-cut, z+h), (x-w+cut, z+h),
               (x-w, z+h-cut), (x-w, z-h+cut)]
    return attach(prism_y(name, profile, y-depth/2, y+depth/2, mat), parent)


root = pivot('SalvageRobot', (0, 0, 0))
body = pivot('BodyPivot', (0, 0, .58), root)
head = pivot('HeadPivot', (0, 0, .94), body)
shell('Torso shell', (0, 0, .61), .43, .30, .34, .045, cream, body)
block('Chest power module', (0, -.165, .62), (.25, .05, .20), teal, body)
block('Chest status', (.075, -.195, .66), (.045, .015, .045), amber, body)
block('Utility belt', (0, -.01, .44), (.44, .32, .065), timber, body)
block('Belt buckle', (0, -.18, .44), (.10, .025, .07), steel, body)
block('Back battery', (0, .205, .61), (.30, .13, .25), teal, body)
block('Battery handle', (0, .22, .78), (.18, .065, .05), dark, body)
for x in [-.085, .085]:
    block('Battery rail', (x, .278, .61), (.03, .02, .19), steel, body)
rod('Neck joint', (0, 0, .78), (0, 0, .86), .065, dark, head)
shell('Head shell', (0, -.012, 1.015), .57, .39, .37, .055, cream, head)
shell('Visor frame', (0, -.216, 1.015), .48, .045, .205, .033, teal, head)
shell('Dark face', (0, -.244, 1.015), .415, .025, .15, .02, visor, head)
for x in [-.10, .10]:
    block('Amber eye', (x, -.261, 1.025), (.068, .012, .068), amber, head)
block('Brow panel', (0, -.213, 1.145), (.25, .025, .025), teal, head)
for sign in [-1, 1]:
    rod('Head hinge', (sign*.28, 0, 1.01), (sign*.31, 0, 1.01), .065, teal, head)
# Head top, the face the game camera sees most: a service hatch on the left and the antenna
# on the right rear corner. Head shell top is z=1.20.
block('Hatch rim', (-.07, .0, 1.21), (.27, .21, .02), dark, head)
block('Hatch lid', (-.07, .0, 1.225), (.22, .16, .02), teal, head)
block('Hatch handle', (-.07, -.045, 1.245), (.11, .025, .02), steel, head)
for x in [-.175, .035]:
    block('Hatch hinge', (x, .07, 1.23), (.025, .045, .025), steel, head)
antenna = pivot('AntennaPivot', (.16, .09, 1.20), head)
rod('Antenna socket', (.16, .09, 1.20), (.16, .09, 1.245), .04, dark, antenna)
rod('Antenna mast', (.16, .09, 1.245), (.16, .09, 1.39), .013, steel, antenna)
block('Antenna beacon', (.16, .09, 1.415), (.06, .06, .06), beacon, antenna)

arms, elbows, legs = [], [], []
# The tool hand's two gripper fingers hinge at the wrist so they can open around the PTO spindle.
fingers = []
for sign, side in [(-1, 'Left'), (1, 'Right')]:
    x = sign*.29
    arm = pivot(side+'ArmPivot', (x, 0, .73), body)
    arms.append(arm)
    rod(side+' shoulder axle', (sign*.205, 0, .73), (sign*.30, 0, .73), .07, dark, arm)
    shell(side+' upper arm', (x, 0, .63), .115, .15, .20, .018, teal, arm)
    rod(side+' elbow', (x-.065, 0, .52), (x+.065, 0, .52), .055, steel, arm)
    elbow = pivot(side+'ElbowPivot', (x, 0, .52), arm)
    elbows.append(elbow)
    shell(side+' forearm', (x, -.01, .46), .135, .16, .14, .022, cream, elbow)
    block(side+' tool socket', (x, -.01, .365), (.13, .12, .055), dark, elbow)
    for dx in [-.047, .047]:
        grip = elbow
        if sign < 0:
            grip = pivot(side+('InnerFinger' if dx > 0 else 'OuterFinger')+'Pivot', (x+dx, -.018, .35), elbow)
            fingers.append((grip, 1 if dx < 0 else -1))
        block(side+' gripper finger', (x+dx, -.018, .30), (.035, .12, .10), steel, grip)
        block(side+' gripper tip', (x+dx*.65, -.048, .26), (.05, .065, .035), steel, grip)
    hip = pivot(side+'LegPivot', (sign*.125, 0, .395), root)
    legs.append(hip)
    rod(side+' hip', (sign*.125-.065, 0, .38), (sign*.125+.065, 0, .38), .06, dark, hip)
    block(side+' thigh', (sign*.125, 0, .30), (.12, .13, .14), teal, hip)
    rod(side+' knee', (sign*.125-.068, -.015, .215), (sign*.125+.068, -.015, .215), .055, steel, hip)
    block(side+' shin', (sign*.125, 0, .15), (.125, .13, .10), cream, hip)
    shell(side+' boot', (sign*.125, -.045, .05), .18, .26, .10, .018, dark, hip)
    block(side+' toe panel', (sign*.125, -.13, .075), (.145, .065, .045), teal, hip)

# Held tools for the work clips. The robot faces -Y, so the arm at -X ('Left', named as seen
# from the front) is its own right hand. ToolPivot is the wrist, between the gripper fingers.
hand = arms[0]
tool_pivot = pivot('ToolPivot', (-.29, -.02, .30), elbows[0])
HELD_LENGTH = .72  # butt to head top, a little over half the robot's height
GRIP_Z = .22  # where the gripper holds the handle, in the tool's own units (butt at 0)


def held_tool(name, build):
    """Build a tool upright at the origin, merge it into one mesh and put it in the hand: handle
    pointing forward (-Y), blade or point down, held at GRIP_Z."""
    before = set(bpy.context.scene.objects)
    build()
    parts = [o for o in bpy.context.scene.objects if o not in before]
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts:
        o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    tool = bpy.context.object
    tool.name = name
    tool.data.transform(tool.matrix_world)
    tool.matrix_world = Matrix.Identity(4)
    zs = [v.co.z for v in tool.data.vertices]
    scale = HELD_LENGTH / (max(zs) - min(zs))
    # Tool space has the handle along +Z, the blade toward +X and the panel side on +Y; in the
    # hand those face forward (-Y), down (-Z) and toward the body (+X).
    turn = Matrix(((0, 1, 0, 0), (0, 0, -1, 0), (-1, 0, 0, 0), (0, 0, 0, 1)))
    tool.data.transform(Matrix.Translation(tool_pivot.matrix_world.translation) @ turn
                        @ Matrix.Scale(scale, 4) @ Matrix.Translation((0, 0, -GRIP_Z)))
    tool.data.update()
    return attach(tool, tool_pivot)


held_tools = [held_tool('HeldAxe', build_axe), held_tool('HeldPickaxe', build_pickaxe),
              held_tool('HeldWrench', build_wrench)]

# Hand PTO (art/concepts/player-building-hand-pto-v2-neutral.png): a fixed teal collar at the
# wrist and a splined male spindle that spins inside it, docking into the shared generator's
# socket (tools/build_shared_generator.py). HeldPTO grows out of the wrist like the other tools;
# PTOSpindle turns around the forearm's axis (local Z). With the forearm level (Operate), the
# spindle tip is .35 ahead of the elbow, which puts it inside the socket at the sawmill.
WRIST = (-.29, -.01, .34)
held_pto = pivot('HeldPTO', WRIST, elbows[0])
spindle = pivot('PTOSpindle', WRIST, held_pto)
rod('PTO collar', WRIST, (WRIST[0], WRIST[1], .31), .058, teal, held_pto)
rod('PTO spindle', (WRIST[0], WRIST[1], .31), (WRIST[0], WRIST[1], .18), .042, steel, spindle)
for i in range(6):
    angle = 2*math.pi*i/6
    spline = block('PTO spline', (WRIST[0] + .043*math.cos(angle), WRIST[1] + .043*math.sin(angle), .25),
                   (.016, .016, .10), steel, spindle)
    spline.rotation_euler.z = angle
rod('PTO nose', (WRIST[0], WRIST[1], .18), (WRIST[0], WRIST[1], .17), .028, dark, spindle)
pto_meshes = [o for o in held_pto.children_recursive if o.type == 'MESH']

bpy.context.view_layer.update()
animated = [body, head, antenna, *arms, *elbows, *legs, tool_pivot, spindle, *(f for f, _ in fingers)]
rest = {obj.name: (obj.location.copy(), obj.rotation_euler.copy()) for obj in animated}
scene = bpy.context.scene
scene.render.fps = 30


# Harvesting swings as key poses over one loop (t from 0 to 1), each with the easing into it:
# ready, a slow wind-up overhead, a fast strike, a recoil, and back to ready. Radians. arm: the
# tool arm's swing (negative raises it forward), arm_out: its sideways lift, wrist: ToolPivot
# pitch (positive tips the head down), lean / twist / dip: the body, off: the other arm,
# nod: head pitch, mast: the antenna whipping with the impact.
_READY = dict(arm=-.9, arm_out=0, wrist=.6, lean=.05, twist=0, dip=0, off=-.2, nod=0, mast=0)
SWINGS = {
    # Level blows into the trunk, the axe horizontal at impact.
    'Chop': [
        (0, _READY, None),
        (.42, dict(arm=-2.6, arm_out=-.5, wrist=-.3, lean=-.08, twist=-.18, dip=0, off=-.5,
                   nod=-.06, mast=-.08), 'smooth'),
        (.52, dict(arm=-.95, arm_out=.1, wrist=.95, lean=.2, twist=.14, dip=-.02, off=.25,
                   nod=.1, mast=.05), 'in'),
        (.62, dict(arm=-1.0, arm_out=.1, wrist=.85, lean=.17, twist=.12, dip=-.018, off=.2,
                   nod=.08, mast=.3), 'out'),
        (1, _READY, 'smooth'),
    ],
    # Higher wind-up and a steeper blow down into the rock, bending further in. The wind-ups swing
    # the arm out so the tool clears the head.
    'Mine': [
        (0, _READY, None),
        (.45, dict(arm=-2.75, arm_out=-.5, wrist=-.35, lean=-.1, twist=-.12, dip=0, off=-.45,
                   nod=-.08, mast=-.1), 'smooth'),
        (.55, dict(arm=-.5, arm_out=.08, wrist=.85, lean=.28, twist=.08, dip=-.03, off=.3,
                   nod=.16, mast=.05), 'in'),
        (.66, dict(arm=-.55, arm_out=.08, wrist=.78, lean=.25, twist=.07, dip=-.027, off=.25,
                   nod=.13, mast=.35), 'out'),
        (1, _READY, 'smooth'),
    ],
}
# Construction: short, quick wrench taps at chest height, two per loop, bent in over the work with
# the head down and the free arm reaching forward to steady the part. The body turns a little
# between the taps, as if working along a seam.
_BUILD_READY = dict(arm=-.85, arm_out=0, wrist=.75, lean=.1, twist=0, dip=0, off=-.7, nod=.15, mast=0)


def _build_tap(t, twist):
    lift = dict(arm=-1.35, arm_out=-.15, wrist=.25, lean=.07, twist=twist, dip=0, off=-.75, nod=.12,
                mast=-.05)
    strike = dict(arm=-.72, arm_out=.05, wrist=1.0, lean=.15, twist=twist, dip=-.012, off=-.68,
                  nod=.2, mast=.05)
    rebound = dict(strike, arm=-.8, wrist=.9, lean=.13, mast=.25)
    return [(t, lift, 'smooth'), (t+.1, strike, 'in'), (t+.18, rebound, 'out')]


SWINGS['Build'] = [(0, _BUILD_READY, None), *_build_tap(.2, -.06), *_build_tap(.62, .06),
                   (1, _BUILD_READY, 'smooth')]
_EASE = {'smooth': lambda u: u*u*(3-2*u), 'in': lambda u: u*u, 'out': lambda u: 1-(1-u)*(1-u)}


def swing_pose(keys, t):
    for (t0, a, _), (t1, b, ease) in zip(keys, keys[1:]):
        if t <= t1:
            u = _EASE[ease]((t-t0)/(t1-t0))
            return {k: a[k] + (b[k]-a[k])*u for k in a}
    return dict(keys[-1][1])


# Walk geometry: the hip pivot to the sole, and how far a planted boot travels either side of the
# hip (the old +/-0.34 radian swing). The body covers 4 * STRIDE (0.527) per loop, which
# PlayerUnit.WALK_CYCLE_DISTANCE matches to the robot's movement speed.
LEG_LENGTH = .395
STRIDE = LEG_LENGTH*math.sin(.34)
# Run (the clip played while moving): each boot is planted for only RUN_CONTACT of the loop, so
# the robot is airborne for the rest of each half, bounding RUN_HANG above the straight line
# between push-off and landing. A planted boot travels RUN_STRIDE either side of the hip (a
# 0.55 radian swing); the body covers 2 * RUN_STRIDE / RUN_CONTACT (1.652) per loop, which
# PlayerUnit.RUN_CYCLE_DISTANCE matches to the robot's movement speed.
RUN_CONTACT = .25
RUN_STRIDE = LEG_LENGTH*math.sin(.55)
RUN_HANG = .035


def _planted_hip(angle):
    """Height of a leg's hip pivot that keeps its tilted boot's lowest corner on the floor."""
    toe_extent = .175 if angle >= 0 else .085
    return LEG_LENGTH*math.cos(angle) + toe_extent*abs(math.sin(angle))


def animate(clip, end_frame):
    for obj in animated:
        obj.animation_data_create()
        obj.animation_data.action = None
    for frame in range(1, end_frame+1):
        phase = 2*math.pi*(frame-1)/(end_frame-1)
        for obj in animated:
            obj.location, obj.rotation_euler = rest[obj.name]
        if clip in SWINGS:
            pose = swing_pose(SWINGS[clip], (frame-1)/(end_frame-1))
            hand.rotation_euler.x += pose['arm']
            hand.rotation_euler.y += pose['arm_out']
            tool_pivot.rotation_euler.x += pose['wrist']
            body.rotation_euler.x += pose['lean']
            body.rotation_euler.z += pose['twist']
            body.location.z += pose['dip']
            arms[1].rotation_euler.x += pose['off']
            head.rotation_euler.x += pose['nod']
            antenna.rotation_euler.x += pose['mast']
        elif clip == 'Operate':
            # Neutral docking pose: upright, tool upper arm hanging, elbow at 90 degrees so the
            # forearm points level straight ahead, gripper open around the spinning spindle (two
            # turns per loop; its six splines make any whole turn seamless). The working thrum is
            # a small fast bob, a buzzing antenna and the free arm swaying, all looping.
            elbows[0].rotation_euler.x = -math.pi/2
            for finger, opens in fingers:
                finger.rotation_euler.y = opens*.45
            spindle.rotation_euler.z = -2*phase
            body.location.z += .004*(1-math.cos(4*phase))
            head.rotation_euler.x = .12 + .015*math.sin(4*phase)
            head.rotation_euler.z = .04*math.sin(phase)
            antenna.rotation_euler.x = .07*math.sin(8*phase)
            arms[1].rotation_euler.x = .04*math.sin(phase)
        elif clip == 'Idle':
            body.location.z += .006*(1-math.cos(phase))
            head.rotation_euler.z = .09*math.sin(phase)
            head.rotation_euler.x = .025*math.sin(phase)
            # The mast trails the head scan slightly.
            antenna.rotation_euler.y = -.05*math.sin(phase-.6)
            for i, arm in enumerate(arms):
                arm.rotation_euler.x = .035*math.sin(phase+i*math.pi)
        elif clip == 'Run':
            t = (frame-1)/(end_frame-1)
            # Hip height for each boot: planted (on the floor) while in contact, the pelvis then
            # follows the planted leg, rising from the touchdown to the push-off; between contacts
            # it floats from one to the next with a little hang.
            us = [(t + i*.5) % 1 for i in range(2)]
            in_contact = [u < RUN_CONTACT for u in us]
            reaches = []
            for u in us:
                if u < RUN_CONTACT:
                    reaches.append(RUN_STRIDE*(2*u/RUN_CONTACT - 1))
                else:
                    s = (u - RUN_CONTACT)/(1 - RUN_CONTACT)
                    reaches.append(RUN_STRIDE*(1 - 2*s*s*(3 - 2*s)))
            angles = [math.asin(r/LEG_LENGTH) for r in reaches]
            if any(in_contact):
                pelvis = _planted_hip(angles[in_contact.index(True)]) - LEG_LENGTH
            else:
                f = ((t % .5) - RUN_CONTACT)/(.5 - RUN_CONTACT)
                off = _planted_hip(math.asin(RUN_STRIDE/LEG_LENGTH)) - LEG_LENGTH
                land = _planted_hip(-math.asin(RUN_STRIDE/LEG_LENGTH)) - LEG_LENGTH
                pelvis = off + (land - off)*f + RUN_HANG*4*f*(1 - f)
            body.location.z += pelvis
            # Leaning into the run, head up to look ahead, the body rolling toward the planted leg.
            body.rotation_euler.x = .14
            body.rotation_euler.z = .05*math.sin(2*math.pi*t)
            head.rotation_euler.x = -.09
            head.rotation_euler.z = -.03*math.sin(2*math.pi*t)
            # The mast whips down on each landing and springs back in the air.
            antenna.rotation_euler.x = .16*math.sin(4*math.pi*t - 1.4)
            antenna.rotation_euler.y = .06*math.sin(2*math.pi*t - .8)
            for i in range(2):
                legs[i].rotation_euler.x = angles[i]
                if in_contact[i]:
                    legs[i].location.z = _planted_hip(angles[i])
                else:
                    # A swinging boot rides with the pelvis, tucked up clear of the floor.
                    tuck = .09*math.sin(math.pi*(us[i] - RUN_CONTACT)/(1 - RUN_CONTACT))
                    legs[i].location.z = LEG_LENGTH + pelvis + tuck
                # Bent arms pump against the legs, furthest forward as the same-side boot pushes off.
                arms[i].rotation_euler.x = -.5*math.cos(2*math.pi*(us[i] - RUN_CONTACT))
                elbows[i].rotation_euler.x = -1.15
        else:
            body.location.z += .014*(1-math.cos(2*phase))
            body.rotation_euler.z = .04*math.sin(phase)
            head.rotation_euler.z = -.025*math.sin(phase)
            # Springy mast: nods with each step's bob and sways with the body, a beat behind.
            antenna.rotation_euler.x = .10*math.sin(2*phase-1.0)
            antenna.rotation_euler.y = .07*math.sin(phase-.8)
            for i in range(2):
                # Each boot is planted for half the loop and swings for the other half, the two
                # legs half a loop apart. Planted, it slides back under the hip at a constant rate
                # (the body moving on over it at constant speed), from STRIDE in front to STRIDE
                # behind; swinging, it eases forward again with a small lift. Reach is the boot's
                # distance behind the hip; positive leg rotation swings it back.
                u = ((frame-1)/(end_frame-1) + i*.5) % 1
                if u < .5:
                    reach = STRIDE*(4*u - 1)
                    lift = 0
                else:
                    s = (u - .5)*2
                    reach = STRIDE*(1 - 2*s*s*(3 - 2*s))
                    lift = .05*math.sin(math.pi*s)
                angle = math.asin(reach/LEG_LENGTH)
                legs[i].rotation_euler.x = angle
                legs[i].location.z = _planted_hip(angle) + lift
                # Arms counter-swing smoothly, furthest forward as the same-side boot is furthest back.
                arms[i].rotation_euler.x = .27*math.cos(2*math.pi*u)
        for obj in animated:
            obj.keyframe_insert('location', frame=frame)
            obj.keyframe_insert('rotation_euler', frame=frame)
    for obj in animated:
        action = obj.animation_data.action
        action.name = clip+'_'+obj.name
        track = obj.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, 1, action)
        strip.extrapolation = 'NOTHING'
        strip.blend_type = 'REPLACE'
        obj.animation_data.action = None
        track.mute = True
        obj.location, obj.rotation_euler = rest[obj.name]


animate('Idle', 91)  # 3 seconds
animate('Walk', 25)  # 0.8 seconds, in place
animate('Run', 33)  # in place; the game plays it at the movement speed (about 4 loops a second)
animate('Chop', 31)  # 1.0 second per blow
animate('Mine', 37)  # 1.2 seconds per blow
animate('Build', 37)  # 1.2 seconds, two taps
animate('Operate', 31)  # 1.0 second loop, the spindle at two turns a second
scene.frame_start, scene.frame_end = 1, 91
scene.frame_set(1)

# Keep rigid pieces parented to their pivots; joining the complete model would destroy the rig.
for obj in list(scene.objects):
    if obj.type == 'MESH':
        bpy.context.view_layer.objects.active = obj
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.ops.object.select_all(action='SELECT')
asset_path = ROOT/'assets/models/units/salvage_robot.glb'
asset_path.parent.mkdir(parents=True, exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(asset_path), export_format='GLB', use_selection=True,
                          export_animation_mode='NLA_TRACKS', export_animations=True,
                          export_force_sampling=True,
                          # Clips are keyed from frame 1; without this each starts at frame 0, holding
                          # its first pose an extra frame and hitching every loop.
                          export_anim_slide_to_zero=True,
                          # Keep held-still channels (the elbow locked at 90 degrees in Operate):
                          # without them a pose that never moves within a clip is lost, and the next
                          # clip wouldn't reset it.
                          export_optimize_animation_keep_anim_object=True)
print('SALVAGE_ROBOT exported:', asset_path)

def solo(clip):
    for obj in animated:
        for track in obj.animation_data.nla_tracks:
            track.mute = track.name != clip


# The held tools only show in the swing and operate previews, as in the game.
for tool in held_tools + pto_meshes:
    tool.hide_render = True
solo('Idle')
render_preview('salvage_robot', target_z=.60, ortho_scale=1.9,
               camera=(-2.8, -5, 3.1), plinth_radius=.65, resolution=768)

# A twelve-frame walk preview uses the same source rig, not a separate animation.
frames_dir = ROOT/'art/previews/salvage_robot_walk'
frames_dir.mkdir(parents=True, exist_ok=True)
solo('Walk')
scene.render.resolution_x = scene.render.resolution_y = 384
scene.cycles.samples = 16
for i, frame in enumerate(range(1, 25, 2)):
    scene.frame_set(frame)
    scene.render.filepath = str(frames_dir/f'{i:02}.png')
    bpy.ops.render.render(write_still=True)
print('WALK preview frames:', frames_dir)

# Run preview: sixteen frames across one loop, side on so the push-off and float read.
frames_dir = ROOT/'art/previews/salvage_robot_run'
frames_dir.mkdir(parents=True, exist_ok=True)
solo('Run')
for i, frame in enumerate(range(1, 33, 2)):
    scene.frame_set(frame)
    scene.render.filepath = str(frames_dir/f'{i:02}.png')
    bpy.ops.render.render(write_still=True)
print('RUN preview frames:', frames_dir)

# Swing previews: ten frames across each blow, held tool shown, from the tool side and a little
# in front so the arc reads, framed wider for the wind-up.
scene.camera.location = (-5.2, -1.6, 1.6)
scene.camera.rotation_euler = (Vector((0, -.25, .62)) - scene.camera.location).to_track_quat('-Z', 'Y').to_euler()
scene.camera.data.ortho_scale = 2.4
for clip, tool, end_frame in [('Chop', held_tools[0], 31), ('Mine', held_tools[1], 37),
                              ('Build', held_tools[2], 37)]:
    frames_dir = ROOT/'art/previews'/('salvage_robot_'+clip.lower())
    frames_dir.mkdir(parents=True, exist_ok=True)
    solo(clip)
    tool.hide_render = False
    for i in range(10):
        scene.frame_set(1 + round(i*(end_frame-1)/10))
        scene.render.filepath = str(frames_dir/f'{i:02}.png')
        bpy.ops.render.render(write_still=True)
    tool.hide_render = True
    print(clip.upper(), 'preview frames:', frames_dir)

# Operate preview: one still of the docking pose from the tool side, PTO shown.
solo('Operate')
for part in pto_meshes:
    part.hide_render = False
scene.frame_set(1)
scene.render.resolution_x = scene.render.resolution_y = 768
scene.cycles.samples = 40
scene.render.filepath = str(ROOT/'art/previews/salvage_robot_operate.png')
bpy.ops.render.render(write_still=True)
print('OPERATE preview:', scene.render.filepath)
