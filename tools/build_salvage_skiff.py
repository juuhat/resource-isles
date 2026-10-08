"""Blender --background --python tools/build_salvage_skiff.py: model, source and previews.

Salvage skiff, tier 1 of the robot-built boats (docs/robot-built-boats.md,
art/concepts/robot-built-boats-v2.png): a narrow open timber hull with a hard pointed bow under a
cream armour plate, an iron keel band and one small teal stern drive block turning a single marine
screw below the transom. The robot drives it standing amidships, its hand PTO docked in a low
post ahead of it; the open deck between the post and the bow crate is K9-DA's, long enough for
it to sit there at its game size (its Sit clip, tools/build_k9_da.py). A cream signal post with
an amber cap on the stern corner gives the boat a mark from afar.

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile), the same scale as the robot
(0.45 tiles = 0.90 units tall). The bow points along +X (Godot +X, the heading WorldView's boats
use); the origin is on the waterline at the middle of the hull, so the hull and screw reach below
it. Markers: 'PilotSpot' (the robot's feet, facing +X), 'DockPoint' (the post's socket, where
the robot's spindle docks), 'CompanionSpot' (K9-DA's seat) and 'PropellerPivot' (the screw,
spinning about +X, parent of its blades).
"""
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
from mathutils import Vector
from lowpoly_kit import (ROOT, PALETTE, TILE, mix, reset_scene, material, box, cylinder, marker, prism_y, export,
                         render_preview)
from build_shared_generator import ring

reset_scene()

timber = material('Timber', PALETTE['timber'])
strake = material('Strake', mix(PALETTE['timber'], PALETTE['iron'], .18))
plank = material('Planks', PALETTE['plank'])
cream = material('Cream', PALETTE['cream'])
teal = material('Teal', PALETTE['teal'])
iron = material('Iron', PALETTE['iron'])
steel = material('Steel', PALETTE['steel'])
shaft = material('Shaft', PALETTE['shaft'])
amber = material('Amber', PALETTE['amber'])
lamp = amber.node_tree.nodes['Principled BSDF']
lamp.inputs['Emission Color'].default_value = (*PALETTE['amber'], 1)
lamp.inputs['Emission Strength'].default_value = .35

# --- Hull -----------------------------------------------------------------------------------
# Stations from the flat transom to the bow tip: x, then (half-width, z) at the gunwale, the chine
# and the flat bottom. Straight gunwales and hard chines; the bottom rakes up into the bow.
STATIONS = [
    (-1.0, (.36, .21), (.33, .02), (.22, -.07)),
    (-.60, (.39, .21), (.36, .02), (.25, -.08)),
    (.25, (.39, .22), (.35, .02), (.24, -.08)),
    (.60, (.31, .24), (.25, .05), (.13, -.04)),
    (1.0, (0, .28), (0, .16), (0, .10)),
]
BOW_SPLIT = .60  # forward of this station the hull wears the cream bow plate
KEEL_BAND = .035  # height of the iron band along the bottom edge
WALL = .04  # hull planking thickness
DECK = .05  # top of the cockpit floor
COCKPIT_END = .77  # forward bulkhead; the hull ahead of it is a closed foredeck


def lerp(a, b, t):
    return a + (b - a) * t


def station_at(x):
    """Hull station at any x, interpolated between STATIONS."""
    for a, b in zip(STATIONS, STATIONS[1:]):
        if a[0] <= x <= b[0]:
            t = (x - a[0]) / (b[0] - a[0])
            return (x, *[(lerp(pa[0], pb[0], t), lerp(pa[1], pb[1], t)) for pa, pb in zip(a[1:], b[1:])])
    raise ValueError(x)


def half_profile(st, grow=0.0):
    """Starboard half of a station, gunwale to keel: gunwale, chine, top of the keel band, bottom.
    grow pushes it out all round (for the iron strip over the bow plate seam)."""
    _, (wt, zt), (wc, zc), (wb, zb) = st
    zk = zb + KEEL_BAND
    wk = lerp(wb, wc, KEEL_BAND / (zc - zb))
    pts = [(wt, zt), (wc, zc), (wk, zk), (wb, zb)]
    if grow:
        pts = [(w + grow if w else 0, z + (grow if i == 0 else -grow if i == 3 else 0)) for i, (w, z) in enumerate(pts)]
    return pts


def ring_points(x, half):
    """Closed section ring: starboard side top to bottom, then port side bottom to top. The last
    edge (port gunwale back to starboard gunwale) closes the top."""
    return [(x, -w, z) for w, z in half] + [(x, w, z) for w, z in reversed(half)]


def loft(name, sections, mats, face_mat, cap_start=True, cap_end=True):
    """Solid from consecutive section rings (same vertex count). face_mat(i, k) picks the
    material index of the side face between rings i and i+1 at ring edge k."""
    bm = bmesh.new()
    rings = [[bm.verts.new(p) for p in r] for r in sections]
    n = len(sections[0])
    for i, (a, b) in enumerate(zip(rings, rings[1:])):
        for k in range(n):
            j = (k + 1) % n
            f = bm.faces.new((a[k], b[k], b[j], a[j]))
            f.material_index = face_mat(i, k)
    if cap_start:
        bm.faces.new(rings[0]).material_index = face_mat(-1, -1)
    if cap_end:
        bm.faces.new(rings[-1]).material_index = face_mat(len(rings) - 1, -1)
    # A zero-width bow tip makes doubled vertices; weld them so its faces close into a point.
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.dissolve_degenerate(bm, edges=bm.edges, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    mesh = bpy.data.meshes.new(name + ' mesh')
    bm.to_mesh(mesh)
    bm.free()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    for m in mats:
        mesh.materials.append(m)
    return o


def cut(obj, cutter):
    """Boolean the cockpit out of obj; cut faces take the cutter's material (timber)."""
    mod = obj.modifiers.new('Cockpit', 'BOOLEAN')
    mod.operation = 'DIFFERENCE'
    mod.object = cutter
    if hasattr(mod, 'material_mode'):
        mod.material_mode = 'TRANSFER'
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.modifier_apply(modifier=mod.name)


def separate_by_material(obj):
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.mode_set(mode='EDIT')
    bpy.ops.mesh.select_all(action='SELECT')
    bpy.ops.mesh.separate(type='MATERIAL')
    bpy.ops.object.mode_set(mode='OBJECT')
    for o in bpy.context.selected_objects:
        used = {p.material_index for p in o.data.polygons}
        keep = o.data.materials[used.pop()] if len(used) == 1 else o.data.materials[0]
        o.data.materials.clear()
        o.data.materials.append(keep)
        for p in o.data.polygons:
            p.material_index = 0


# Shell: timber sides, cream ahead of the bow split, iron keel band and bottom. Ring edges 0 and 6
# are the sides above the chine, 1 and 5 below it, 2 and 4 the keel band, 3 the bottom, 7 the top.
HULL_MATS = [timber, cream, iron, strake]
xs = [s[0] for s in STATIONS]


def hull_face(i, k):
    if k < 0:
        return 0  # transom
    if k in (2, 3, 4):
        return 2
    forward = i >= 0 and xs[i] >= BOW_SPLIT
    if k == 7:
        return 1 if forward else 0
    return 1 if forward else 0


hull = loft('Hull', [ring_points(s[0], half_profile(s)) for s in STATIONS], HULL_MATS, hull_face,
            cap_end=False)

# Strakes: split the timber sides into horizontal planks, alternating two tones.
bm = bmesh.new()
bm.from_mesh(hull.data)
for z in (.085, .15):
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, 0, z), plane_no=(0, 0, 1))
for f in bm.faces:
    c = f.calc_center_median()
    if f.material_index == 0 and abs(f.normal.z) < .5 and .085 < c.z < .15:
        f.material_index = 3
bm.to_mesh(hull.data)
bm.free()

# The cockpit, cut out of the hull: walls WALL thick down to the deck, open from the transom to
# the forward bulkhead.


def inner_section(x):
    st = station_at(x)
    _, (wt, zt), (wc, zc), _ = st
    w_deck = lerp(wc, wt, (DECK - zc) / (zt - zc)) - WALL
    w_top = wt - WALL
    top = .6
    w_up = w_top + (w_top - w_deck) * (top - zt) / (zt - DECK)
    return [(x, -w_deck, DECK), (x, -w_up, top), (x, w_up, top), (x, w_deck, DECK)]


cutter_xs = [xs[0] + WALL * 1.2, *xs[1:4], COCKPIT_END]
cutter = loft('Cockpit cutter', [inner_section(x) for x in cutter_xs], [timber], lambda i, k: 0)
cut(hull, cutter)

# The iron strip over the bow plate seam, a band hugging the hull, cut by the same cockpit.
seam = [station_at(BOW_SPLIT - .025), station_at(BOW_SPLIT + .025)]
strip = loft('Bow seam strip', [ring_points(s[0], half_profile(s, .012)) for s in seam], [iron], lambda i, k: 0)
cut(strip, cutter)
bpy.data.objects.remove(cutter, do_unlink=True)
separate_by_material(hull)

# Cockpit floor: fore-and-aft deck boards in two tones over the cut floor.
floor_xs = cutter_xs
outline = [(x, inner_section(x)[0][1]) for x in floor_xs] + [(x, -inner_section(x)[0][1]) for x in reversed(floor_xs)]
bm = bmesh.new()
bottom = [bm.verts.new((x, y, DECK - .005)) for x, y in outline]
top = [bm.verts.new((x, y, DECK + .012)) for x, y in outline]
bm.faces.new(bottom)
bm.faces.new(top)
for a, b in zip(range(len(outline)), list(range(1, len(outline))) + [0]):
    bm.faces.new((bottom[a], bottom[b], top[b], top[a]))
for y in [-.25, -.15, -.05, .05, .15, .25]:
    geom = bm.verts[:] + bm.edges[:] + bm.faces[:]
    bmesh.ops.bisect_plane(bm, geom=geom, plane_co=(0, y, 0), plane_no=(0, 1, 0))
bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
for f in bm.faces:
    f.material_index = int(math.floor((f.calc_center_median().y + .05) / .1)) % 2
mesh = bpy.data.meshes.new('Deck mesh')
bm.to_mesh(mesh)
bm.free()
deck = bpy.data.objects.new('Deck', mesh)
bpy.context.collection.objects.link(deck)
mesh.materials.append(plank)
mesh.materials.append(material('Planks dark', mix(PALETTE['plank'], PALETTE['timber'], .45)))
separate_by_material(deck)


def gunwale(x):
    st = station_at(x)
    return st[1]  # (half-width, z)


# Iron cleats clamped over the gunwales, and corner plates on the transom.
for x in (-.70, .27):
    w, z = gunwale(x)
    for s in (-1, 1):
        box('Gunwale cleat', (x, s * (w - WALL / 2), z + .012), (.075, .075, .05), iron)
for s in (-1, 1):
    box('Transom corner plate', (xs[0] - .005, s * .30, .11), (.02, .09, .16), iron)

# --- Foredeck: a teal hatch on the closed bow, and the cargo crate ahead of the open deck ------
hx = .85
hw, hz = gunwale(hx)
slope = math.atan2(STATIONS[4][1][1] - STATIONS[3][1][1], STATIONS[4][0] - STATIONS[3][0])
hatch = box('Foredeck hatch', (hx, 0, hz + .008), (.11, .11, .02), teal)
hatch.rotation_euler.y = -slope

CRATE_X, CRATE = .65, .18
box('Bow crate', (CRATE_X, 0, DECK + CRATE / 2), (CRATE, CRATE, CRATE), cream)
box('Crate band', (CRATE_X, 0, DECK + CRATE / 2), (CRATE + .016, CRATE + .016, .045), timber)
box('Crate panel', (CRATE_X, 0, DECK + CRATE + .004), (.10, .10, .012), teal)

# --- Helm: the robot's PTO post ------------------------------------------------------------
# The robot stands at PilotSpot facing the bow. Its docking pose puts the spindle .20 ahead of
# its feet, .41 up and .2175 out to its right hand side (starboard, -Y), as at the sawmill.
PILOT = (-.47, .05, DECK)
SOCKET = (PILOT[0] + .20, PILOT[1] - .2175, DECK + .41)
sx, sy, sz = SOCKET
HEAD = (.13, .19, .22)  # post head: depth (X), width, height
head_x = sx + HEAD[0] / 2
head = box('PTO post head', (head_x, sy, sz), HEAD, teal)
bore = cylinder('Socket bore cutter', (sx - .02, sy, sz), (sx + .07, sy, sz), .055, shaft, 12)
mod = head.modifiers.new('Socket bore', 'BOOLEAN')
mod.operation = 'DIFFERENCE'
mod.object = bore
bpy.context.view_layer.objects.active = head
bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.data.objects.remove(bore, do_unlink=True)
cylinder('Socket recess', (sx + .065, sy, sz), (sx + .072, sy, sz), .056, shaft, 12)
collar = ring('PTO post collar', (sx - .008, sy, sz), 'X', .095, .058, .03, cream, 8)
for i in range(6):
    a = 2 * math.pi * i / 6
    spline = box('Socket spline', (sx + .03, sy + .047 * math.cos(a), sz + .047 * math.sin(a)), (.06, .014, .02), iron)
    spline.rotation_euler.x = a
box('PTO post lamp frame', (head_x, sy + HEAD[1] / 2 + .006, sz + .03), (.06, .014, .11), iron)
box('PTO post lamp', (head_x, sy + HEAD[1] / 2 + .012, sz + .03), (.04, .008, .085), amber)
box('PTO post cap', (head_x, sy, sz + HEAD[2] / 2 + .01), (HEAD[0] + .02, HEAD[1] + .02, .02), iron)
box('PTO post column', (head_x + .01, sy, (DECK + sz - HEAD[2] / 2) / 2), (.075, .075, sz - HEAD[2] / 2 - DECK), iron)
box('PTO post foot', (head_x + .01, sy, DECK + .02), (.15, .15, .03), iron)
# Drive line from the post to the stern drive, a low iron cover along the starboard side of
# the cockpit floor.
MOTOR_X0, MOTOR_X1 = -.96, -.73
box('Drive line cover', ((MOTOR_X1 + head_x) / 2, sy - .03, DECK + .025), (head_x - MOTOR_X1, .06, .04), iron)

# --- Stern drive ----------------------------------------------------------------------------
# A small chamfered teal block on iron feet, the generator family's cream octagonal service inlet
# on each side and an amber lamp on its aft face.
MOTOR_HALF_Y, MOTOR_H = .16, .27
c = .035
mz0 = DECK + .03
profile = [(MOTOR_X0, mz0), (MOTOR_X1, mz0), (MOTOR_X1, mz0 + MOTOR_H - c), (MOTOR_X1 - c, mz0 + MOTOR_H),
           (MOTOR_X0 + c, mz0 + MOTOR_H), (MOTOR_X0, mz0 + MOTOR_H - c)]
prism_y('Stern drive housing', profile, -MOTOR_HALF_Y, MOTOR_HALF_Y, teal)
mx = (MOTOR_X0 + MOTOR_X1) / 2
for y in (-.10, .10):
    box('Stern drive foot', (mx, y, DECK + .015), (.26, .06, .03), iron)
box('Stern drive hatch', (mx, 0, mz0 + MOTOR_H + .008), (.13, .20, .016), iron)
inlet_z = mz0 + MOTOR_H * .5
for s in (-1, 1):
    ring('Service inlet collar', (mx, s * (MOTOR_HALF_Y + .012), inlet_z), 'Y', .075, .045, .028, cream, 8)
    cylinder('Service inlet recess', (mx, s * (MOTOR_HALF_Y - .004), inlet_z), (mx, s * (MOTOR_HALF_Y + .004), inlet_z),
             .046, shaft, 12)
box('Stern drive lamp frame', (MOTOR_X0 - .006, -.08, inlet_z + .02), (.014, .06, .12), iron)
box('Stern drive lamp', (MOTOR_X0 - .012, -.08, inlet_z + .02), (.008, .04, .095), amber)

# Under the stern: an iron skeg carrying the shaft back to a three-bladed screw, axis fore and aft.
SHAFT_Z = -.115
HUB_X = -1.10
prism_y('Skeg', [(-.75, -.075), (-.99, -.075), (-1.01, SHAFT_Z - .025), (-.81, -.095)], -.022, .022, iron)
cylinder('Prop shaft', (-1.01, 0, SHAFT_Z), (HUB_X + .02, 0, SHAFT_Z), .016, steel)
prop = marker('PropellerPivot', (HUB_X, 0, SHAFT_Z))


def attach(obj, parent):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world
    return obj


attach(cylinder('Prop hub', (HUB_X + .025, 0, SHAFT_Z), (HUB_X - .035, 0, SHAFT_Z), .03, steel), prop)
attach(cylinder('Prop nose', (HUB_X - .035, 0, SHAFT_Z), (HUB_X - .05, 0, SHAFT_Z), .018, steel), prop)
R = .062
for i in range(3):
    a = 2 * math.pi * i / 3
    blade = box('Prop blade', (HUB_X, -math.sin(a) * R, SHAFT_Z + math.cos(a) * R), (.018, .07, .075), iron)
    blade.rotation_mode = 'ZYX'
    blade.rotation_euler = (a, 0, .55)
    attach(blade, prop)
# Merge the blades and hub into one spinning mesh per material.
for m in (steel, iron):
    group = [o for o in prop.children if o.type == 'MESH' and o.data.materials[0] == m]
    bpy.ops.object.select_all(action='DESELECT')
    for o in group:
        o.select_set(True)
    bpy.context.view_layer.objects.active = group[0]
    if len(group) > 1:
        bpy.ops.object.join()
    bpy.context.object.name = 'Propeller ' + m.name

# --- Signal post on the port stern corner ---------------------------------------------------
# Taller than the drive and the robot's shoulder, below its antenna: the skiff's mark from afar.
PX, PY = -.87, .27
POST_TOP = .80
box('Signal post', (PX, PY, (DECK + POST_TOP) / 2), (.05, .05, POST_TOP - DECK), cream)
box('Signal post foot', (PX, PY, DECK + .02), (.09, .09, .04), iron)
box('Signal lamp', (PX, PY, POST_TOP + .04), (.10, .10, .08), amber)
box('Signal hood', (PX, PY, POST_TOP + .09), (.12, .12, .02), iron)

# --- Layout metadata ------------------------------------------------------------------------
marker('PilotSpot', PILOT)
marker('DockPoint', SOCKET)
# K9-DA's origin when it rides along, facing the bow in its Sit pose, on the deck boards. Seated,
# at its game size (0.55 tiles long standing, Dog.visual_size_tiles), it reaches .33 aft of here
# to its rump, clear of the post's foot, .26 ahead to its front paws, short of the bow crate, and
# .25 to either side with its folded hind paws, inside the hull's planking.
COMPANION = (.24, 0, DECK + .012)
marker('CompanionSpot', COMPANION)

export('salvage_skiff', folder='assets/models/boats', join_label='Skiff')

# --- Previews -------------------------------------------------------------------------------
render_preview('salvage_skiff', target_z=.15, ortho_scale=2.9, camera=(-2.6, -5.6, 4.2),
               plinth_radius=1.35, plinth_z=(-.30, -.22), resolution=900)
scene = bpy.context.scene
cam = scene.camera
base = ROOT / 'art/previews'

# Overhead, bow to the right, as the concept board's lower row.
cam.location = (0, 0, 8)
cam.rotation_euler = (0, 0, 0)
cam.data.ortho_scale = 2.7
scene.render.filepath = str(base / 'salvage_skiff_top.png')
bpy.ops.render.render(write_still=True)


def import_posed(path, clip):
    """Import a unit's model, holding the first frame of its clip; returns the root and its
    meshes' resting bounds (lowest point and widest horizontal extent)."""
    bpy.ops.object.select_all(action='DESELECT')
    bpy.ops.import_scene.gltf(filepath=str(path))
    imported = bpy.context.selected_objects
    for o in imported:
        if o.animation_data:
            o.animation_data.action = None
    bpy.context.view_layer.update()
    corners = [o.matrix_world @ Vector(c) for o in imported if o.type == 'MESH' for c in o.bound_box]
    low = min(p.z for p in corners)
    extent = max(max(p.x for p in corners) - min(p.x for p in corners),
                 max(p.y for p in corners) - min(p.y for p in corners))
    action = bpy.data.actions[clip]
    root = None
    for o in imported:
        if o.parent is None:
            root = o
        ad = o.animation_data
        if ad:
            ad.action = action
            if getattr(ad, 'action_slot', None) is None and hasattr(action, 'slots'):
                for slot in action.slots:
                    if slot.name_display == o.name:
                        ad.action_slot = slot
    root.rotation_mode = 'XYZ'  # the glTF importer leaves it on quaternions
    return root, low, extent


# Crewed: the real robot, scaled to 0.45 tiles, docked at the post in its Operate pose, and
# K9-DA seated at CompanionSpot as the game places it (Dog.ride): scaled to 0.55 tiles across
# its standing length, paws on the boards, facing the bow.
robot, _, _ = import_posed(ROOT / 'assets/models/units/salvage_robot.glb', 'Operate')
for o in robot.children_recursive:
    if o.name.startswith(('HeldAxe', 'HeldPickaxe', 'HeldWrench')):
        o.hide_render = True
        for child in o.children_recursive:
            child.hide_render = True
robot.scale = (.75, .75, .75)
robot.rotation_euler = (0, 0, math.pi / 2)
robot.location = PILOT
dog, low, extent = import_posed(ROOT / 'assets/models/units/k9_da.glb', 'Sit')
size = .55 * TILE / extent
dog.scale = (size, size, size)
dog.rotation_euler = (0, 0, math.pi / 2)
dog.location = Vector(COMPANION) - Vector((0, 0, low * size))
scene.frame_set(1)
cam.location = (2.6, -5.6, 4.2)  # from ahead, to see both faces
cam.rotation_euler = (Vector((0, 0, .3)) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.ortho_scale = 2.9
scene.render.filepath = str(base / 'salvage_skiff_crewed.png')
bpy.ops.render.render(write_still=True)

# Docking check: from the starboard side, close in on the spindle in the post's socket.
cam.location = (SOCKET[0] - .3, SOCKET[1] - 4, SOCKET[2] + .3)
cam.rotation_euler = (Vector(SOCKET) - cam.location).to_track_quat('-Z', 'Y').to_euler()
cam.data.ortho_scale = 1.0
scene.render.filepath = str(base / 'salvage_skiff_dock_check.png')
bpy.ops.render.render(write_still=True)
