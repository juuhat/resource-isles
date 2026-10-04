"""Build the salvage robot, two looping clips, editable source, and studio previews.

Blender --background --python tools/build_player_robot.py
Mechanical pivot rig: rigid parts, no deforming skin or texture dependency.
Blender front -Y exports as Godot +Z; native standing height is 1.20 to the head top, with
the antenna rising to 1.445 above that (the game scales by the 1.20 body height).
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import ROOT, PALETTE, mix, reset_scene, material, box, cylinder, prism_y, render_preview

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

arms, legs = [], []
for sign, side in [(-1, 'Left'), (1, 'Right')]:
    x = sign*.29
    arm = pivot(side+'ArmPivot', (x, 0, .73), body)
    arms.append(arm)
    rod(side+' shoulder axle', (sign*.205, 0, .73), (sign*.30, 0, .73), .07, dark, arm)
    shell(side+' upper arm', (x, 0, .63), .115, .15, .20, .018, teal, arm)
    rod(side+' elbow', (x-.065, 0, .52), (x+.065, 0, .52), .055, steel, arm)
    shell(side+' forearm', (x, -.01, .46), .135, .16, .14, .022, cream, arm)
    block(side+' tool socket', (x, -.01, .365), (.13, .12, .055), dark, arm)
    for dx in [-.047, .047]:
        block(side+' gripper finger', (x+dx, -.018, .30), (.035, .12, .10), steel, arm)
        block(side+' gripper tip', (x+dx*.65, -.048, .26), (.05, .065, .035), steel, arm)
    hip = pivot(side+'LegPivot', (sign*.125, 0, .395), root)
    legs.append(hip)
    rod(side+' hip', (sign*.125-.065, 0, .38), (sign*.125+.065, 0, .38), .06, dark, hip)
    block(side+' thigh', (sign*.125, 0, .30), (.12, .13, .14), teal, hip)
    rod(side+' knee', (sign*.125-.068, -.015, .215), (sign*.125+.068, -.015, .215), .055, steel, hip)
    block(side+' shin', (sign*.125, 0, .15), (.125, .13, .10), cream, hip)
    shell(side+' boot', (sign*.125, -.045, .05), .18, .26, .10, .018, dark, hip)
    block(side+' toe panel', (sign*.125, -.13, .075), (.145, .065, .045), teal, hip)

bpy.context.view_layer.update()
animated = [body, head, antenna, *arms, *legs]
rest = {obj.name: (obj.location.copy(), obj.rotation_euler.copy()) for obj in animated}
scene = bpy.context.scene
scene.render.fps = 30


def animate(clip, end_frame):
    for obj in animated:
        obj.animation_data_create()
        obj.animation_data.action = None
    for frame in range(1, end_frame+1):
        phase = 2*math.pi*(frame-1)/(end_frame-1)
        for obj in animated:
            obj.location, obj.rotation_euler = rest[obj.name]
        if clip == 'Idle':
            body.location.z += .006*(1-math.cos(phase))
            head.rotation_euler.z = .09*math.sin(phase)
            head.rotation_euler.x = .025*math.sin(phase)
            # The mast trails the head scan slightly.
            antenna.rotation_euler.y = -.05*math.sin(phase-.6)
            for i, arm in enumerate(arms):
                arm.rotation_euler.x = .035*math.sin(phase+i*math.pi)
        else:
            body.location.z += .014*(1-math.cos(2*phase))
            body.rotation_euler.z = .04*math.sin(phase)
            head.rotation_euler.z = -.025*math.sin(phase)
            # Springy mast: nods with each step's bob and sways with the body, a beat behind.
            antenna.rotation_euler.x = .10*math.sin(2*phase-1.0)
            antenna.rotation_euler.y = .07*math.sin(phase-.8)
            for i in range(2):
                stride = math.sin(phase+i*math.pi)
                angle = .34*stride
                legs[i].rotation_euler.x = angle
                # Keep the stance boot's lowest corner on the floor; lift only the swing boot.
                toe_extent = .175 if angle >= 0 else .085
                legs[i].location.z = (.395*math.cos(angle) + toe_extent*abs(math.sin(angle))
                                      + .04*max(0, -stride))
                arms[i].rotation_euler.x = -.27*stride
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
                          export_force_sampling=True)
print('SALVAGE_ROBOT exported:', asset_path)

for obj in animated:
    for track in obj.animation_data.nla_tracks:
        track.mute = track.name != 'Idle'
render_preview('salvage_robot', target_z=.60, ortho_scale=1.9,
               camera=(-2.8, -5, 3.1), plinth_radius=.65, resolution=768)

# A twelve-frame walk preview uses the same source rig, not a separate animation.
frames_dir = ROOT/'art/previews/salvage_robot_walk'
frames_dir.mkdir(parents=True, exist_ok=True)
for obj in animated:
    for track in obj.animation_data.nla_tracks:
        track.mute = track.name != 'Walk'
scene.render.resolution_x = scene.render.resolution_y = 384
scene.cycles.samples = 16
for i, frame in enumerate(range(1, 25, 2)):
    scene.frame_set(frame)
    scene.render.filepath = str(frames_dir/f'{i:02}.png')
    bpy.ops.render.render(write_still=True)
print('WALK preview frames:', frames_dir)
