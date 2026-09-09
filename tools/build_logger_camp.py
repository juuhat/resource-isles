"""Rebuild with Blender --background --python tools/build_logger_camp.py."""
import bpy
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets/models/buildings'
SOURCE = ROOT / 'art/blender'
PREVIEW = ROOT / 'art/previews'
for folder in (OUT, SOURCE, PREVIEW):
    folder.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def material(name, color, metal=0):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = .78
    p.inputs['Metallic'].default_value = metal
    return m

wood = material('Warm timber', (.34, .17, .065))
end = material('Fresh cut wood', (.69, .43, .19))
plank = material('Honey planks', (.49, .27, .105))
dark = material('Dark iron', (.105, .14, .135), .25)
steel = material('Saw steel', (.43, .48, .43), .55)
teal = material('Salvaged teal panels', (.045, .31, .30), .15)
canvas = material('Rust orange canopy', (.62, .18, .065))
cream = material('Warm indicator', (.95, .69, .27))

def finish(obj, name, mat, bevel=0):
    obj.name = name
    obj.data.materials.append(mat)
    if bevel:
        mod = obj.modifiers.new('Small readable edge bevel', 'BEVEL')
        mod.width = bevel
        mod.segments = 1
        obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    return obj

def box(name, loc, size, mat, bevel=.025):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, name, mat, bevel)

def cylinder(name, a, b, radius, mat, vertices=10):
    a, b = Vector(a), Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=(b-a).length, location=(a+b)/2)
    o = bpy.context.object
    o.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return finish(o, name, mat)

def beam(name, a, b, width, mat):
    a, b = Vector(a), Vector(b)
    o = box(name, (a+b)/2, (width, width, (b-a).length), mat)
    o.rotation_euler = (b-a).to_track_quat('Z', 'Y').to_euler()
    return o

def log(name, x, y, z, length, radius):
    cylinder(name+' bark', (x,y-length/2,z),(x,y+length/2,z),radius,wood)
    for s in [-1,1]:
        yy = y+s*(length/2+.003)
        cylinder(name+' cut end', (x,yy,z),(x,yy+s*.012,z),radius*.84,end)
        cylinder(name+' heartwood', (x,yy+s*.013,z),(x,yy+s*.016,z),radius*.31,plank)

# Compact timber skid base, open-front workshop and a raised log rack.
for x in [-.70,.70]:
    box('Foundation skid', (x,0,.10),(.19,1.75,.20),dark)
for i in range(8):
    box('Deck plank', (-.79+i*.225,0,.23),(.215,1.70,.12),plank,.012)
for x in [-.64,.64]:
    for y in [-.24,.61]:
        cylinder('Structural timber post',(x,y,.27),(x,y,1.78),.095,wood)
        box('Iron post collar',(x,y,1.46),(.215,.215,.16),dark,.015)
        cylinder('Oversized brass bolt',(x,y-.115,1.46),(x,y-.14,1.46),.045,end,8)
for x in [-.66,.66]:
    beam('Upper rack rail',(x,-.34,1.61),(x,.77,1.61),.14,plank)
for y in [-.19,.58]:
    beam('Rack cross member',(-.75,y,1.61),(.75,y,1.61),.13,wood)
for i in range(5):
    log('Stored timber',-.47+i*.23,.22,1.76,1.0,.105)
for i in range(5):
    box('Back wall plank',(-.48+i*.24,.60,.79),(.225,.09,.98),plank,.01)
box('Teal machine body',(.02,.29,.69),(.66,.51,.78),teal,.075)
box('Dark machine opening',(.02,.019,.68),(.39,.025,.46),dark,.04)
box('Log feed table',(.02,-.38,.49),(.72,.81,.13),wood)
for x in [-.27,.27]:
    beam('Feed runner',(x,-.86,.54),(x,.04,.54),.095,end)
log('Log on feed bed',.02,-.48,.68,.88,.12)
# A broad sloping canvas canopy, tied to chunky timber bars.
roof = box('Orange canvas awning',(0,-.15,1.20),(1.24,.96,.075),canvas,.025)
roof.rotation_euler.x = math.radians(19)
for x in [-.61,.61]:
    beam('Awning side spar',(x,-.61,1.04),(x,.31,1.36),.065,wood)
beam('Awning front spar',(-.67,-.61,1.04),(.67,-.61,1.04),.075,end)
# Battery on right; fat, readable vent slits and indicator.
box('Battery dark surround',(.87,.02,.66),(.43,.60,.68),dark,.06)
box('Teal battery cover',(.90,-.015,.69),(.43,.57,.56),teal,.06)
for i in range(3):
    box('Battery indicator',(.79+i*.085,-.306,.72),(.04,.012,.13),cream,.006)
box('Battery top cap',(.88,.04,1.02),(.17,.21,.13),dark)
# Articulated saw arm along the left side, outside the canopy silhouette.
beam('Saw mounting bracket',(-.63,.34,.99),(-.92,.34,1.22),.19,dark)
beam('Upper teal saw arm',(-.92,.34,1.22),(-1.02,-.02,1.60),.17,teal)
beam('Lower teal saw arm',(-1.02,-.02,1.60),(-1.00,-.52,1.00),.15,teal)
for y,z in [(.34,1.22),(-.02,1.60),(-.52,1.00)]:
    cylinder('Arm pivot',(-1.12,y,z),(-.86,y,z),.12,dark)
    cylinder('Pivot bolt',(-1.135,y,z),(-1.12,y,z),.068,end)
# Extruded alternating tooth profile: saw lies in YZ plane, axle along X.
verts=[]
n=48
for x in [-1.045,-.985]:
    for i in range(n):
        angle=2*math.pi*i/n
        radius=.29 if i%2==0 else .245
        verts.append((x,-.56+math.cos(angle)*radius,.77+math.sin(angle)*radius))
faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
faces += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
mesh=bpy.data.meshes.new('Saw tooth mesh')
mesh.from_pydata(verts,[],faces)
mesh.update()
obj=bpy.data.objects.new('Circular harvesting saw',mesh)
bpy.context.collection.objects.link(obj)
finish(obj,obj.name,steel)
cylinder('Saw hub',(-1.075,-.56,.77),(-.955,-.56,.77),.095,dark)

# Apply bevels for a self-contained, material-only glTF with no external textures.
asset_objects=list(bpy.context.scene.objects)
bpy.ops.object.select_all(action='DESELECT')
for obj in asset_objects:
    obj.select_set(True)
    bpy.context.view_layer.objects.active=obj
    for modifier in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=modifier.name)
bpy.ops.export_scene.gltf(filepath=str(OUT/'logger_camp.glb'),export_format='GLB',use_selection=True)
print('LOGGER_ASSET meshes=%d triangles=%d' % (len(asset_objects),sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in asset_objects)))

# Studio setup is only in the editable .blend and preview, never exported to the game.
ground=material('Preview background',(.075,.105,.10))
cylinder('Preview hex plinth',(0,0,-.16),(0,0,-.025),1.58,ground,6)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=40
scene.cycles.use_denoising=True
scene.world.color=(.25,.25,.25)
def point_at(obj,target):
    obj.rotation_euler=(Vector(target)-obj.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(-3.5,-5,3.8))
scene.camera=bpy.context.object
point_at(scene.camera,(0,0,.85))
scene.camera.data.type='ORTHO'
scene.camera.data.ortho_scale=3.85
for name,loc,power,size in [('Key',(-3,-4,7),650,5),('Fill',(4,-1,4),400,4),('Rim',(1,4,5),700,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc)
    light=bpy.context.object
    light.name=name
    light.data.energy=power
    light.data.shape='DISK'
    light.data.size=size
    point_at(light,(0,0,.8))
scene.render.resolution_x=1000
scene.render.resolution_y=1000
scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.filepath=str(PREVIEW/'logger_camp.png')
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'logger_camp.blend'))
bpy.ops.render.render(write_still=True)
