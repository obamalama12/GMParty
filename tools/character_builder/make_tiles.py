#!/usr/bin/env python3
"""Draws our own board-tile emblems and portraits for the two helper characters:
  Joy    (controller buddy)  -> tile_gnu_col.png   (orange hex tile) + gnu_icon.png stays Joy's portrait
  Glitch (purple pixel imp)  -> tile_nolok_col.jpg (dark hex tile)   + nolokicon.png (dialog portrait)

    python tools/character_builder/make_tiles.py
"""
import math
import random
from PIL import Image, ImageDraw, ImageFilter, ImageChops

MAT = "common/scenes/board_logic/node/material/"
ICONS = "common/scenes/board_logic/controller/icons/"
OUT = (27, 20, 74)
K = 3


def interior_mask():
    """Inside of the hex tile, taken from the plain blue tile."""
    b = Image.open(MAT + "tile_blue_col.png").convert("RGB")
    r, g, bl = b.split()
    m = ImageChops.subtract(bl, r).point(lambda v: 255 if v > 90 else 0)
    return m.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.GaussianBlur(1.2))


def radial(size, inner, outer):
    img = Image.new("RGB", (size, size))
    px = img.load()
    c = size / 2
    for y in range(size):
        for x in range(size):
            t = min(1.0, math.hypot(x - c, y - c) / (size * 0.55))
            px[x, y] = tuple(int(inner[i] + (outer[i] - inner[i]) * t) for i in range(3))
    return img


def tile(base_file, inner, outer, emblem, out_file, is_jpg=False):
    base = Image.open(MAT + base_file).convert("RGB")
    fill = radial(base.width, inner, outer)
    mask = interior_mask()
    tile = Image.composite(fill, base, mask).convert("RGBA")
    e = emblem.resize((int(base.width * 0.62), int(base.width * 0.62)), Image.LANCZOS)
    # soft shadow under the emblem
    sh = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    sh.paste((0, 0, 0, 110), (int((base.width - e.width) / 2) + 8, int((base.height - e.height) / 2) + 14), e.split()[3])
    sh = sh.filter(ImageFilter.GaussianBlur(10))
    tile = Image.alpha_composite(tile, sh)
    tile.alpha_composite(e, (int((base.width - e.width) / 2), int((base.height - e.height) / 2)))
    rgb = tile.convert("RGB")
    rgb = Image.composite(rgb, base, mask)
    if is_jpg:
        rgb.save(MAT + out_file, quality=95)
    else:
        rgb.save(MAT + out_file)


def draw_glitch(size=512):
    S = size * K
    img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    u = S / 512.0

    def P(pts):
        return [(x * u, y * u) for x, y in pts]

    def shape(draw_fn, color, grow=0):
        m = Image.new("L", (S, S), 0)
        draw_fn(ImageDraw.Draw(m))
        if grow:
            m = m.filter(ImageFilter.MaxFilter(grow * 2 + 1))
        return m

    def fill(draw_fn, color, outline=True):
        nonlocal img
        m = shape(draw_fn, color)
        if outline:
            big = m.filter(ImageFilter.MaxFilter(int(9 * u / 3) * 2 + 1))
            img.paste(OUT + (255,), (0, 0), big)
        img.paste(color + (255,), (0, 0), m)
        return m

    purple, dark, light = (150, 70, 220), (104, 44, 168), (196, 130, 255)
    # horns / antennas (pixel stairs)
    for sx in (-1, 1):
        cx = 256 + sx * 118
        fill(lambda d, cx=cx, sx=sx: d.polygon(P([(cx - 28, 150), (cx + 28, 150), (cx + sx * 40, 62), (cx + sx * 8, 62), (cx + sx * 8, 96), (cx - sx * 22, 96)]), fill=255), (255, 90, 90))
    # body: blocky head with stepped edges (a glitchy pixel blob)
    def body(d):
        d.rounded_rectangle([P([(90, 130)])[0], P([(422, 450)])[0]], radius=70 * u, fill=255)
        for (x0, y0, x1, y1) in [(60, 210, 100, 270), (412, 280, 452, 340), (110, 440, 190, 470), (330, 436, 410, 466)]:
            d.rectangle([x0 * u, y0 * u, x1 * u, y1 * u], fill=255)
    m = fill(body, purple)
    # shade lower half, highlight top-left
    sh = Image.new("L", (S, S), 0)
    ImageDraw.Draw(sh).rectangle([0, 350 * u, S, S], fill=255)
    img.paste(dark + (255,), (0, 0), ImageChops.multiply(m, sh))
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).rounded_rectangle([130 * u, 160 * u, 250 * u, 200 * u], radius=18 * u, fill=255)
    img.paste(light + (255,), (0, 0), ImageChops.multiply(m, hl))
    # glitch bars: shifted horizontal slices of lighter/darker colour
    rnd = random.Random(7)
    d = ImageDraw.Draw(img)
    for y in (250, 300, 372):
        x0 = rnd.randint(140, 220)
        d.rectangle([x0 * u, y * u, (x0 + rnd.randint(60, 120)) * u, (y + 12) * u], fill=light + (255,))
    # eyes: angry slits with red pupils
    for sx in (-1, 1):
        cx = 256 + sx * 82
        eye = lambda dd, cx=cx: dd.rounded_rectangle([(cx - 50) * u, 216 * u, (cx + 50) * u, 304 * u], radius=26 * u, fill=255)
        fill(eye, (255, 255, 255))
        d.ellipse([(cx - 22 - sx * 6) * u, 232 * u, (cx + 22 - sx * 6) * u, 284 * u], fill=(235, 40, 60, 255))
        d.ellipse([(cx - 8 - sx * 6) * u, 244 * u, (cx + 4 - sx * 6) * u, 258 * u], fill=(255, 255, 255, 255))
        # angry brow
        d.polygon(P([(cx + 62 * sx, 198), (cx - 58 * sx, 238), (cx - 58 * sx, 214), (cx + 62 * sx, 176)]), fill=OUT + (255,))
    # zigzag grin with teeth
    zig = [(170, 360), (205, 395), (240, 358), (272, 396), (306, 358), (342, 392)]
    fill(lambda dd: dd.polygon(P(zig + [(342, 420), (170, 420)]), fill=255), (30, 12, 58))
    for x in (205, 272, 342 - 8):
        d.polygon(P([(x - 14, 372), (x + 14, 372), (x, 398)]), fill=(255, 255, 255, 255))
    return img.resize((size, size), Image.LANCZOS)


def main():
    joy = Image.open(ICONS + "gnu_icon.png").convert("RGBA")
    tile("tile_gnu_col.png", (255, 190, 70), (240, 120, 20), joy, "tile_gnu_col.png")
    glitch = draw_glitch(512)
    tile("tile_nolok_col.jpg", (62, 28, 110), (20, 10, 44), glitch, "tile_nolok_col.jpg", is_jpg=True)
    glitch.resize((256, 256), Image.LANCZOS).save(ICONS + "nolokicon.png")
    print("tiles written")


if __name__ == "__main__":
    main()
