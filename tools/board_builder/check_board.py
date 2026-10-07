#!/usr/bin/env python3
"""Checks the layout written by layout.py.

    python tools/board_builder/check_board.py <layout dir>

Reports spaces whose top surface is hidden by the terrain (clipping), spaces that hover too high,
and scenery that stands on or too close to the path between spaces.
"""
import json
import math
import os
import sys

import numpy as np

d = sys.argv[1]
L = json.load(open(os.path.join(d, "layout.json")))
n, cell, half = L["n"], L["cell"], L["half"]
H = np.fromfile(os.path.join(d, "heights.bin"), dtype="<f4").reshape(n, n)
nodes = {x["name"]: x for x in L["nodes"]}


def mesh_height(x, z):
    """Height of the terrain mesh (two triangles per cell, diagonal from (ix+1, iz) to (ix, iz+1))."""
    fx, fz = (x + half) / cell, (z + half) / cell
    ix = int(min(max(math.floor(fx), 0), n - 2))
    iz = int(min(max(math.floor(fz), 0), n - 2))
    tx, tz = fx - ix, fz - iz
    a, b, c, e = H[iz, ix], H[iz, ix + 1], H[iz + 1, ix], H[iz + 1, ix + 1]
    if tx + tz <= 1.0:      # triangle a, b, c
        return float(a + (b - a) * tx + (c - a) * tz)
    return float(e + (c - e) * (1 - tx) + (b - e) * (1 - tz))


def footprint(x, z):
    pts = [(x, z)]
    for r in (0.35, 0.7, 1.0):
        for i in range(24):
            a = 2 * math.pi * i / 24
            pts.append((x + r * math.cos(a), z + r * math.sin(a)))
    for gx in range(math.floor(x - 1.0), math.ceil(x + 1.0) + 1):      # the terrain peaks at grid vertices
        for gz in range(math.floor(z - 1.0), math.ceil(z + 1.0) + 1):
            if math.hypot(gx - x, gz - z) <= 1.0:
                pts.append((gx, gz))
    return pts


bad_clip, bad_float = [], []
for nd in L["nodes"]:
    if nd["hidden"] or nd["bridge"]:
        continue
    x, y, z = nd["pos"]
    normal = np.array(nd.get("normal", [0, 1, 0]))
    worst = -9
    low = 9
    for px, pz in footprint(x, z):
        # height of the space's top surface above this point
        top = y - (normal[0] * (px - x) + normal[2] * (pz - z)) / max(normal[1], 1e-6)
        gap = top - mesh_height(px, pz)
        worst = max(worst, -gap)
        low = min(low, gap)
    if worst > -0.01:
        bad_clip.append((nd["name"], round(worst, 2)))
    if low > 0.35:
        bad_float.append((nd["name"], round(low, 2)))
print("spaces clipped by terrain: %d %s" % (len(bad_clip), bad_clip[:12]))
print("spaces hovering > 0.35 m above the ground: %d %s" % (len(bad_float), bad_float[:12]))

# path segments between linked spaces
segs = []
for nd in L["nodes"]:
    for nx in nd["next"]:
        a, b = nd["pos"], nodes[nx]["pos"]
        segs.append((a[0], a[2], b[0], b[2]))
segs = np.array(segs)


def dist_to_path(x, z):
    ax, az, bx, bz = segs[:, 0], segs[:, 1], segs[:, 2], segs[:, 3]
    dx, dz = bx - ax, bz - az
    t = np.clip(((x - ax) * dx + (z - az) * dz) / np.maximum(dx * dx + dz * dz, 1e-9), 0, 1)
    return float(np.min(np.hypot(ax + t * dx - x, az + t * dz - z)))


MIN_CLEAR = float(os.environ.get("MIN_CLEAR", "2.4"))
RADIUS = {"Lantern": 0.3, "Signpost": 0.6, "Hay": 1.2, "Tombstone": 0.6, "Cross": 0.6, "Snowman": 0.8, "Umbrella": 1.2,
          "Stall": 1.8, "Flag": 0.6, "Arch": 0.0, "Portal": 1.6, "Campfire": 1.2, "Statue": 1.4, "Well": 1.8,
          "Cottage": 3.4, "Barn": 5.0, "Windmill": 3.0, "Dock": 1.4, "Lighthouse": 2.8, "Castle": 8.0, "Cave": 4.5,
          "Crypt": 3.0, "BeachHut": 2.4, "Igloo": 2.6, "Tent": 2.2, "Fountain": 9.0, "TownHall": 12.0, "BoatProp": 1.5}
too_close = {}
for lm in L["landmarks"]:
    x, _, z = lm["pos"]
    r = RADIUS.get(lm["kind"], 1.5) * lm.get("scale", 1.0)
    dist = dist_to_path(x, z) - r
    if lm["kind"] == "Arch":
        continue
    if dist < MIN_CLEAR - 1.0 and not (lm["kind"] in ("Lantern", "Signpost", "Flag") and dist > 0.6):
        too_close.setdefault(lm["kind"], []).append((round(x), round(z), round(dist, 1)))
print("landmarks too close to the path:", {k: len(v) for k, v in too_close.items()}, too_close)
sc = {}
for kind, items in L["scatter"].items():
    size = 0.35 if kind.startswith(("Grass", "Plant", "Flower", "Petals")) else 0.8 if kind.startswith(("Bush", "Rock")) else 1.0
    for it in items:
        x, z = it[0], it[2]
        sc_ = it[4] if len(it) > 4 else 1.0
        dist = dist_to_path(x, z) - size * sc_
        limit = 0.9 if kind.startswith(("Grass", "Plant", "Flower", "Petals")) else 1.8
        if dist < limit:
            sc.setdefault(kind, []).append((round(x), round(z), round(dist, 1)))
print("scatter too close to the path:", {k: len(v) for k, v in sc.items()})
