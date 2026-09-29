"""Blender --background --python tools/build_sawmill.py: model, source and preview."""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
for folder in ['assets/models/buildings', 'art/blender', 'art/previews']:
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def mat(name, color, metal=0):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=.78
    p.inputs['Metallic'].default_value=metal
    return m

wood=mat('Warm timber',(.34,.17,.065))
plank=mat('Honey planks',(.49,.27,.105))
end=mat('Fresh cut wood',(.69,.43,.19))
dark=mat('Dark iron',(.105,.14,.135),.25)
steel=mat('Saw steel',(.43,.48,.43),.55)
teal=mat('Salvaged teal panels',(.045,.31,.30),.15)
roofmat=mat('Oxide red roof',(.43,.12,.055))
cream=mat('Warm indicator',(.95,.69,.27))

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

def log(x,y,z,length,r):
    cyl('Raw log bark',(x,y-length/2,z),(x,y+length/2,z),r,wood)
    for s in [-1,1]:
        yy=y+s*length/2
        cyl('Cut end',(x,yy,z),(x,yy+s*.014,z),r*.85,end)
        cyl('Heartwood',(x,yy+s*.015,z),(x,yy+s*.018,z),r*.32,plank)

# Low foundation and an open-front mill shed. The work area remains visible below roof.
for x in [-.73,.73]:
    box('Iron foundation skid',(x,0,.10),(.20,1.96,.20),dark)
for i in range(9):
    box('Floor board',(-.88+i*.22,0,.23),(.208,1.91,.12),plank,.012)
for x in [-.64,.64]:
    for y in [.03,.72]:
        box('Square timber post',(x,y,.91),(.15,.15,1.28),wood)
        box('Post foot bracket',(x,y,.37),(.19,.19,.19),dark)
        cyl('Large bolt',(x,y-.10,.37),(x,y-.115,.37),.039,end,8)
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
    cyl('Feed roller',(-.47,y,.733),(.19,y,.733),.04,steel)
log(-.06,.27,.85,.66,.12)
# Big vertical toothed blade in the YZ plane, projecting above the table.
verts=[]
n=64
for x in [-.25,-.20]:
    for i in range(n):
        a=2*math.pi*i/n
        r=.365 if i%2==0 else .316
        verts.append((x,-.39+math.cos(a)*r,.80+math.sin(a)*r))
faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh=bpy.data.meshes.new('Circular blade teeth')
mesh.from_pydata(verts,[],faces)
mesh.update()
o=bpy.data.objects.new('Mill circular blade',mesh)
bpy.context.collection.objects.link(o)
finish(o,o.name,steel)
cyl('Blade axle',(-.59,-.39,.80),(-.14,-.39,.80),.065,dark)
cyl('Blade hub',(-.29,-.39,.80),(-.17,-.39,.80),.105,dark)
cyl('Hub cap',(-.305,-.39,.80),(-.29,-.39,.80),.05,end,8)
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
    log(x,.50,.43,.67,.10)
log(.885,.50,.60,.67,.10)

objects=list(bpy.context.scene.objects)
bpy.ops.object.select_all(action='DESELECT')
for o in objects:
    o.select_set(True)
    bpy.context.view_layer.objects.active=o
    for mod in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
# Consolidate static geometry by material to avoid dozens of draw calls per building.
for m in [wood,plank,end,dark,steel,teal,roofmat,cream]:
    bpy.ops.object.select_all(action='DESELECT')
    group=[o for o in bpy.context.scene.objects if o.type=='MESH' and o.data.materials[0]==m]
    for o in group:
        o.select_set(True)
    if group:
        bpy.context.view_layer.objects.active=group[0]
        bpy.ops.object.join()
        bpy.context.object.name='Sawmill '+m.name
bpy.ops.object.select_all(action='SELECT')
print('SAWMILL triangles=%d' % sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in bpy.context.selected_objects))
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/buildings/sawmill.glb'),export_format='GLB',use_selection=True)

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
aim(scene.camera,(0,0,.87))
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
scene.render.filepath=str(ROOT/'art/previews/sawmill.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/sawmill.blend'))
bpy.ops.render.render(write_still=True)
