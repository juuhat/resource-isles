"""Shared helpers for the headless Blender builders (tools/build_*.py).

A builder calls reset_scene(), models with the primitives below, then export() and
render_preview(). Run a builder with:

    blender --background --python tools/build_<asset>.py

Builders import this module by putting tools/ on sys.path first (Blender doesn't add the
script's folder itself).
"""
import math
import random
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector

ROOT = Path(__file__).resolve().parents[1]


def _linear(c):
    return c / 12.92 if c <= .04045 else ((c + .055) / 1.055) ** 2.4


def _gamma(c):
    return c * 12.92 if c <= .0031308 else 1.055 * c ** (1 / 2.4) - .055


def srgb(hex_color):
    """'#RRGGBB' as linear RGB, the space Principled BSDF Base Color expects."""
    h = hex_color.lstrip('#')
    return tuple(_linear(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))


def mix(a, b, t):
    """Blend two linear RGB colors by t (0 = a, 1 = b), interpolating in sRGB so the steps
    look even."""
    return tuple(_linear(_gamma(x) + (_gamma(y) - _gamma(x)) * t) for x, y in zip(a, b))


# Art direction palette (docs/building-style-palette.md), as linear RGB.
PALETTE = {
    'cream': srgb('#E7D9B8'),
    'timber': srgb('#98623D'),
    'terracotta': srgb('#B85F43'),
    'teal': srgb('#397E80'),
    'stone': srgb('#89938D'),
    'iron': srgb('#3F5057'),
    'pine': srgb('#486A4C'),
    'amber': srgb('#E5B653'),
}
_BLACK = (0, 0, 0)
# Secondary tones, each mixed from palette colors so they stay in the same family.
PALETTE.update({
    'plank': mix(PALETTE['timber'], PALETTE['cream'], .25),       # boards, lighter than beams
    'cut_wood': mix(PALETTE['timber'], PALETTE['cream'], .6),     # log ends, finished lumber
    'steel': mix(PALETTE['iron'], PALETTE['stone'], .6),          # blades, rails, cable
    'stone_dark': mix(PALETTE['stone'], PALETTE['iron'], .45),    # shadowed or weathered rock
    'stone_cut': mix(PALETTE['stone'], PALETTE['cream'], .45),    # freshly cut quarry stone
    'dust': mix(PALETTE['stone'], PALETTE['cream'], .7),          # worked ledges
    'shaft': mix(PALETTE['iron'], _BLACK, .7),                    # tunnel depth
    'iron_ore': mix(PALETTE['terracotta'], PALETTE['iron'], .35),  # rust
    'coal': mix(PALETTE['iron'], _BLACK, .55),
})

# Primitive defaults, set per builder by reset_scene(). The low-poly standard wants crisp
# facets (no bevels) and 6- or 8-sided cylinders.
_defaults = {'bevel': .02, 'bevels': False, 'sides': 8}

# Assets authored at true tile scale use TILE model units per hex tile width (flat to flat),
# so visual_size_tiles in the game is the model's width / TILE. Fronts face -Y: Blender -Y
# exports as glTF/Godot +Z, toward the game camera at its default yaw.
TILE = 2.0


def reset_scene(sides=8, bevels=False, bevel=.02):
    """Empty the scene, make sure the output folders exist, and set the primitive defaults.

    bevels=False ignores every bevel width, including ones passed explicitly to box(); turn
    it on for the older soft-edged look, with bevel as the default width."""
    for folder in ('art/blender', 'art/previews'):
        (ROOT / folder).mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    _defaults.update(sides=sides, bevels=bevels, bevel=bevel)


def material(name, color, metal=0, rough=.78):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    return m


def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel and _defaults['bevels']:
        mod = obj.modifiers.new('Edge bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        obj.modifiers.new('Corner normals', 'WEIGHTED_NORMAL')
    return obj


def box(name, loc, size, mat, bevel=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, name, mat, _defaults['bevel'] if bevel is None else bevel)


def cylinder(name, a, b, radius, mat, sides=None):
    """Cylinder from point a to point b."""
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=sides or _defaults['sides'], radius=radius, depth=(b - a).length, location=(a + b) / 2)
    o = bpy.context.object
    o.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    return finish(o, name, mat)


def beam(name, a, b, width, mat):
    """Square-section box from point a to point b."""
    a, b = Vector(a), Vector(b)
    o = box(name, (a + b) / 2, (width, width, (b - a).length), mat)
    o.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    return o


def log(name, x, y, z, length, radius, bark, cut, heart, sides=None):
    """Log lying along Y, with a cut-end disc and heartwood ring at both ends."""
    cylinder(name + ' bark', (x, y - length / 2, z), (x, y + length / 2, z), radius, bark, sides)
    for s in [-1, 1]:
        yy = y + s * length / 2
        cylinder(name + ' cut end', (x, yy, z), (x, yy + s * .014, z), radius * .85, cut, sides)
        cylinder(name + ' heartwood', (x, yy + s * .015, z), (x, yy + s * .018, z), radius * .32, heart, sides)


def saw_blade(name, x0, x1, y, z, outer, inner, teeth, mat):
    """Circular saw blade in the YZ plane (axle along X), extruded from x0 to x1."""
    n = teeth * 2
    verts = []
    for x in [x0, x1]:
        for i in range(n):
            angle = 2 * math.pi * i / n
            radius = outer if i % 2 == 0 else inner
            verts.append((x, y + math.cos(angle) * radius, z + math.sin(angle) * radius))
    faces = [tuple(reversed(range(n))), tuple(range(n, 2 * n))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new(name + ' mesh')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    return finish(o, name, mat)


def boulder(name, loc, size, mat, subdiv=2, jitter=.16, floor=None, top=None):
    """Faceted low-poly rock: a jittered icosphere, squashed flat where it meets the ground
    (floor, in world Z) and, with top, sheared off into a flat ledge that far above its centre.
    Uses the global random module, so seed it in the builder for repeatable shapes."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv, radius=.5, location=loc)
    o = bpy.context.object
    for v in o.data.vertices:
        v.co *= 1 + random.uniform(-jitter, jitter)
    o.dimensions = size
    # Small wobble only: spinning an elongated rock swings its long axis into neighbours.
    o.rotation_euler.z = random.uniform(-.3, .3)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    for v in o.data.vertices:
        if floor is not None:
            v.co.z = max(v.co.z, floor - loc[2])
        if top is not None:
            v.co.z = min(v.co.z, top)
    return finish(o, name, mat)


def marker(name, loc, half_size=None):
    """Exported empty the game can read as layout metadata, e.g. 'WorkSpot' (where the robot
    stands to work the building) or 'Footprint' (box empty whose scale is the solid
    footprint's half extents). Empties carry no mesh, so they never affect the model's
    measured bounds."""
    o = bpy.data.objects.new(name, None)
    o.location = loc
    if half_size:
        o.empty_display_type = 'CUBE'
        o.scale = half_size
    else:
        o.empty_display_type = 'SINGLE_ARROW'
        o.empty_display_size = .2
    bpy.context.collection.objects.link(o)
    return o


def _sink(objects, depth):
    """Lower every mesh by depth and cut away whatever ends up below z=0. Drops a model that
    was laid out on a base (deck, paving) onto the ground once the base is removed; legs and
    rocks that reached into the base are trimmed flush."""
    for o in objects:
        if o.type != 'MESH':
            continue
        bm = bmesh.new()
        bm.from_mesh(o.data)
        bm.transform(o.matrix_world)
        bmesh.ops.translate(bm, vec=(0, 0, -depth), verts=bm.verts)
        bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                               plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
        if not bm.faces:
            bm.free()
            bpy.data.objects.remove(o)
            continue
        bm.to_mesh(o.data)
        bm.free()
        o.matrix_world = Matrix.Identity(4)


def export(name, folder='assets/models/buildings', join_label=None, sink=0):
    """Apply modifiers and export every object in the scene to <folder>/<name>.glb.

    With join_label, static meshes are first merged per material (named '<label> <material>')
    so a building costs one draw call per material instead of dozens. With sink, the model is
    lowered by that much and trimmed at the ground (see _sink)."""
    out = ROOT / folder
    out.mkdir(parents=True, exist_ok=True)
    objects = list(bpy.context.scene.objects)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        for mod in list(o.modifiers):
            bpy.ops.object.modifier_apply(modifier=mod.name)
    if sink:
        _sink(objects, sink)
        objects = list(bpy.context.scene.objects)
    if join_label:
        materials = []
        for o in objects:
            if o.type == 'MESH' and o.data.materials[0] not in materials:
                materials.append(o.data.materials[0])
        for m in materials:
            bpy.ops.object.select_all(action='DESELECT')
            group = [o for o in bpy.context.scene.objects if o.type == 'MESH' and o.data.materials[0] == m]
            for o in group:
                o.select_set(True)
            bpy.context.view_layer.objects.active = group[0]
            bpy.ops.object.join()
            bpy.context.object.name = join_label + ' ' + m.name
    bpy.ops.object.select_all(action='SELECT')
    meshes = [o for o in bpy.context.selected_objects if o.type == 'MESH']
    print('%s meshes=%d triangles=%d' % (
        name.upper(), len(meshes), sum(sum(len(p.vertices) - 2 for p in o.data.polygons) for o in meshes)))
    bpy.ops.export_scene.gltf(filepath=str(out / (name + '.glb')), export_format='GLB', use_selection=True)


def _aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


def _robot_figure(loc):
    """Preview-only stand-in for the robot at its target size (about 0.22 x 0.45 tiles), so a
    work spot can be judged against the building around it."""
    cream = material('Preview robot', PALETTE['cream'])
    teal = material('Preview robot panels', PALETTE['teal'])
    amber = material('Preview robot eyes', PALETTE['amber'])
    x, y = loc[0], loc[1]
    box('Preview robot legs', (x, y, .09), (.30, .20, .18), teal)
    box('Preview robot body', (x, y, .36), (.42, .30, .38), cream)
    box('Preview robot head', (x, y, .70), (.34, .30, .28), cream)
    box('Preview robot visor', (x, y - .155, .71), (.26, .02, .12), teal)
    for dx in [-.06, .06]:
        box('Preview robot eye', (x + dx, y - .168, .71), (.05, .01, .05), amber)


def render_preview(name, target_z=.8, ortho_scale=4.05, plinth_radius=1.65, plinth_z=(-.16, -.025),
                   camera=None, resolution=1000, true_tile=False):
    """Add the studio (dark hex plinth, ortho camera, three area lights), save the editable
    art/blender/<name>.blend and render art/previews/<name>.png. Call after export(): the
    studio lives only in the .blend and preview, never in the game asset.

    With true_tile, the plinth is exactly one game tile (TILE wide, pointy along Y as in the
    game) and a robot-sized figure stands on the 'WorkSpot' marker, if there is one. Its
    default camera is close to the game's: from the front, about 45 degrees down, yawed a
    little so side faces read."""
    if camera is None:
        camera = (-1.85, -5.7, 6.0) if true_tile else (-3.5, -5, 3.8)
    ground = material('Preview ground', (.075, .105, .10))
    if true_tile:
        plinth_radius = TILE / math.sqrt(3)
    plinth = cylinder('Preview hex plinth', (0, 0, plinth_z[0]), (0, 0, plinth_z[1]), plinth_radius, ground, 6)
    if true_tile:
        # Turn a corner onto +Y: the game's hexes are pointy along Godot Z (Blender Y).
        first = plinth.data.vertices[0].co
        plinth.rotation_euler.z = math.pi / 2 - math.atan2(first.y, first.x)
        spot = bpy.context.scene.objects.get('WorkSpot')
        if spot:
            _robot_figure(spot.location)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 40
    scene.cycles.use_denoising = True
    scene.world.color = (.25, .25, .25)
    bpy.ops.object.camera_add(location=camera)
    scene.camera = bpy.context.object
    _aim(scene.camera, (0, 0, target_z))
    scene.camera.data.type = 'ORTHO'
    scene.camera.data.ortho_scale = ortho_scale
    for light_name, loc, power, size in [('Key', (-3, -4, 7), 650, 5), ('Fill', (4, -1, 4), 400, 4),
                                         ('Rim', (1, 4, 5), 700, 3)]:
        bpy.ops.object.light_add(type='AREA', location=loc)
        light = bpy.context.object
        light.name = light_name
        light.data.energy = power
        light.data.shape = 'DISK'
        light.data.size = size
        _aim(light, (0, 0, .8))
    scene.render.resolution_x = resolution
    scene.render.resolution_y = resolution
    scene.render.resolution_percentage = 100
    scene.view_settings.view_transform = 'AgX'
    scene.render.filepath = str(ROOT / 'art/previews' / (name + '.png'))
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT / 'art/blender' / (name + '.blend')))
    bpy.ops.render.render(write_still=True)
