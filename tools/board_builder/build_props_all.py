#!/usr/bin/env python3
"""Builds the Retro Valley landmark props: Blender -> glb -> Godot import -> plugins/boards/RetroValley/props.

    python tools/board_builder/build_props_all.py --bpy-python <python with bpy+pillow> --godot <godot> --project .

The glb files are imported in a throw-away project with the same folder layout (see
tools/character_builder/build_all.py for why). The "Props" material of every glb is
mapped to props/Props.tres, a toon material with an outline pass.
"""
import argparse
import glob
import os
import shutil
import subprocess
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
BOARD = os.path.join("plugins", "boards", "RetroValley", "props")

MATERIAL = '''[gd_resource type="StandardMaterial3D" load_steps=3 format=3]

[ext_resource type="Texture2D" path="res://plugins/boards/RetroValley/props/palette.png" id="1"]

[sub_resource type="StandardMaterial3D" id="1"]
cull_mode = 1
shading_mode = 0
albedo_color = Color(0, 0, 0, 1)
grow = true
grow_amount = 0.05

[resource]
next_pass = SubResource("1")
diffuse_mode = 3
specular_mode = 1
albedo_texture = ExtResource("1")
roughness = 0.8
texture_filter = 0
'''


def run(cmd):
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=False)


ap = argparse.ArgumentParser()
ap.add_argument("--bpy-python", required=True)
ap.add_argument("--godot", required=True)
ap.add_argument("--project", default=".")
args = ap.parse_args()
project = os.path.abspath(args.project)
dest = os.path.join(project, BOARD)
os.makedirs(dest, exist_ok=True)

work = tempfile.mkdtemp(prefix="props_")
built = os.path.join(work, "built")
run([args.bpy_python, os.path.join(HERE, "blender", "build_props.py"), built])

mirror = os.path.join(work, "mirror")
mdir = os.path.join(mirror, BOARD)
os.makedirs(mdir)
with open(os.path.join(mirror, "project.godot"), "w") as f:
    f.write('[application]\nconfig/name="mirror"\nconfig/features=PackedStringArray("4.7")\n')
for f in glob.glob(os.path.join(built, "*")):
    shutil.copy(f, mdir)
run([args.godot, "--headless", "--import", "--path", mirror])
for imp in glob.glob(os.path.join(mdir, "*.glb.import")):
    text = open(imp).read()
    assert "_subresources={}" in text, imp
    sub = ('_subresources={"materials": {"Props": {"use_external/enabled": true, '
           '"use_external/path": "res://%s/Props.tres"}}}' % BOARD.replace(os.sep, "/"))
    open(imp, "w").write(text.replace("_subresources={}", sub))
with open(os.path.join(mdir, "Props.tres"), "w") as f:
    f.write(MATERIAL)
run([args.godot, "--headless", "--import", "--path", mirror])

for f in glob.glob(os.path.join(mdir, "*")):
    if f.endswith((".glb", ".glb.import", ".png", ".png.import", ".tres")):
        shutil.copy(f, dest)
cache = os.path.join(project, ".godot", "imported")
if os.path.isdir(cache):
    for f in glob.glob(os.path.join(mirror, ".godot", "imported", "*")):
        shutil.copy(f, cache)
shutil.rmtree(work, ignore_errors=True)
print("done")
