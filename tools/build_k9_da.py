"""Blender --background --python tools/build_k9_da.py.

K9-DA: cream/teal mechanical companion, rigid pivots, embedded Idle, LieDown, Sit and Walk.
Front is Blender -Y / Godot +Z. Studio scenery is excluded from the GLB.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import ROOT, PALETTE, reset_scene, material, box, cylinder, prism_y, render_preview

reset_scene()
cream = material('K9 cream shell', PALETTE['cream'])
teal = material('K9 teal panels', PALETTE['teal'])
iron = material('K9 iron joints', PALETTE['iron'])
steel = material('K9 steel', PALETTE['steel'])
dark = material('K9 visor and paw pads', PALETTE['shaft'])
amber = material('K9 amber eyes', PALETTE['amber'])
amber.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value = (*PALETTE['amber'], 1)
amber.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = .35


def pivot(name, loc, parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = loc
    if parent:
        obj.parent = parent
        obj.location = Vector(loc) - parent.matrix_world.translation
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


def rod(name, start, end, radius, mat, parent):
    return attach(cylinder(name, start, end, radius, mat, 8), parent)


def shell(name, loc, size, cut, mat, parent):
    x, y, z = loc
    w, depth, h = (s / 2 for s in size)
    profile = [(x-w+cut, z-h), (x+w-cut, z-h), (x+w, z-h+cut),
               (x+w, z+h-cut), (x+w-cut, z+h), (x-w+cut, z+h),
               (x-w, z+h-cut), (x-w, z-h+cut)]
    return attach(prism_y(name, profile, y-depth, y+depth, mat), parent)


root = pivot('K9DA', (0, 0, 0))
body = pivot('BodyPivot', (0, 0, .43), root)
shell('Barrel shell', (0, .025, .45), (.40, .68, .30), .055, cream, body)
shell('Back service hatch', (0, .06, .612), (.27, .43, .035), .014, teal, body)
for x in [-.19, .19]:
    block('Side battery', (x, .10, .45), (.055, .32, .15), teal, body)
    for y in [.01, .08, .15]:
        block('Battery cooling fin', (x * 1.17, y, .46), (.015, .025, .085), iron, body)
block('Back latch', (0, .20, .637), (.08, .08, .02), steel, body)
rod('Neck coupling', (0, -.25, .49), (0, -.37, .57), .09, iron, body)
head = pivot('HeadPivot', (0, -.36, .59), body)
shell('Head shell', (0, -.43, .64), (.37, .30, .27), .045, cream, head)
shell('Visor frame', (0, -.59, .655), (.31, .025, .145), .025, teal, head)
shell('Dark visor', (0, -.606, .655), (.265, .02, .108), .02, dark, head)
for x in [-.075, .075]:
    block('Amber eye', (x, -.621, .66), (.052, .016, .040), amber, head)
shell('Short muzzle', (0, -.616, .555), (.20, .12, .095), .022, cream, head)
block('Nose sensor', (0, -.683, .573), (.075, .018, .044), iron, head)
ears = []
for side, x in [('Left', -.145), ('Right', .145)]:
    ear = pivot(side+'EarPivot', (x, -.40, .745), head)
    attach(prism_y(side+' ear', [(x-.058, .748), (x+.058, .748), (x+.035, .92),
                                (x-.025, .90)], -.43, -.37, teal), ear)
    ears.append(ear)

# Four independently articulated legs; diagonal pairs trot together.
legs = []
for label, x, y in [('FrontLeft', -.205, -.205), ('FrontRight', .205, -.205),
                    ('RearLeft', -.205, .255), ('RearRight', .205, .255)]:
    leg = pivot(label+'LegPivot', (x, y, .39), body)
    rod(label+' shoulder', (x-.04, y, .39), (x+.04, y, .39), .072, iron, leg)
    shell(label+' upper leg', (x, y, .285), (.105, .13, .20), .02, teal, leg)
    rod(label+' knee', (x-.059, y, .19), (x+.059, y, .19), .043, steel, leg)
    shell(label+' shin', (x, y, .115), (.085, .095, .16), .014, cream, leg)
    shell(label+' paw', (x, y-.035, .035), (.135, .18, .07), .016, iron, leg)
    block(label+' pad', (x, y-.035, .008), (.11, .15, .016), dark, leg)
    legs.append(leg)
tail = pivot('TailPivot', (0, .37, .51), body)
rod('Tail hinge', (-.05, .37, .51), (.05, .37, .51), .055, iron, tail)
rod('Raised tail', (0, .37, .51), (0, .55, .77), .034, teal, tail)
rod('Tail tip', (0, .55, .77), (0, .575, .805), .046, cream, tail)

scene = bpy.context.scene
scene.render.fps = 30
animated = [body, head, tail] + ears + legs
rest = {o.name: (o.location.copy(), o.rotation_euler.copy()) for o in animated}


def animate(clip, frames):
    for frame in range(1, frames+1):
        phase = 2 * math.pi * (frame-1) / (frames-1)
        for obj in animated:
            obj.location, obj.rotation_euler = rest[obj.name]
        tail.rotation_euler.z = (.25 if clip == 'Idle' else .15) * math.sin(phase * 2)
        if clip == 'Idle':
            body.location.z += .007 * math.sin(phase)
            head.rotation_euler.z = .13 * math.sin(phase)
            head.rotation_euler.x = .035 * math.sin(phase * 2)
            ears[0].rotation_euler.y = .08 * math.sin(phase)
            ears[1].rotation_euler.y = -.06 * math.sin(phase + .7)
        elif clip == 'LieDown':
            # Roll onto the right flank; the upper legs relax across the lower pair.
            breath = .004 * (1-math.cos(phase))
            body.location.z = .27 + breath
            body.location.x = .12
            body.rotation_euler.y = math.pi/2
            head.location.x += .06
            head.rotation_euler.x = .12 + .012 * math.sin(phase)
            head.rotation_euler.z = .018 * math.sin(phase)
            tail.rotation_euler.x = -.9
            tail.rotation_euler.z = .035 * math.sin(phase * 2)
            ears[0].rotation_euler.y = -.18 + .035 * math.sin(phase * 2)
            ears[1].rotation_euler.y = .18 - .025 * math.sin(phase * 2)
            for i, leg in enumerate(legs):
                leg.rotation_euler.x = [-.32, -.12, .28, .12][i]
                leg.rotation_euler.y = -.95 if i in [0, 2] else .02
        elif clip == 'Sit':
            # Riding the skiff: the barrel pitched up onto its rump, front legs straight down, the
            # rigid hind legs folded forward along the deck just outside the front paws, the tail
            # curled round to its left. The head scans the water.
            body.location.z += -.097 + .004 * (1-math.cos(phase))
            body.rotation_euler.x = -.675
            head.rotation_euler.x = .5 + .03 * math.sin(phase * 2)
            head.rotation_euler.z = .22 * math.sin(phase)
            tail.rotation_euler.x = -.35
            tail.rotation_euler.z = -.9 + .2 * math.sin(phase * 2)
            ears[0].rotation_euler.y = .08 * math.sin(phase)
            ears[1].rotation_euler.y = -.06 * math.sin(phase + .7)
            for i, leg in enumerate(legs):
                front, left = i < 2, i % 2 == 0
                leg.rotation_euler.x = .675 if front else -.67
                leg.rotation_euler.y = (-.25 if front else .08) * (1 if left else -1)
        else:
            body.location.z += .014 * (1-math.cos(phase*2))
            head.rotation_euler.x = .035 * math.sin(phase*2)
            for i, leg in enumerate(legs):
                u = ((frame-1)/(frames-1) + (0 if i in [0, 3] else .5)) % 1
                # Constant-speed planted sweep, then a lifted return. No root translation.
                reach = .10 - .40*u if u < .5 else -.10 + .40*(u-.5)
                angle = math.asin(reach/.39)
                leg.rotation_euler.x = angle
                leg.location.z += .39*(math.cos(angle)-1)
                if u >= .5:
                    leg.location.z += .075 * math.sin(2*math.pi*(u-.5))
        for obj in animated:
            obj.keyframe_insert('location', frame=frame)
            obj.keyframe_insert('rotation_euler', frame=frame)
    for obj in animated:
        action = obj.animation_data.action
        action.name = clip+'_'+obj.name
        for layer in action.layers:
            for strip in layer.strips:
                for bag in strip.channelbags:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = 'LINEAR'
        track = obj.animation_data.nla_tracks.new()
        track.name = clip
        strip = track.strips.new(clip, 1, action)
        strip.extrapolation = 'NOTHING'
        obj.animation_data.action = None
        track.mute = True
        obj.location, obj.rotation_euler = rest[obj.name]


animate('Idle', 91)
animate('Walk', 25)  # .8 seconds; .4 native units traveled per cycle.
animate('LieDown', 121)  # Four-second quiet stranded loop.
animate('Sit', 91)  # Three seconds, seated aboard the skiff.
scene.frame_start, scene.frame_end = 1, 91
scene.frame_set(1)
bpy.ops.object.select_all(action='SELECT')
asset = ROOT/'assets/models/units/k9_da.glb'
bpy.ops.export_scene.gltf(filepath=str(asset), export_format='GLB', use_selection=True,
                          export_animation_mode='NLA_TRACKS', export_animations=True,
                          export_force_sampling=True, export_anim_slide_to_zero=True,
                          export_optimize_animation_keep_anim_object=True)
for obj in animated:
    for track in obj.animation_data.nla_tracks:
        track.mute = track.name != 'Idle'
render_preview('k9_da', target_z=.43, ortho_scale=1.75, plinth_radius=.75,
               camera=(-3, -5, 3.1), resolution=768)
print('K9-DA exported:', asset)
for obj in animated:
    for track in obj.animation_data.nla_tracks:
        track.mute = track.name != 'LieDown'
scene.frame_set(1)
scene.render.filepath = str(ROOT/'art/previews/k9_da_lying.png')
bpy.ops.render.render(write_still=True)
for obj in animated:
    for track in obj.animation_data.nla_tracks:
        track.mute = track.name != 'Sit'
scene.frame_set(1)
scene.render.filepath = str(ROOT/'art/previews/k9_da_sitting.png')
bpy.ops.render.render(write_still=True)
