"""Blender --background --python tools/build_dock.py: model, source and preview.

Dock (docs/building-style-palette.md): a horizontal timber pier, the one building that stands
out in the water. It covers a line of three tiles (BuildingDefinition.footprint): a stone quay
and cargo on a sandy shore tile, the pier on pilings over the coast tile beside it, widening
into a T-head with a mooring post and a teal beacon post with an amber lamp, and the berth on the
water tile beyond, where the salvage skiff (tools/build_salvage_skiff.py) lies stern to the pier
head with its bow out to sea. The renderer moors the skiff at the 'BoatSpot' marker; it is not
part of this model.

Authored at true tile scale (lowpoly_kit.TILE = 2 units per tile) for the footprint at rotation
0: the shore tile (the anchor) centred at x = -2, the coast tile east of it at x = 0 and the
berth at x = +2. The origin is the centroid of the tile centres (the coast tile's centre), on the
shore tile's ground, where the renderer puts it (BuildingDefinition.true_tile_model); it turns
the model with the footprint. The pilings stand on the coast seabed, below the sand. The robot's
work spot is on the shore at the pier's root, looking out along it.
"""
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
import bpy
from lowpoly_kit import (ROOT, PALETTE, TILE, reset_scene, material, box, cylinder, marker, hex_tile, export,
                         render_preview)

reset_scene()

wood = material('Timber', PALETTE['timber'])
plank = material('Planks', PALETTE['plank'])
end = material('Cut wood', PALETTE['cut_wood'])
stone = material('Stone', PALETTE['stone'])
cut_stone = material('Cut stone', PALETTE['stone_cut'])
dark = material('Iron', PALETTE['iron'])
teal = material('Teal', PALETTE['teal'])
amber = material('Amber', PALETTE['amber'])

T = TILE
SHORE_X, SEA_X = -T / 2, T / 2  # tile centres; their shared edge runs along x = 0
# Game heights in model units (64 world units each): the water surface and the coast seabed
# sit this far below the sand the quay stands on (IslandRenderer: SAND_TOP_Y 14,
# WATER_TOP_Y 6, COAST_SEABED_TOP_Y 3).
WATER_Z = -8 / 64
SEABED_Z = -11 / 64

# Stone quay along the shoreline: a seawall block reaching down to the seabed, with a lighter
# cut-stone cap the pier rests on.
QUAY_X0, QUAY_X1, QUAY_W = -.42, .06, 1.04
box('Quay wall', ((QUAY_X0 + QUAY_X1) / 2, 0, (SEABED_Z + .06) / 2), (QUAY_X1 - QUAY_X0, QUAY_W, .06 - SEABED_Z), stone)
box('Quay cap', ((QUAY_X0 + QUAY_X1) / 2, 0, .075), (QUAY_X1 - QUAY_X0 + .04, QUAY_W + .06, .03), cut_stone)

# Pier: boards laid across a walkway on two stringers, running out from the shore and widening
# into a T-head over the middle of the coast tile.
DECK_TOP = .20
WALK_X0, HEAD_X0, HEAD_X1 = -.80, 1.10, 1.68
WALK_HALF, HEAD_HALF = .38, .66
box('Shore sleeper', (WALK_X0 - .06, 0, .045), (.12, .80, .09), wood)
for y in [-.27, .27]:
    box('Stringer', ((WALK_X0 + HEAD_X1) / 2, y, .11), (HEAD_X1 - WALK_X0, .08, .08), wood)
for y in [-.58, .58]:
    box('Head stringer', ((HEAD_X0 + HEAD_X1) / 2, y, .11), (HEAD_X1 - HEAD_X0, .08, .08), wood)


def boards(x0, x1, count, half_width, shifts):
    pitch = (x1 - x0) / count
    for i in range(count):
        x = x0 + pitch * (i + .5)
        box('Deck board', (x, shifts[i % len(shifts)], DECK_TOP - .025), (pitch - .035, half_width * 2, .05), plank)


boards(WALK_X0, HEAD_X0, 9, WALK_HALF, (.016, -.012, .008, -.018, .012, -.008))  # hand-laid, not machined
boards(HEAD_X0, HEAD_X1, 3, HEAD_HALF, (.0, .012, -.01))
box('Fender beam', (HEAD_X1 + .035, 0, .11), (.07, HEAD_HALF * 2 + .08, .08), wood)

# Pilings on the seabed: two pairs under the walkway, four at the T-head's corners. The back
# corner's piling rises above the deck as the mooring post.
PILE_R, MOOR_TOP = .055, .42
MOOR = (1.62, .62)
piles = [(x, y) for x in [.40, .80] for y in [-.33, .33]] + [(x, y) for x in [1.16, 1.62] for y in [-.62, .62]]
for x, y in piles:
    top = MOOR_TOP if (x, y) == MOOR else DECK_TOP - .05
    cylinder('Piling', (x, y, SEABED_Z), (x, y, top), PILE_R, wood)
cylinder('Mooring post cap', (*MOOR, MOOR_TOP), (*MOOR, MOOR_TOP + .015), PILE_R * .85, end)

# The beacon on the front corner of the T-head: the dock's tall mark from across the map.
BX, BY = 1.62, -.62
cylinder('Beacon base', (BX, BY, DECK_TOP), (BX, BY, DECK_TOP + .08), .08, teal)
cylinder('Beacon post', (BX, BY, DECK_TOP), (BX, BY, 1.02), .045, teal)
cylinder('Beacon lamp', (BX, BY, 1.02), (BX, BY, 1.14), .075, amber)
cylinder('Beacon hood', (BX, BY, 1.14), (BX, BY, 1.185), .10, dark)

# Cargo waiting to ship on the shore, behind the pier root: wooden crates and a teal salvage
# case, turned a little so the stack doesn't read as one block.
def crate(x, y, size, turn=0):
    body = box('Crate', (x, y, size / 2), (size, size, size), plank)
    band = box('Crate band', (x, y, size / 2), (size + .02, size + .02, size * .22), wood)
    body.rotation_euler.z = band.rotation_euler.z = turn


crate(-1.02, .52, .28, .1)
crate(-.72, .66, .24, -.15)
case = box('Salvage case', (-1.02, .52, .28 + .085), (.24, .18, .17), teal)
latch = box('Case latch', (-1.02, .52, .28 + .175), (.06, .20, .014), dark)
case.rotation_euler.z = latch.rotation_euler.z = .45

# Layout metadata for the game: the solid footprint, where the robot works from, and where the
# skiff moors: its origin (waterline, mid-hull) on the berth tile, its screw (.15 past the
# transom) a hand's width off the fender beam, bow (+X) out to sea. The hull is 2.0 long.
marker('Footprint', (.25, 0, .5), (1.45, .72, .5))
marker('WorkSpot', (SHORE_X - .30, 0, 0))
marker('BoatSpot', (HEAD_X1 + .07 + .15 + 1.0, 0, WATER_Z))

# Everything above is laid out around the midpoint of the shore and coast tiles. The berth
# makes the footprint three tiles, so shift it all west half a tile: the origin becomes the
# coast tile's centre, the centroid of the three.
for o in bpy.context.scene.objects:
    if o.parent is None:
        o.location.x -= T / 2

export('dock', join_label='Dock')

# Preview only: the coast and berth tiles at the game's water height, with the skiff moored.
water = material('Preview water', (.05, .23, .30))
for x in (0, T):
    hex_tile('Preview water tile', (x, 0), -.16, WATER_Z, water)
berth = bpy.context.scene.objects['BoatSpot'].location.copy()
bpy.ops.object.select_all(action='DESELECT')
bpy.ops.import_scene.gltf(filepath=str(ROOT / 'assets/models/boats/salvage_skiff.glb'))
for o in bpy.context.selected_objects:
    if o.parent is None:
        o.location += berth
render_preview('dock', target_z=.2, ortho_scale=7.0, camera=(-1.0, -5.7, 6.0), true_tile=True,
               tiles=[(-T, 0)])
