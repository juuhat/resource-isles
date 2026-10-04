"""Blender --background --python tools/build_furnace.py: stone kiln, source and preview.

Coal-heated kiln with mechanically driven bellows. Broad stone body and short square
flue distinguish it from the generator's tall iron boiler. True tile scale, open front yard.
"""
import sys
from pathlib import Path
import bpy

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import PALETTE, TILE, reset_scene, material, box, cylinder, beam, marker, export, render_preview, mix
from build_shared_generator import build_shared_generator

reset_scene()
stone = material('Stone', PALETTE['stone'])
cut = material('Refractory stone', PALETTE['stone_cut'])
dark_stone = material('Dark stone', PALETTE['stone_dark'])
wood = material('Timber', PALETTE['timber'])
teal = material('Teal', PALETTE['teal'])
leather = material('Bellows leather', mix(PALETTE['timber'], PALETTE['iron'], .45))
steel = material('Steel', PALETTE['steel'])
iron = material('Iron', PALETTE['iron'])
ore = material('Iron ore', PALETTE['iron_ore'])
coal = material('Coal', PALETTE['coal'])
shaft = material('Kiln interior', PALETTE['shaft'])
fire = material('Fire', PALETTE['amber'])
p = fire.node_tree.nodes.get('Principled BSDF')
p.inputs['Emission Color'].default_value = (*PALETTE['amber'], 1)
p.inputs['Emission Strength'].default_value = .7

# Masonry chamber: a wide kiln, its mouth framed by a simple arch-like lintel.
box('Chamber', (-.26, .45, .33), (.60, .52, .66), stone)
box('Capstone', (-.26, .45, .70), (.66, .57, .08), cut)
box('Kiln mouth', (-.26, .178, .31), (.35, .024, .37), shaft)
for x in [-.48, -.04]:
    box('Mouth jamb', (x, .155, .31), (.09, .08, .43), cut)
box('Mouth lintel', (-.26, .15, .55), (.53, .09, .10), cut)
box('Mouth sill', (-.26, .14, .105), (.53, .16, .09), dark_stone)
box('Embers', (-.26, .161, .22), (.28, .012, .11), fire)
box('Flue', (-.26, .55, .84), (.24, .24, .28), dark_stone)
box('Flue rim', (-.26, .55, .99), (.31, .31, .05), cut)
box('Flue opening', (-.26, .55, 1.017), (.19, .19, .005), shaft)

# Shared robot PTO socket: same docking offsets as the sawmill and quarry. It turns
# the bellows drive, while coal supplies the heat. It is not an island power source.
WORK_Y = -.30 * TILE
GEN = (.2175, WORK_Y + .20 + .265, .15)
build_shared_generator(GEN, name='BellowsDrive')
for x in [GEN[0]-.18, GEN[0]+.18]:
    box('Drive sleeper', (x, GEN[1], .075), (.11, .38, .15), wood)

def moving(obj, pivot):
    bpy.context.view_layer.update()
    world = obj.matrix_world.copy()
    obj.parent = pivot
    obj.matrix_world = world
    return obj

# Three broad accordion folds. Their pivot is the fixed lower plate, so scaling
# vertically contracts the body without sliding the base. Rigid top moves separately.
BX, BY, BASE, HEIGHT = .30, .43, .24, .20
box('Bellows stand', (BX, BY, .11), (.28, .26, .22), wood)
box('Bellows lower plate', (BX, BY, BASE-.02), (.38, .34, .04), teal)
body = marker('BellowsBody', (BX, BY, BASE))
for index in range(3):
    z = BASE + (index+.5) * HEIGHT / 3
    moving(box('Accordion fold', (BX, BY, z), (.34, .30, HEIGHT / 3), leather), body)
    moving(box('Pleat lip', (BX, BY, z), (.38, .34, .025), wood), body)
top = marker('BellowsTop', (BX, BY, BASE+HEIGHT))
moving(box('Bellows top plate', (BX, BY, BASE+HEIGHT+.02), (.38, .34, .04), teal), top)
moving(box('Compression arm', (.47, BY, BASE+HEIGHT+.045), (.19, .07, .05), steel), top)
cylinder('Air nozzle', (.01, BY, BASE+.02), (.16, BY, BASE+.02), .055, dark_stone)

# The socket drives a short cross shaft and cam beside the bellows.
FX = GEN[0]+.375
cylinder('Bellows drive shaft', (FX, GEN[1], .40), (FX, BY, .40), .026, steel)
cam = marker('BellowsCamPivot', (FX, BY, .40))
moving(cylinder('Bellows cam', (FX-.025, BY, .40), (FX+.025, BY, .40), .095, iron), cam)
moving(box('Cam lobe', (FX, BY-.07, .40), (.065, .09, .055), wood), cam)

# Two stock groups: coal bin to the left, and ore/casting bench to the right.
box('Coal bin', (-.65, .50, .075), (.20, .35, .15), wood)
for x, y, z in [(-.68, .39, .18), (-.62, .49, .19), (-.68, .58, .16)]:
    box('Coal chunk', (x, y, z), (.12, .14, .12), coal)
box('Casting bench', (.35, .70, .16), (.28, .16, .32), stone)
box('Ingot mould', (.35, .70, .34), (.22, .14, .04), dark_stone)
box('Finished ingot', (.35, .70, .375), (.16, .10, .04), iron)
box('Ore chunk', (.56, .65, .095), (.10, .12, .19), ore)

marker('Footprint', (-.05, .19, .51), (.36 * TILE, .30 * TILE, .51))
marker('WorkSpot', (0, -.30 * TILE, 0))
export('furnace', join_label='Furnace')
render_preview('furnace', target_z=.43, ortho_scale=3.0, true_tile=True)
