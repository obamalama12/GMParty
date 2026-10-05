"""Builds the Bolt, Kit and Mushi characters in Blender (bpy) and exports them as
rigged .glb files with a palette texture, in the style of the existing characters
(chibi proportions, flat colour atlas, toon shading in Godot).

    pip install bpy numpy pillow
    python build_characters.py <output dir>          # e.g. plugins/characters

Writes <out>/<Name>/<name>.glb and <out>/<Name>/palette.png.

Conventions: Blender is Z up and the character faces -Y (glTF turns that into
Godot's +Z). Positions below are written as (x, up, front) and converted by v().
Animations are written as Godot-style euler degrees (x, y, z) and converted by
g2b(): Godot x -> Blender x, Godot y (turn) -> Blender z, Godot z (roll) -> -Blender y.
"""
import math
import os
import sys

import bpy  # must come before bmesh and mathutils
import bmesh
import mathutils
from PIL import Image

OUT = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else sys.argv[1]
FPS = 24

# ---------------------------------------------------------------- palette

PALETTE_COLORS = {}


def swatch(name, rgb):
    PALETTE_COLORS[name] = rgb
    return name


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def write_palette(path, names):
    img = Image.new("RGBA", (256, 256), (255, 255, 255, 255))
    for i, name in enumerate(names):
        col, row = i % 8, i // 8
        c = PALETTE_COLORS[name]
        for x in range(col * 32, col * 32 + 32):
            for y in range(row * 32, row * 32 + 32):
                img.putpixel((x, y), c + (255,))
    img.save(path)


# ---------------------------------------------------------------- mesh helpers

class Builder:
    def __init__(self, name, scale, palette):
        self.name = name
        self.k = scale
        self.palette = list(palette)
        self.bones = []          # (bone name, parent name, head position)
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.verify()
        self.dvert = self.bm.verts.layers.deform.verify()

    def v(self, x, up, front):
        return mathutils.Vector((x * self.k, -front * self.k, up * self.k))

    def bone(self, name, parent, x, up, front):
        self.bones.append((name, parent, self.v(x, up, front)))

    def _add(self, part_bm, color, bone, smooth):
        mesh = bpy.data.meshes.new("part")
        part_bm.to_mesh(mesh)
        part_bm.free()
        first_v = len(self.bm.verts)
        first_f = len(self.bm.faces)
        self.bm.from_mesh(mesh)
        bpy.data.meshes.remove(mesh)
        self.bm.verts.ensure_lookup_table()
        self.bm.faces.ensure_lookup_table()
        idx = self.palette.index(color)
        u = (idx % 8 + 0.5) / 8.0
        w = 1.0 - (idx // 8 + 0.5) / 8.0
        group = [b[0] for b in self.bones].index(bone)
        for vert in self.bm.verts[first_v:]:
            vert[self.dvert][group] = 1.0
        for face in self.bm.faces[first_f:]:
            face.smooth = smooth
            for loop in face.loops:
                loop[self.uv].uv = (u, w)

    def blob(self, color, bone, pos, size, rot=(0, 0, 0), smooth=True):
        """An ellipsoid. pos=(x, up, front); size = radii (x, up, front)."""
        bm = bmesh.new()
        bmesh.ops.create_uvsphere(bm, u_segments=20, v_segments=12, radius=1.0)
        self._finish(bm, color, bone, pos, size, rot, smooth)

    def block(self, color, bone, pos, size, rot=(0, 0, 0), bevel=0.0, smooth=False):
        """A box. size = half extents (x, up, front). bevel rounds the edges."""
        bm = bmesh.new()
        bmesh.ops.create_cube(bm, size=2.0)
        self._finish(bm, color, bone, pos, size, rot, smooth, bevel)

    def cone(self, color, bone, pos, radius, depth, rot=(0, 0, 0), top=0.0, smooth=True):
        """A cone/cylinder along the up axis; rot is (pitch, yaw, roll) degrees."""
        bm = bmesh.new()
        bmesh.ops.create_cone(bm, cap_ends=True, cap_tris=False, segments=14,
                              radius1=radius, radius2=top, depth=depth)
        self._finish(bm, color, bone, pos, (1, 1, 1), rot, smooth)

    def _finish(self, bm, color, bone, pos, size, rot, smooth, bevel=0.0):
        sx, sy, sz = size
        # to blender axes: x, y(depth) = -front, z = up
        scale = mathutils.Matrix.Diagonal((sx * self.k, sz * self.k, sy * self.k, 1.0))
        # rot: pitch about x, yaw about up (blender z), roll about front (blender -y)
        rx, ry, rz = (math.radians(a) for a in rot)
        rotation = mathutils.Euler((rx, -rz, ry), "XYZ").to_matrix().to_4x4()
        bmesh.ops.transform(bm, matrix=scale, verts=bm.verts)
        if bevel > 0:
            bmesh.ops.bevel(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces),
                            offset=bevel * self.k, segments=3, affect="EDGES", profile=0.6)
        bmesh.ops.transform(bm, matrix=rotation, verts=bm.verts)
        bmesh.ops.transform(bm, matrix=mathutils.Matrix.Translation(self.v(*pos)), verts=bm.verts)
        self._add(bm, color, bone, smooth)

    # ---- build the object, armature and animations

    def finish(self, anims, folder):
        mesh = bpy.data.meshes.new(self.name + "Mesh")
        self.bm.to_mesh(mesh)
        self.bm.free()
        body = bpy.data.objects.new("Body", mesh)
        bpy.context.collection.objects.link(body)
        for bone in self.bones:
            body.vertex_groups.new(name=bone[0])

        arm_data = bpy.data.armatures.new("Armature")
        arm = bpy.data.objects.new("Armature", arm_data)
        bpy.context.collection.objects.link(arm)
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="EDIT")
        edit = {}
        for name, parent, head in self.bones:
            eb = arm_data.edit_bones.new(name)
            eb.head = head
            eb.tail = head + mathutils.Vector((0, 0.08 * self.k, 0))  # every bone has identity rest orientation
            eb.roll = 0.0
            if parent:
                eb.parent = edit[parent]
            edit[name] = eb
        bpy.ops.object.mode_set(mode="OBJECT")

        body.parent = arm
        mod = body.modifiers.new("Armature", "ARMATURE")
        mod.object = arm

        # material using the palette
        mat = bpy.data.materials.new(self.name)
        mat.use_nodes = True
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.image = bpy.data.images.load(os.path.join(folder, "palette.png"))
        tex.interpolation = "Closest"
        bsdf = mat.node_tree.nodes["Principled BSDF"]
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        bsdf.inputs["Roughness"].default_value = 0.75
        mesh.materials.append(mat)

        self.animate(arm, anims)
        return arm, body

    def animate(self, arm, anims):
        arm.animation_data_create()
        bpy.context.view_layer.objects.active = arm
        bpy.ops.object.mode_set(mode="POSE")
        for pb in arm.pose.bones:
            pb.rotation_mode = "XYZ"
        for name, spec in anims.items():
            action = bpy.data.actions.new(name)
            action.use_fake_user = True
            arm.animation_data.action = action
            for pb in arm.pose.bones:
                pb.rotation_euler = (0, 0, 0)
                pb.location = (0, 0, 0)
            tracks = spec["tracks"]
            for bone_name, keys in tracks.items():
                pb = arm.pose.bones.get(bone_name)
                if pb is None:
                    continue
                for t, value in keys:
                    frame = 1 + round(t * FPS)
                    if bone_name.endswith("@loc"):
                        continue
                    rot = g2b(value)
                    pb.rotation_euler = rot
                    pb.keyframe_insert("rotation_euler", frame=frame)
            for t, dy in spec.get("hips_y", []):
                pb = arm.pose.bones["Hips"]
                pb.location = (0, 0, dy * self.k)
                pb.keyframe_insert("location", frame=1 + round(t * FPS))
            # make loops seamless and give the action its frame range
            action.use_frame_range = True
            action.frame_start = 1
            action.frame_end = 1 + round(spec["length"] * FPS)
        bpy.ops.object.mode_set(mode="OBJECT")
        # one NLA track per action, so every animation is exported by name
        for name in anims:
            track = arm.animation_data.nla_tracks.new()
            track.name = name
            strip = track.strips.new(name, 1, bpy.data.actions[name])
            strip.name = name
        arm.animation_data.action = None


def g2b(rot):
    """Godot-style euler degrees (x, y, z) to blender radians (x, y, z)."""
    x, y, z = rot
    return (math.radians(x), math.radians(-z), math.radians(y))


# ---------------------------------------------------------------- animations

def anim_set(tail=False):
    A = {}

    def loop(name, length, tracks, hips_y):
        A[name] = {"length": length, "tracks": tracks, "hips_y": hips_y}

    r = lambda x, y=0.0, z=0.0: (x, y, z)
    loop("idle", 2.0, {
        "Head": [(0, r(0)), (1, r(-3, 0, 2)), (2, r(0))],
        "ArmL": [(0, r(0, 0, 5)), (1, r(0, 0, 8)), (2, r(0, 0, 5))],
        "ArmR": [(0, r(0, 0, -5)), (1, r(0, 0, -8)), (2, r(0, 0, -5))],
    }, [(0, 0), (1, 0.02), (2, 0)])
    loop("walk", 0.8, {
        "Hips": [(0, r(3, 4)), (0.4, r(3, -4)), (0.8, r(3, 4))],
        "LegL": [(0, r(-25)), (0.4, r(25)), (0.8, r(-25))],
        "LegR": [(0, r(25)), (0.4, r(-25)), (0.8, r(25))],
        "ArmL": [(0, r(20, 0, 5)), (0.4, r(-20, 0, 5)), (0.8, r(20, 0, 5))],
        "ArmR": [(0, r(-20, 0, -5)), (0.4, r(20, 0, -5)), (0.8, r(-20, 0, -5))],
    }, [(0, 0), (0.2, 0.03), (0.4, 0), (0.6, 0.03), (0.8, 0)])
    run = {
        "Hips": [(0, r(12, 6)), (0.25, r(12, -6)), (0.5, r(12, 6))],
        "LegL": [(0, r(-50)), (0.25, r(50)), (0.5, r(-50))],
        "LegR": [(0, r(50)), (0.25, r(-50)), (0.5, r(50))],
        "ArmL": [(0, r(55, 0, 8)), (0.25, r(-55, 0, 8)), (0.5, r(55, 0, 8))],
        "ArmR": [(0, r(-55, 0, -8)), (0.25, r(55, 0, -8)), (0.5, r(-55, 0, -8))],
    }
    run_hips = [(0, 0), (0.125, 0.06), (0.25, 0), (0.375, 0.06), (0.5, 0)]
    loop("run", 0.5, run, run_hips)
    A["jump"] = {"length": 0.8, "hips_y": [(0, 0), (0.15, -0.1), (0.4, 0.05), (0.8, 0)], "tracks": {
        "ArmL": [(0, r(0, 0, 5)), (0.15, r(25, 0, 8)), (0.4, r(-150, 0, 20)), (0.8, r(-100, 0, 15))],
        "ArmR": [(0, r(0, 0, -5)), (0.15, r(25, 0, -8)), (0.4, r(-150, 0, -20)), (0.8, r(-100, 0, -15))],
        "LegL": [(0, r(0)), (0.15, r(-20)), (0.4, r(-35)), (0.8, r(-10))],
        "LegR": [(0, r(0)), (0.15, r(-20)), (0.4, r(15)), (0.8, r(-10))],
    }}
    loop("happy", 1.0, {
        "Head": [(0, r(0, 0, 6)), (0.5, r(0, 0, -6)), (1, r(0, 0, 6))],
        "ArmL": [(0, r(-160, 0, 10)), (0.5, r(-160, 0, 35)), (1, r(-160, 0, 10))],
        "ArmR": [(0, r(-160, 0, -35)), (0.5, r(-160, 0, -10)), (1, r(-160, 0, -35))],
        "LegL": [(0, r(0)), (0.25, r(-15)), (0.5, r(0)), (0.75, r(-15)), (1, r(0))],
        "LegR": [(0, r(0)), (0.25, r(10)), (0.5, r(0)), (0.75, r(10)), (1, r(0))],
    }, [(0, 0), (0.25, 0.16), (0.5, 0), (0.75, 0.16), (1, 0)])
    loop("sad", 2.0, {
        "Hips": [(0, r(0, 0, -2)), (1, r(0, 0, 2)), (2, r(0, 0, -2))],
        "Head": [(0, r(35)), (1, r(40)), (2, r(35))],
        "ArmL": [(0, r(8, 0, -3)), (1, r(12, 0, -3)), (2, r(8, 0, -3))],
        "ArmR": [(0, r(8, 0, 3)), (1, r(12, 0, 3)), (2, r(8, 0, 3))],
    }, [(0, -0.06), (1, -0.07), (2, -0.06)])
    loop("stun", 1.0, {
        "Hips": [(0, r(0, 0, -12)), (0.5, r(0, 0, 12)), (1, r(0, 0, -12))],
        "Head": [(0, r(10, -35, 0)), (0.5, r(10, 35, 0)), (1, r(10, -35, 0))],
        "ArmL": [(0, r(20, 0, 25)), (0.5, r(-10, 0, 35)), (1, r(20, 0, 25))],
        "ArmR": [(0, r(-10, 0, -35)), (0.5, r(20, 0, -25)), (1, r(-10, 0, -35))],
    }, [(0, -0.05), (1, -0.05)])
    A["punch"] = {"length": 0.5, "hips_y": [], "tracks": {
        "Hips": [(0, r(0)), (0.1, r(0, 18)), (0.2, r(0, -22)), (0.5, r(0))],
        "ArmR": [(0, r(0, 0, -5)), (0.1, r(35, 0, -5)), (0.2, r(-95, 0, -3)), (0.5, r(0, 0, -5))],
        "ArmL": [(0, r(0, 0, 5)), (0.2, r(25, 0, 10)), (0.5, r(0, 0, 5))],
    }}
    A["kick"] = {"length": 0.6, "hips_y": [], "tracks": {
        "Hips": [(0, r(0)), (0.35, r(-8)), (0.6, r(0))],
        "LegR": [(0, r(0)), (0.2, r(30)), (0.35, r(-85)), (0.6, r(0))],
        "ArmL": [(0, r(0, 0, 5)), (0.3, r(0, 0, 45)), (0.6, r(0, 0, 5))],
        "ArmR": [(0, r(0, 0, -5)), (0.3, r(0, 0, -45)), (0.6, r(0, 0, -5))],
    }}
    loop("carry", 1.0, {
        "ArmL": [(0, r(-70, 0, -10)), (1, r(-70, 0, -10))],
        "ArmR": [(0, r(-70, 0, 10)), (1, r(-70, 0, 10))],
    }, [(0, 0), (0.5, 0.015), (1, 0)])
    rc = {k: v for k, v in run.items()}
    rc["ArmL"] = [(0, r(-70, 0, -10)), (0.25, r(-76, 0, -10)), (0.5, r(-70, 0, -10))]
    rc["ArmR"] = [(0, r(-70, 0, 10)), (0.25, r(-76, 0, 10)), (0.5, r(-70, 0, 10))]
    loop("run-carry", 0.5, rc, run_hips)
    loop("sit", 1.0, {
        "LegL": [(0, r(-90, 0, 6)), (1, r(-90, 0, 6))],
        "LegR": [(0, r(-90, 0, -6)), (1, r(-90, 0, -6))],
        "ArmL": [(0, r(-20, 0, 8)), (1, r(-20, 0, 8))],
        "ArmR": [(0, r(-20, 0, -8)), (1, r(-20, 0, -8))],
    }, [(0, -0.22), (1, -0.22)])
    if tail:
        A["idle"]["tracks"]["Tail"] = [(0, r(0, -12)), (1, r(0, 12)), (2, r(0, -12))]
        A["walk"]["tracks"]["Tail"] = [(0, r(0, -15)), (0.4, r(0, 15)), (0.8, r(0, -15))]
        A["run"]["tracks"]["Tail"] = [(0, r(35, -8)), (0.25, r(35, 8)), (0.5, r(35, -8))]
        A["run-carry"]["tracks"]["Tail"] = A["run"]["tracks"]["Tail"]
        A["happy"]["tracks"]["Tail"] = [(0, r(0, -35)), (0.25, r(0, 35)), (0.5, r(0, -35)),
                                        (0.75, r(0, 35)), (1, r(0, -35))]
        A["sad"]["tracks"]["Tail"] = [(0, r(-25)), (2, r(-25))]
        A["jump"]["tracks"]["Tail"] = [(0, r(0)), (0.4, r(25)), (0.8, r(10))]
    return A


# ---------------------------------------------------------------- characters

def standard_bones(b, hips_up, shoulder_x, shoulder_up, leg_x, head_up, tail=None):
    b.bone("Hips", None, 0, hips_up, 0)
    b.bone("Head", "Hips", 0, head_up, 0)
    b.bone("ArmL", "Hips", shoulder_x, shoulder_up, 0)
    b.bone("ArmR", "Hips", -shoulder_x, shoulder_up, 0)
    b.bone("LegL", "Hips", leg_x, hips_up, 0)
    b.bone("LegR", "Hips", -leg_x, hips_up, 0)
    if tail:
        b.bone("Tail", "Hips", *tail)


def build_bolt(folder):
    steel = swatch("steel", hexc("#9db7e0"))
    shade = swatch("steel_dark", hexc("#5d6f94"))
    navy = swatch("navy", hexc("#27304a"))
    orange = swatch("orange", hexc("#ff8a1f"))
    white = swatch("white", hexc("#f4f4f4"))
    black = swatch("black", hexc("#141414"))
    red = swatch("red", hexc("#e8312f"))
    cyan = swatch("cyan", hexc("#5fe3f0"))
    pal = [steel, shade, navy, orange, white, black, red, cyan]
    b = Builder("Bolt", 0.62, pal)
    standard_bones(b, 0.36, 0.27, 0.6, 0.14, 0.67)

    for s, sign in (("L", 1), ("R", -1)):
        b.blob(shade, "Leg" + s, (sign * 0.14, 0.2, 0), (0.07, 0.17, 0.075))
        b.block(orange, "Leg" + s, (sign * 0.14, 0.05, 0.04), (0.09, 0.05, 0.14), bevel=0.04, smooth=True)
        b.blob(shade, "Arm" + s, (sign * 0.29, 0.45, 0), (0.05, 0.15, 0.05))
        b.blob(steel, "Arm" + s, (sign * 0.27, 0.6, 0), (0.08, 0.08, 0.08))
        b.blob(orange, "Arm" + s, (sign * 0.29, 0.29, 0), (0.075, 0.075, 0.075))
    b.block(steel, "Hips", (0, 0.5, 0), (0.22, 0.17, 0.17), bevel=0.06, smooth=True)
    b.block(orange, "Hips", (0, 0.5, 0.165), (0.12, 0.08, 0.015), bevel=0.01)
    b.blob(cyan, "Hips", (0, 0.5, 0.185), (0.03, 0.03, 0.015))
    b.cone(shade, "Hips", (0, 0.35, 0), 0.19, 0.06)

    b.block(steel, "Head", (0, 0.97, 0), (0.31, 0.26, 0.25), bevel=0.09, smooth=True)
    b.block(navy, "Head", (0, 0.96, 0.23), (0.25, 0.16, 0.03), bevel=0.02)
    for sign in (1, -1):
        b.blob(white, "Head", (sign * 0.12, 0.99, 0.265), (0.095, 0.105, 0.035))
        b.blob(black, "Head", (sign * 0.12, 0.97, 0.292), (0.05, 0.055, 0.025))
        b.cone(orange, "Head", (sign * 0.33, 0.97, 0), 0.075, 0.11, rot=(0, 0, 90))
    b.block(white, "Head", (0, 0.85, 0.262), (0.09, 0.016, 0.012))
    b.cone(shade, "Head", (0.12, 1.32, 0), 0.02, 0.15)
    b.blob(red, "Head", (0.12, 1.42, 0), (0.06, 0.06, 0.06))
    return b, anim_set(), "Bolt"


def build_kit(folder):
    orange = swatch("fox", hexc("#f28a24"))
    cream = swatch("cream", hexc("#fff0d6"))
    brown = swatch("brown", hexc("#5a3320"))
    black = swatch("black", hexc("#141414"))
    white = swatch("white", hexc("#f6f6f6"))
    pink = swatch("pink", hexc("#ff9aa8"))
    dark = swatch("fox_dark", hexc("#c4651a"))
    pal = [orange, cream, brown, black, white, pink, dark]
    b = Builder("Kit", 0.66, pal)
    standard_bones(b, 0.34, 0.27, 0.58, 0.12, 0.62, tail=(0, 0.38, -0.2))

    for s, sign in (("L", 1), ("R", -1)):
        b.blob(brown, "Leg" + s, (sign * 0.12, 0.18, 0), (0.065, 0.16, 0.07))
        b.blob(brown, "Leg" + s, (sign * 0.12, 0.05, 0.035), (0.085, 0.05, 0.12))
        b.blob(orange, "Arm" + s, (sign * 0.28, 0.46, 0), (0.05, 0.13, 0.05))
        b.blob(brown, "Arm" + s, (sign * 0.28, 0.34, 0), (0.06, 0.06, 0.06))
    b.blob(orange, "Hips", (0, 0.46, 0), (0.24, 0.22, 0.2))
    b.blob(cream, "Hips", (0, 0.44, 0.13), (0.16, 0.17, 0.08))

    b.blob(orange, "Head", (0, 0.92, 0), (0.34, 0.29, 0.3))
    for sign in (1, -1):
        b.blob(cream, "Head", (sign * 0.25, 0.82, 0.16), (0.14, 0.11, 0.1))
        b.blob(white, "Head", (sign * 0.13, 0.96, 0.265), (0.09, 0.105, 0.035))
        b.blob(black, "Head", (sign * 0.13, 0.945, 0.292), (0.05, 0.058, 0.025))
        b.cone(orange, "Head", (sign * 0.21, 1.25, -0.02), 0.14, 0.32, rot=(0, 0, -sign * 14))
        b.cone(pink, "Head", (sign * 0.21, 1.22, 0.03), 0.085, 0.22, rot=(0, 0, -sign * 14))
        b.cone(brown, "Head", (sign * 0.235, 1.37, -0.02), 0.045, 0.08, rot=(0, 0, -sign * 14))
    b.blob(cream, "Head", (0, 0.83, 0.28), (0.15, 0.1, 0.12))
    b.blob(black, "Head", (0, 0.865, 0.385), (0.045, 0.035, 0.035))
    b.block(black, "Head", (0, 0.79, 0.385), (0.025, 0.006, 0.006))

    b.blob(orange, "Tail", (0, 0.56, -0.34), (0.12, 0.3, 0.12), rot=(-50, 0, 0))
    b.blob(cream, "Tail", (0, 0.76, -0.54), (0.115, 0.115, 0.115))
    return b, anim_set(tail=True), "Kit"


def build_mushi(folder):
    red = swatch("cap", hexc("#e23a3e"))
    cream = swatch("cream", hexc("#fbe9c4"))
    spot = swatch("spot", hexc("#fff8ee"))
    brown = swatch("brown", hexc("#6e4326"))
    black = swatch("black", hexc("#141414"))
    white = swatch("white", hexc("#f6f6f6"))
    blush = swatch("blush", hexc("#ff8d8d"))
    shade = swatch("cap_dark", hexc("#a82428"))
    pal = [red, cream, spot, brown, black, white, blush, shade]
    b = Builder("Mushi", 0.78, pal)
    standard_bones(b, 0.3, 0.25, 0.52, 0.1, 0.62)

    for s, sign in (("L", 1), ("R", -1)):
        b.blob(cream, "Leg" + s, (sign * 0.1, 0.17, 0), (0.06, 0.12, 0.06))
        b.blob(brown, "Leg" + s, (sign * 0.1, 0.05, 0.035), (0.09, 0.05, 0.125))
        b.blob(cream, "Arm" + s, (sign * 0.27, 0.41, 0), (0.045, 0.11, 0.045))
        b.blob(cream, "Arm" + s, (sign * 0.27, 0.3, 0), (0.06, 0.06, 0.06))
    b.blob(cream, "Hips", (0, 0.45, 0), (0.25, 0.25, 0.23))
    for sign in (1, -1):
        b.blob(white, "Hips", (sign * 0.1, 0.5, 0.2), (0.085, 0.1, 0.035))
        b.blob(black, "Hips", (sign * 0.1, 0.485, 0.228), (0.048, 0.056, 0.025))
        b.blob(blush, "Hips", (sign * 0.18, 0.39, 0.18), (0.055, 0.032, 0.02), rot=(0, 0, sign * 10))
    b.blob(black, "Hips", (0, 0.385, 0.222), (0.035, 0.012, 0.01))

    b.blob(red, "Head", (0, 0.92, 0), (0.46, 0.28, 0.46))
    b.blob(shade, "Head", (0, 0.69, 0), (0.42, 0.04, 0.42))
    b.blob(spot, "Head", (0, 1.19, 0.02), (0.12, 0.04, 0.12))
    for ang, elev, size in ((0, 28, 0.11), (75, 22, 0.1), (150, 30, 0.1), (230, 25, 0.12), (300, 20, 0.1)):
        a, e = math.radians(ang), math.radians(elev)
        pos = (0.46 * math.cos(e) * math.sin(a) * 0.9, 0.92 + 0.28 * math.sin(e) * 0.9,
               0.46 * math.cos(e) * math.cos(a) * 0.9)
        b.blob(spot, "Head", pos, (size, size * 0.45, size), rot=(0, 0, 0))
    return b, anim_set(), "Mushi"


# ---------------------------------------------------------------- main

def export(builder_fn):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    probe = builder_fn.__name__
    # the palette must exist on disk before the material loads it
    b, anims, char_name = builder_fn(OUT)
    folder = os.path.join(OUT, char_name)
    os.makedirs(folder, exist_ok=True)
    write_palette(os.path.join(folder, "palette.png"), b.palette)
    arm, body = b.finish(anims, folder)
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    body.select_set(True)
    path = os.path.join(folder, char_name.lower() + ".glb")
    bpy.ops.export_scene.gltf(
        filepath=path, export_format="GLB", use_selection=True, export_apply=False,
        export_yup=True, export_skins=True, export_materials="EXPORT", export_image_format="NONE",
        export_animations=True, export_animation_mode="NLA_TRACKS",
        export_optimize_animation_size=False, export_force_sampling=True)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(folder, char_name.lower() + ".blend"))
    print("EXPORTED", path, "height", max(v.co.z for v in body.data.vertices))


for fn in (build_bolt, build_kit, build_mushi):
    export(fn)
