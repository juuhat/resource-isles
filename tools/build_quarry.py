"""Blender --background --python tools/build_quarry.py: model, source and preview.

Open-pit counterpart to the tunnel mines (tools/build_mine.py): a stepped cut-stone face,
a derrick lifting a block, and the finished blocks stacked for pickup.
"""
import bpy
import math
import random
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
for folder in ['assets/models/buildings', 'art/blender', 'art/previews']:
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
random.seed(11)

def mat(name, color, metal=0, rough=.78):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=rough
    p.inputs['Metallic'].default_value=metal
    return m

wood=mat('Warm timber',(.34,.17,.065))
plank=mat('Honey planks',(.49,.27,.105))
end=mat('Fresh cut wood',(.69,.43,.19))
dark=mat('Dark iron',(.105,.14,.135),.25)
steel=mat('Cable steel',(.43,.48,.43),.55)
teal=mat('Salvaged teal panels',(.045,.31,.30),.15)
cream=mat('Warm indicator',(.95,.69,.27))
rock=mat('Outcrop rock',(.15,.135,.12),0,.9)
rock2=mat('Shadowed rock',(.095,.09,.088),0,.9)
paving=mat('Paving stone',(.22,.205,.185),0,.88)
cut=mat('Fresh cut stone',(.46,.39,.29),0,.85)
dust=mat('Quarry dust',(.55,.50,.42),0,.95)

def finish(o,name,m,bevel=0):
    o.name=name
    o.data.materials.append(m)
    if bevel:
        mod=o.modifiers.new('Edge bevel','BEVEL')
        mod.width=bevel
        mod.segments=1
        o.modifiers.new('Corner normals','WEIGHTED_NORMAL')
    return o

def box(name,loc,size,m,bevel=.02):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    o=bpy.context.object
    o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    return finish(o,name,m,bevel)

def cyl(name,a,b,r,m,n=12):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=r,depth=(b-a).length,location=(a+b)/2)
    o=bpy.context.object
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return finish(o,name,m)

def beam(name,a,b,w,m):
    a,b=Vector(a),Vector(b)
    o=box(name,(a+b)/2,(w,w,(b-a).length),m)
    o.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    return o

def boulder(name,loc,size,m,subdiv=2,jitter=.16,floor=None,top=None):
    """Faceted low-poly rock: a jittered icosphere, flattened at the ground and optionally on top."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv,radius=.5,location=loc)
    o=bpy.context.object
    for v in o.data.vertices:
        v.co*=1+random.uniform(-jitter,jitter)
    o.dimensions=size
    o.rotation_euler.z=random.uniform(-.3,.3)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    for v in o.data.vertices:
        if floor is not None:
            v.co.z=max(v.co.z,floor-loc[2])
        if top is not None:
            v.co.z=min(v.co.z,top)
    return finish(o,name,m)

def chip(loc,r,m=cut):
    return boulder('Stone chip',loc,(r*2,r*1.7,r*1.3),m,subdiv=1,jitter=.25)

GROUND=.12
# Paved working floor in front of the face.
for i in range(4):
    for j in range(3):
        box('Flagstone',(-.84+i*.56,-.88+j*.40,GROUND/2+random.uniform(-.012,.012)),(.54,.38,GROUND),paving,.03)

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
    cyl('Drill hole',(x,-.125,.46),(x,-.125,.52),.022,dark,8)
box('Split line',(.46,-.127,.30),(.62,.012,.012),dark,0)
# Half-lifted block on the lowest bench with an iron wedge driven in.
box('Wedge',(.10,-.14,.49),(.03,.05,.08),steel,.005)

# Stiff-leg derrick: mast, two back legs, a boom reaching over the floor.
MAST=Vector((-.70,-.30,GROUND))
TOP=MAST+Vector((0,0,1.62))
cyl('Derrick mast',MAST,TOP,.065,wood,10)
box('Mast foot plate',(MAST.x,MAST.y,GROUND+.03),(.26,.26,.06),dark)
for foot in [(-1.02,.20,GROUND),(-1.00,-.82,GROUND)]:
    beam('Stiff leg',TOP-Vector((0,0,.08)),foot,.07,wood)
    box('Leg anchor',(foot[0],foot[1],GROUND+.04),(.16,.16,.08),dark)
box('Mast cap',TOP,(.16,.16,.10),dark,.01)
cyl('Top sheave',(TOP.x-.05,TOP.y,TOP.z+.06),(TOP.x+.05,TOP.y,TOP.z+.06),.06,end,10)
BOOM_FOOT=MAST+Vector((0,0,.42))
TIP=Vector((.20,-.30,1.46))
beam('Derrick boom',BOOM_FOOT,TIP,.075,wood)
box('Boom collar',BOOM_FOOT,(.17,.17,.10),dark,.01)
beam('Topping cable',TOP+Vector((0,0,.05)),TIP,.018,steel)
cyl('Boom tip sheave',(TIP.x,TIP.y-.05,TIP.z),(TIP.x,TIP.y+.05,TIP.z),.055,end,10)
# Load line down to a hook and a block of fresh stone in chains.
HOOK=Vector((TIP.x,TIP.y,.98))
cyl('Load line',TIP,HOOK,.014,steel,6)
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
cyl('Winch drum',(-.50,-.66,.30),(-.30,-.66,.30),.085,steel,14)
for x in [-.50,-.30]:
    cyl('Drum flange',(x-.012,-.66,.30),(x+.012,-.66,.30),.12,wood,14)
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

objects=list(bpy.context.scene.objects)
bpy.ops.object.select_all(action='DESELECT')
for o in objects:
    o.select_set(True)
    bpy.context.view_layer.objects.active=o
    for mod in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
# Consolidate static geometry by material to avoid dozens of draw calls per building.
for m in [wood,plank,end,dark,steel,teal,cream,rock,rock2,paving,cut,dust]:
    bpy.ops.object.select_all(action='DESELECT')
    group=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.data.materials[0]==m]
    for o in group:
        o.select_set(True)
    if group:
        bpy.context.view_layer.objects.active=group[0]
        bpy.ops.object.join()
        bpy.context.object.name='Quarry '+m.name
bpy.ops.object.select_all(action='SELECT')
print('QUARRY triangles=%d' % sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.selected_objects))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/buildings/quarry.glb'),export_format='GLB',use_selection=True)

# Studio setup is only in the editable .blend and preview, never exported to the game.
ground=mat('Preview ground',(.075,.105,.10))
cyl('Preview hex plinth',(0,0,-.16),(0,0,-.025),1.65,ground,6)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=40
scene.cycles.use_denoising=True
scene.world.color=(.25,.25,.25)
def aim(o,p):
    o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(-3.5,-5,3.8))
scene.camera=bpy.context.object
aim(scene.camera,(0,0,.80))
scene.camera.data.type='ORTHO'
scene.camera.data.ortho_scale=4.05
for name,loc,power,size in [('Key',(-3,-4,7),650,5),('Fill',(4,-1,4),400,4),('Rim',(1,4,5),700,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc)
    o=bpy.context.object
    o.name=name
    o.data.energy=power
    o.data.shape='DISK'
    o.data.size=size
    aim(o,(0,0,.8))
scene.render.resolution_x=1000
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.filepath=str(ROOT/'art/previews/quarry.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/quarry.blend'))
bpy.ops.render.render(write_still=True)
