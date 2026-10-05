#!/usr/bin/env python3
"""Builds the game icon files (assets/icons/icon*.png and icon.ico) from a character render.

    ICON_SIZE=1024 WRITE_ICONS=1 CHARACTERS=Businessman godot --path . \
        --script res://tools/character_builder/render_characters.gd
    python tools/character_builder/make_game_icon.py plugins/characters/Businessman/splash.png assets/icons

Puts the character on a round sky-blue badge, like the main menu background.
"""
import os
import sys

from PIL import Image, ImageDraw

source, out = sys.argv[1], sys.argv[2]
size = 1024
char = Image.open(source).convert("RGBA")
assert char.size == (size, size), "render the character at ICON_SIZE=1024"

badge = Image.new("RGBA", (size, size), (0, 0, 0, 0))
d = ImageDraw.Draw(badge)
d.ellipse((24, 24, size - 24, size - 24), fill=(20, 20, 28, 255))
d.ellipse((44, 44, size - 44, size - 44), fill=(255, 255, 255, 255))
d.ellipse((64, 64, size - 64, size - 64), fill=(89, 200, 224, 255))
glow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
ImageDraw.Draw(glow).ellipse((64, 380, size - 64, size + 260), fill=(130, 222, 238, 255))
inner = Image.new("L", (size, size), 0)
ImageDraw.Draw(inner).ellipse((64, 64, size - 64, size - 64), fill=255)
badge = Image.composite(Image.alpha_composite(badge, glow), badge, inner)
scaled = char.resize((int(size * 0.92),) * 2, Image.LANCZOS)
badge.alpha_composite(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2 + 30))
outer = Image.new("L", (size, size), 0)
ImageDraw.Draw(outer).ellipse((24, 24, size - 24, size - 24), fill=255)
final = Image.new("RGBA", (size, size), (0, 0, 0, 0))
final.paste(badge, (0, 0), outer)

final.save(os.path.join(out, "icon.png"))
final.resize((512, 512), Image.LANCZOS).save(os.path.join(out, "icon-smaller.png"))
final.resize((256, 256), Image.LANCZOS).save(os.path.join(out, "icon-smallest.png"))
final.save(os.path.join(out, "icon.ico"), sizes=[(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)])
print("wrote icons to", out)
