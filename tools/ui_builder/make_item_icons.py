#!/usr/bin/env python3
"""Draws the icons of the shop items (plugins/items/<name>/icon.png) in the same hand-drawn style as the portraits.

    python tools/ui_builder/make_item_icons.py
"""
import math
from PIL import Image, ImageDraw, ImageFilter

S = 256
K = 4
OUT = (27, 20, 74)


def canvas():
    return Image.new("RGBA", (S * K, S * K), (0, 0, 0, 0))


def finish(img, name):
    img = img.resize((S, S), Image.LANCZOS)
    img.save("plugins/items/%s/icon.png" % name)
    print("wrote", name)


def outlined(img, fn, color, w=9):
    m = Image.new("L", img.size, 0)
    fn(ImageDraw.Draw(m))
    big = m.filter(ImageFilter.MaxFilter(w * K // 2 * 2 + 1))
    img.paste(OUT + (255,), (0, 0), big)
    img.paste(color + (255,), (0, 0), m)


def u(v):
    return v * K


def die(img, cx, cy, size, color, pips, rot=0):
    half = size / 2
    outlined(img, lambda d: d.rounded_rectangle([u(cx - half), u(cy - half), u(cx + half), u(cy + half)], radius=u(size * 0.18), fill=255), color)
    d = ImageDraw.Draw(img)
    pos = {1: [(0, 0)], 2: [(-1, -1), (1, 1)], 3: [(-1, -1), (0, 0), (1, 1)], 4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
           5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)], 6: [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)]}[pips]
    for px, py in pos:
        r = size * 0.075
        x, y = cx + px * size * 0.26, cy + py * size * 0.26
        d.ellipse([u(x - r), u(y - r), u(x + r), u(y + r)], fill=OUT + (255,))


def double_dice():
    img = canvas()
    die(img, 100, 120, 110, (255, 255, 255), 4)
    die(img, 160, 140, 110, (255, 224, 74), 5)
    finish(img, "double_dice")


def slow_dice():
    img = canvas()
    die(img, 128, 100, 110, (150, 220, 255), 2)
    # a snail shell under the die
    outlined(img, lambda d: d.ellipse([u(70), u(150), u(190), u(230)], fill=255), (255, 170, 80))
    d = ImageDraw.Draw(img)
    d.arc([u(95), u(165), u(165), u(220)], 0, 280, fill=OUT + (255,), width=u(7))
    finish(img, "slow_dice")


def hero_dice():
    img = canvas()
    # a star behind a golden die
    pts = []
    for i in range(10):
        r = 118 if i % 2 == 0 else 52
        a = -math.pi / 2 + i * math.pi / 5
        pts.append((u(128 + math.cos(a) * r), u(128 + math.sin(a) * r)))
    outlined(img, lambda d: d.polygon(pts, fill=255), (255, 120, 80))
    die(img, 128, 132, 100, (255, 214, 50), 6)
    finish(img, "hero_dice")


def pickpocket():
    img = canvas()
    # a hand grabbing a cookie
    outlined(img, lambda d: d.ellipse([u(60), u(50), u(200), u(190)], fill=255), (222, 160, 90))
    d = ImageDraw.Draw(img)
    for x, y in [(110, 95), (150, 120), (120, 150), (160, 80)]:
        d.ellipse([u(x - 8), u(y - 8), u(x + 8), u(y + 8)], fill=(90, 50, 30, 255))
    outlined(img, lambda dd: (dd.rounded_rectangle([u(112), u(150), u(200), u(235)], radius=u(30), fill=255)), (255, 214, 170))
    d = ImageDraw.Draw(img)
    for i in range(4):
        x = 124 + i * 20
        d.line([u(x), u(165), u(x), u(190)], fill=OUT + (255,), width=u(5))
    finish(img, "pickpocket")


def swap_places():
    img = canvas()
    outlined(img, lambda d: d.ellipse([u(20), u(20), u(236), u(236)], fill=255), (110, 90, 230))
    d = ImageDraw.Draw(img)
    for sign, y in ((1, 98), (-1, 158)):
        x0, x1 = (62, 190) if sign == 1 else (194, 66)
        d.line([u(x0), u(y), u(x1), u(y)], fill=(255, 255, 255, 255), width=u(18))
        d.polygon([(u(x1 + sign * 30), u(y)), (u(x1 - sign * 4), u(y - 30)), (u(x1 - sign * 4), u(y + 30))], fill=(255, 255, 255, 255))
    finish(img, "swap_places")


def cookie_bomb():
    img = canvas()
    outlined(img, lambda d: d.ellipse([u(40), u(80), u(206), u(246)], fill=255), (60, 60, 80))
    d = ImageDraw.Draw(img)
    d.ellipse([u(70), u(105), u(105), u(140)], fill=(150, 150, 175, 255))
    outlined(img, lambda dd: dd.rounded_rectangle([u(104), u(60), u(144), u(96)], radius=u(8), fill=255), (130, 130, 150))
    d = ImageDraw.Draw(img)
    d.line([u(124), u(62), u(150), u(30)], fill=(190, 140, 70, 255), width=u(8))
    spark = [(u(150 + math.cos(a) * r), u(26 + math.sin(a) * r)) for a, r in
             [(i * math.pi / 4, 22 if i % 2 == 0 else 9) for i in range(8)]]
    d.polygon(spark, fill=(255, 220, 60, 255), outline=(255, 120, 40, 255))
    # a chocolate chip cookie bite
    d.ellipse([u(120), u(165), u(150), u(195)], fill=(120, 70, 40, 255))
    d.ellipse([u(90), u(150), u(108), u(168)], fill=(120, 70, 40, 255))
    finish(img, "cookie_bomb")


if __name__ == "__main__":
    double_dice()
    slow_dice()
    hero_dice()
    pickpocket()
    swap_places()
    cookie_bomb()
