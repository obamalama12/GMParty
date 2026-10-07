#!/usr/bin/env python3
"""Draws the big poster picture of the mascot Joy for the title screen.

    python tools/character_builder/draw_mascot_art.py assets/textures/title/mascot.png

Joy jumps with both arms up in front of a star burst. Same hand-drawn style as the portraits (draw_portraits.py).
"""
import math
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

import draw_portraits as dp
from draw_portraits import Canvas, E, P, R, hexc

dp.OW = 12              # a thicker outline for the big picture
W, H = 1024, 1280
K = dp.K


def capsule(p0, p1, w):
    """A thick line with round ends."""
    def fn(d):
        x0, y0 = p0
        x1, y1 = p1
        dx, dy = x1 - x0, y1 - y0
        n = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / n * w / 2, dx / n * w / 2
        d.polygon([((x0 + nx) * K, (y0 + ny) * K), ((x1 + nx) * K, (y1 + ny) * K),
                   ((x1 - nx) * K, (y1 - ny) * K), ((x0 - nx) * K, (y0 - ny) * K)], fill=255)
        for x, y in (p0, p1):
            d.ellipse(((x - w / 2) * K, (y - w / 2) * K, (x + w / 2) * K, (y + w / 2) * K), fill=255)
    return fn


def star(cx, cy, r_out, r_in, n, rot=0.0):
    pts = []
    for i in range(n * 2):
        a = rot + math.pi * i / n
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return P(pts)


def eye(c, cx, cy, rx, ry, pupil):
    c.paint(E(cx, cy, rx, ry), (255, 255, 255), shade=False)
    c.paint(E(cx, cy + 8, pupil, pupil * 1.25), (20, 18, 30), shade=False, outline=False)
    c.paint(E(cx - 14, cy - 12, pupil * 0.34, pupil * 0.4), (255, 255, 255), shade=False, outline=False)


def figure():
    f = Canvas(W, H)
    dark, gray = hexc("#2a2f3a"), hexc("#aeb6c6")
    blue, red = hexc("#1fa9ff"), hexc("#ff3b4a")
    # legs (jumping) and sneakers
    f.paint(capsule((420, 880), (350, 1090), 74), dark)
    f.paint(capsule((610, 880), (700, 1050), 74), dark)
    f.paint(E(325, 1150, 105, 52), (255, 255, 255)); f.paint(E(335, 1176, 98, 22), blue, shade=False, outline=False)
    f.paint(E(735, 1100, 105, 52), (255, 255, 255)); f.paint(E(745, 1126, 98, 22), red, shade=False, outline=False)
    # arms up
    f.paint(capsule((270, 560), (140, 330), 70), dark)
    f.paint(capsule((754, 560), (860, 330), 70), dark)
    f.paint(E(130, 290, 70, 70), (255, 255, 255)); f.paint(E(872, 292, 72, 72), (255, 255, 255))
    for dx in (-30, 0, 30):                                                     # fingers of the waving glove
        f.paint(capsule((130 + dx, 250), (130 + dx * 1.5, 205), 30), (255, 255, 255))
    # the controller
    f.paint(R(262, 150, 514, 930, 120), blue)
    f.paint(R(510, 150, 762, 930, 120), red)
    f.paint(R(236, 240, 300, 800, 24), hexc("#1678c4"), shade=False)
    f.paint(R(724, 240, 788, 800, 24), hexc("#c42433"), shade=False)
    f.paint(R(500, 210, 524, 880, 6), dp.OUTLINE, shade=False, outline=False)
    f.paint(R(300, 90, 480, 160, 28), dark); f.paint(R(544, 90, 724, 160, 28), dark)     # shoulder buttons
    for i in range(4):                                                           # sync lights
        f.paint(E(262, 290 + i * 70, 12, 20), hexc("#5fe3f0") if i < 2 else (255, 255, 255), shade=False, outline=False)
    # face
    eye(f, 395, 360, 70, 86, 38); eye(f, 629, 360, 70, 86, 38)
    for x in (300, 724):
        f.paint(E(x, 506, 44, 24), hexc("#ff9aa8"), shade=False, outline=False)
    mouth = [(512 + 118 * math.cos(math.radians(a_)), 520 + 96 * math.sin(math.radians(a_))) for a_ in range(0, 181, 10)]
    f.paint(P(mouth), hexc("#5a1020"), shade=False)                                     # open smile
    f.paint(E(512, 590, 62, 34), hexc("#ff7b8a"), shade=False, outline=False)           # tongue
    f.paint(R(446, 516, 578, 540, 6), (255, 255, 255), shade=False, outline=False)      # teeth
    # stick and buttons
    f.paint(E(390, 700, 78, 78), dark); f.paint(E(390, 692, 56, 56), gray, shade=False)
    for dx, dy, col in ((0, -82, hexc("#ffd21f")), (0, 82, hexc("#3fd36a")), (82, 0, hexc("#5fe3f0")), (-82, 0, hexc("#ff9aa8"))):
        f.paint(E(636 + dx, 700 + dy, 40, 40), col, shade=False)
    f.paint(R(350, 850, 430, 872, 8), dark, shade=False, outline=False); f.paint(R(594, 850, 674, 872, 8), dark, shade=False, outline=False)
    return f.done()


def main():
    out = sys.argv[1] if len(sys.argv) > 1 else "mascot.png"
    art = Canvas(W, H)
    # burst behind the figure
    art.paint(star(512, 620, 500, 340, 12, rot=0.1), hexc("#ffe46b"), shade=True)
    art.paint(E(512, 620, 320, 320), hexc("#ffb400"), shade=True)
    art.paint(E(512, 620, 250, 250), hexc("#ffd84a"), shade=False, outline=False)
    base = art.done()
    # a soft shadow under the feet
    shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).ellipse((250, 1210, 800, 1260), fill=(10, 10, 60, 110))
    shadow = shadow.filter(ImageFilter.GaussianBlur(14))
    base.alpha_composite(shadow)
    fig = figure().rotate(-7, resample=Image.BICUBIC, center=(512, 800))
    base.alpha_composite(fig)
    # sparkles
    sp = Canvas(W, H)
    for x, y, r in ((90, 170, 46), (960, 120, 38), (120, 900, 34), (940, 760, 42), (500, 40, 30)):
        sp.paint(star(x, y, r, r * 0.3, 4, rot=math.pi / 4), (255, 255, 255), shade=False, outline=False)
    base.alpha_composite(sp.done())
    base.save(out)
    print("wrote", out)


main()
