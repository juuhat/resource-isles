"""Build the robot's three lost tools (the "Recover Your Tools" pickups): axe, pickaxe, wrench.

Blender --background --python tools/build_robot_tools.py
Exports assets/models/items/<tool>.glb, saves art/blender/tool_<tool>.blend and renders
art/previews/tool_<tool>.png plus art/previews/robot_tools.png with all three side by side.

Each tool keeps its classic head silhouette (bearded axe blade, curved pick with a point and a
chisel, open-end wrench with a nut seat) on a handle built like the salvage robot (tools/build_player_robot.py):
an iron socket plug at the butt that slots into the robot's arm tool socket, with an amber
status light, teal collars, a timber-coloured grip wrap like the robot's utility belt, a cream
shaft and a cream head housing with a teal panel and steel bolts.

Modelled upright (handle along +Z, details on the +Y face), then laid flat on the ground so the
silhouette faces the camera. True tile scale (lowpoly_kit.TILE units per tile): every tool is
TOOL_LENGTH_TILES long, its origin at the centre of its bounds on the ground, head toward -Y
(Godot +Z). The game spawns it at the fixed true-tile scale and turns it per pickup.
"""
import math
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import (ROOT, PALETTE, TILE, mix, reset_scene, material, box, cylinder, prism_y,
                         export, render_preview)

# Sized for the robot (0.45 tiles tall) to carry: about two thirds of its height.
TOOL_LENGTH_TILES = .3

reset_scene()
cream = material('Tool shell cream', PALETTE['cream'])
teal = material('Tool workshop teal', PALETTE['teal'])
iron = material('Tool socket iron', PALETTE['iron'])
# Dark forged heads with a bright honed edge, like the icons' signature tools.
steel = material('Tool head steel', mix(PALETTE['iron'], PALETTE['stone'], .3), rough=.55)
bright = material('Tool bright steel', PALETTE['steel'], rough=.55)
edge = material('Tool honed edge', mix(PALETTE['steel'], PALETTE['cream'], .3), rough=.4)
grip = material('Tool grip wrap', PALETTE['timber'])
# The status light is the one self-lit part, so a dropped tool glints on the ground.
light = material('Tool status light', PALETTE['amber'])
light.node_tree.nodes['Principled BSDF'].inputs['Emission Color'].default_value = (*PALETTE['amber'], 1)
light.node_tree.nodes['Principled BSDF'].inputs['Emission Strength'].default_value = .6


def shell(name, center, width, depth, height, cut, mat):
    """Box with chamfered corners in the XZ plane, the robot's shell profile."""
    x, y, z = center
    w, h = width / 2, height / 2
    profile = [(x-w+cut, z-h), (x+w-cut, z-h), (x+w, z-h+cut), (x+w, z+h-cut),
               (x+w-cut, z+h), (x-w+cut, z+h), (x-w, z+h-cut), (x-w, z-h+cut)]
    return prism_y(name, profile, y - depth/2, y + depth/2, mat)


def bolt(x, z, y=.0, radius=.019):
    """Steel bolt head on the housing's top (+Y) face, whose surface is at y."""
    cylinder('Housing bolt', (x, y, z), (x, y + .014, z), radius, bright, 6)


def handle(shaft_top):
    """Robot-built handle from the butt (z=0) up to shaft_top."""
    cylinder('Socket end cap', (0, 0, -.018), (0, 0, 0), .044, bright)
    cylinder('Socket plug', (0, 0, 0), (0, 0, .11), .058, iron)
    for z in [.025, .085]:
        cylinder('Socket key ridge', (0, 0, z - .006), (0, 0, z + .006), .062, iron)
    box('Socket status light', (0, .056, .055), (.026, .014, .034), light)
    cylinder('Lower collar', (0, 0, .11), (0, 0, .14), .052, teal)
    cylinder('Grip wrap', (0, 0, .14), (0, 0, .40), .045, grip)
    for z in [.20, .27, .34]:
        cylinder('Grip ridge', (0, 0, z - .008), (0, 0, z + .008), .049, iron)
    cylinder('Upper collar', (0, 0, .40), (0, 0, .43), .047, teal)
    cylinder('Shaft', (0, 0, .43), (0, 0, shaft_top), .04, cream)


def housing(center, width, height, depth=.11):
    """Cream head housing where the head mounts, with a teal panel and two bolts on top."""
    x, _, z = center
    shell('Head housing', center, width, depth, height, .03, cream)
    box('Housing panel', (x, depth/2 + .005, z), (width - .05, .01, height - .07), teal)
    for dz in [-1, 1]:
        bolt(x, z + dz * (height/2 - .035), depth/2)


def arc(cx, cz, radius, degrees):
    return [(cx + radius * math.cos(math.radians(a)), cz + radius * math.sin(math.radians(a)))
            for a in degrees]


def build_axe():
    handle(.80)
    housing((0, 0, .865), .15, .25)
    # Bearded blade on +X: a dark steel body and a thinner, lighter honed edge along the arc.
    angles = [40 - 11 * i for i in range(9)]  # 40 .. -48 degrees
    outer = arc(.12, .85, .25, angles)
    inner = arc(.12, .85, .20, angles)
    body = [(.06, .955), (.17, .945)] + inner + [(.18, .745), (.11, .79), (.06, .80)]
    prism_y('Axe blade', body, -.03, .03, steel)
    prism_y('Axe edge', outer + inner[::-1], -.019, .019, edge)
    # Teal poll on the back, like a robot module, capped in steel.
    box('Axe poll', (-.10, 0, .865), (.07, .085, .13), teal)
    box('Axe poll cap', (-.14, 0, .865), (.02, .075, .11), bright)


def build_pickaxe():
    handle(.85)
    # Curved head: a point on the left, a flat chisel on the right; tips in honed steel.
    def profile(t0, t1, steps):
        top, bottom = [], []
        for i in range(steps + 1):
            t = t0 + (t1 - t0) * i / steps
            x, z = .47 * t, .985 - .22 * t * t
            h = .135 * (1 - abs(t) ** 1.4) + .01 if t < 0 else .135 - .085 * t * t
            top.append((x, z))
            bottom.append((x, z - h))
        return top + bottom[::-1]
    prism_y('Pick head', profile(-.78, .8, 16), -.042, .042, steel)
    prism_y('Pick point', profile(-1, -.78, 3), -.03, .03, edge)
    prism_y('Pick chisel', profile(.8, 1, 3), -.03, .03, edge)
    housing((0, 0, .895), .15, .20, depth=.12)


def build_wrench():
    handle(.80)
    # Open-end jaw: a round steel head with a slot tilted 15 degrees off the handle, its bottom
    # a half-hexagon seat for a nut, and honed steel faces lining the slot.
    cx, cz, radius, half_slot = 0, .955, .14, .055
    axis = math.radians(75)
    d = (math.cos(axis), math.sin(axis))   # slot direction, out of the jaw mouth
    n = (math.sin(axis), -math.cos(axis))  # across the slot, toward its right side
    spread = math.degrees(math.asin(half_slot / radius))
    start, end = 75 + spread, 75 - spread + 360
    rim = arc(cx, cz, radius, [start + (end - start) * i / 20 for i in range(21)])

    def at(along, across):
        return (cx + d[0] * along + n[0] * across, cz + d[1] * along + n[1] * across)
    seat = [at(0, half_slot), at(-.032, half_slot * .5), at(-.032, -half_slot * .5), at(0, -half_slot)]
    prism_y('Wrench jaw', rim + seat, -.035, .035, steel)
    for side in [1, -1]:
        face = [at(.02, side * half_slot), at(radius * .93, side * half_slot),
                at(radius * .93, side * (half_slot + .016)), at(.02, side * (half_slot + .016))]
        prism_y('Wrench jaw face', face, -.037, .037, edge)
    # Neck flaring from the shaft into the jaw, under the cream housing.
    prism_y('Wrench neck', [(-.045, .78), (.045, .78), (.075, .87), (-.075, .87)], -.03, .03, steel)
    housing((0, 0, .80), .13, .12, depth=.10)


def lay_flat():
    """Bake every mesh's transform, lay the tool on its back (+Y face up, head toward -Y), scale
    it to TOOL_LENGTH_TILES, and put the origin at the centre of its bounds on the ground."""
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    lay = Matrix.Rotation(math.radians(90), 4, 'X')
    for o in meshes:
        o.data.transform(lay @ o.matrix_world)
        o.matrix_world = Matrix.Identity(4)
    points = [v.co for o in meshes for v in o.data.vertices]
    lo = Vector([min(p[i] for p in points) for i in range(3)])
    hi = Vector([max(p[i] for p in points) for i in range(3)])
    length = hi.y - lo.y
    scale = TOOL_LENGTH_TILES * TILE / length
    center = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    fit = Matrix.Scale(scale, 4) @ Matrix.Translation(-center)
    for o in meshes:
        o.data.transform(fit)
        o.data.update()


TOOLS = [('axe', build_axe), ('pickaxe', build_pickaxe), ('wrench', build_wrench)]
for name, build in TOOLS:
    reset_scene()
    build()
    lay_flat()
    export(name, folder='assets/models/items', join_label='Tool ' + name)
    render_preview('tool_' + name, target_z=0, ortho_scale=1.1, true_tile=True,
                   camera=(-1.4, -4.3, 4.5), resolution=600)

# Group shot: the three tools on one tile as they might lie after the crash.
reset_scene()
for (name, _), (x, y, yaw) in zip(TOOLS, [(-.35, .15, 35), (.15, .3, -20), (.35, -.25, 70)]):
    bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/models/items' / (name + '.glb')))
    for o in bpy.context.selected_objects:
        if o.parent is None:
            o.location = (x, y, 0)
            o.rotation_euler = (0, 0, math.radians(yaw))
render_preview('robot_tools', target_z=0, ortho_scale=2.0, true_tile=True,
               camera=(-1.85, -5.7, 6.0), resolution=800)
