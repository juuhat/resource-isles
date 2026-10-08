"""Blender --background --python tools/build_trees.py -- [pine|leaf|palm]: model, source and preview.

Tree deposits, low-poly kit (docs/building-style-palette.md): a small stand of trees on one tile,
the robot's and the logger camp's source of wood. Each variant has its own silhouette:

- pine: five conifers of stepped heights, each two or three stacked eight-sided cones, lighter
  toward the top, on short trunks, plus a sapling. The tallest stand at the back.
- leaf: three broadleaf trees, each a tapered trunk forking into a crown of faceted, rounded
  clumps, lit lighter on top, and a low bush.
- palm: three palms on a beach, each a ringed, curving trunk leaning out from the others, with a
  crown of folded, drooping fronds over a cluster of coconuts. Two coconuts lie on the sand.

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile, front toward -Y), the base at
the tile's ground. There is no WorkSpot: the robot fells a stand from its tile or any neighbour.
"""
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import (PALETTE, TILE, srgb, reset_scene, material, mix, finish, boulder, marker,
                         export, render_preview)

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
VARIANT = args[0] if args else 'pine'
NAME = VARIANT + '_trees'

random.seed(11)
reset_scene()

T = TILE
bark = material('Bark', mix(PALETTE['timber'], PALETTE['iron'], .2))
# Broadleaf and palm greens. Mixes of pine and amber come out olive, the grass's own hue, and the
# trees sink into it, so these two are fresher greens of their own (docs/building-style-palette.md).
LEAF = srgb('#55863A')
FROND = srgb('#679440')


def frustum(name, a, b, r0, r1, mat, sides=6, turn=None):
    """Tapered cylinder from point a (radius r0) to point b (radius r1); r1 = 0 makes a cone. turn
    spins it about its own axis (random when None), so stacked parts don't line up."""
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cone_add(vertices=sides, radius1=r0, radius2=r1, depth=(b - a).length)
    o = bpy.context.object
    spin = Matrix.Rotation(random.uniform(0, 2 * math.pi) if turn is None else turn, 4, 'Z')
    aim = (b - a).to_track_quat('Z', 'Y').to_matrix().to_4x4()
    o.matrix_world = Matrix.Translation((a + b) / 2) @ aim @ spin
    return finish(o, name, mat)


def strip(name, sections, mat):
    """A folded leaf: sections is a list of (left, rib, right) points from base to tip, and
    neighbouring sections are joined by two faces, one each side of the rib, so it shows a lit and
    a shaded half. A section of one point (the tip) closes it."""
    verts, faces, rows = [], [], []
    for section in sections:
        rows.append(list(range(len(verts), len(verts) + len(section))))
        verts.extend(tuple(p) for p in section)
    for near, far in zip(rows, rows[1:]):
        if len(far) == 1:
            faces += [(far[0], near[1], near[0]), (far[0], near[2], near[1])]
        else:
            faces += [(far[0], far[1], near[1], near[0]), (far[1], far[2], near[2], near[1])]
    mesh = bpy.data.meshes.new(name + ' mesh')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    return finish(o, name, mat)


def conifer(x, y, height, radius, tiers, sides=8):
    """A pine: a short trunk under stacked cones, each tier narrower and a shade lighter. tiers is
    one material per cone, bottom to top."""
    trunk = height * .2
    frustum('Pine trunk', (x, y, 0), (x, y, trunk + .08), radius * .2, radius * .15, bark)
    crown = height - trunk
    n = len(tiers)
    for i, mat in enumerate(tiers):
        f = i / n
        z0 = trunk + crown * f * .78
        z1 = trunk + crown * (.5 + .5 * (i + 1) / n)
        r = radius * (1 - .62 * f) * random.uniform(.94, 1.04)
        frustum('Pine crown', (x, y, z0), (x, y, z1), r, 0, mat, sides)


def broadleaf(x, y, height, radius, crown, light, lean=(0, 0)):
    """A broadleaf tree: a tapered trunk with a branch forking off it, under one rounded crown of
    faceted clumps packed around a big top clump in the lighter green. radius is the crown's."""
    top = Vector((x + lean[0], y + lean[1], height - radius * .78))
    fork = Vector((x + lean[0] * .4, y + lean[1] * .4, top.z * .5))
    frustum('Trunk', (x, y, 0), fork, radius * .2, radius * .15, bark)
    frustum('Trunk', fork, top, radius * .15, radius * .09, bark)
    spin = random.uniform(0, 2 * math.pi)
    for k in range(4):
        a = spin + 2 * math.pi * (k + random.uniform(-.15, .15)) / 4
        end = top + Vector((math.cos(a), math.sin(a), 0)) * radius * .5 - Vector((0, 0, radius * .28))
        if k == 0:
            frustum('Branch', fork, end, radius * .09, radius * .06, bark)
        size = radius * random.uniform(1.05, 1.2)
        boulder('Leaf clump', tuple(end), (size, size, size * .8), crown, subdiv=1, jitter=.1)
    size = radius * 1.5
    boulder('Leaf crown', tuple(top + Vector((0, 0, radius * .1))), (size, size, size * .85), light,
            subdiv=1, jitter=.1)


def palm(x, y, height, lean, fronds, nuts):
    """A palm: a curving trunk of ringed, tapering segments (alternating two barks), leaning by
    lean (dx, dy) at the top, a cluster of coconuts and a crown of folded, drooping fronds
    alternating fronds' two greens."""
    def at(t):  # rises straight from the sand, then bends over
        return Vector((x + lean[0] * t * t, y + lean[1] * t * t, height * t))
    segments = 7
    for i in range(segments):
        t0, t1 = i / segments, (i + 1) / segments
        r0 = .085 - .03 * t0
        r1 = .085 - .03 * t1
        frustum('Palm trunk', at(t0), at(t1), r0 * 1.16, r1 * .92, palm_bark[i % 2], 6)
    crown = at(1)
    tangent = (at(1) - at(.9)).normalized()
    for k in range(3):
        a = 2 * math.pi * k / 3 + random.uniform(-.4, .4)
        out = Vector((math.cos(a), math.sin(a), 0)) * .07
        boulder('Coconut', tuple(crown + out - tangent * .07), (.09, .09, .1), nuts, subdiv=1, jitter=.08)
    count = 7
    spin = random.uniform(0, 2 * math.pi)
    for k in range(count):
        a = spin + 2 * math.pi * (k + random.uniform(-.2, .2)) / count
        along = Vector((math.cos(a), math.sin(a), 0))
        side = Vector((-along.y, along.x, 0))
        length = random.uniform(.44, .52)
        rise, droop = random.uniform(.18, .26), random.uniform(.5, .62)
        sections = []
        for s, width in [(0, .03), (.3, .13), (.62, .11), (.86, .06)]:
            rib = crown + along * length * s + Vector((0, 0, rise * s - droop * s * s + .02))
            fold = Vector((0, 0, -width * .55))
            sections.append((rib - side * width + fold, rib, rib + side * width + fold))
        sections.append((crown + along * length + Vector((0, 0, rise - droop - .02)),))
        strip('Palm frond', sections, fronds[k % 2])


if VARIANT == 'pine':
    shades = [material('Pine', PALETTE['pine']),
              material('Pine light', mix(PALETTE['pine'], PALETTE['cream'], .12)),
              material('Pine top', mix(PALETTE['pine'], PALETTE['cream'], .24))]
    # Stepped heights, the tallest at the back, and a sapling in the open foreground.
    for x, y, height, radius in [(-.30, .34, 1.86, .38), (.30, .40, 1.62, .35), (-.02, .04, 1.42, .33),
                                 (.46, -.10, 1.12, .29), (-.48, -.18, 1.0, .27)]:
        conifer(x, y, height, radius, shades)
    conifer(.10, -.44, .52, .17, shades[1:], sides=6)

elif VARIANT == 'leaf':
    leaves = material('Leaves', LEAF)
    lit = material('Leaves light', mix(LEAF, PALETTE['amber'], .25))
    # One big tree at the back, two smaller to either side and a bush in front.
    broadleaf(-.16, .30, 1.66, .46, leaves, lit, lean=(-.04, .04))
    broadleaf(.34, .18, 1.34, .40, leaves, lit, lean=(.04, 0))
    broadleaf(-.36, -.24, 1.1, .33, leaves, lit, lean=(-.03, -.03))
    boulder('Bush', (.16, -.32, .1), (.36, .30, .3), leaves, subdiv=1, jitter=.1, floor=0)
    boulder('Bush', (.30, -.22, .14), (.24, .22, .24), lit, subdiv=1, jitter=.1, floor=0)

elif VARIANT == 'palm':
    palm_bark = [material('Palm bark', mix(PALETTE['timber'], PALETTE['cream'], .42)),
                 material('Palm bark rings', mix(PALETTE['timber'], PALETTE['cream'], .18))]
    fronds = [material('Palm fronds', FROND),
              material('Palm fronds light', mix(FROND, PALETTE['amber'], .25))]
    nuts = material('Coconut', mix(PALETTE['timber'], PALETTE['iron'], .55))
    # Three palms leaning out from one another, so the crowns spread over the tile.
    palm(-.10, .26, 1.78, (-.18, .10), fronds, nuts)
    palm(.12, .30, 1.46, (.20, .06), fronds, nuts)
    palm(0, -.14, 1.12, (.12, -.14), fronds, nuts)
    for x, y in [(-.30, -.32), (-.18, -.40)]:
        boulder('Coconut', (x, y, .045), (.09, .09, .09), nuts, subdiv=1, jitter=.08, floor=0)

else:
    sys.exit('Unknown tree variant %r (pine, leaf or palm)' % VARIANT)

# Width and height in tiles, for the definition's visual_size_tiles and the scale table.
bpy.context.view_layer.update()
corners = [o.matrix_world @ v.co for o in bpy.context.scene.objects if o.type == 'MESH'
           for v in o.data.vertices]
lo = [min(c[i] for c in corners) for i in range(3)]
hi = [max(c[i] for c in corners) for i in range(3)]
size = [b - a for a, b in zip(lo, hi)]
print('%s width=%.3f tiles height=%.3f tiles' % (NAME.upper(), max(size[0], size[1]) / T, size[2] / T))

# Layout metadata for the game: the space the stand takes up.
marker('Footprint', tuple((a + b) / 2 for a, b in zip(lo, hi)), tuple(s / 2 for s in size))

export(NAME, folder='assets/models/resources', join_label=VARIANT.capitalize() + ' trees')
render_preview(NAME, target_z=.6, ortho_scale=3.0, true_tile=True)
