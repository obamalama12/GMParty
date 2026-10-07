#!/usr/bin/env python3
"""Synthesises the dice sounds (rattle, landing thud, little chime) into assets/sounds/dice.

    python tools/ui_builder/make_dice_sounds.py assets/sounds/dice

Needs numpy. Everything is generated from noise and sine waves, so there is nothing to license.
"""
import os
import sys
import wave

import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/sounds/dice"
os.makedirs(OUT, exist_ok=True)
SR = 44100
rng = np.random.default_rng(64)


def save(name, data):
    data = np.clip(data, -1, 1)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype("<i2").tobytes())
    print("wrote", name, round(len(data) / SR, 2), "s")


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


def click(length=0.03, pitch=1800.0, gain=1.0):
    t = t_axis(length)
    env = np.exp(-t * 170)
    noise = rng.uniform(-1, 1, len(t))
    # crude band pass: difference of a smoothed noise copy
    k = 6
    smooth = np.convolve(noise, np.ones(k) / k, mode="same")
    body = (noise - smooth) * env
    ping = np.sin(2 * np.pi * pitch * t) * np.exp(-t * 260) * 0.7
    return (body * 0.9 + ping) * gain


# rattle: clicks that get further apart as the dice slows down, ending when it lands (about 1.05 s)
rattle = np.zeros(int(SR * 1.15))
t, gap = 0.0, 0.03
while t < 1.05:
    c = click(pitch=rng.uniform(1300, 2600), gain=rng.uniform(0.45, 1.0) * (1.0 - 0.45 * t))
    i = int(t * SR)
    rattle[i:i + len(c)] += c[:len(rattle) - i]
    t += gap * rng.uniform(0.8, 1.3)
    gap *= 1.075
rattle *= 0.7
save("dice_rattle.wav", rattle)

# landing: a low thump with a short clack on top
tt = t_axis(0.42)
freq = 55 + 130 * np.exp(-tt * 22)
thump = np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-tt * 11)
clack = np.concatenate([click(0.05, 1500, 1.2), np.zeros(len(tt) - int(0.05 * SR))])
save("dice_land.wav", thump * 0.9 + clack * 0.55)

# little chime when the number is shown
tc = t_axis(0.7)
chime = (np.sin(2 * np.pi * 988 * tc) + 0.6 * np.sin(2 * np.pi * 1480 * tc) + 0.3 * np.sin(2 * np.pi * 1976 * tc)) * np.exp(-tc * 6)
chime[: int(0.004 * SR)] *= np.linspace(0, 1, int(0.004 * SR))
save("dice_chime.wav", chime * 0.35)
