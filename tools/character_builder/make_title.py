#!/usr/bin/env python3
"""Draws the title logo (assets/textures/title/Title.png, 1024 x 640) with Pillow.

    python tools/character_builder/make_title.py assets/textures/title/Title.png

MARKY in glossy gold and PARTY in candy colours, both with a thick outline and a drop shadow,
on a slight tilt, with sparkles and a "a party game" ribbon.
"""
import math
import random
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1] if len(sys.argv) > 1 else "Title.png"
FONT = "assets/fonts/Boogaloo-Regular.ttf"
W, H = 1024, 640
random.seed(7)


def gradient(size, stops):
    """Vertical gradient image from [(pos 0..1, (r, g, b)), ...]."""
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for y in range(h):
        t = y / max(h - 1, 1)
        for i in range(len(stops) - 1):
            (t0, c0), (t1, c1) = stops[i], stops[i + 1]
            if t0 <= t <= t1:
                f = (t - t0) / max(t1 - t0, 1e-6)
                c = tuple(int(c0[k] + (c1[k] - c0[k]) * f) for k in range(3))
                break
        else:
            c = stops[-1][1]
        for x in range(w):
            px[x, y] = c
    return img


def hgradient(size, stops):
    return gradient((size[1], size[0]), stops).rotate(90, expand=True).transpose(Image.FLIP_TOP_BOTTOM) if False else _h(size, stops)


def _h(size, stops):
    w, h = size
    img = Image.new("RGB", size)
    px = img.load()
    for x in range(w):
        t = x / max(w - 1, 1)
        c = stops[-1][1]
        for i in range(len(stops) - 1):
            (t0, c0), (t1, c1) = stops[i], stops[i + 1]
            if t0 <= t <= t1:
                f = (t - t0) / max(t1 - t0, 1e-6)
                c = tuple(int(c0[k] + (c1[k] - c0[k]) * f) for k in range(3))
                break
        for y in range(h):
            px[x, y] = c
    return img


def word(text, size, fill, outline_px, outline_color, extrude_px, extrude_color):
    """One word on a transparent layer: extrusion, outline, gradient fill and a gloss."""
    font = ImageFont.truetype(FONT, size)
    pad = outline_px + extrude_px + 20
    box = font.getbbox(text, stroke_width=outline_px)
    w, h = box[2] - box[0] + 2 * pad, box[3] - box[1] + 2 * pad
    pos = (pad - box[0], pad - box[1])
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    # extrusion: the outlined word repeated down and to the right
    ext = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(ext)
    for i in range(extrude_px, 0, -1):
        d.text((pos[0] + i * 0.6, pos[1] + i), text, font=font, fill=255, stroke_width=outline_px)
    layer.paste(Image.new("RGBA", (w, h), extrude_color), mask=ext)
    # outline
    out = Image.new("L", (w, h), 0)
    ImageDraw.Draw(out).text(pos, text, font=font, fill=255, stroke_width=outline_px)
    layer.paste(Image.new("RGBA", (w, h), outline_color), mask=out)
    # fill
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).text(pos, text, font=font, fill=255)
    layer.paste(fill(w, h).convert("RGBA"), mask=mask)
    # gloss on the upper third
    gloss = Image.new("L", (w, h), 0)
    ImageDraw.Draw(gloss).rectangle((0, pad, w, pad + (box[3] - box[1]) * 0.42), fill=70)
    gloss = ImageChops.multiply(gloss, mask)
    layer.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), mask=gloss)
    return layer, mask, pos


def sparkle(draw, x, y, r, color=(255, 255, 255, 255)):
    pts = []
    for i in range(8):
        a = i * math.pi / 4
        rr = r if i % 2 == 0 else r * 0.28
        pts.append((x + rr * math.cos(a - math.pi / 2), y + rr * math.sin(a - math.pi / 2)))
    draw.polygon(pts, fill=color)


NAVY = (27, 20, 74, 255)
canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))

# MARKY: golden
retro, _, _ = word(
    "RETRO", 330,
    lambda w, h: gradient((w, h), [(0, (255, 244, 150)), (0.35, (255, 205, 60)), (0.7, (255, 150, 30)), (1, (240, 110, 30))]),
    16, NAVY, 20, (92, 40, 130, 255))
# PARTY: candy colours from left to right
party, _, _ = word(
    "PARTY", 330,
    lambda w, h: ImageChops.add(_h((w, h), [(0, (255, 90, 160)), (0.35, (200, 90, 240)), (0.7, (90, 150, 255)), (1, (60, 220, 200))]),
                                Image.new("RGB", (w, h), (0, 0, 0))),
    16, NAVY, 20, (60, 30, 110, 255))

for layer, cy, tilt in ((retro, 175, -3.0), (party, 440, 2.0)):
    layer = layer.rotate(tilt, resample=Image.BICUBIC, expand=True)
    sc = min(1.0, (W - 30) / layer.width)
    if sc < 1.0:
        layer = layer.resize((int(layer.width * sc), int(layer.height * sc)), Image.LANCZOS)
    # soft drop shadow
    shadow = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    shadow.paste((10, 5, 40, 150), mask=layer.getchannel("A"))
    shadow = shadow.filter(ImageFilter.GaussianBlur(10))
    x = (W - layer.width) // 2
    y = cy - layer.height // 2
    canvas.alpha_composite(shadow, (x + 6, y + 14))
    canvas.alpha_composite(layer, (x, y))

# ribbon between the words
rib = Image.new("RGBA", (W, H), (0, 0, 0, 0))
d = ImageDraw.Draw(rib)
rx0, rx1, ry0, ry1 = 330, 700, 292, 352
d.polygon([(rx0 - 36, ry0 + 14), (rx0 + 10, ry0 + 14), (rx0 + 10, ry1 + 14), (rx0 - 36, ry1 + 14), (rx0 - 12, (ry0 + ry1) / 2 + 14)], fill=(150, 30, 80, 255))
d.polygon([(rx1 + 36, ry0 + 14), (rx1 - 10, ry0 + 14), (rx1 - 10, ry1 + 14), (rx1 + 36, ry1 + 14), (rx1 + 12, (ry0 + ry1) / 2 + 14)], fill=(150, 30, 80, 255))
d.rounded_rectangle((rx0, ry0, rx1, ry1), radius=14, fill=(226, 52, 120, 255), outline=NAVY, width=6)
d.rounded_rectangle((rx0 + 8, ry0 + 8, rx1 - 8, ry0 + 26), radius=8, fill=(255, 255, 255, 50))
f = ImageFont.truetype(FONT, 40)
text = "A PARTY GAME"
tw = d.textlength(text, font=f)
d.text(((rx0 + rx1) / 2 - tw / 2, ry0 + 3), text, font=f, fill=(255, 255, 255, 255), stroke_width=3, stroke_fill=NAVY)
canvas.alpha_composite(rib)

# sparkles
sp = ImageDraw.Draw(canvas)
for x, y, r, c in [(70, 90, 34, (255, 255, 255, 255)), (950, 70, 26, (255, 240, 160, 255)), (980, 330, 22, (255, 255, 255, 255)),
                   (48, 400, 22, (255, 240, 160, 255)), (880, 560, 30, (255, 255, 255, 255)), (140, 590, 24, (255, 240, 160, 255)),
                   (500, 30, 18, (255, 255, 255, 255))]:
    sparkle(sp, x, y, r, c)
canvas.save(OUT)
print("wrote", OUT)
