#!/usr/bin/env python3
"""Synthesises the sounds of the "your turn" banner and the minigame rounds into assets/sounds/ui.

    python tools/ui_builder/make_turn_sound.py

turn_start.wav: a rising whoosh and a two-note chime. round_win.wav: a short three-note fanfare. Needs numpy.
"""
import os
import wave

import numpy as np

OUT = "assets/sounds/ui"
SR = 44100
rng = np.random.default_rng(7)


def save(name, data):
    data = np.clip(data / max(1e-6, np.max(np.abs(data))) * 0.8, -1, 1)
    with wave.open(os.path.join(OUT, name), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype("<i2").tobytes())
    print("wrote", name, round(len(data) / SR, 2), "s")


def note(freq, dur, vol=1.0, kind="tri"):
    t = np.arange(int(dur * SR)) / SR
    ph = (t * freq) % 1.0
    w = (4 * np.abs(ph - 0.5) - 1) if kind == "tri" else np.where(ph < 0.25, 1.0, -1.0)
    return w * np.exp(-t * 6.0) * vol * np.minimum(1.0, t * 400)


def at(buf, sound, start):
    s = int(start * SR)
    buf[s:s + len(sound)] += sound[:len(buf) - s]


def turn_start():
    buf = np.zeros(int(0.9 * SR))
    n = int(0.28 * SR)
    t = np.arange(n) / SR
    sweep = rng.uniform(-1, 1, n) * np.sin(np.pi * t / 0.28) ** 2 * 0.35
    # a crude low-pass that opens up: the noise gets brighter towards the end
    k = np.cumsum(sweep)
    sweep = sweep * 0.5 + (k - np.roll(k, 40)) / 40.0 * 0.8
    at(buf, sweep, 0.0)
    at(buf, note(659.3, 0.5, 0.7), 0.16)       # E5
    at(buf, note(987.8, 0.6, 0.8), 0.30)       # B5
    return buf


def round_win():
    buf = np.zeros(int(0.9 * SR))
    for i, f in enumerate([523.3, 659.3, 784.0]):
        at(buf, note(f, 0.4, 0.8, "sq"), 0.1 * i)
    at(buf, note(1046.5, 0.5, 0.8, "sq"), 0.3)
    return buf


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    save("turn_start.wav", turn_start())
    save("round_win.wav", round_win())
