#!/usr/bin/env python3
"""Draws the 9-patch panels, buttons, player cards and the glove cursor of the party-game UI into assets/ui.

    python tools/ui_builder/make_ui_art.py assets/ui

Bright colours, a thick white border and a navy outline, like the menus of the 90s party games.
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/ui"
os.makedirs(OUT, exist_ok=True)
NAVY = (16, 33, 90)
SS = 4


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


def box(size, radius, top, bottom, border=(255, 255, 255), bw=6, ow=4, gloss=True):
    """Rounded 9-patch box: navy outline, white border, vertical gradient, gloss on the top half."""
    w = h = size * SS
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    r = radius * SS
    d.rounded_rectangle((0, 0, w - 1, h - 1), radius=r, fill=NAVY + (255,))
    o = ow * SS
    d.rounded_rectangle((o, o, w - 1 - o, h - 1 - o), radius=r - o, fill=border + (255,))
    b = (ow + bw) * SS
    inner = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    px = inner.load()
    for y in range(h):
        c = lerp(top, bottom, y / (h - 1))
        for x in range(w):
            px[x, y] = c + (255,)
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle((b, b, w - 1 - b, h - 1 - b), radius=max(r - b, 2), fill=255)
    img.paste(inner, mask=mask)
    if gloss:
        g = Image.new("L", (w, h), 0)
        ImageDraw.Draw(g).rounded_rectangle((b, b, w - 1 - b, int(h * 0.48)), radius=max(r - b, 2), fill=60)
        g = ImageChops.multiply(g, mask)
        img.paste(Image.new("RGBA", (w, h), (255, 255, 255, 255)), mask=g)
    return img.resize((size, size), Image.LANCZOS)


def save(img, name):
    img.save(os.path.join(OUT, name))
    print("wrote", name)


BLUE = (hexc("#5b97ff"), hexc("#1f4fd0"))
save(box(128, 34, *BLUE), "panel_blue.png")
save(box(128, 34, hexc("#2a3f9c"), hexc("#141f66")), "panel_dark.png")
save(box(96, 30, *BLUE), "button.png")
save(box(96, 30, hexc("#ffe46b"), hexc("#ffb400")), "button_focus.png")
save(box(96, 30, hexc("#e8b800"), hexc("#c48a00")), "button_pressed.png")
save(box(96, 30, hexc("#7f8aa8"), hexc("#555f80")), "button_disabled.png")
save(box(128, 34, hexc("#ff7b6b"), hexc("#d4202a")), "card_red.png")
save(box(128, 34, hexc("#6fb0ff"), hexc("#1e56d8")), "card_blue.png")
save(box(128, 34, hexc("#7fe07a"), hexc("#1f9f3a")), "card_green.png")
save(box(128, 34, hexc("#ffe46b"), hexc("#f0a800")), "card_yellow.png")
save(box(64, 20, hexc("#ffffff"), hexc("#d8e6ff"), bw=3, ow=3, gloss=False), "pill.png")


def glove():
    """A white cartoon glove pointing to the right."""
    s = 128 * SS
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))

    def shape(draw_fn, fill):
        m = Image.new("L", (s, s), 0)
        draw_fn(ImageDraw.Draw(m))
        o = m.filter(ImageFilter.GaussianBlur(3.5 * SS)).point(lambda v: 255 if v > 30 else 0)
        img.paste(Image.new("RGBA", (s, s), NAVY + (255,)), mask=o)
        img.paste(Image.new("RGBA", (s, s), fill + (255,)), mask=m)
    k = SS
    shape(lambda d: d.rounded_rectangle((8 * k, 52 * k, 62 * k, 106 * k), radius=18 * k, fill=255), (255, 255, 255))   # cuff
    shape(lambda d: d.ellipse((34 * k, 40 * k, 100 * k, 100 * k), fill=255), (255, 255, 255))                          # palm
    shape(lambda d: d.rounded_rectangle((70 * k, 52 * k, 124 * k, 70 * k), radius=9 * k, fill=255), (255, 255, 255))   # index finger
    for i, y in enumerate((74, 86, 98)):
        shape(lambda d, y=y: d.rounded_rectangle((60 * k, y * k, 96 * k, (y + 13) * k), radius=6 * k, fill=255), (245, 248, 255))
    shape(lambda d: d.ellipse((34 * k, 34 * k, 64 * k, 58 * k), fill=255), (255, 255, 255))                            # thumb
    shape(lambda d: d.rounded_rectangle((4 * k, 60 * k, 22 * k, 98 * k), radius=8 * k, fill=255), (230, 20, 40))       # red band
    return img.resize((128, 128), Image.LANCZOS)


save(glove(), "glove.png")


# the speech dialog uses these two as 9-patches; run this script from the project root
DIALOG = "common/scenes/speech_dialog"
box(512, 70, hexc("#4f8fff"), hexc("#1d45c4"), bw=12, ow=7).save(os.path.join(DIALOG, "dialog_box.png"))
box(512, 70, hexc("#ffe46b"), hexc("#ffb400"), bw=12, ow=7).save(os.path.join(DIALOG, "dialog_box_focus.png"))


def dice_faces():
    """Atlas for the 3D dice block: 3 x 2 tiles of 256 px, tile i shows i + 1 pips (1 is the big red one)."""
    T = 256
    atlas = Image.new("RGBA", (T * 3, T * 2), (0, 0, 0, 255))
    pips = {1: [(0.5, 0.5)], 2: [(0.27, 0.27), (0.73, 0.73)], 3: [(0.27, 0.27), (0.5, 0.5), (0.73, 0.73)],
            4: [(0.27, 0.27), (0.73, 0.27), (0.27, 0.73), (0.73, 0.73)],
            5: [(0.27, 0.27), (0.73, 0.27), (0.5, 0.5), (0.27, 0.73), (0.73, 0.73)],
            6: [(0.27, 0.25), (0.73, 0.25), (0.27, 0.5), (0.73, 0.5), (0.27, 0.75), (0.73, 0.75)]}
    for n in range(1, 7):
        tile = Image.new("RGBA", (T * SS, T * SS), (0, 0, 0, 255))
        d = ImageDraw.Draw(tile)
        d.rectangle((0, 0, T * SS, T * SS), fill=hexc("#f4f6ff") + (255,))
        d.rectangle((0, 0, T * SS - 1, T * SS - 1), outline=hexc("#b9c6ee") + (255,), width=10 * SS)
        for px_, py_ in pips[n]:
            r = (0.17 if n == 1 else 0.10) * T * SS
            col = hexc("#e8312f") if n == 1 else hexc("#1b2f7a")
            d.ellipse((px_ * T * SS - r, py_ * T * SS - r, px_ * T * SS + r, py_ * T * SS + r), fill=col + (255,))
            d.ellipse((px_ * T * SS - r * 0.5, py_ * T * SS - r * 0.7, px_ * T * SS - r * 0.1, py_ * T * SS - r * 0.3),
                      fill=(255, 255, 255, 110))
        tile = tile.resize((T, T), Image.LANCZOS)
        atlas.paste(tile, (((n - 1) % 3) * T, ((n - 1) // 3) * T))
    return atlas


save(dice_faces(), "dice_faces.png")


def bg_panel():
    """Soft shine strip for headings: used behind big titles."""
    img = Image.new("RGBA", (256, 64), (0, 0, 0, 0))
    return img


