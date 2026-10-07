#!/usr/bin/env python3
"""Copies the Git LFS assets (textures, models, music, sounds) from a checkout of the
original Super Tux Party into this project.

    git clone https://gitlab.com/SuperTuxParty/SuperTuxParty.git upstream
    cd upstream && git lfs pull && cd ..
    python tools/get_assets.py upstream

Files that already exist here are kept, and the characters and art that were removed from
Retro Party are not copied. Works on Linux, macOS and Windows (Python 3.6 or newer).
"""
import os
import shutil
import sys

SKIP_DIRS = [
    ".git", ".godot",
    "plugins/characters/Tux", "plugins/characters/Green Tux", "plugins/characters/Beastie",
    "plugins/characters/Godette", "assets/tux", "assets/icons/blender",
]
SKIP_FILES = ["assets/icons/icon.xcf"]
SKIP_PREFIXES = ["assets/models/cake/tux"]


def main():
    if len(sys.argv) != 2:
        sys.exit("usage: python tools/get_assets.py <path to the upstream checkout>")
    src = os.path.abspath(sys.argv[1])
    dst = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    if not os.path.isdir(os.path.join(src, "assets")):
        sys.exit("%s does not look like a Super Tux Party checkout" % src)
    copied = skipped = pointers = 0
    for folder, dirs, files in os.walk(src):
        rel_folder = os.path.relpath(folder, src).replace(os.sep, "/")
        rel_folder = "" if rel_folder == "." else rel_folder
        dirs[:] = [d for d in dirs if (rel_folder + "/" + d).lstrip("/") not in SKIP_DIRS]
        for name in files:
            rel = (rel_folder + "/" + name).lstrip("/")
            if rel in SKIP_FILES or any(rel.startswith(p) for p in SKIP_PREFIXES):
                continue
            target = os.path.join(dst, rel)
            if os.path.exists(target):
                skipped += 1
                continue
            with open(os.path.join(folder, name), "rb") as f:
                if f.read(40).startswith(b"version https://git-lfs"):
                    pointers += 1      # the upstream checkout did not run `git lfs pull`
            os.makedirs(os.path.dirname(target), exist_ok=True)
            shutil.copy2(os.path.join(folder, name), target)
            copied += 1
    print("copied %d files, kept %d that already exist here" % (copied, skipped))
    if pointers:
        print("WARNING: %d copied files are Git LFS placeholders, run `git lfs pull` in the upstream checkout first" % pointers)


main()
