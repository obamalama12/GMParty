#!/usr/bin/env python3
"""Imports all assets once, so the project runs right after `get_assets.py`.

    python tools/first_import.py [path to godot executable]

Godot's normal import can skip assets whose .import file is committed but whose imported
data is missing (a fresh clone). This runs a temporary editor plugin that forces the import.
Afterwards you can open the project in the editor as usual.
"""
import pathlib
import shutil
import subprocess
import sys

root = pathlib.Path(__file__).resolve().parent.parent
godot = sys.argv[1] if len(sys.argv) > 1 else (shutil.which("godot") or "godot")
addon = root / "addons" / "zz_first_import"
project = root / "project.godot"
original = project.read_text()

addon.mkdir(parents=True, exist_ok=True)
shutil.copy(root / "tools" / "first_import" / "plugin.gd", addon / "plugin.gd")
(addon / "plugin.cfg").write_text(
    '[plugin]\nname="first_import"\ndescription="temporary"\nauthor="-"\nversion="1"\nscript="plugin.gd"\n')
try:
    entry = '"res://addons/zz_first_import/plugin.cfg"'
    if "enabled=PackedStringArray(" in original:
        text = original.replace("enabled=PackedStringArray(", "enabled=PackedStringArray(" + entry + ", ", 1)
    else:
        text = original + "\n[editor_plugins]\n\nenabled=PackedStringArray(" + entry + ")\n"
    project.write_text(text)
    subprocess.run([godot, "--editor", "--headless", "--path", str(root)], check=False)
finally:
    project.write_text(original)
    shutil.rmtree(addon, ignore_errors=True)
print("Done. Open the project in Godot now.")
