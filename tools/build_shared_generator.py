"""Reusable PTO generator. Blender --background --python tools/build_shared_generator.py.

Building builders may import build_shared_generator() after their own reset_scene().
Authored in the kit's tile units; bottom mount at zero, socket faces Blender -Y.
"""
import math
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))

import bmesh
import bpy
from mathutils import Vector
from lowpoly_kit import ROOT, PALETTE, box, cylinder, marker, prism_y, material, reset_scene, render_preview


def ring(name, center, axis, outer, inner, depth, mat, sides=12):
    """Actual open annulus, including inner wall; never a painted black socket."""
    verts = []
    for offset, radius in [(-depth/2, outer), (-depth/2, inner),
                           (depth/2, outer), (depth/2, inner)]:
        for i in range(sides):
            a = 2 * math.pi * i / sides
            u, v = radius * math.cos(a), radius * math.sin(a)
            p = (offset, u, v) if axis == 'X' else (u, offset, v)
            verts.append(tuple(Vector(center) + Vector(p)))
    faces = []
    for i in range(sides):
        j = (i + 1) % sides
        faces.extend([(i, j, sides+j, sides+i),
                      (2*sides+i, 3*sides+i, 3*sides+j, 2*sides+j),
                      (i, 2*sides+i, 2*sides+j, j),
                      (sides+i, sides+j, 3*sides+j, 3*sides+i)])
    mesh = bpy.data.meshes.new(name + 'Mesh')
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    mesh.materials.append(mat)
    return obj


def build_shared_generator(location=(0, 0, 0), parent=None, name='SharedGenerator'):
    """Return a root with independent SocketRotor/FlywheelPivot and DockPoint/OutputShaft.

    Local dimensions: X [-.28,.43], Y [-.265,.235], Z [0,.47].
    DockPoint = (0,-.265,.25); mount root .16 above ground for a .41-high inlet.
    Root translation/rotation/scale moves all pieces and markers together.
    """
    collection = bpy.data.collections.new(name)
    bpy.context.scene.collection.children.link(collection)
    root = marker(name, (0, 0, 0))
    for c in list(root.users_collection):
        c.objects.unlink(root)
    collection.objects.link(root)

    def attach(obj, target=root):
        bpy.context.view_layer.update()
        world = obj.matrix_world.copy()
        obj.parent = target
        obj.matrix_world = world
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        collection.objects.link(obj)
        return obj

    mats = {key: material(name + '_' + key, PALETTE[key])
            for key in ('teal', 'cream', 'iron', 'steel', 'amber', 'shaft')}
    amber_shader = mats['amber'].node_tree.nodes['Principled BSDF']
    amber_shader.inputs['Emission Color'].default_value = (*PALETTE['amber'], 1)
    amber_shader.inputs['Emission Strength'].default_value = .35

    # One broad chamfered shell, two mounting rails. No texture or tiny fasteners.
    profile = [(-.25,.055), (.25,.055), (.28,.085), (.28,.405),
               (.245,.44), (-.245,.44), (-.28,.405), (-.28,.085)]
    housing = attach(prism_y('Housing', profile, -.18, .18, mats['teal']))
    cutter = cylinder('SocketBoreCutter', (0,-.28,.25), (0,-.14,.25), .10,mats['shaft'],12)
    modifier = housing.modifiers.new('Recessed socket bore', 'BOOLEAN')
    modifier.operation = 'DIFFERENCE'
    modifier.object = cutter
    bpy.context.view_layer.objects.active = housing
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    bpy.data.objects.remove(cutter, do_unlink=True)
    for x in (-.18,.18):
        attach(box('MountFoot', (x,0,.035), (.11,.40,.07), mats['iron']))
    attach(box('TopHatch', (0,.025,.45), (.23,.20,.02), mats['iron']))

    # Cream octagonal collar surrounding a visibly recessed female inlet.
    attach(ring('SocketCollar', (0,-.2075,.25), 'Y', .163,.107,.095,mats['cream'],8))
    attach(ring('SocketBezel', (0,-.257,.25), 'Y', .113,.09,.016,mats['iron'],12))
    rotor = attach(marker('SocketRotor', (0,-.205,.25)))
    attach(ring('SocketSleeve', (0,-.205,.25), 'Y', .098,.078,.086,mats['steel'],12), rotor)
    # Six broad splines inside the bore; its back is closed deep inside the casing.
    for i in range(6):
        angle = 2 * math.pi * i / 6
        obj = box('FemaleSpline', (.08*math.cos(angle),-.205,.25+.08*math.sin(angle)),
                  (.017,.072,.024), mats['iron'])
        obj.rotation_euler.y = -angle
        attach(obj, rotor)
    attach(cylinder('SocketRecess', (0,-.160,.25), (0,-.151,.25), .086,mats['shaft'],12))
    attach(box('IndicatorFrame', (.215,-.19,.25), (.07,.024,.16),mats['iron']))
    attach(box('PowerIndicator', (.215,-.205,.25), (.045,.013,.125),mats['amber']))

    # Open spoked flywheel with a real centre pivot, axle along X.
    wheel = attach(marker('FlywheelPivot', (.375,.015,.25)))
    attach(cylinder('OutputAxle', (.265,.015,.25), (.43,.015,.25),.038,mats['steel']),wheel)
    attach(ring('FlywheelRim', (.375,.015,.25), 'X', .22,.166,.07,mats['iron'],12),wheel)
    attach(cylinder('FlywheelHub', (.33,.015,.25), (.423,.015,.25),.064,mats['iron']),wheel)
    attach(cylinder('HubCap', (.423,.015,.25), (.43,.015,.25),.037,mats['steel']),wheel)
    for i in range(6):
        angle = 2 * math.pi * i / 6
        obj = box('FlywheelSpoke', (.375,.015+.109*math.cos(angle),.25+.109*math.sin(angle)),
                  (.047,.15,.037), mats['iron'])
        obj.rotation_euler.x = angle
        attach(obj,wheel)
    attach(marker('DockPoint', (0,-.265,.25)))
    attach(marker('OutputShaft', (.43,.015,.25)))

    # Merge only within the same parent and material, keeping rotating pieces independent.
    for target in (root, rotor, wheel):
        for mat in mats.values():
            group = [o for o in collection.objects if o.type == 'MESH'
                     and o.parent == target and o.data.materials[0] == mat]
            if not group:
                continue
            bpy.ops.object.select_all(action='DESELECT')
            for obj in group:
                obj.select_set(True)
            bpy.context.view_layer.objects.active = group[0]
            if len(group) > 1:
                bpy.ops.object.join()
            bpy.context.object.name = target.name + '_' + mat.name.rsplit('_',1)[-1]
    root.location = location
    if parent:
        root.parent = parent
    bpy.context.view_layer.update()
    return root


def main():
    reset_scene()
    root = build_shared_generator()
    meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
    triangles = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
    assert len(meshes) <= 10 and triangles < 1800
    assert all(not p.use_smooth for o in meshes for p in o.data.polygons)
    out = ROOT/'assets/models/parts/shared_generator.glb'
    out.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.export_scene.gltf(filepath=str(out), export_format='GLB', use_selection=True,
                             export_animations=False)
    print('SHARED_GENERATOR meshes=%d triangles=%d exported=%s' % (len(meshes),triangles,out))
    render_preview('shared_generator', target_z=.23, ortho_scale=1.15,
                   camera=(3,-5,2.7), plinth_radius=.60, resolution=768)


if __name__ == '__main__':
    main()
