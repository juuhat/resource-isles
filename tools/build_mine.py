"""Blender --background --python tools/build_mine.py -- [iron|coal]: model, source and preview.

One mine layout, two ore variants (Iron Mine / Coal Mine, see docs/second-island-progression.md).
"""
import bpy
import math
import random
import sys
from pathlib import Path
from mathutils import Vector

VARIANTS = {
    # name: (ore color, ore metallic, ore roughness)
    'iron': ((.40, .105, .04), .35, .62),
    'coal': ((.03, .03, .035), .15, .38),
}
args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
VARIANT = args[0] if args else 'iron'
ore_color, ore_metal, ore_rough = VARIANTS[VARIANT]
NAME = VARIANT + '_mine'

ROOT = Path(__file__).resolve().parents[1]
for folder in ['assets/models/buildings', 'art/blender', 'art/previews']:
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
random.seed(7)

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
steel=mat('Rail steel',(.43,.48,.43),.55)
teal=mat('Salvaged teal panels',(.045,.31,.30),.15)
cream=mat('Warm indicator',(.95,.69,.27))
rock=mat('Outcrop rock',(.15,.135,.12),0,.9)
rock2=mat('Shadowed rock',(.095,.09,.088),0,.9)
paving=mat('Paving stone',(.22,.205,.185),0,.88)
shaft=mat('Tunnel dark',(.018,.018,.02),0,1)
ore=mat(VARIANT.capitalize()+' ore',ore_color,ore_metal,ore_rough)

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

def boulder(name,loc,size,m,subdiv=2,jitter=.13,floor=None,top=None):
    """Faceted low-poly rock: a jittered icosphere, squashed flat where it meets the ground
    and, with top, sheared off into a flat ledge that far above its centre."""
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=subdiv,radius=.5,location=loc)
    o=bpy.context.object
    for v in o.data.vertices:
        v.co*=1+random.uniform(-jitter,jitter)
    o.dimensions=size
    # Small wobble only: spinning an elongated rock swings its long axis into the tunnel.
    o.rotation_euler.z=random.uniform(-.3,.3)
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    if floor is not None:
        for v in o.data.vertices:
            v.co.z=max(v.co.z,floor-loc[2])
    if top is not None:
        for v in o.data.vertices:
            v.co.z=min(v.co.z,top)
    return finish(o,name,m)

def chunk(loc,r,m=ore):
    return boulder('Ore chunk',loc,(r*2,r*1.8,r*1.6),m,subdiv=1,jitter=.22)

GROUND=.12
# Paved yard: chunky flagstones the rails and cart sit on.
for i in range(4):
    for j in range(4):
        x=-.84+i*.56
        y=-.88+j*.40
        box('Flagstone',(x,y,GROUND/2+random.uniform(-.012,.012)),(.54,.38,GROUND),paving,.03)

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
    cyl('Plate rivet',(x,-.47,1.08),(x,-.485,1.08),.022,end,8)
# Lantern hung from the lintel's right end.
cyl('Lantern hook',(.30,-.455,.99),(.30,-.455,.90),.012,dark,6)
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
        cyl('Cart wheel',(x-.03,y,.25),(x+.03,y,.25),.07,dark,12)
        cyl('Wheel hub',(x-.035*math.copysign(1,-x),y,.25),(x-.05*math.copysign(1,-x),y,.25),.028,end,8)
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
cyl('Tow hook',(0,CY+.26,.34),(0,CY+.31,.34),.02,dark,6)

# Teal winch motor that hauls carts up the incline; cable runs into the tunnel.
box('Winch feet',(-.74,-.62,GROUND+.06),(.40,.46,.12),dark)
box('Teal winch motor',(-.80,-.62,.37),(.28,.38,.34),teal,.05)
for y in [-.74,-.62,-.50]:
    box('Motor cooling rib',(-.955,y,.37),(.025,.045,.20),dark,.006)
box('Motor switch',(-.80,-.825,.44),(.12,.035,.09),cream,.015)
cyl('Drive shaft',(-.66,-.62,.36),(-.50,-.62,.36),.04,dark,8)
cyl('Winch drum',(-.48,-.80,.36),(-.48,-.44,.36),.10,dark,14)
for y in [-.80,-.44]:
    cyl('Drum flange',(-.48,y-.015,.36),(-.48,y+.015,.36),.14,wood,14)
for y in [-.72,-.62,-.52]:
    cyl('Wound cable',(-.48,y-.03,.36),(-.48,y+.03,.36),.108,steel,14)
beam('Winch cable',(-.44,-.44,.45),(-.28,-.02,.30),.018,steel)

# Ore heap and a timber retaining board at front right: the mine's output.
box('Heap retaining board',(.72,-.34,.21),(.58,.06,.20),plank,.01)
for x in [.46,.98]:
    box('Board stake',(x,-.37,.23),(.06,.06,.26),wood,.01)
for x,y,z,r in [(.58,-.58,.19,.10),(.78,-.55,.19,.11),(.95,-.62,.18,.09),(.66,-.78,.17,.08),
                (.86,-.80,.17,.085),(.70,-.62,.32,.10),(.88,-.66,.30,.08),(.55,-.72,.27,.07),
                (.78,-.70,.42,.08),(1.02,-.46,.17,.07),(.48,-.88,.16,.06)]:
    chunk((x,y,z),r)

objects=list(bpy.context.scene.objects)
bpy.ops.object.select_all(action='DESELECT')
for o in objects:
    o.select_set(True)
    bpy.context.view_layer.objects.active=o
    for mod in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
# Consolidate static geometry by material to avoid dozens of draw calls per building.
title=VARIANT.capitalize()+' mine '
for m in [wood,plank,end,dark,steel,teal,cream,rock,rock2,paving,shaft,ore]:
    bpy.ops.object.select_all(action='DESELECT')
    group=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.data.materials[0]==m]
    for o in group:
        o.select_set(True)
    if group:
        bpy.context.view_layer.objects.active=group[0]
        bpy.ops.object.join()
        bpy.context.object.name=title+m.name
bpy.ops.object.select_all(action='SELECT')
print('%s triangles=%d' % (NAME.upper(),sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.selected_objects)))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/buildings'/(NAME+'.glb')),export_format='GLB',use_selection=True)

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
scene.render.filepath=str(ROOT/'art/previews'/(NAME+'.png'))
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender'/(NAME+'.blend')))
bpy.ops.render.render(write_still=True)
