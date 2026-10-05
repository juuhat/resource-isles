"""Blender --background --python tools/build_deposit.py -- [stone|iron|coal|copper]: model, source and
preview.

Resource deposits, low-poly kit (docs/building-style-palette.md): natural, irregular rock, so a
deposit never reads as the quarry's stepped, man-made cut or a mine's portal. Each variant has
its own silhouette, not just its own color:

- stone: a medium outcrop of grey blocks, its broad main block split open on one face to fresh,
  lighter stone, a slab leaning on it, lower blocks and the broken-off chunk around its foot.
- iron: a tall, dense mound of packed grey blocks (the kit's block()), bright rust-orange ore
  veins wedged down the cracks between them, ore chunks and rubble at the foot.
- coal: a wide, low mound with a core of black coal blocks under a broad, flat grey cap slab,
  wrapped in grey blocks, coal lumps spilled in front.
- copper: a split, low ridge with warm copper seams and broad green mineral faces.

All variants are packed outcrops of chunky, flat-topped blocks, after
art/concepts/iron-coal-deposits-v1.png (which shows iron and coal; stone follows the same style).

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile, front toward -Y), with the rock
toward the back of the tile. There is no WorkSpot: the robot harvests a deposit from its tile or
any neighbour.
"""
import random
import sys
from pathlib import Path

import bpy

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import (PALETTE, TILE, reset_scene, material, mix, block, marker, export,
                         render_preview)

args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
VARIANT = args[0] if args else 'stone'
NAME = VARIANT + '_deposit'

random.seed(7)
reset_scene()

T = TILE
# Every layout below is drawn at this scale: the deposits were first laid out about 0.65 tiles
# wide and scaled up so they hold their own beside forests and buildings.
SCALE = 1.15


def outcrop(parts):
    """A packed pile of blocks: (name, material, loc, size[, block() keywords]) per block, with
    loc, size and any cut points scaled by SCALE (cut normals are unchanged)."""
    def scaled(v):
        return tuple(c * SCALE for c in v)
    for name, mat, loc, size, *kwargs in parts:
        kwargs = dict(kwargs[0]) if kwargs else {}
        kwargs['cuts'] = [(scaled(p), n) for p, n in kwargs.get('cuts', ())]
        block(name, scaled(loc), scaled(size), mat, **kwargs)


stone = material('Stone', PALETTE['stone'])
weathered = material('Weathered stone', mix(PALETTE['stone'], PALETTE['stone_dark'], .7))

if VARIANT == 'stone':
    cut = material('Cut stone', PALETTE['stone_cut'])
    outcrop([
        # One broad block dominates, split open on its front-right to fresh, lighter stone, with
        # a slab leaning against its right side and a lower block behind it on the left.
        ('Main block', stone, (-.06, .22, 0), (.72, .58, .72),
         {'cuts': [((.06, .10, .40), (.5, -.8, .3))], 'cut_mat': cut}),
        ('Leaning slab', weathered, (.32, .30, 0), (.40, .36, .56), {'lean': (.12, 0)}),
        ('Back block', stone, (-.42, .34, 0), (.36, .34, .48)),
        # Lower blocks around the foot, one with its broken top turned up.
        ('Left block', weathered, (-.48, .02, 0), (.32, .30, .32)),
        ('Front block', stone, (.10, -.06, 0), (.34, .28, .30),
         {'cuts': [((.10, -.06, .22), (-.2, -.3, 1))], 'cut_mat': cut}),
        ('Right block', stone, (.50, .02, 0), (.28, .26, .26)),
        # The chunk that broke off, rubble and a few pebbles.
        ('Broken chunk', stone, (.30, -.26, 0), (.20, .18, .16),
         {'cuts': [((.30, -.26, .11), (.3, -.2, 1))], 'cut_mat': cut}),
        ('Rubble', weathered, (-.24, -.22, 0), (.16, .14, .12)),
        ('Pebble', stone, (-.50, -.30, 0), (.08, .08, .06)),
        ('Pebble', cut, (.04, -.36, 0), (.07, .07, .05)),
        ('Pebble', weathered, (.56, -.30, 0), (.08, .07, .06)),
    ])

elif VARIANT == 'iron':
    # Bright terracotta rather than the mines' browner iron_ore, so the veins read at map zoom.
    ore = material('Iron ore', mix(PALETTE['terracotta'], PALETTE['iron'], .08))
    outcrop([
        # Broad grey columns packed into one mound, the middle one highest.
        ('Central column', weathered, (-.04, .24, 0), (.56, .50, .92)),
        ('Left column', stone, (-.36, .30, 0), (.46, .44, .72)),
        ('Right column', stone, (.36, .30, 0), (.44, .42, .68)),
        # Ore veins wedged down the cracks between them, standing a little proud so each shows
        # as a band, and one spilling over the top.
        ('Ore vein', ore, (.22, .14, 0), (.26, .40, .78)),
        ('Ore vein', ore, (-.26, .10, 0), (.24, .36, .64)),
        ('Ore cap', ore, (.18, .30, .56), (.34, .36, .24), {'tip': .4}),
        # A lower ring in front, with its own vein.
        ('Left block', stone, (-.48, .00, 0), (.40, .38, .48)),
        ('Right block', stone, (.46, .02, 0), (.38, .36, .46)),
        ('Front block', weathered, (.00, -.04, 0), (.40, .32, .44)),
        ('Ore vein', ore, (.25, -.12, 0), (.20, .24, .34)),
        # Ore chunks and grey rubble at the foot, a few pebbles.
        ('Ore chunk', ore, (-.24, -.20, 0), (.28, .24, .26)),
        ('Ore chunk', ore, (.16, -.30, 0), (.18, .16, .15)),
        ('Rubble', stone, (.42, -.22, 0), (.24, .22, .22)),
        ('Rubble', weathered, (-.54, -.20, 0), (.22, .20, .20)),
        ('Pebble', stone, (-.42, -.38, 0), (.08, .08, .06)),
        ('Pebble', weathered, (.02, -.42, 0), (.07, .07, .05)),
        ('Pebble', ore, (-.10, -.38, 0), (.07, .06, .05)),
        ('Pebble', stone, (.56, -.38, 0), (.08, .07, .06)),
    ])

elif VARIANT == 'coal':
    # Lifted a little off the palette's coal so the black blocks' facets still read in the game.
    coal = material('Coal', mix(PALETTE['iron'], (0, 0, 0), .25))
    outcrop([
        # A core of black coal blocks...
        ('Coal block', coal, (-.14, .26, 0), (.48, .42, .44)),
        ('Coal block', coal, (.24, .28, 0), (.44, .40, .40)),
        ('Coal block', coal, (.04, .04, 0), (.42, .34, .38)),
        ('Coal block', coal, (.36, .02, 0), (.34, .32, .34)),
        ('Coal block', coal, (-.32, .06, 0), (.34, .32, .32)),
        # ...capped by a broad, flat grey slab...
        ('Cap slab', stone, (-.02, .22, .36), (.70, .52, .16), {'crown': .95, 'tip': .1}),
        # ...and wrapped in grey blocks, lowest at the front so the coal shows.
        ('Side block', stone, (-.50, .26, 0), (.34, .34, .34)),
        ('Side block', weathered, (.52, .30, 0), (.32, .32, .36)),
        ('Side block', stone, (-.50, -.02, 0), (.32, .30, .26)),
        ('Front block', weathered, (-.20, -.18, 0), (.34, .26, .24)),
        ('Front block', stone, (.24, -.20, 0), (.36, .26, .22)),
        ('Coal block', coal, (.54, -.08, 0), (.24, .24, .26)),
        # Coal and rubble spilled in front, a few pebbles.
        ('Coal lump', coal, (-.42, -.26, 0), (.20, .18, .18)),
        ('Coal lump', coal, (.02, -.32, 0), (.16, .15, .14)),
        ('Rubble', stone, (.48, -.32, 0), (.12, .11, .10)),
        ('Pebble', coal, (-.14, -.42, 0), (.08, .08, .07)),
        ('Pebble', stone, (.30, -.42, 0), (.08, .08, .06)),
    ])

elif VARIANT == 'copper':
    ore = material('Copper ore', mix(PALETTE['terracotta'], PALETTE['amber'], .48))
    mineral = material('Green copper mineral', mix(PALETTE['teal'], PALETTE['pine'], .35))
    outcrop([
        # Two broken ridges separated by an exposed green-and-copper seam.
        ('Left ridge', weathered, (-.30, .24, 0), (.50, .46, .62),
         {'cuts': [((-.18, .08, .32), (.4, -.9, .2))], 'cut_mat': mineral}),
        ('Right ridge', stone, (.27, .29, 0), (.48, .48, .76),
         {'cuts': [((.25, .09, .40), (-.2, -.9, .2))], 'cut_mat': mineral}),
        ('Copper seam', ore, (-.02, .15, 0), (.20, .38, .60)),
        ('Mineral cap', mineral, (.25, .30, .58), (.34, .36, .16)),
        ('Copper cap', ore, (-.29, .25, .48), (.32, .32, .12)),
        ('Left foot', stone, (-.48, -.02, 0), (.32, .30, .30)),
        ('Right foot', weathered, (.48, .01, 0), (.32, .32, .38)),
        ('Front mineral', mineral, (.15, -.08, 0), (.34, .28, .30)),
        ('Copper seam', ore, (.34, -.09, 0), (.12, .22, .28)),
        ('Ore chunk', ore, (-.16, -.24, 0), (.22, .20, .18)),
        ('Mineral chunk', mineral, (.33, -.28, 0), (.18, .16, .14)),
        ('Rubble', stone, (-.46, -.24, 0), (.16, .14, .12)),
        ('Pebble', ore, (.06, -.38, 0), (.08, .07, .06)),
        ('Pebble', weathered, (.53, -.30, 0), (.08, .08, .06)),
    ])

else:
    sys.exit('Unknown deposit variant %r (stone, iron, coal or copper)' % VARIANT)

# Width and height in tiles, for the definition's visual_size_tiles and the scale table.
bpy.context.view_layer.update()
corners = [o.matrix_world @ v.co for o in bpy.context.scene.objects if o.type == 'MESH'
           for v in o.data.vertices]
lo = [min(c[i] for c in corners) for i in range(3)]
hi = [max(c[i] for c in corners) for i in range(3)]
size = [b - a for a, b in zip(lo, hi)]
print('%s width=%.3f tiles height=%.3f tiles' % (NAME.upper(), max(size[0], size[1]) / T, size[2] / T))

# Layout metadata for the game: the solid footprint the rock covers.
marker('Footprint', tuple((a + b) / 2 for a, b in zip(lo, hi)), tuple(s / 2 for s in size))

export(NAME, folder='assets/models/resources', join_label=VARIANT.capitalize() + ' deposit')
render_preview(NAME, target_z=.3, ortho_scale=2.6, true_tile=True)
