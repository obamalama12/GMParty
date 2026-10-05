"""Replaces the figure on top of the board cake with a gold star and cherries.

    python cake_topper.py <path to cake.blend> <output cake.glb>

The star reuses the existing "crown" material (gold), so the external material the
import settings point to keeps working. The "cherry" material is embedded in the glb.
Node names of the other parts (Cake, Icing, Circle) are unchanged, so the float and
collect animations in cake.tscn still apply.
"""
import math
import sys

import bpy  # must come before bmesh and mathutils
import bmesh

blend_path, out_path = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:3]
bpy.ops.wm.open_mainfile(filepath=blend_path)

for name in ("tux", "Crown"):
    obj = bpy.data.objects.get(name)
    if obj:
        bpy.data.objects.remove(obj, do_unlink=True)
for mat in list(bpy.data.materials):
    if mat.name.startswith("tux"):
        bpy.data.materials.remove(mat)

gold = bpy.data.materials["crown"]
cherry = bpy.data.materials.new("cherry")
cherry.use_nodes = True
cherry.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.82, 0.05, 0.1, 1)
cherry.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.4

TOP = 0.315   # the top of the cake, in blender units (z up)


def make_object(name, bm, material, location=(0, 0, 0), smooth=True):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    mesh.materials.append(material)
    for poly in mesh.polygons:
        poly.use_smooth = smooth
    obj = bpy.data.objects.new(name, mesh)
    obj.location = location
    bpy.context.collection.objects.link(obj)
    return obj


# the star, standing upright and facing the front (-Y in blender)
bm = bmesh.new()
points = []
for i in range(10):
    radius = 0.2 if i % 2 == 0 else 0.088
    angle = math.pi / 2 + i * math.pi / 5
    points.append(bm.verts.new((radius * math.cos(angle), 0, radius * math.sin(angle))))
face = bm.faces.new(points)
bmesh.ops.solidify(bm, geom=[face], thickness=0.07)
bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0.035, 0))
star = make_object("Star", bm, gold, (0, 0, TOP + 0.3), smooth=False)
bevel = star.modifiers.new("Bevel", "BEVEL")
bevel.width = 0.012
bevel.segments = 2

bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=20, radius1=0.12, radius2=0.1, depth=0.035)
make_object("StarBase", bm, gold, (0, 0, TOP + 0.0175))

bm = bmesh.new()
bmesh.ops.create_cone(bm, cap_ends=True, segments=12, radius1=0.022, radius2=0.022, depth=0.14)
make_object("StarStem", bm, gold, (0, 0, TOP + 0.1))

for i, angle in enumerate((90, 210, 330)):
    a = math.radians(angle)
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=0.058)
    make_object("Cherry%d" % (i + 1), bm, cherry, (0.33 * math.cos(a), 0.33 * math.sin(a), TOP + 0.05))

bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out_path, export_format="GLB", export_apply=True,
                          export_yup=True, export_materials="EXPORT", export_image_format="AUTO")
print("EXPORTED", out_path)
