"""Blender --background --python tools/build_sawmill.py: model, source and preview."""
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True  # keep tools/ free of __pycache__
sys.path.insert(0, str(Path(__file__).resolve().parent))
from lowpoly_kit import PALETTE, reset_scene, material, box, cylinder, beam, log, saw_blade, export, render_preview

reset_scene()

wood=material('Timber',PALETTE['timber'])
plank=material('Planks',PALETTE['plank'])
end=material('Cut wood',PALETTE['cut_wood'])
dark=material('Iron',PALETTE['iron'])
steel=material('Steel',PALETTE['steel'])
teal=material('Teal',PALETTE['teal'])
roofmat=material('Terracotta',PALETTE['terracotta'])
cream=material('Amber',PALETTE['amber'])

def timber(x,y,z,length,r):
    log('Raw log',x,y,z,length,r,wood,end,plank)

# Open-front mill shed standing straight on the tile. The work area remains visible below roof.
for x in [-.64,.64]:
    for y in [.03,.72]:
        box('Square timber post',(x,y,.91),(.15,.15,1.28),wood)
        box('Post foot bracket',(x,y,.37),(.19,.19,.19),dark)
        cylinder('Large bolt',(x,y-.10,.37),(x,y-.115,.37),.039,end)
for i in range(6):
    box('Rear wall board',(-.52+i*.21,.75,.89),(.20,.075,1.1),plank,.01)
for x in [-.65,.65]:
    beam('Side diagonal brace',(x,.08,1.36),(x,.65,.86),.09,wood)
beam('Front lintel',(-.77,.01,1.51),(.77,.01,1.51),.16,wood)
# Gabled roof with broad panels and stout edge trim, set back from exposed blade.
for side in [-1,1]:
    for i in range(5):
        panel=box('Roof panel',(side*.39,.00+i*.205,1.74),(.87,.194,.065),roofmat,.012)
        panel.rotation_euler.y=side*math.radians(28)
    for y in [-.11,.96]:
        beam('Roof edge trim',(0,y,1.96),(side*.80,y,1.535),.085,wood)
beam('Roof ridge',(0,-.15,1.97),(0,1.0,1.97),.10,end)
# Teal riveted roof repair plate reinforces the robot-built identity.
patch=box('Teal roof patch',(-.40,.40,1.766),(.41,.42,.035),teal,.012)
patch.rotation_euler.y=math.radians(-28)

# Deep cutting table with clear log-in / plank-out arrangement.
for x in [-.43,.16]:
    for y in [-.73,.32]:
        box('Workbench leg',(x,y,.46),(.12,.12,.42),wood)
for x in [-.43,.16]:
    beam('Steel table rail',(x,-.96,.66),(x,.47,.66),.10,dark)
box('Cutting table',(-.135,-.26,.66),(.76,1.37,.095),plank)
box('Blade slot',(-.22,-.38,.713),(.08,.63,.012),dark,.002)
for y in [-.82,-.63,.05,.27]:
    cylinder('Feed roller',(-.47,y,.733),(.19,y,.733),.04,steel)
timber(-.06,.27,.85,.66,.12)
# Big vertical toothed blade in the YZ plane, projecting above the table.
saw_blade('Mill circular blade',-.25,-.20,-.39,.80,.365,.285,12,steel)
cylinder('Blade axle',(-.59,-.39,.80),(-.14,-.39,.80),.065,dark)
cylinder('Blade hub',(-.29,-.39,.80),(-.17,-.39,.80),.105,dark)
cylinder('Hub cap',(-.305,-.39,.80),(-.29,-.39,.80),.05,end)
# Motor directly coupled to blade axle, readable from the front-left camera.
box('Motor feet',(-.76,-.34,.47),(.38,.44,.12),dark)
box('Teal electric motor',(-.76,-.34,.72),(.36,.43,.43),teal,.055)
for y in [-.46,-.34,-.22]:
    box('Motor cooling rib',(-.955,y,.72),(.025,.045,.24),dark,.006)
box('Motor switch',(-.76,-.565,.80),(.13,.035,.10),cream,.015)
# Output stack on right, raw timber storage at rear right.
for z in [.35,.425,.50]:
    for x in [.43,.65,.87]:
        box('Finished plank',(x,-.48,z),(.18,.88,.065),end,.01)
for y in [-.74,-.23]:
    box('Plank stack binding',(.65,y,.542),(.64,.035,.018),dark,.002)
for x in [.77,1.0]:
    timber(x,.50,.43,.67,.10)
timber(.885,.50,.60,.67,.10)

export('sawmill', join_label='Sawmill', sink=.29)
render_preview('sawmill', target_z=.87)
