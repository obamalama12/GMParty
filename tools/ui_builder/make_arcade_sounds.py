#!/usr/bin/env python3
"""Synthesises the sounds of the arcade minigames (explosion, pass blip, thud) into assets/sounds/arcade.

    python tools/ui_builder/make_arcade_sounds.py assets/sounds/arcade
"""
import os
import sys
import wave

import numpy as np

OUT = sys.argv[1] if len(sys.argv) > 1 else "assets/sounds/arcade"
os.makedirs(OUT, exist_ok=True)
SR = 44100
rng = np.random.default_rng(7)


def save(name, data):
    data = np.clip(data, -1, 1)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype("<i2").tobytes())
    print("wrote", name)


def t_axis(sec):
    return np.arange(int(SR * sec)) / SR


t = t_axis(0.9)
noise = rng.uniform(-1, 1, len(t))
rumble = np.convolve(noise, np.ones(40) / 40, mode="same") * np.exp(-t * 4.0)
thump = np.sin(2 * np.pi * np.cumsum(40 + 120 * np.exp(-t * 14)) / SR) * np.exp(-t * 5.5)
crack = noise * np.exp(-t * 40)
save("boom.wav", rumble * 1.6 + thump * 0.9 + crack * 0.5)

t = t_axis(0.2)
sweep = np.sin(2 * np.pi * np.cumsum(500 + 1400 * (t / 0.2)) / SR) * np.exp(-t * 14) * 0.5
save("pass.wav", sweep)

t = t_axis(0.3)
body = np.sin(2 * np.pi * np.cumsum(50 + 140 * np.exp(-t * 25)) / SR) * np.exp(-t * 12)
save("thud.wav", body * 0.95 + rng.uniform(-1, 1, len(t)) * np.exp(-t * 90) * 0.35)
