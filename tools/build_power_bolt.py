"""Blender --background --python tools/build_power_bolt.py: model, source and preview.

The red "no power" lightning bolt that floats above unpowered buildings: an extruded zigzag with
a soft rounded bevel and flat (hardened) front/back faces. Its cartoon outline is a separate
"Power bolt outline" shell, not Godot's grow-along-normals pass: growing the bolt by more than
its inner-corner radius folds the hull over itself and pokes dark slivers through the face. The
shell is the outline polygon offset outward (rounded at convex corners, mitred at concave
ones) and extruded a little deeper, so it always encloses the bolt; Godot draws only its back
faces. The front faces Blender -Y, which glTF exports as Godot +Z (the indicator turns +Z to
the camera).
"""
import bpy
import bmesh
import math
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
for folder in ['assets/models/ui', 'art/blender', 'art/previews']:
    (ROOT / folder).mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)

def mat(name, color, emit=0.0):
    m=bpy.data.materials.new(name)
    m.diffuse_color=(*color,1)
    m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=.55
    if emit:
        p.inputs['Emission Color'].default_value=(*color,1)
        p.inputs['Emission Strength'].default_value=emit
    return m

red=mat('Warning red',(.80,.045,.03),.35)
rim=mat('Bolt outline',(.23,.035,.024))
rim.use_backface_culling=True

# Classic two-step bolt, 1 unit tall, centred on the origin in the XZ plane. The upper arm is
# broad and the lower arm tapers to a point so the silhouette reads instantly as "power".
outline=[(.05,.50),(.34,.50),(.11,.08),(.36,.08),(-.14,-.50),(-.03,-.05),(-.26,-.05)]
DEPTH=.20
OUTLINE_WIDTH=.035

def prism(name,points,depth,material):
    bm=bmesh.new()
    face=bm.faces.new([bm.verts.new((x,-depth/2,z)) for x,z in points])
    bmesh.ops.recalc_face_normals(bm,faces=[face])
    ext=bmesh.ops.extrude_face_region(bm,geom=[face])
    bmesh.ops.translate(bm,vec=Vector((0,depth,0)),verts=[v for v in ext['geom'] if isinstance(v,bmesh.types.BMVert)])
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces[:])
    bmesh.ops.triangulate(bm,faces=bm.faces[:])
    mesh=bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    o=bpy.data.objects.new(name,mesh)
    bpy.context.collection.objects.link(o)
    o.data.materials.append(material)
    return o

# Outward offset of a simple polygon: convex corners get a round arc, concave corners a miter.
def offset_polygon(points,d,arc_steps=5):
    pts=[Vector(p) for p in points]
    n=len(pts)
    area=sum(pts[i].x*pts[(i+1)%n].y-pts[(i+1)%n].x*pts[i].y for i in range(n))
    sign=1 if area>0 else -1
    def normal(a,b):
        e=(b-a).normalized()
        return Vector((e.y,-e.x))*sign
    out=[]
    for i in range(n):
        p,v,q=pts[i-1],pts[i],pts[(i+1)%n]
        n1,n2=normal(p,v),normal(v,q)
        turn=(v-p).x*(q-v).y-(v-p).y*(q-v).x
        if turn*sign>0:
            a1,a2=math.atan2(n1.y,n1.x),math.atan2(n2.y,n2.x)
            delta=(a2-a1+math.pi)%(2*math.pi)-math.pi
            for s in range(arc_steps+1):
                a=a1+delta*s/arc_steps
                out.append(tuple(v+Vector((math.cos(a),math.sin(a)))*d))
        else:
            out.append(tuple(v+(n1+n2)*d/(1+n1.dot(n2))))
    return out

bolt=prism('Power bolt',outline,DEPTH,red)
bpy.ops.object.select_all(action='DESELECT')
bpy.context.view_layer.objects.active=bolt
bolt.select_set(True)
bpy.ops.object.shade_smooth()
bev=bolt.modifiers.new('Pillow bevel','BEVEL')
bev.width=.045
bev.segments=4
bev.limit_method='NONE'
bev.use_clamp_overlap=True
# Flat caps, rounded rim: without this the big triangulated caps interpolate tilted rim
# normals across their slivers and show diagonal shading streaks.
bev.harden_normals=True
bpy.ops.object.modifier_apply(modifier=bev.name)

shell=prism('Power bolt outline',offset_polygon(outline,OUTLINE_WIDTH),DEPTH+2*OUTLINE_WIDTH,rim)

print('POWER BOLT triangles=%d outline=%d' % (len(bolt.data.polygons),len(shell.data.polygons)))
bpy.ops.object.select_all(action='DESELECT')
bolt.select_set(True)
shell.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'assets/models/ui/power_bolt.glb'),export_format='GLB',use_selection=True)

# Preview: the bolt floating above a dark hex plinth, from the game's front-left angle. Cycles
# ignores backface culling, so the shell's preview shader shows only its back faces (as Godot
# draws it) and lets the near side through.
bolt.location.z=.85
shell.location.z=.85
nodes=rim.node_tree.nodes
links=rim.node_tree.links
out=nodes.get('Material Output')
mix=nodes.new('ShaderNodeMixShader')
links.new(nodes.new('ShaderNodeNewGeometry').outputs['Backfacing'],mix.inputs['Fac'])
links.new(nodes.new('ShaderNodeBsdfTransparent').outputs['BSDF'],mix.inputs[1])
links.new(nodes.get('Principled BSDF').outputs['BSDF'],mix.inputs[2])
links.new(mix.outputs['Shader'],out.inputs['Surface'])
ground=mat('Preview ground',(.075,.105,.10))
bpy.ops.mesh.primitive_cylinder_add(vertices=6,radius=.75,depth=.12,location=(0,0,-.06))
bpy.context.object.data.materials.append(ground)
scene=bpy.context.scene
scene.render.engine='CYCLES'
scene.cycles.samples=40
scene.cycles.use_denoising=True
scene.world.color=(.25,.25,.25)
def aim(o,p):
    o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(-1.2,-5,3.0))
scene.camera=bpy.context.object
aim(scene.camera,(0,0,.6))
scene.camera.data.type='ORTHO'
scene.camera.data.ortho_scale=2.2
for name,loc,power,size in [('Key',(-3,-4,7),650,5),('Fill',(4,-1,4),400,4),('Rim',(1,4,5),700,3)]:
    bpy.ops.object.light_add(type='AREA',location=loc)
    o=bpy.context.object
    o.name=name
    o.data.energy=power
    o.data.shape='DISK'
    o.data.size=size
    aim(o,(0,0,.8))
scene.render.resolution_x=600
scene.render.resolution_y=600
scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
scene.render.filepath=str(ROOT/'art/previews/power_bolt.png')
bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'art/blender/power_bolt.blend'))
bpy.ops.render.render(write_still=True)
