#!/usr/bin/env python3
"""Rebuilds Bolt, Kit and Mushi from scratch: Blender -> glb -> Godot import -> scenes.

    python tools/character_builder/build_all.py --bpy-python /path/to/python-with-bpy \
        --godot /path/to/godot [--project .]

It needs a Python with `bpy` and `pillow` installed (pip install bpy pillow numpy)
and a Godot 4.7 binary. The glb files are imported in a throw-away project that has
the same folder layout, so the generated .import files and import cache are valid
for the real project too. Animation loop flags are written into the .glb.import files.
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
NAMES = {"Bolt": "bolt", "Kit": "kit", "Mushi": "mushi", "Businessman": "businessman", "Timber": "timber", "Emo": "emo"}
LOOPING = ["idle", "walk", "run", "happy", "sad", "stun", "carry", "run-carry", "sit"]


def run(cmd, **kw):
    print("+", " ".join(cmd))
    subprocess.run(cmd, check=False, **kw)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bpy-python", required=True)
    ap.add_argument("--godot", required=True)
    ap.add_argument("--project", default=".")
    ap.add_argument("--keep-blend", action="store_true", help="copy the .blend files into the character folders")
    args = ap.parse_args()
    project = os.path.abspath(args.project)
    chars_dir = os.path.join(project, "plugins", "characters")

    work = tempfile.mkdtemp(prefix="characters_")
    built = os.path.join(work, "built")
    os.makedirs(built)
    # the exporter segfaults on interpreter exit, so check the files instead of the exit code
    run([args.bpy_python, os.path.join(HERE, "blender", "build_characters.py"), built])

    mirror = os.path.join(work, "mirror")
    os.makedirs(os.path.join(mirror, "plugins", "characters"))
    with open(os.path.join(mirror, "project.godot"), "w") as f:
        f.write('[application]\nconfig/name="mirror"\nconfig/features=PackedStringArray("4.7")\n')
    for name, file in NAMES.items():
        dest = os.path.join(mirror, "plugins", "characters", name)
        os.makedirs(dest)
        for f in (file + ".glb", "palette.png"):
            shutil.copy(os.path.join(built, name, f), dest)
    run([args.godot, "--headless", "--import", "--path", mirror])

    loops = ", ".join('"%s": {"settings/loop_mode": 1}' % l for l in LOOPING)
    for imp in glob.glob(os.path.join(mirror, "plugins", "characters", "*", "*.glb.import")):
        text = open(imp).read()
        assert "_subresources={}" in text, imp
        open(imp, "w").write(text.replace("_subresources={}", '_subresources={"animations": {%s}}' % loops))
    run([args.godot, "--headless", "--import", "--path", mirror])

    for name, file in NAMES.items():
        src = os.path.join(mirror, "plugins", "characters", name)
        dest = os.path.join(chars_dir, name)
        os.makedirs(dest, exist_ok=True)
        for f in (file + ".glb", file + ".glb.import", "palette.png", "palette.png.import"):
            shutil.copy(os.path.join(src, f), dest)
        if args.keep_blend:
            shutil.copy(os.path.join(built, name, file + ".blend"), dest)

    # the import cache lets a project run the characters without opening the editor first
    cache = os.path.join(project, ".godot", "imported")
    if os.path.isdir(cache):
        for f in glob.glob(os.path.join(mirror, ".godot", "imported", "*")):
            shutil.copy(f, cache)

    run([sys.executable, os.path.join(HERE, "write_scenes.py"), chars_dir])
    shutil.rmtree(work, ignore_errors=True)
    print("done")


main()
