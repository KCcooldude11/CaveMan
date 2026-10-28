#!/usr/bin/env python3
"""Generates the placeholder sound effects (16-bit mono WAV) into assets/sounds.

    python3 tools/gen_sounds.py

Synthesised so the game has feedback today; replace any file with a real
recording of the same name later.
"""
import os
import wave
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sounds")
RATE = 22050
rng = np.random.default_rng(7)


def write(name, samples):
    samples = np.clip(samples, -1, 1)
    data = (samples * 32767 * 0.8).astype(np.int16)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(data.tobytes())


def t(seconds):
    return np.arange(int(RATE * seconds)) / RATE


def clang(pitch=1.0, length=0.9):
    x = t(length)
    partials = [(523, 1.0, 6), (1247, 0.6, 9), (1890, 0.45, 12), (2711, 0.3, 15), (3580, 0.2, 20)]
    s = sum(a * np.sin(2 * np.pi * f * pitch * x) * np.exp(-d * x) for f, a, d in partials)
    s += rng.normal(0, 1, len(x)) * np.exp(-60 * x) * 0.8  # strike noise
    return s / 2.2


def thud():
    x = t(0.25)
    s = np.sin(2 * np.pi * 90 * x) * np.exp(-18 * x) + rng.normal(0, 1, len(x)) * np.exp(-40 * x) * 0.3
    return s


def coin():
    x = t(0.35)
    a = np.sin(2 * np.pi * 1975 * x) * np.exp(-10 * x)
    b = np.sin(2 * np.pi * 2637 * x) * np.exp(-10 * x)
    s = np.concatenate([a[: int(RATE * 0.08)], b])
    return s * 0.6


def fanfare():
    notes = [523, 659, 784, 1047]
    out = []
    for i, f in enumerate(notes):
        x = t(0.16 if i < 3 else 0.6)
        tone = np.sign(np.sin(2 * np.pi * f * x)) * 0.25 + np.sin(2 * np.pi * f * 2 * x) * 0.15
        out.append(tone * np.exp(-(2 if i == 3 else 6) * x))
    return np.concatenate(out)


def whoosh():
    x = t(0.18)
    n = rng.normal(0, 1, len(x))
    n = np.convolve(n, np.ones(8) / 8, mode="same")
    return n * np.sin(np.pi * x / x[-1]) * 0.6


def main():
    os.makedirs(OUT, exist_ok=True)
    write("anvil_perfect", clang(1.0))
    write("anvil_good", clang(0.92, 0.6) * 0.8)
    write("anvil_miss", thud())
    write("coin", coin())
    write("fanfare", fanfare())
    write("whoosh", whoosh())
    print("sounds written to", OUT)


if __name__ == "__main__":
    main()
