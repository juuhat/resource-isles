"""Blender --background --python tools/build_mine.py -- [iron|coal]: model, source and preview.

One mine layout, two ore variants (Iron Mine / Coal Mine, see docs/second-island-progression.md).
"""
import math
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import PALETTE, reset_scene, material, box, cylinder, beam, boulder, export, render_preview

VARIANTS = {
    # name: ore palette tone
    'iron': 'iron_ore',
    'coal': 'coal',
}
args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
VARIANT = args[0] if args else 'iron'
NAME = VARIANT + '_mine'

reset_scene()
random.seed(7)

wood=material('Timber',PALETTE['timber'])
plank=material('Planks',PALETTE['plank'])
end=material('Cut wood',PALETTE['cut_wood'])
dark=material('Iron',PALETTE['iron'])
steel=material('Steel',PALETTE['steel'])
teal=material('Teal',PALETTE['teal'])
cream=material('Amber',PALETTE['amber'])
rock=material('Stone',PALETTE['stone'])
rock2=material('Dark stone',PALETTE['stone_dark'])
shaft=material('Tunnel dark',PALETTE['shaft'])
ore=material(VARIANT.capitalize()+' ore',PALETTE[VARIANTS[VARIANT]])

def chunk(loc,r,m=ore):
    return boulder('Ore chunk',loc,(r*2,r*1.8,r*1.6),m,subdiv=1,jitter=.22)

GROUND=.12  # layout height of the old paving; export() sinks the model by it
# Rock outcrop the tunnel is driven into: a flat-topped mass with shoulders hugging the
# portal. Rocks stay clear of the tunnel volume (|x|<.52, y<.2, z<1.0) so nothing pokes
# through the lining.
for loc,size,m,top in [
    ((0,.88,.62),(2.25,1.00,1.30),rock2,.42),
    ((-.98,.30,.46),(.74,.88,.92),rock,.30),
    ((.98,.26,.38),(.70,.84,.76),rock2,.24),
    ((0,.42,1.34),(1.30,.80,.56),rock,.16),
    ((-.62,.66,1.28),(.86,.72,.62),rock,.20),
    ((.62,.70,1.22),(.84,.70,.60),rock,.18),
    ((.05,.80,1.55),(.80,.55,.40),rock2,.10),
    ((1.02,-.30,.18),(.34,.30,.22),rock2,None),
    ((-1.04,-.30,.16),(.26,.28,.18),rock,None),
]:
    boulder('Outcrop boulder',loc,size,m,jitter=.16,floor=GROUND-.02,top=top)
# Ore veins breaking the rock surface: tell iron from coal at a glance.
for cx,cy,cz in [(-.90,-.10,.52),(.90,-.12,.40),(-.30,.05,1.40),(.45,.33,1.40),(-.62,.30,1.30)]:
    for dx,dy,dz,r in [(0,0,0,.10),(.09,.02,.07,.07),(-.07,.03,-.06,.06)]:
        chunk((cx+dx,cy+dy,cz+dz),r)

# Timber-lined adit: plank walls and ceiling, a black back face for depth.
for x in [-.36,.36]:
    for i in range(4):
        box('Tunnel wall plank',(x,-.12,.20+i*.19),(.05,.56,.18),plank,.01)
for i in range(4):
    box('Tunnel ceiling plank',(-.27+i*.18,-.07,.965),(.17,.60,.05),plank,.01)
box('Tunnel depth',(0,.23,.55),(.72,.06,.86),shaft,0)
# Portal frame: two stout post sets and a lintel carrying a teal robot-made plate.
for y in [-.36,.10]:
    for x in [-.44,.44]:
        box('Portal post',(x,y,.56),(.15,.15,.90),wood)
        box('Post foot bracket',(x,y,.18),(.19,.19,.12),dark)
    beam('Portal lintel',(-.60,y,1.08),(.60,y,1.08),.17,wood)
for x in [-.44,.44]:
    beam('Portal cap beam',(x,-.42,1.17),(x,.18,1.17),.11,wood)
    beam('Portal brace',(x,-.36,.84),(x*.58,-.36,1.0),.08,wood)
box('Teal portal plate',(0,-.455,1.08),(.46,.03,.13),teal,.012)
for x in [-.19,.19]:
    cylinder('Plate rivet',(x,-.47,1.08),(x,-.485,1.08),.022,end,8)
# Lantern hung from the lintel's right end.
cylinder('Lantern hook',(.30,-.455,.99),(.30,-.455,.90),.012,dark,6)
box('Lantern cage',(.30,-.455,.84),(.09,.09,.12),dark,.01)
box('Lantern glow',(.30,-.455,.84),(.065,.10,.08),cream,.008)

# Rails running out of the tunnel to the front edge of the yard.
for y in [.12-i*.17 for i in range(7)]:
    box('Rail sleeper',(0,y,GROUND+.025),(.46,.09,.05),wood,.008)
for x in [-.13,.13]:
    box('Rail',(x,-.38,GROUND+.07),(.035,1.16,.04),steel,.006)
    box('Rail end stop',(x,-.97,GROUND+.09),(.07,.05,.08),dark,.01)
    beam('Stop brace',(x,-1.00,GROUND+.13),(x,-.92,GROUND+.05),.035,dark)

# Ore cart loaded and rolling out.
CY=-.62
for x in [-.13,.13]:
    for y in [CY-.14,CY+.14]:
        cylinder('Cart wheel',(x-.03,y,.25),(x+.03,y,.25),.07,dark)
        cylinder('Wheel hub',(x-.035*math.copysign(1,-x),y,.25),(x-.05*math.copysign(1,-x),y,.25),.028,end,8)
box('Cart chassis',(0,CY,.30),(.34,.46,.05),dark,.01)
cart=box('Cart hopper',(0,CY,.42),(.42,.52,.20),teal,.03)
for v in cart.data.vertices:
    if v.co.z<0:
        v.co.x*=.8
        v.co.y*=.85
box('Cart rim',(0,CY,.525),(.44,.54,.03),dark,.008)
for x,y,z,r in [(-.10,CY-.14,.56,.075),(.08,CY-.12,.57,.08),(-.02,CY+.02,.60,.09),
                (.11,CY+.12,.56,.07),(-.11,CY+.14,.57,.075),(.02,CY+.17,.55,.06)]:
    chunk((x,y,z),r)
cylinder('Tow hook',(0,CY+.26,.34),(0,CY+.31,.34),.02,dark,6)

# Teal winch motor that hauls carts up the incline; cable runs into the tunnel.
box('Winch feet',(-.74,-.62,GROUND+.06),(.40,.46,.12),dark)
box('Teal winch motor',(-.80,-.62,.37),(.28,.38,.34),teal,.05)
for y in [-.74,-.62,-.50]:
    box('Motor cooling rib',(-.955,y,.37),(.025,.045,.20),dark,.006)
box('Motor switch',(-.80,-.825,.44),(.12,.035,.09),cream,.015)
cylinder('Drive shaft',(-.66,-.62,.36),(-.50,-.62,.36),.04,dark,8)
cylinder('Winch drum',(-.48,-.80,.36),(-.48,-.44,.36),.10,dark)
for y in [-.80,-.44]:
    cylinder('Drum flange',(-.48,y-.015,.36),(-.48,y+.015,.36),.14,wood)
for y in [-.72,-.62,-.52]:
    cylinder('Wound cable',(-.48,y-.03,.36),(-.48,y+.03,.36),.108,steel)
beam('Winch cable',(-.44,-.44,.45),(-.28,-.02,.30),.018,steel)

# Ore heap and a timber retaining board at front right: the mine's output.
box('Heap retaining board',(.72,-.34,.21),(.58,.06,.20),plank,.01)
for x in [.46,.98]:
    box('Board stake',(x,-.37,.23),(.06,.06,.26),wood,.01)
for x,y,z,r in [(.58,-.58,.19,.10),(.78,-.55,.19,.11),(.95,-.62,.18,.09),(.66,-.78,.17,.08),
                (.86,-.80,.17,.085),(.70,-.62,.32,.10),(.88,-.66,.30,.08),(.55,-.72,.27,.07),
                (.78,-.70,.42,.08),(1.02,-.46,.17,.07),(.48,-.88,.16,.06)]:
    chunk((x,y,z),r)

export(NAME, join_label=VARIANT.capitalize()+' mine', sink=GROUND)
render_preview(NAME)
