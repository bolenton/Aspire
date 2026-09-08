"""Small Blender mesh helpers. Public coordinates are Unity's x / height / forward."""
import math
import random
import bpy
import bmesh
from mathutils import Vector


def point(p):
    return Vector((-p[0], -p[2], p[1]))


def material(name, color, roughness=.65, metallic=0, emission=0):
    value = bpy.data.materials.new(name)
    value.diffuse_color = (*color, 1)
    value.use_nodes = True
    shader = value.node_tree.nodes.get('Principled BSDF')
    shader.inputs['Base Color'].default_value = (*color, 1)
    shader.inputs['Roughness'].default_value = roughness
    shader.inputs['Metallic'].default_value = metallic
    if emission:
        shader.inputs['Emission Color'].default_value = (*color, 1)
        shader.inputs['Emission Strength'].default_value = emission
    return value


def finish(obj, name, mat=None, parent=None, smooth=True):
    obj.name = name
    if mat:
        obj.data.materials.append(mat)
    if parent:
        obj.parent = parent
    if obj.type == 'MESH' and smooth:
        for face in obj.data.polygons:
            face.use_smooth = True
    return obj


def empty(name, pos=(0, 0, 0), parent=None):
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.location = point(pos)
    obj.parent = parent
    return obj


def ellipsoid(name, pos, size, mat, parent=None, segments=32):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=16, location=point(pos))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    return finish(obj, name, mat, parent)


def box(name, pos, size, mat, bevel=.06, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=point(pos))
    obj = bpy.context.object
    obj.scale = (size[0], size[2], size[1])
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    if bevel:
        mod = obj.modifiers.new('Soft crafted edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.modifiers.new('Weighted corner normals', 'WEIGHTED_NORMAL')
    return finish(obj, name, mat, parent)


def mesh(name, vertices, faces, mat, parent=None, smooth=True):
    data = bpy.data.meshes.new(name)
    data.from_pydata([point(v) for v in vertices], [], [tuple(reversed(f)) for f in faces])
    data.update()
    bm = bmesh.new()
    bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(data)
    bm.free()
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat, parent, smooth)


def tube(name, points, radii, mat, parent=None, sides=12):
    """A smoothly tapered, bent surface; not a chain of cylinders."""
    pts = [Vector(p) for p in points]
    # Support loops retain contact with the ground and adjoining limbs after subdivision.
    pts = [pts[0],pts[0].lerp(pts[1],.03),*pts[1:-1],pts[-2].lerp(pts[-1],.97),pts[-1]]
    radii = [radii[0],radii[0],*radii[1:-1],radii[-1],radii[-1]]
    vertices, faces = [], []
    for i, p in enumerate(pts):
        tangent = (pts[min(i+1, len(pts)-1)] - pts[max(0, i-1)]).normalized()
        normal = tangent.cross(Vector((0, 0, 1)))
        if normal.length < .01:
            normal = tangent.cross(Vector((1, 0, 0)))
        normal.normalize()
        other = tangent.cross(normal).normalized()
        for j in range(sides):
            a = j * math.tau / sides
            vertices.append(p + radii[i] * (normal * math.cos(a) + other * math.sin(a)))
        if i:
            for j in range(sides):
                a, b = (i-1)*sides+j, (i-1)*sides+(j+1)%sides
                faces.append((a, b, b+sides, a+sides))
    faces += [tuple(reversed(range(sides))), tuple((len(pts)-1)*sides+j for j in range(sides))]
    obj = mesh(name, vertices, faces, mat, parent)
    subdivision = obj.modifiers.new('Sculpted continuous surface', 'SUBSURF')
    subdivision.levels = subdivision.render_levels = 2
    return obj


def lathe(name, rings, mat, parent=None, sides=40):
    """Horizontal elliptical profile rings: height, width, depth, forward offset."""
    verts, faces = [], []
    for i, (height, width, depth, forward) in enumerate(rings):
        for j in range(sides):
            angle = j * math.tau / sides
            verts.append((math.sin(angle)*width, height, forward+math.cos(angle)*depth))
            if i:
                a = (i-1)*sides+j
                b = (i-1)*sides+(j+1)%sides
                faces.append((a, b, b+sides, a+sides))
    faces += [tuple(reversed(range(sides))), tuple((len(rings)-1)*sides+j for j in range(sides))]
    obj = mesh(name, verts, faces, mat, parent)
    subdivision = obj.modifiers.new('Soft profile', 'SUBSURF')
    subdivision.levels = subdivision.render_levels = 2
    return obj


def curve(name, points, width, mat, parent=None):
    data = bpy.data.curves.new(name, 'CURVE')
    data.dimensions = '3D'
    data.bevel_depth = width
    data.bevel_resolution = 3
    data.use_fill_caps = True
    data.resolution_u = 12
    spline = data.splines.new('BEZIER')
    spline.bezier_points.add(len(points)-1)
    for knot, p in zip(spline.bezier_points, points):
        knot.co = point(p)
        knot.handle_left_type = knot.handle_right_type = 'AUTO'
    obj = bpy.data.objects.new(name, data)
    bpy.context.collection.objects.link(obj)
    return finish(obj, name, mat, parent)


def leaf_cloud(name, center, size, count, mats, seed):
    rng = random.Random(seed)
    batches = [([], []) for _ in mats]
    for _ in range(count):
        offset = Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1)))
        while offset.length > 1:
            offset = Vector((rng.uniform(-1,1),rng.uniform(-1,1),rng.uniform(-1,1)))
        p = Vector((offset.x*size[0]*.62,offset.y*size[1]*.58,offset.z*size[2]*.62)) + Vector(center)
        a = rng.uniform(0, math.tau)
        length = rng.uniform(.20, .44)
        axis = Vector((math.cos(a), rng.uniform(-.35, .65), math.sin(a))) * length
        side = Vector((-math.sin(a), rng.uniform(-.25, .25), math.cos(a))) * length*.44
        verts, faces = batches[rng.randrange(len(mats))]
        k = len(verts)
        verts.append(p+Vector((0,.06,0)))
        for j in range(10):
            theta = math.tau*j/10
            verts.append(p+axis*math.cos(theta)+side*math.sin(theta))
        faces.extend((k,k+j+1,k+(j+1)%10+1) for j in range(10))
    return [mesh(name+str(i), v, f, mat, smooth=False) for i, ((v,f), mat) in enumerate(zip(batches,mats))]


def join_static():
    """Batch environment geometry by material without changing character pivots."""
    for obj in list(bpy.context.scene.objects):
        if obj.type == 'CURVE':
            bpy.ops.object.select_all(action='DESELECT')
            obj.select_set(True)
            bpy.context.view_layer.objects.active = obj
            bpy.ops.object.convert(target='MESH')
    # Resolve each object's modifiers before batching. Otherwise the first object's
    # subdivision modifier can accidentally subdivide an entire material batch.
    depsgraph = bpy.context.evaluated_depsgraph_get()
    for obj in list(bpy.context.scene.objects):
        if obj.type == 'MESH' and obj.modifiers:
            evaluated = obj.evaluated_get(depsgraph)
            obj.data = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
            obj.modifiers.clear()
    groups = {}
    for obj in bpy.context.scene.objects:
        if obj.type == 'MESH':
            groups.setdefault(obj.data.materials[0].name, []).append(obj)
    for name, objects in groups.items():
        bpy.ops.object.select_all(action='DESELECT')
        for obj in objects:
            obj.select_set(True)
        bpy.context.view_layer.objects.active = objects[0]
        bpy.ops.object.join()
        objects[0].name = name


def reset():
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)


def export(path):
    # Explicit tangents and normals avoid relying on the runtime to repair surfaces.
    bpy.ops.export_scene.gltf(filepath=str(path), export_format='GLB', export_apply=True,
                             export_yup=True, export_animations=False, export_cameras=False,
                             export_lights=False, export_materials='EXPORT')
