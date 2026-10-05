#!/usr/bin/env python3
"""Generates Godot .import files (and the import cache) for new PNG files.

    python tools/character_builder/import_images.py --godot /path/to/godot --project . \
        plugins/characters/Bolt/icon.png plugins/characters/Bolt/splash.png

Headless `godot --import` skips new files in a big project, so the images are imported
in a throw-away project with the same folder layout and the results are copied back.
"""
import argparse
import glob
import os
import shutil
import subprocess
import tempfile

ap = argparse.ArgumentParser()
ap.add_argument("--godot", required=True)
ap.add_argument("--project", default=".")
ap.add_argument("images", nargs="+", help="paths relative to the project")
args = ap.parse_args()
project = os.path.abspath(args.project)

work = tempfile.mkdtemp(prefix="images_")
with open(os.path.join(work, "project.godot"), "w") as f:
    f.write('[application]\nconfig/name="mirror"\nconfig/features=PackedStringArray("4.7")\n')
for rel in args.images:
    dest = os.path.join(work, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    shutil.copy(os.path.join(project, rel), dest)
subprocess.run([args.godot, "--headless", "--import", "--path", work], check=False,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
cache = os.path.join(project, ".godot", "imported")
for rel in args.images:
    shutil.copy(os.path.join(work, rel + ".import"), os.path.join(project, rel + ".import"))
if os.path.isdir(cache):
    for f in glob.glob(os.path.join(work, ".godot", "imported", "*")):
        shutil.copy(f, cache)
shutil.rmtree(work, ignore_errors=True)
print("imported", len(args.images), "images")
