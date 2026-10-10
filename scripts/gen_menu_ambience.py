#!/usr/bin/env python3
# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of PointBlank Swarm (GPLv3; see LICENSE).
"""Regenerates godot/assets/audio/amb.menu.wav: a plain sea-and-wind ambience loop for the
pregame menu. Fully synthesized (no third-party samples), gentle, distant; seamless 46 s loop, mono 22.05 kHz.
Usage: python3 scripts/gen_menu_ambience.py   (requires numpy)"""
import numpy as np, wave, pathlib

OUT = pathlib.Path(__file__).resolve().parent.parent / "godot" / "assets" / "audio" / "amb.menu.wav"
sr = 22050
dur = 48.0
n = int(sr * dur)
rng = np.random.default_rng(7)

brown = np.cumsum(rng.standard_normal(n)); brown /= np.max(np.abs(brown))

def lowpass(x, alpha):
    y = np.empty_like(x); acc = 0.0
    for i in range(len(x)):
        acc += alpha * (x[i] - acc); y[i] = acc
    return y

t = np.arange(n) / sr
sea = lowpass(brown, 0.035)
sea *= 0.75 + 0.25 * (0.6 * np.sin(2 * np.pi * 0.035 * t) + 0.4 * np.sin(2 * np.pi * 0.021 * t + 1.7))
white = rng.standard_normal(n)
wind = lowpass(white, 0.12) - lowpass(white, 0.04)
wind *= (0.35 + 0.65 * np.clip(0.5 + 0.5 * np.sin(2 * np.pi * 0.023 * t + 0.9) + 0.25 * np.sin(2 * np.pi * 0.011 * t), 0, 1)) * 0.3

mix = sea * 0.85 + wind * 0.22
xf = int(2.0 * sr)
fade = np.linspace(0, 1, xf)
mix[:xf] = mix[:xf] * fade + mix[-xf:] * (1 - fade)
mix = mix[:n - xf]
mix = (mix / np.max(np.abs(mix)) * 0.38 * 32767).astype(np.int16)

with wave.open(str(OUT), "w") as w:
    w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
    w.writeframes(mix.tobytes())
print("wrote", OUT, len(mix) / sr, "s")
