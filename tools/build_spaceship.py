"""blender --background --python tools/build_spaceship.py: the robot's ship, intact and wrecked.

One hull, two game models (docs/spaceship-model.md):

- spaceship.glb: the ship as it flew, level on three landing legs. For the intro before the crash
  and the lift-off once it is repaired.
- crashed_spaceship.glb: the same ship nosed into the start island, scorched, its belly in a dirt
  furrow. Every part the robot can repair is in it twice, as a '<Part>Broken' and a
  '<Part>Repaired' node; the game shows one of them from the repair state (ShipWreck). PARTS lists
  them: the radar is repaired in the game today, the rest wait as broken slots for later repairs.

Both are authored at true tile scale (lowpoly_kit.TILE = 2 units per tile), the robot's scale
(0.90 units tall). In ship space the nose points along +X, port is +Y and the belly rests at z=0;
the starboard side (-Y) faces the camera. The wreck pitches that nose-down and rolls it onto its
starboard side, then trims everything at the ground. 'RadarSpin' is the radar dish's pivot,
spinning about its local up axis (Godot +Y) once the radar works.

Outputs: the two GLBs, art/blender/spaceship.blend and crashed_spaceship.blend, and the previews
art/previews/spaceship.png, crashed_spaceship.png (all broken), crashed_spaceship_radar.png (the
radar repaired) and crashed_spaceship_repaired.png (every slot repaired).
"""
import math
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
from mathutils import Matrix, Vector
from lowpoly_kit import (ROOT, PALETTE, TILE, mix, reset_scene, material, finish, box, cylinder, beam,
                         boulder, prism_y, export, render_preview)

# Repairable parts, in the order the wreck lists them. The game maps GameTypes.ShipPart onto these
# names (ShipRepairs.MODEL_NODES); a part with no ShipPart yet always shows broken.
PARTS = ['Radar', 'Windshield', 'Hull', 'Wing', 'Engine']

# The wreck's pose: pitched nose-down, rolled onto its starboard side, sunk so the nose digs in.
WRECK_PITCH = 6.0
WRECK_ROLL = 7.0
WRECK_SINK = .10
# The intact ship stands this high on its legs.
GEAR_HEIGHT = .26

RADAR_X = -.15
RADAR_TOP = 1.28
HULL_TOP = .99

# Hull stations along the ship: (x, half width, half height, centre height). Octagonal sections,
# so the hull is broad flat facets in the workshop low-poly style.
HULL = [
    (1.62, .10, .09, .42),
    (1.45, .26, .21, .43),
    (1.28, .38, .31, .45),
    (1.05, .48, .39, .47),
    (.82, .55, .44, .49),
    (.45, .59, .47, .50),
    (.10, .60, .48, .51),
    (-.30, .59, .47, .52),
    (-.75, .56, .45, .53),
    (-1.05, .50, .41, .54),
    (-1.22, .45, .37, .54),
    (-1.30, .42, .34, .54),
]
CANOPY = [
    (1.20, .06, .04, .80),
    (1.02, .26, .16, .84),
    (.76, .36, .23, .88),
    (.46, .36, .23, .92),
    (.26, .23, .15, .95),
    (.14, .06, .04, .96),
]

# Octagon faces of a section, counter-clockwise seen from the nose: 0 upper port chamfer, 1 port
# side, 2 lower port chamfer, 3 belly, 4 lower starboard chamfer, 5 starboard side, 6 upper
# starboard chamfer, 7 top.
BELLY = {2, 3, 4}
STARBOARD_SIDE = 5


def ring(x, hw, hh, zc, c=.45):
    return [(x, hw * c, zc + hh), (x, hw, zc + hh * c), (x, hw, zc - hh * c), (x, hw * c, zc - hh),
            (x, -hw * c, zc - hh), (x, -hw, zc - hh * c), (x, -hw, zc + hh * c), (x, -hw * c, zc + hh)]


def loft(name, stations, mats, face_mat=lambda segment, side: 0):
    """Closed octagonal tube through stations (see HULL). face_mat(segment, side) picks each
    facet's material, an index into mats; the end caps take mats[0]."""
    rings = [ring(*s) for s in stations]
    verts = [v for r in rings for v in r]
    faces, indices = [], []
    for i in range(len(rings) - 1):
        for s in range(8):
            a, b = i * 8 + s, i * 8 + (s + 1) % 8
            faces.append((a, b, b + 8, a + 8))
            indices.append(face_mat(i, s))
    last = (len(rings) - 1) * 8
    faces += [tuple(range(8)), tuple(range(last, last + 8))]
    indices += [0, 0]
    mesh = bpy.data.meshes.new(name + ' mesh')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    finish(o, name, mats[0])
    for m in mats[1:]:
        o.data.materials.append(m)
    for polygon, index in zip(mesh.polygons, indices):
        polygon.material_index = index
    _outward(o)
    return o


def _outward(o):
    bm = bmesh.new()
    bm.from_mesh(o.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(o.data)
    bm.free()


def hull_at(x):
    """(half width, half height, centre height) of the hull at x, between its stations."""
    for (x0, *a), (x1, *b) in zip(HULL, HULL[1:]):
        if x1 <= x <= x0:
            t = (x0 - x) / (x0 - x1)
            return tuple(p + (q - p) * t for p, q in zip(a, b))
    return tuple(HULL[-1][1:])


def slab(name, points, z0, z1, mat):
    """Flat shape in the XY plane, points as (x, y), extruded from z0 to z1 (wings, plates)."""
    n = len(points)
    verts = [(x, y, z) for z in (z0, z1) for x, y in points]
    faces = [tuple(range(n)), tuple(reversed(range(n, 2 * n)))]
    faces += [(i, (i + 1) % n, (i + 1) % n + n, i + n) for i in range(n)]
    mesh = bpy.data.meshes.new(name + ' mesh')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    finish(o, name, mat)
    _outward(o)
    return o


def cone(name, a, b, radius_a, radius_b, mat, sides=8):
    """Truncated cone from point a (radius_a) to point b (radius_b)."""
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=radius_a, radius2=radius_b,
                                    depth=(b - a).length, location=(a + b) / 2)
    o = bpy.context.object
    o.rotation_euler = (b - a).to_track_quat('Z', 'Y').to_euler()
    return finish(o, name, mat)


def shard(name, loc, size, mat, yaw=0.0, lean=0.0):
    """A jagged triangle of glass or plate standing at loc, size (width, thickness, height)."""
    w, t, h = size
    o = prism_y(name, [(-w / 2, 0), (w / 2, 0), (w * .15, h)], -t / 2, t / 2, mat)
    o.location = loc
    o.rotation_euler = (lean, 0, yaw)
    return o


def build_materials():
    m = {
        'cream': material('Hull', PALETTE['cream']),
        'teal': material('Teal', PALETTE['teal']),
        'iron': material('Iron', PALETTE['iron']),
        'steel': material('Steel', PALETTE['steel'], metal=.3, rough=.55),
        'dark': material('Interior', PALETTE['shaft']),
        'scorch': material('Scorch', mix(PALETTE['cream'], PALETTE['coal'], .62)),
        'patch': material('Patch plate', mix(PALETTE['stone'], PALETTE['cream'], .3), metal=.2),
        'soil': material('Soil', mix(PALETTE['timber'], PALETTE['stone_dark'], .3)),
    }
    for key, color, strength in [('glass', PALETTE['amber'], .35), ('lamp', PALETTE['amber'], 1.2),
                                 ('glow', mix(PALETTE['teal'], PALETTE['cream'], .55), 2.5)]:
        mat = material(key.title(), color, rough=.35)
        p = mat.node_tree.nodes.get('Principled BSDF')
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = strength
        m[key] = mat
    return m


class Ship:
    """Builds the ship's meshes in ship space, recording which repair group each belongs to."""

    def __init__(self, mats, wrecked):
        self.m = mats
        self.wrecked = wrecked
        self.groups = {}   # node name ('RadarBroken') -> meshes in ship space
        self.ground = {}   # node name -> meshes placed on the ground (world space), wreck only
        self.dish = []     # the radar dish, spinning on RadarSpin

    def add(self, group, *objects):
        self.groups.setdefault(group, []).extend(objects)

    def build(self):
        self.hull()
        self.canopy()
        self.fin_and_thrusters()
        self.radar()
        self.hull_panel()
        self.wings()
        self.engine()
        if not self.wrecked:
            self.landing_gear()

    # --- Permanent parts ---

    def hull(self):
        m = self.m
        mats = [m['cream'], m['teal'], m['scorch']]

        def face(segment, side):
            # Soot where the nose burned in and around the engine that failed.
            if self.wrecked and (segment, side) in {(0, 4), (0, 5), (1, 4), (1, 5), (1, 3), (2, 5), (9, 5), (10, 5),
                                                    (10, 4), (10, 6)}:
                return 2
            # Teal belly and nose, and a band behind the canopy and before the engine.
            if segment in (0, 3, 9) or side in BELLY:
                return 1
            return 0

        loft('Hull', HULL, mats, face)
        # Hatch, vent and portholes. The starboard side faces the camera; the port side gets its
        # own window row.
        hw, hh, zc = hull_at(.62)
        box('Hatch', (.62, -hw - .012, zc), (.36, .03, .42), m['teal'])
        box('Hatch hinge', (.62, -hw - .03, zc + .23), (.40, .02, .04), m['iron'])
        box('Hatch handle', (.5, -hw - .035, zc), (.04, .03, .1), m['lamp'])
        hw, hh, zc = hull_at(-.86)
        box('Vent', (-.86, -hw - .02, zc), (.18, .02, .04), m['iron'])
        for x, side in [(1.08, -1), (1.08, 1), (.25, 1), (-.2, 1), (-.6, 1)]:
            hw, hh, zc = hull_at(x)
            cylinder('Porthole', (x, side * (hw - .02), zc + .04), (x, side * (hw + .02), zc + .04), .075, m['glass'])
        # Radar base plate: stays when the mast is lost.
        box('Radar base', (RADAR_X, 0, HULL_TOP - .01), (.22, .22, .06), m['iron'])

    def canopy(self):
        """Canopy frame: the glass itself is the Windshield part."""
        for x in [.76, .46]:
            hw, hh, zc = next((s[1:] for s in CANOPY if s[0] == x))
            loft('Canopy rib', [(x + .022, hw + .025, hh + .025, zc), (x - .022, hw + .025, hh + .025, zc)], [self.m['iron']])
        beam('Canopy spine', (1.12, 0, 1.0), (.2, 0, 1.13), .04, self.m['iron'])

    def fin_and_thrusters(self):
        m = self.m
        prism_y('Tail fin', [(-.42, .9), (-1.2, .86), (-1.5, 1.44), (-1.27, 1.47)], -.045, .045, m['teal'])
        prism_y('Fin stripe', [(-1.31, 1.12), (-1.40, 1.30), (-1.25, 1.31), (-1.12, 1.12)], -.05, .05, m['cream'])
        box('Fin light', (-1.38, 0, 1.49), (.08, .06, .05), m['lamp'])
        for side in [-1, 1]:
            cylinder('Side thruster', (-1.12, side * .44, .36), (-1.36, side * .44, .36), .075, m['iron'])
            cylinder('Side thruster mouth', (-1.36, side * .44, .36), (-1.38, side * .44, .36), .05, m['dark'])

    # --- Repairable parts ---

    def radar(self):
        m = self.m
        x = RADAR_X
        top = Vector((x, 0, RADAR_TOP))
        mast = cylinder('Radar mast', (x, 0, HULL_TOP), top, .035, m['steel'])
        yoke = box('Radar yoke', top + Vector((0, 0, .03)), (.08, .08, .08), m['iron'])
        # The dish looks out and up; it is a squat cone, its face a teal disc with a feed horn.
        look = Vector((0, -math.cos(math.radians(35)), math.sin(math.radians(35))))
        back = top + Vector((0, 0, .07))
        front = back + look * .12
        dish = [
            cone('Radar dish', back, front, .07, .30, m['cream']),
            cylinder('Radar face', front, front + look * .01, .26, m['teal']),
            beam('Radar feed', front, front + look * .22, .025, m['steel']),
            box('Radar horn', front + look * .24, (.06, .06, .06), m['lamp']),
        ]
        self.dish = dish
        self.add('RadarRepaired', mast, yoke, *dish)
        self.radar_pivot = top

        # Broken: a snapped stub, a loose cable down the hull, and the dish thrown onto the ground.
        stub = cylinder('Radar stub', (x, 0, HULL_TOP), (x, 0, HULL_TOP + .11), .035, m['steel'])
        snap = shard('Radar stub break', (x, 0, HULL_TOP + .1), (.07, .07, .06), m['steel'], yaw=.6, lean=.3)
        cable = beam('Radar cable', (x - .02, -.04, HULL_TOP + .06), (x - .1, -.42, .78), .022, m['iron'])
        self.add('RadarBroken', stub, snap, cable)

    def hull_panel(self):
        m = self.m
        x = .02
        hw, hh, zc = hull_at(x)
        y = -hw
        # Broken: a torn hole into the dark interior, its ribs showing, the panel peeled off below.
        hole = box('Hull breach', (x, y - .004, zc + .02), (.44, .03, .30), m['dark'])
        ribs = [box('Hull rib', (x + dx, y - .012, zc + .02), (.035, .03, .32), m['iron']) for dx in [-.1, .1]]
        flap = box('Peeled panel', (x, y - .07, zc - .17), (.40, .025, .18), m['cream'])
        flap.rotation_euler = (math.radians(-50), 0, math.radians(4))
        # Jagged metal hanging into the top of the hole.
        torn = [shard('Torn edge', (x + dx, y - .006, zc + .23), (.08, .02, .06), m['cream'])
                for dx in [-.15, -.02, .13]]
        for t in torn:
            t.rotation_euler = (0, math.pi, 0)
        self.add('HullBroken', hole, *ribs, flap, *torn)

        # Repaired: a riveted patch plate over the hole.
        plate = box('Hull patch', (x, y - .012, zc + .02), (.48, .03, .34), m['patch'])
        rivets = [box('Rivet', (x + dx, y - .03, zc + .02 + dz), (.035, .02, .035), m['iron'])
                  for dx in [-.2, .2] for dz in [-.13, .13]]
        self.add('HullRepaired', plate, *rivets)

    def wings(self):
        m = self.m
        z0, z1 = .19, .26
        port = [(.45, .5), (-.55, .5), (-.85, 1.3), (-.55, 1.3)]
        slab('Port wing', port, z0, z1, m['cream'])
        self._wing_tip(1)
        starboard = [(x, -y) for x, y in port]
        full = slab('Starboard wing', starboard, z0, z1, m['cream'])
        self.add('WingRepaired', full, *self._wing_tip(-1))
        # Broken: a jagged stub; the outer half lies on the ground (wreck only).
        stub = [(.45, -.5), (.08, -.80), (-.05, -.72), (-.18, -.88), (-.32, -.76), (-.45, -.90), (-.66, -.80), (-.55, -.5)]
        self.add('WingBroken', slab('Wing stub', stub, z0, z1, m['cream']))
        self.wing_piece = [(.08, -.80), (-.55, -1.3), (-.85, -1.3), (-.66, -.80), (-.45, -.90), (-.32, -.76),
                           (-.18, -.88), (-.05, -.72)]

    def _wing_tip(self, side):
        m = self.m
        tip = slab('Wing tip', [(-.55 - .07 * .4, side * 1.12), (-.81, side * 1.12), (-.85, side * 1.3), (-.55, side * 1.3)],
                   .18, .27, m['teal'])
        lamp = box('Wing light', (-.70, side * 1.32, .225), (.1, .04, .05), m['lamp'])
        return [tip, lamp]

    def engine(self):
        m = self.m
        zc = .54
        cylinder('Engine housing', (-1.24, 0, zc), (-1.42, 0, zc), .30, m['iron'])
        a = Vector((-1.42, 0, zc))
        bell = cone('Engine bell', a, a + Vector((-.24, 0, 0)), .22, .30, m['steel'])
        glow = cylinder('Engine glow', a + Vector((-.20, 0, 0)), a + Vector((-.215, 0, 0)), .24, m['glow'])
        self.add('EngineRepaired', bell, glow)
        # Broken: the bell knocked askew, its throat sooted dark, cables hanging loose.
        skew = Vector((-math.cos(math.radians(24)), -math.sin(math.radians(12)), -math.sin(math.radians(20)))).normalized()
        b = a + Vector((-.02, -.03, -.03))
        bent = cone('Engine bell', b, b + skew * .24, .22, .30, m['steel'])
        soot = cylinder('Engine soot', b + skew * .2, b + skew * .215, .24, m['dark'])
        cables = [beam('Engine cable', (-1.40, dy, zc - .2), (-1.50, dy * 1.4, zc - .42), .025, m['iron']) for dy in [-.12, .1]]
        self.add('EngineBroken', bent, soot, *cables)

    def landing_gear(self):
        m = self.m
        for x, y in [(.95, 0), (-.72, -.42), (-.72, .42)]:
            hw, hh, zc = hull_at(x)
            foot = (x + (.06 if x > 0 else -.06), y * 1.25, -GEAR_HEIGHT + .03)
            beam('Landing strut', (x, y * .6, zc - hh + .1), foot, .06, m['iron'])
            cylinder('Landing pad', (foot[0], foot[1], -GEAR_HEIGHT), (foot[0], foot[1], -GEAR_HEIGHT + .04), .1, m['steel'])


# --- Scene assembly ---

def bake(objects, matrix):
    """Move meshes by matrix into world space and bake it into their data."""
    for o in objects:
        o.data.transform(matrix @ o.matrix_world)
        o.matrix_world = Matrix.Identity(4)


def trim_at_ground(objects):
    """Cut every mesh at z=0, dropping what's underground. Returns the meshes left."""
    left = []
    for o in objects:
        bm = bmesh.new()
        bm.from_mesh(o.data)
        if min(v.co.z for v in bm.verts) < 0:
            bmesh.ops.bisect_plane(bm, geom=bm.verts[:] + bm.edges[:] + bm.faces[:],
                                   plane_co=(0, 0, 0), plane_no=(0, 0, 1), clear_inner=True)
        if not bm.faces:
            bm.free()
            bpy.data.objects.remove(o)
            continue
        bm.to_mesh(o.data)
        bm.free()
        left.append(o)
    return left


def parent_keep(child, parent):
    bpy.context.view_layer.update()
    world = child.matrix_world.copy()
    child.parent = parent
    child.matrix_world = world


def join_by_material(objects, label):
    """Merge meshes sharing a first material, keeping their parent."""
    by_material = {}
    for o in objects:
        by_material.setdefault(o.data.materials[0].name, []).append(o)
    for name, group in by_material.items():
        bpy.ops.object.select_all(action='DESELECT')
        for o in group:
            o.select_set(True)
        bpy.context.view_layer.objects.active = group[0]
        if len(group) > 1:
            bpy.ops.object.join()
        bpy.context.object.name = '%s %s' % (label, name)


def apply_modifiers():
    for o in bpy.context.scene.objects:
        if o.type == 'MESH':
            bpy.context.view_layer.objects.active = o
            for mod in list(o.modifiers):
                bpy.ops.object.modifier_apply(modifier=mod.name)


def wreck_ground(ship):
    """Dirt, debris and the pieces thrown off the ship, in world space around the posed wreck."""
    m = ship.m
    random.seed(7)
    # Dirt shoved up ahead of the buried nose, and the furrow it dug coming in.
    for loc, size in [((1.62, -.18, 0), (.5, .46, .30)), ((1.78, .2, 0), (.42, .5, .24)),
                      ((1.42, -.52, 0), (.34, .3, .17)), ((1.40, .52, 0), (.34, .28, .16)),
                      ((1.88, -.12, 0), (.26, .3, .12))]:
        boulder('Dirt', loc, size, m['soil'], floor=0)
    for i in range(9):
        x = -1.45 - i * .08 + random.uniform(-.03, .03)
        y = (.3 if i % 2 else -.3) + random.uniform(-.06, .06)
        s = random.uniform(.13, .22) * (1 - i * .06)
        boulder('Furrow clod', (x, y, 0), (s, s * .9, s * .5), m['soil'], floor=0)
    # Scattered hull scraps.
    for loc, size, yaw, mat in [((-.2, -.95, .012), (.2, .12, .025), .5, m['cream']),
                                ((-1.25, .95, .012), (.16, .1, .025), -.3, m['teal']),
                                ((1.15, .9, .012), (.12, .1, .025), 1.1, m['cream'])]:
        box('Scrap', loc, size, mat).rotation_euler.z = yaw
    # The radar dish where it landed: tipped on its rim, half sunk, beside a bent length of mast.
    rim = Vector((1.25, -1.22, .1))
    tilt = Vector((.35, -.4, .85)).normalized()
    ship.ground['RadarBroken'] = [
        cone('Fallen dish', rim, rim + tilt * .12, .07, .30, m['cream']),
        cylinder('Fallen dish face', rim + tilt * .12, rim + tilt * .13, .26, m['teal']),
        cylinder('Fallen mast', (1.62, -.98, .03), (1.80, -1.20, .05), .035, m['steel']),
    ]
    # The outer half of the starboard wing, tip dug into the ground.
    piece = slab('Fallen wing', [(x + .35, y + 1.05) for x, y in ship.wing_piece], -.035, .035, m['cream'])
    piece.location = (.42, -1.42, .12)
    piece.rotation_euler = (math.radians(-14), math.radians(6), math.radians(-28))
    ship.ground['WingBroken'] = [piece]
    # Glass from the canopy.
    ship.ground['WindshieldBroken'] = [
        shard('Glass shard', (1.08, -.84, 0), (.12, .03, .14), m['glass'], yaw=.4, lean=.3),
        shard('Glass shard', (.95, -.94, 0), (.09, .03, .1), m['glass'], yaw=1.6, lean=-.4),
        shard('Glass shard', (1.2, -.95, 0), (.07, .03, .08), m['glass'], yaw=2.4, lean=.2),
    ]


def windshield(ship):
    m = ship.m
    ship.add('WindshieldRepaired', loft('Canopy glass', CANOPY, [m['glass']]))
    # Broken: the frame open onto the dark cockpit, a few panes left standing in it.
    hole = loft('Canopy hole', [(x, hw * .97, hh * .97, zc) for x, hw, hh, zc in CANOPY], [m['dark']])
    shards = [shard('Canopy shard', (x, y, z), (w, .025, h), m['glass'], yaw=yaw, lean=lean)
              for x, y, z, w, h, yaw, lean in [(1.0, -.2, .9, .16, .16, .3, .35), (.62, .3, .98, .18, .2, -.2, -.3),
                                               (.38, -.26, 1.0, .12, .14, .1, .4), (.86, .27, .96, .1, .12, .5, -.2)]]
    ship.add('WindshieldBroken', hole, *shards)


def build(wrecked):
    reset_scene()
    mats = build_materials()
    ship = Ship(mats, wrecked)
    ship.build()
    windshield(ship)
    if not wrecked:
        for name in [n for n in ship.groups if n.endswith('Broken')]:
            for o in ship.groups.pop(name):
                bpy.data.objects.remove(o)
    apply_modifiers()

    if wrecked:
        pose = (Matrix.Translation((0, 0, -WRECK_SINK))
                @ Matrix.Rotation(math.radians(WRECK_ROLL), 4, 'X')
                @ Matrix.Rotation(math.radians(WRECK_PITCH), 4, 'Y'))
    else:
        pose = Matrix.Translation((0, 0, GEAR_HEIGHT))
    bpy.context.view_layer.update()
    bake([o for o in bpy.context.scene.objects if o.type == 'MESH'], pose)
    if wrecked:
        wreck_ground(ship)
        bpy.context.view_layer.update()
        bake([o for o in bpy.context.scene.objects if o.type == 'MESH'], Matrix.Identity(4))
        kept = trim_at_ground([o for o in bpy.context.scene.objects if o.type == 'MESH'])
        for objects in list(ship.groups.values()) + list(ship.ground.values()):
            objects[:] = [o for o in objects if o in kept]

    # The intact ship has only Repaired nodes, so an intro or lift-off scene finds the same names.
    for part in PARTS:
        for name in [part + 'Broken', part + 'Repaired'] if wrecked else [part + 'Repaired']:
            group = bpy.data.objects.new(name, None)
            bpy.context.collection.objects.link(group)
            members = ship.groups.get(name, []) + ship.ground.get(name, [])
            for o in members:
                parent_keep(o, group)
            dish = [o for o in members if o in ship.dish]
            if dish:
                spin = bpy.data.objects.new('RadarSpin', None)
                spin.location = pose @ ship.radar_pivot
                spin.rotation_euler = pose.to_euler()
                bpy.context.collection.objects.link(spin)
                parent_keep(spin, group)
                for o in dish:
                    parent_keep(o, spin)
                join_by_material(dish, 'Radar dish')
            rest = [o for o in members if o not in ship.dish]
            if rest:
                join_by_material(rest, name)
    return ship


def show(state):
    """Show each part in state ('Broken' or 'Repaired', per part name) in the preview render."""
    def hide(o, hidden):
        o.hide_render = hidden
        o.hide_viewport = hidden
        for child in o.children:
            hide(child, hidden)
    for part in PARTS:
        for suffix in ['Broken', 'Repaired']:
            group = bpy.data.objects.get(part + suffix)
            if group:
                hide(group, state.get(part, 'Broken') != suffix)


def render(name):
    bpy.context.scene.render.filepath = str(ROOT / 'art/previews' / (name + '.png'))
    bpy.ops.render.render(write_still=True)


NEIGHBOURS = ((0, 0), (TILE, 0), (-TILE, 0), (TILE / 2, TILE * .866), (-TILE / 2, TILE * .866),
              (TILE / 2, -TILE * .866), (-TILE / 2, -TILE * .866))
PREVIEW = dict(target_z=.45, ortho_scale=5.2, true_tile=True, tiles=NEIGHBOURS, camera=(-2.6, -6.2, 5.6))

build(wrecked=False)
export('spaceship', join_label='Spaceship')
render_preview('spaceship', **PREVIEW)

# Export before hiding anything: the exporter only takes what it can select.
build(wrecked=True)
export('crashed_spaceship', join_label='Wreck')
show({})
render_preview('crashed_spaceship', **PREVIEW)
show({'Radar': 'Repaired'})
render('crashed_spaceship_radar')
show({part: 'Repaired' for part in PARTS})
render('crashed_spaceship_repaired')
