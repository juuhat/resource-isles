"""Blender --background --python tools/build_quarry.py: model, source and preview.

Open-pit counterpart to the tunnel mines (tools/build_mine.py): a stepped cut-stone face,
a derrick lifting a block, and the finished blocks stacked for pickup.
"""
import random
import sys
from pathlib import Path

from mathutils import Vector

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import PALETTE, reset_scene, material, box, cylinder, beam, boulder, export, render_preview

reset_scene()
random.seed(11)

wood=material('Timber',PALETTE['timber'])
plank=material('Planks',PALETTE['plank'])
end=material('Cut wood',PALETTE['cut_wood'])
dark=material('Iron',PALETTE['iron'])
steel=material('Steel',PALETTE['steel'])
teal=material('Teal',PALETTE['teal'])
cream=material('Amber',PALETTE['amber'])
rock=material('Stone',PALETTE['stone'])
rock2=material('Dark stone',PALETTE['stone_dark'])
cut=material('Cut stone',PALETTE['stone_cut'])
dust=material('Dust',PALETTE['dust'])

def chip(loc,r,m=cut):
    return boulder('Stone chip',loc,(r*2,r*1.7,r*1.3),m,subdiv=1,jitter=.25)

GROUND=.12  # layout height of the old paving; export() sinks the model by it
# Stepped quarry face: three benches stepping down toward the front, each laid up from
# horizontal bedding courses with staggered joints so it reads as layered rock, not columns.
# Upper benches are weathered; the lowest, most recently worked one is fresh stone.
BENCHES=[
    # front to back: y range, top height, course materials bottom-up
    ((-.12,.22),.50,[cut,cut]),
    ((.22,.62),.94,[cut,rock]),
    ((.62,1.02),1.36,[rock,rock2]),
]
below=0
for (y0,y1),top,mats in BENCHES:
    # Hidden core under the exposed face; its left end is the stepped side profile.
    if below:
        box('Bench core',(0,(y0+y1)/2,below/2),(2.04,y1-y0,below),rock2,.03)
    for c,m in enumerate(mats):
        z0=below+(top-below)*c/len(mats)
        z1=below+(top-below)*(c+1)/len(mats)
        # Each bed sits a touch further back than the one below: a slightly battered face.
        setback=c*.03
        x=-1.02
        while x<1.0:
            w=min(random.uniform(.55,1.0),1.02-x)
            if 1.02-x-w<.3:
                w=1.02-x
            dy=random.uniform(-.025,.025)+setback/2
            box('Bench bed',(x+w/2,(y0+y1)/2+dy,(z0+z1)/2),(w-.025,y1-y0-setback,z1-z0-.02),m,.035)
            x+=w
    # Worked ledges carry a pale layer of dust and chips so each step reads from above.
    if top<1.0:
        box('Ledge dust',(0,(y0+y1)/2+.03,top+.006),(1.96,y1-y0-.10,.02),dust,.008)
    below=top
# Weathered rim of natural rock the quarry is biting into.
for loc,size in [((-.66,.90,1.38),(.80,.55,.40)),((.10,.94,1.42),(.95,.50,.44)),
                 ((.76,.88,1.36),(.70,.55,.36)),((-1.00,.50,.92),(.34,.50,.40)),
                 ((1.00,.46,.92),(.30,.50,.38))]:
    boulder('Rim boulder',loc,size,rock2,floor=loc[2]-.1,top=.14)
# Row of drill holes along the lowest bench: the next block about to be split off.
for x in [.18,.32,.46,.60,.74]:
    cylinder('Drill hole',(x,-.125,.46),(x,-.125,.52),.022,dark,8)
box('Split line',(.46,-.127,.30),(.62,.012,.012),dark,0)
# Half-lifted block on the lowest bench with an iron wedge driven in.
box('Wedge',(.10,-.14,.49),(.03,.05,.08),steel,.005)

# Stiff-leg derrick: mast, two back legs, a boom reaching over the floor.
MAST=Vector((-.70,-.30,GROUND))
TOP=MAST+Vector((0,0,1.62))
cylinder('Derrick mast',MAST,TOP,.065,wood)
box('Mast foot plate',(MAST.x,MAST.y,GROUND+.03),(.26,.26,.06),dark)
for foot in [(-1.02,.20,GROUND),(-1.00,-.82,GROUND)]:
    beam('Stiff leg',TOP-Vector((0,0,.08)),foot,.07,wood)
    box('Leg anchor',(foot[0],foot[1],GROUND+.04),(.16,.16,.08),dark)
box('Mast cap',TOP,(.16,.16,.10),dark,.01)
cylinder('Top sheave',(TOP.x-.05,TOP.y,TOP.z+.06),(TOP.x+.05,TOP.y,TOP.z+.06),.06,end)
BOOM_FOOT=MAST+Vector((0,0,.42))
TIP=Vector((.20,-.30,1.46))
beam('Derrick boom',BOOM_FOOT,TIP,.075,wood)
box('Boom collar',BOOM_FOOT,(.17,.17,.10),dark,.01)
beam('Topping cable',TOP+Vector((0,0,.05)),TIP,.018,steel)
cylinder('Boom tip sheave',(TIP.x,TIP.y-.05,TIP.z),(TIP.x,TIP.y+.05,TIP.z),.055,end)
# Load line down to a hook and a block of fresh stone in chains.
HOOK=Vector((TIP.x,TIP.y,.98))
cylinder('Load line',TIP,HOOK,.014,steel,6)
box('Hook block',HOOK,(.08,.06,.09),dark,.01)
for sx in [-1,1]:
    beam('Lifting chain',HOOK,(TIP.x+sx*.13,TIP.y,.78),.016,dark)
box('Lifted stone block',(TIP.x,TIP.y,.64),(.34,.26,.26),cut,.03)

# Teal winch at the mast foot drives the load line.
box('Winch feet',(-.56,-.66,GROUND+.05),(.44,.34,.10),dark)
box('Teal winch motor',(-.66,-.66,.33),(.26,.30,.30),teal,.05)
for x in [-.74,-.66,-.58]:
    box('Motor cooling rib',(x,-.82,.33),(.035,.025,.18),dark,.006)
box('Motor switch',(-.66,-.82,.43),(.10,.03,.07),cream,.012)
cylinder('Winch drum',(-.50,-.66,.30),(-.30,-.66,.30),.085,steel)
for x in [-.50,-.30]:
    cylinder('Drum flange',(x-.012,-.66,.30),(x+.012,-.66,.30),.12,wood)
beam('Winch line',(-.40,-.66,.38),(MAST.x+.05,MAST.y,1.0),.016,steel)

# Finished blocks stacked on a pallet, ready for the robot to haul.
box('Pallet',(.58,-.60,GROUND+.04),(.78,.56,.06),plank,.01)
for x in [.28,.58,.88]:
    box('Pallet runner',(x,-.60,GROUND+.015),(.07,.56,.03),wood,.005)
for x,z in [(.34,.25),(.58,.25),(.82,.25),(.46,.47),(.70,.47),(.58,.69)]:
    box('Cut stone block',(x+random.uniform(-.01,.01),-.60,z),(.22,.34,.21),cut,.025)
# Loose chips at the foot of the face.
for x,y,z,r in [(-.35,-.30,.16,.06),(-.20,-.38,.15,.05),(.05,-.40,.15,.045),(-.48,-.20,.17,.07),
                (.98,-.28,.16,.05),(.30,-.28,.15,.04)]:
    chip((x,y,z),r)

export('quarry', join_label='Quarry', sink=GROUND)
render_preview('quarry')
