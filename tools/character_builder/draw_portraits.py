#!/usr/bin/env python3
"""Draws the 2D character portraits (icon.png and splash.png of every character) and the Mayor Pixel portrait.

    python tools/character_builder/draw_portraits.py plugins/characters common/scenes/board_logic/controller/icons/host.png

Hand-drawn style: thick dark outline, flat colours with one shade tone and a highlight, drawn with Pillow
at 4x size and scaled down. Run `tools/first_import.py` afterwards so Godot imports the new pictures.
"""
import math
import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 512
K = 3                      # supersampling
OUTLINE = (27, 20, 74)
OW = 9                     # outline width in 512-unit pixels


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def shade_of(c, f=0.78):
    return tuple(int(v * f) for v in c)


class Canvas:
    def __init__(self):
        self.img = Image.new("RGBA", (S * K, S * K), (0, 0, 0, 0))

    def mask(self, fn):
        m = Image.new("L", (S * K, S * K), 0)
        fn(ImageDraw.Draw(m))
        return m

    def paint(self, fn, color, shade=True, outline=True, light=None):
        """fn(draw) draws the shape in white (coordinates in 512 units via helpers below)."""
        m = self.mask(fn)
        if outline:
            # grow the shape by the outline width: blur it and threshold (a big MaxFilter is far too slow)
            o = m.filter(ImageFilter.GaussianBlur(OW * K * 0.62)).point(lambda v: 255 if v > 30 else 0)
            self.img.paste(Image.new("RGBA", m.size, OUTLINE + (255,)), mask=o)
        self.img.paste(Image.new("RGBA", m.size, tuple(color) + (255,)), mask=m)
        if shade:
            off = ImageChops.offset(m, -int(S * K * 0.035), -int(S * K * 0.045))
            crescent = ImageChops.subtract(m, off)
            self.img.paste(Image.new("RGBA", m.size, shade_of(color) + (255,)), mask=crescent)
            if light is not False:
                hl = ImageChops.offset(m, int(S * K * 0.02), int(S * K * 0.03))
                glow = ImageChops.subtract(m, hl)
                glow = glow.point(lambda v: v * 0.5)
                self.img.paste(Image.new("RGBA", m.size, tuple(min(255, int(v * 1.12 + 14)) for v in color) + (255,)), mask=glow)

    def done(self):
        return self.img.resize((S, S), Image.LANCZOS)


def E(cx, cy, rx, ry):
    return lambda d: d.ellipse(((cx - rx) * K, (cy - ry) * K, (cx + rx) * K, (cy + ry) * K), fill=255)


def R(x0, y0, x1, y1, r=20):
    return lambda d: d.rounded_rectangle((x0 * K, y0 * K, x1 * K, y1 * K), radius=r * K, fill=255)


def P(pts):
    return lambda d: d.polygon([(x * K, y * K) for x, y in pts], fill=255)


def both(*fns):
    def f(d):
        for fn in fns:
            fn(d)
    return f


def eye(c, cx, cy, rx=34, ry=40, pupil=19, look=(0, 0)):
    c.paint(E(cx, cy, rx, ry), (255, 255, 255), shade=False)
    c.paint(E(cx + look[0], cy + look[1] + 4, pupil, pupil * 1.2), (20, 18, 30), shade=False, outline=False)
    c.paint(E(cx + look[0] - 6, cy + look[1] - 6, 6, 7), (255, 255, 255), shade=False, outline=False)


def blush(c, cx, cy, color=(255, 140, 150)):
    c.paint(E(cx, cy, 20, 11), color, shade=False, outline=False)


# ---------------------------------------------------------------- characters

def businessman(mayor=False):
    c = Canvas()
    skin, hair, suit = hexc("#f4cba8"), hexc("#5a3a22"), hexc("#26263a")
    if mayor:
        hair, suit = hexc("#cfcfd8"), hexc("#3a2a5a")
    c.paint(R(70, 400, 442, 560, 70), suit)                                   # shoulders
    c.paint(P([(215, 400), (297, 400), (270, 500), (242, 500)]), (247, 247, 247), shade=False)   # shirt
    if mayor:
        c.paint(P([(120, 420), (170, 400), (330, 520), (300, 560), (200, 560)]), hexc("#d12b2b"))   # sash
        c.paint(E(312, 478, 24, 24), hexc("#f2c230"))
        c.paint(P([(244, 410), (268, 410), (275, 470), (256, 484), (237, 470)]), hexc("#d12b2b"), shade=False)
    else:
        c.paint(P([(244, 410), (268, 410), (275, 470), (256, 490), (237, 470)]), hexc("#d12b2b"))     # tie
    c.paint(P([(196, 400), (230, 400), (246, 470), (170, 480)]), shade_of(suit, 1.5), shade=False)   # lapels
    c.paint(P([(316, 400), (282, 400), (266, 470), (342, 480)]), shade_of(suit, 1.5), shade=False)
    if not mayor:
        c.paint(E(256, 190, 176, 150), hair)                                     # hair at the back
    c.paint(E(256, 250, 156, 150), skin)                                         # head
    c.paint(E(104, 262, 24, 34), skin); c.paint(E(408, 262, 24, 34), skin)       # ears
    if mayor:
        c.paint(P([(112, 235), (140, 175), (170, 235)]), hair, shade=False)      # grey side hair
        c.paint(P([(400, 235), (372, 175), (342, 235)]), hair, shade=False)
        c.paint(R(130, 70, 382, 150, 12), hexc("#16151f"))                       # top hat
        c.paint(R(88, 135, 424, 170, 14), hexc("#16151f"))
        c.paint(R(130, 128, 382, 150, 4), hexc("#c8452f"), shade=False, outline=False)
    else:
        # side-swept fringe: sweeps from the left parting over the forehead to the right
        c.paint(P([(104, 250), (96, 170), (150, 100), (256, 70), (370, 96), (420, 170), (410, 250),
                   (380, 190), (330, 168), (250, 196), (170, 190), (130, 215)]), hair)
        c.paint(P([(250, 196), (330, 168), (380, 190), (360, 150), (300, 120), (200, 130), (160, 170)]), hair, shade=False, outline=False)
    eye(c, 198, 262); eye(c, 314, 262)
    c.paint(E(256, 292, 17, 14), hexc("#e8a98a"), shade=False)                   # nose
    if mayor:
        c.paint(P([(184, 330), (256, 312), (328, 330), (318, 366), (256, 346), (194, 366)]), (245, 245, 250))   # moustache
        c.paint(R(226, 360, 286, 376, 8), hexc("#8c3b3b"), shade=False)
    else:
        c.paint(R(222, 336, 290, 350, 6), hexc("#8c3b3b"), shade=False)
    return c.done()


def emo():
    c = Canvas()
    skin, black, purple = hexc("#f3dccf"), hexc("#17171d"), hexc("#7a2fa8")
    c.paint(R(80, 400, 432, 560, 70), black)
    c.paint(R(80, 440, 432, 470, 8), purple, shade=False, outline=False)
    c.paint(R(80, 500, 432, 528, 8), purple, shade=False, outline=False)
    c.paint(E(256, 462, 22, 26), (245, 245, 245), shade=False)                  # skull print
    c.paint(E(248, 456, 6, 8), black, shade=False, outline=False); c.paint(E(268, 456, 6, 8), black, shade=False, outline=False)
    for tip in [(150, 60), (240, 28), (330, 50), (412, 98)]:                    # spikes at the back
        c.paint(P([(tip[0] - 44, 170), tip, (tip[0] + 46, 170)]), black, shade=False)
    c.paint(E(256, 190, 170, 140), black)
    c.paint(E(256, 250, 152, 146), skin)
    c.paint(E(108, 262, 22, 32), skin); c.paint(E(404, 262, 22, 32), skin)
    c.paint(E(330, 270, 46, 54), black, shade=False, outline=False)             # eyeliner
    eye(c, 330, 268, 32, 38, 18)
    # the long fringe covers the other eye
    c.paint(P([(94, 230), (110, 140), (200, 90), (330, 110), (420, 170), (380, 200), (300, 200), (250, 250),
               (230, 340), (170, 330), (120, 300)]), black)
    c.paint(E(256, 300, 15, 12), hexc("#d8b8a8"), shade=False)
    c.paint(R(232, 346, 292, 358, 6), hexc("#6b2c3a"), shade=False)
    return c.done()


def kit():
    c = Canvas()
    fox, cream, dark = hexc("#f28a24"), hexc("#fff0d6"), hexc("#5a3320")
    c.paint(E(256, 520, 150, 120), fox)
    c.paint(E(256, 530, 90, 100), cream, shade=False)
    c.paint(P([(86, 220), (110, 40), (230, 130)]), fox)                         # ears
    c.paint(P([(426, 220), (402, 40), (282, 130)]), fox)
    c.paint(P([(118, 190), (128, 90), (190, 140)]), hexc("#ff9aa8"), shade=False, outline=False)
    c.paint(P([(394, 190), (384, 90), (322, 140)]), hexc("#ff9aa8"), shade=False, outline=False)
    c.paint(E(256, 260, 172, 150), fox)                                          # head
    c.paint(E(120, 320, 84, 62), cream); c.paint(E(392, 320, 84, 62), cream)    # cheek tufts
    c.paint(E(256, 340, 80, 62), cream)                                          # muzzle
    c.paint(E(256, 175, 40, 40), hexc("#f6c27a"), shade=False, outline=False)   # forehead mark
    eye(c, 190, 250, 28, 34, 16); eye(c, 322, 250, 28, 34, 16)
    c.paint(E(256, 318, 24, 18), (20, 18, 30), shade=False)                     # nose
    c.paint(E(250, 312, 6, 4), (255, 255, 255), shade=False, outline=False)
    c.paint(R(254, 336, 258, 358, 2), OUTLINE, shade=False, outline=False)
    c.paint(P([(222, 350), (256, 360), (290, 350), (256, 376)]), hexc("#ff9aa8"), shade=False, outline=False)
    return c.done()


def bolt():
    c = Canvas()
    steel, navy, orange = hexc("#9db7e0"), hexc("#27304a"), hexc("#ff8a1f")
    c.paint(R(100, 420, 412, 560, 40), steel)
    c.paint(R(190, 450, 322, 520, 10), orange)
    c.paint(E(256, 485, 14, 14), hexc("#5fe3f0"), shade=False)
    c.paint(R(244, 20, 268, 110, 6), hexc("#5d6f94"))                            # antenna
    c.paint(E(256, 30, 28, 28), hexc("#e8312f"))
    c.paint(R(60, 230, 110, 330, 14), orange); c.paint(R(402, 230, 452, 330, 14), orange)   # ear bolts
    c.paint(R(90, 100, 422, 410, 70), steel)                                     # head
    c.paint(R(130, 190, 382, 350, 40), navy)                                     # screen
    c.paint(E(206, 262, 40, 46), (255, 255, 255), shade=False); c.paint(E(306, 262, 40, 46), (255, 255, 255), shade=False)
    c.paint(E(206, 270, 20, 24), (20, 18, 30), shade=False, outline=False); c.paint(E(306, 270, 20, 24), (20, 18, 30), shade=False, outline=False)
    c.paint(E(198, 258, 7, 8), (255, 255, 255), shade=False, outline=False); c.paint(E(298, 258, 7, 8), (255, 255, 255), shade=False, outline=False)
    c.paint(R(226, 322, 286, 332, 4), (255, 255, 255), shade=False, outline=False)
    return c.done()


def mushi():
    c = Canvas()
    cap, cream = hexc("#e23a3e"), hexc("#fbe9c4")
    c.paint(E(256, 520, 150, 110), cream)
    c.paint(E(256, 290, 150, 140), cream)                                        # face
    c.paint(E(256, 150, 230, 130), cap)                                          # cap
    c.paint(R(40, 190, 472, 232, 20), hexc("#a82428"), shade=False)             # rim
    for cx, cy, rx, ry in [(150, 110, 44, 30), (270, 70, 52, 34), (380, 120, 40, 28), (100, 190, 30, 20), (440, 185, 28, 18)]:
        c.paint(E(cx, cy, rx, ry), (255, 248, 238), shade=False)
    eye(c, 200, 310, 26, 32, 15); eye(c, 312, 310, 26, 32, 15)
    blush(c, 150, 354); blush(c, 362, 354)
    c.paint(E(256, 366, 12, 8), hexc("#6e4326"), shade=False, outline=False)
    return c.done()


def timber():
    c = Canvas()
    bark, dark, wood = hexc("#8a5530"), hexc("#5a341c"), hexc("#e2b26a")
    c.paint(R(90, 130, 422, 540, 36), bark)
    for x, h in [(140, 120), (200, 80), (330, 100), (385, 90)]:
        c.paint(R(x, 450 - h, x + 8, 450, 3), dark, shade=False, outline=False)
    c.paint(E(256, 130, 166, 52), wood)                                          # cut top
    c.paint(E(256, 130, 118, 34), hexc("#b97f3f"), shade=False, outline=False)
    c.paint(E(256, 130, 70, 20), wood, shade=False, outline=False)
    c.paint(E(256, 130, 24, 8), hexc("#b97f3f"), shade=False, outline=False)
    c.paint(P([(250, 110), (240, 20), (276, 20), (268, 110)]), hexc("#3f8c2b"), shade=False)       # sprout stem
    c.paint(E(190, 32, 74, 30), hexc("#69bd3f")); c.paint(E(318, 40, 78, 30), hexc("#69bd3f"))
    eye(c, 188, 270, 32, 38, 18); eye(c, 324, 270, 32, 38, 18)
    c.paint(R(130, 206, 230, 222, 6), dark, shade=False, outline=False); c.paint(R(282, 206, 382, 222, 6), dark, shade=False, outline=False)
    c.paint(E(400, 340, 28, 44), dark, shade=False, outline=False)              # knot
    c.paint(R(210, 366, 302, 384, 8), hexc("#4a1f12"), shade=False)
    return c.done()


def joy():
    c = Canvas()
    blue, red = hexc("#1fa9ff"), hexc("#ff3b4a")
    c.paint(R(76, 60, 258, 560, 70), blue)                                      # left half
    c.paint(R(254, 60, 436, 560, 70), red)                                      # right half
    c.paint(R(250, 90, 262, 560, 4), OUTLINE, shade=False, outline=False)       # seam
    c.paint(R(120, 30, 230, 80, 18), hexc("#2a2f3a")); c.paint(R(282, 30, 392, 80, 18), hexc("#2a2f3a"))   # shoulder buttons
    for i, y in enumerate((130, 190, 250, 310)):                                 # sync lights
        c.paint(E(92, y, 8, 14), hexc("#5fe3f0") if i < 2 else (255, 255, 255), shade=False, outline=False)
    eye(c, 190, 200, 44, 54, 24); eye(c, 322, 200, 44, 54, 24)
    blush(c, 140, 300); blush(c, 372, 300)
    c.paint(P([(190, 312), (256, 346), (322, 312), (312, 300), (256, 326), (200, 300)]), hexc("#5a1020"), shade=False)   # smile
    c.paint(E(170, 440, 48, 48), hexc("#2a2f3a")); c.paint(E(170, 436, 34, 34), hexc("#aeb6c6"), shade=False)         # thumb stick
    for dx, dy, col in ((0, -50, hexc("#ffd21f")), (0, 50, hexc("#3fd36a")), (50, 0, hexc("#5fe3f0")), (-50, 0, hexc("#ff9aa8"))):
        c.paint(E(342 + dx, 440 + dy, 24, 24), col, shade=False)
    return c.done()


def main():
    chars, host = sys.argv[1], sys.argv[2]
    for name, fn in {"Businessman": businessman, "Emo": emo, "Kit": kit, "Bolt": bolt, "Mushi": mushi, "Timber": timber, "Joy": joy}.items():
        img = fn()
        for f in ("icon.png", "splash.png"):
            img.save(os.path.join(chars, name, f))
        print("drew", name)
    businessman(mayor=True).save(host)
    print("drew Mayor Pixel")


main()
