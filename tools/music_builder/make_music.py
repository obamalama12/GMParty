#!/usr/bin/env python3
"""Synthesises the original chiptune tracks of the game (pulse, triangle and noise channels) and encodes them to ogg.

    python tools/music_builder/make_music.py [track ...]        # default: all tracks

Writes assets/music/retro/<name>.ogg (needs numpy and ffmpeg). Everything is generated from the track tables below,
so the music is original work of this project. Run tools/first_import.py afterwards so Godot imports the files.
"""
import os
import subprocess
import sys
import tempfile
import wave

import numpy as np

SR = 32000
OUT = "assets/music/retro"

MAJOR = [0, 2, 4, 5, 7, 9, 11]
MINOR = [0, 2, 3, 5, 7, 8, 10]


def mid2f(m):
    return 440.0 * 2 ** ((m - 69) / 12.0)


class Track:
    def __init__(self, name, bpm, root, scale, prog, seed, style, duty=0.25, lead_oct=1, swing=0.0):
        self.name, self.bpm, self.root, self.scale, self.prog = name, bpm, root, scale, prog
        self.seed, self.style, self.duty, self.lead_oct, self.swing = seed, style, duty, lead_oct, swing
        self.beat = 60.0 / bpm


def degree_note(t, deg, octave=0):
    """MIDI note of scale degree `deg` (0 based, may exceed the scale)."""
    o, d = divmod(deg, 7)
    return t.root + t.scale[d] + 12 * (o + octave)


def chord_tones(t, root_deg):
    return [degree_note(t, root_deg + k) for k in (0, 2, 4)]


# ---------- voices ----------

def pulse(freq, n, duty):
    ph = (np.arange(n) * freq / SR) % 1.0
    return np.where(ph < duty, 1.0, -1.0)


def tri(freq, n):
    ph = (np.arange(n) * freq / SR) % 1.0
    return 4.0 * np.abs(ph - 0.5) - 1.0


def env(n, attack=0.004, release=0.05, decay=0.0):
    e = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, min(n, int(release * SR)))
    e[:a] = np.linspace(0, 1, min(a, n))
    e[n - r:] *= np.linspace(1, 0, r)
    if decay > 0:
        e *= np.exp(-np.arange(n) / SR / decay)
    return e


def render(t, notes, total_beats, kind):
    """notes: (start_beat, dur_beats, midi, volume)."""
    buf = np.zeros(int((total_beats * t.beat + 1.0) * SR))
    for start, dur, midi, vol in notes:
        n = int(dur * t.beat * SR)
        if n < 8:
            continue
        f = mid2f(midi)
        if kind == "lead":
            w = pulse(f, n, t.duty)
            # light vibrato on long notes
            if dur >= 1.0:
                vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * np.arange(n) / SR)
                ph = np.cumsum(f * vib) / SR % 1.0
                w = np.where(ph < t.duty, 1.0, -1.0)
            w = w * env(n, 0.005, 0.06, decay=0.9 if dur < 1 else 0.0)
        elif kind == "arp":
            w = pulse(f, n, 0.125) * env(n, 0.002, 0.03, decay=0.18)
        elif kind == "bass":
            w = tri(f, n) * env(n, 0.003, 0.04)
        s = int(start * t.beat * SR)
        buf[s:s + n] += w * vol
    return buf


def drums(t, bars, pattern):
    total = int(bars * 4 * t.beat * SR + SR)
    buf = np.zeros(total)
    rng = np.random.RandomState(t.seed + 99)
    for bar in range(bars):
        for step in range(16):
            hit = pattern(bar, step)
            if not hit:
                continue
            start = int((bar * 4 + step * 0.25 + (t.swing * 0.25 if step % 2 else 0)) * t.beat * SR)
            for h in hit:
                if h == "k":
                    n = int(0.16 * SR)
                    tt = np.arange(n) / SR
                    f = 140 * np.exp(-tt * 28) + 45
                    w = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt * 18) * 0.95
                elif h == "s":
                    n = int(0.14 * SR)
                    tt = np.arange(n) / SR
                    w = (rng.uniform(-1, 1, n) * 0.6 + np.sin(2 * np.pi * 190 * tt) * 0.4) * np.exp(-tt * 26) * 0.8
                elif h == "h":
                    n = int(0.045 * SR)
                    tt = np.arange(n) / SR
                    w = rng.uniform(-1, 1, n) * np.exp(-tt * 90) * 0.38
                elif h == "o":
                    n = int(0.12 * SR)
                    tt = np.arange(n) / SR
                    w = rng.uniform(-1, 1, n) * np.exp(-tt * 28) * 0.34
                else:
                    continue
                buf[start:start + n] += w
    return buf


# ---------- composing ----------

LEAD_RHYTHMS = [
    [(0, 1), (1, 1), (2, 1), (3, 1)],
    [(0, 1.5), (1.5, 0.5), (2, 1), (3, 1)],
    [(0, 0.5), (0.5, 0.5), (1, 1), (2, 0.5), (2.5, 0.5), (3, 1)],
    [(0, 2), (2, 1), (3, 1)],
    [(0, 0.5), (0.5, 0.5), (1, 0.5), (1.5, 0.5), (2, 1), (3, 1)],
    [(0, 1), (1, 0.5), (1.5, 0.5), (2, 0.5), (2.5, 0.5), (3, 1)],
    [(0, 0.75), (0.75, 0.75), (1.5, 0.5), (2, 2)],
]


def compose(t, bars=32):
    rng = np.random.RandomState(t.seed)
    lead, arp, bass = [], [], []
    prog = t.prog
    # four 8-bar sections: A, B, A (varied), C ; each section walks the progression twice
    motifs = {}
    for sec in range(4):
        if sec == 2:
            motifs[sec] = motifs[0]
        else:
            motifs[sec] = [rng.randint(0, len(LEAD_RHYTHMS)) for _ in range(len(prog))]
    for bar in range(bars):
        sec = bar // 8
        chord_deg = prog[bar % len(prog)]
        tones = chord_tones(t, chord_deg)
        b0 = bar * 4
        # --- bass
        if t.style == "oompah":
            for k in range(4):
                midi = degree_note(t, chord_deg, -2) if k % 2 == 0 else degree_note(t, chord_deg + 4, -2)
                bass.append((b0 + k, 0.45, midi, 0.55))
        elif t.style == "march":
            for k in range(4):
                midi = degree_note(t, chord_deg, -2)
                bass.append((b0 + k, 0.7, midi if k % 2 == 0 else midi + 12, 0.55))
        else:
            for k in range(8):
                midi = degree_note(t, chord_deg, -2) if k not in (3, 6) else degree_note(t, chord_deg + 4, -2)
                bass.append((b0 + k * 0.5, 0.45, midi, 0.55))
        # --- arpeggio (starts in section B, always in C)
        if sec in (1, 3) or (sec == 2 and bar % 2 == 0):
            for k in range(8):
                arp.append((b0 + k * 0.5, 0.4, tones[(k % 3)] + 12 * (1 + (k // 3 % 2)), 0.16))
        elif sec == 0 and bar >= 4:
            for k in range(4):
                arp.append((b0 + k, 0.8, tones[k % 3] + 12, 0.14))
        # --- lead melody (silent for the first 2 bars: intro)
        if bar < 2:
            continue
        rhythm = LEAD_RHYTHMS[motifs[sec][bar % len(prog)]]
        if sec == 3:
            rhythm = LEAD_RHYTHMS[(motifs[sec][bar % len(prog)] + 2) % len(LEAD_RHYTHMS)]
        pos = chord_deg + rng.choice([2, 4, 7])
        for i, (st, du) in enumerate(rhythm):
            if i == 0 or rng.rand() < 0.35:
                pos = chord_deg + int(rng.choice([0, 2, 4, 7, 9]))
            else:
                pos += int(rng.choice([-2, -1, 1, 1, 2]))
            pos = int(np.clip(pos, chord_deg - 1, chord_deg + 10))
            midi = degree_note(t, pos, t.lead_oct)
            if i == len(rhythm) - 1 and bar % len(prog) == len(prog) - 1:
                midi = degree_note(t, 0 if sec % 2 == 0 else 4, t.lead_oct)   # lean towards home
            lead.append((b0 + st, du * 0.92, midi, 0.30))
    return lead, arp, bass


def drum_pattern(style):
    def rock(bar, step):
        hit = []
        if step in (0, 8) or (step == 10 and bar % 2):
            hit.append("k")
        if step in (4, 12):
            hit.append("s")
        if step % 2 == 0:
            hit.append("h")
        if bar % 8 == 7 and step >= 12:
            hit.append("s")
        return hit

    def drive(bar, step):
        hit = []
        if step % 4 == 0:
            hit.append("k")
        if step in (4, 12):
            hit.append("s")
        if step % 2 == 0:
            hit.append("h")
        if step % 4 == 2:
            hit.append("o")
        if bar % 8 == 7 and step >= 8:
            hit.append("s")
        return hit

    def march(bar, step):
        hit = []
        if step in (0, 8):
            hit.append("k")
        if step in (4, 12, 14, 15):
            hit.append("s")
        if step % 4 == 2:
            hit.append("h")
        return hit

    def oompah(bar, step):
        hit = []
        if step in (0, 8):
            hit.append("k")
        if step in (4, 12):
            hit.append("s")
        if step % 4 == 2:
            hit.append("h")
        return hit

    return {"rock": rock, "drive": drive, "march": march, "oompah": oompah}[style]


TRACKS = [
    # name, bpm, root (midi), scale, chord roots (scale degrees), seed, bass style, lead duty, lead octave, swing, drum style
    (Track("valley_stroll", 112, 60, MAJOR, [0, 5, 3, 4, 0, 5, 1, 4], 11, "walk", duty=0.5, lead_oct=1, swing=0.1), "rock"),
    (Track("cookie_rush", 156, 55, MAJOR, [0, 4, 5, 3], 23, "walk", duty=0.25, lead_oct=1), "drive"),
    (Track("volcano_panic", 168, 50, MINOR, [0, 5, 2, 6, 0, 5, 3, 4], 37, "walk", duty=0.125, lead_oct=1), "drive"),
    (Track("big_top", 144, 53, MAJOR, [0, 3, 0, 4, 0, 3, 4, 0], 41, "oompah", duty=0.5, lead_oct=1), "oompah"),
    (Track("tug_march", 128, 51, MAJOR, [0, 0, 3, 4, 0, 5, 3, 4], 53, "march", duty=0.25, lead_oct=1), "march"),
    (Track("disco_floor", 132, 57, MAJOR, [0, 3, 4, 3, 0, 5, 3, 4], 79, "walk", duty=0.5, lead_oct=1, swing=0.12), "drive"),
    (Track("press_start", 124, 64, MAJOR, [0, 4, 5, 3, 0, 4, 3, 4], 67, "walk", duty=0.25, lead_oct=1, swing=0.08), "rock"),
]


def build(track, drum_style, bars=32):
    lead, arp, bass = compose(track, bars)
    total_beats = bars * 4
    mix = render(track, lead, total_beats, "lead") + render(track, arp, total_beats, "arp") + render(track, bass, total_beats, "bass")
    d = drums(track, bars, drum_pattern(drum_style))
    n = max(len(mix), len(d))
    out = np.zeros(n)
    out[:len(mix)] += mix
    out[:len(d)] += d * 0.9
    loop_len = int(total_beats * track.beat * SR)
    # fold the tail of the last notes onto the start so the loop is seamless
    tail = out[loop_len:]
    out = out[:loop_len].copy()
    out[:len(tail)] += tail[:loop_len]
    # soft clip and normalise
    out = np.tanh(out * 1.1)
    out = out / max(1e-6, np.max(np.abs(out))) * 0.55
    # a little stereo width: the arpeggio-heavy high end is delayed slightly on the right channel
    delay = int(0.012 * SR)
    left = out
    right = np.roll(out, delay) * 0.97
    return np.stack([left, right], axis=1)


def write_ogg(name, stereo):
    os.makedirs(OUT, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        wav_path = os.path.join(tmp, name + ".wav")
        data = (np.clip(stereo, -1, 1) * 32767).astype("<i2")
        with wave.open(wav_path, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes(data.tobytes())
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav_path, "-c:a", "libvorbis", "-q:a", "4",
                        os.path.join(OUT, name + ".ogg")], check=True)


def main():
    wanted = set(sys.argv[1:])
    for track, drum_style in TRACKS:
        if wanted and track.name not in wanted:
            continue
        stereo = build(track, drum_style)
        write_ogg(track.name, stereo)
        print("wrote", track.name, "%.1f s" % (len(stereo) / SR))


if __name__ == "__main__":
    main()
