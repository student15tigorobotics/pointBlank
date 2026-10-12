#!/usr/bin/env python3
# Copyright (C) 2026 tigo.robotics@gmail.com
# This file is part of Picket Line.
#
# Picket Line is free software: you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# It is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; see the
# GNU General Public License for more details. See the LICENSE file in the repository root.
"""
Synthesises the music loops and sound effects for Picket Line with numpy, then encodes each
one to Ogg Vorbis with ffmpeg (libvorbis).

Everything is generated from fixed seeds, so a run always produces the same PCM. Music is built
on a bar grid and rendered modulo the loop length: notes, reverb tails and echoes wrap around the
end of the loop, so the last sample joins the first without a seam. Effects that modulate over
time (filter sweeps, tension ramps) are periodic over the loop for the same reason.

Usage, from the repository root:
    python3 picket-line/scripts/gen_audio.py [--out DIR]
"""

import argparse
import math
import pathlib
import shutil
import subprocess
import sys
import zlib

import numpy as np

SR = 44100
TWO_PI = 2.0 * math.pi
TBL = 4096                # wavetable length, one cycle
MAX_HARM_HZ = 8000.0      # additive oscillators keep every harmonic below this frequency
CHUNK_MAX = 256           # longest block for the one-pole filter recursion
ROOT = pathlib.Path(__file__).resolve().parents[1]
DEFAULT_OUT = ROOT / "assets" / "audio"


# ------------------------------------------------------------------ basics

def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def rng_for(name):
    return np.random.default_rng(zlib.crc32(name.encode("utf-8")))


def _n(sec):
    return max(1, int(round(sec * SR)))


def _t(n):
    return np.arange(n, dtype=np.float64) / SR


def _place(buf, sig, t0):
    """Add a mono signal into a mono buffer starting at t0 seconds (clipped to the buffer)."""
    s = int(round(t0 * SR))
    if s >= buf.shape[0]:
        return
    m = min(sig.shape[0], buf.shape[0] - s)
    buf[s:s + m] += sig[:m]


def _fade(x, fin=0.002, fout=0.004):
    n = x.shape[0]
    ni = min(n, int(fin * SR))
    no = min(n, int(fout * SR))
    if ni > 0:
        x[:ni] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(ni) / ni)
    if no > 0:
        x[n - no:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(no) / no)
    return x


def adsr(dur, attack, rel):
    """Raised-cosine attack, sustain for dur seconds, raised-cosine release of rel seconds."""
    n = _n(dur + rel)
    t = _t(n)
    a = np.clip(t / max(attack, 1e-4), 0.0, 1.0)
    a = 0.5 - 0.5 * np.cos(np.pi * a)
    r = np.clip((t - dur) / max(rel, 1e-4), 0.0, 1.0)
    r = 0.5 + 0.5 * np.cos(np.pi * r)
    return a * r


# ------------------------------------------------------- wavetables and filters

_TABLES = {}


def _table(key, amps):
    """One band-limited cycle from harmonic sine amplitudes amps[k-1] (k = 1..len)."""
    if key in _TABLES:
        return _TABLES[key]
    spec = np.zeros(TBL // 2 + 1, dtype=np.complex128)
    m = min(len(amps), TBL // 2 - 1)
    # irfft of -i*a*N/2 gives a sum of a*sin(k*theta)
    spec[1:m + 1] = -1j * np.asarray(amps[:m], dtype=np.float64) * (TBL / 2)
    tbl = np.fft.irfft(spec, n=TBL)
    peak = float(np.max(np.abs(tbl)))
    if peak > 0:
        tbl = tbl / peak
    tbl = np.concatenate([tbl, tbl[:1]])
    _TABLES[key] = tbl
    return tbl


def wavetable(f0, shape="saw", p=1.0):
    kmax = int(max(1, min(MAX_HARM_HZ // f0, TBL // 2 - 2)))
    k = np.arange(1, kmax + 1, dtype=np.float64)
    if shape == "saw":
        amps = k ** (-p)
    elif shape == "square":
        amps = np.where(k % 2 == 1, k ** (-p), 0.0)
    elif shape == "tri":
        sign = np.where(((k - 1) // 2) % 2 == 0, 1.0, -1.0)
        amps = np.where(k % 2 == 1, sign * k ** (-2.0), 0.0)
    else:
        amps = np.ones(1)
    return _table((round(f0, 2), shape, p), amps)


def wt_read(tbl, cycles):
    """Linear-interpolated table read; cycles is the running phase in cycles (any float array)."""
    pos = (cycles - np.floor(cycles)) * TBL
    i0 = np.minimum(pos.astype(np.int64), TBL - 1)
    fr = pos - i0
    return tbl[i0] * (1.0 - fr) + tbl[i0 + 1] * fr


def osc(f, t, shape="saw", p=1.0, phase=0.0):
    """Band-limited oscillator at constant frequency f over time axis t (seconds)."""
    return wt_read(wavetable(f, shape, p), phase + t * f)


def lp1(x, fc):
    """One-pole lowpass y[n] = y[n-1] + a (x[n] - y[n-1]), fc in Hz (scalar or per-sample array).

    Exact recursion evaluated in blocks with a closed form. Works on (n,) or (n, channels)."""
    x = np.asarray(x, dtype=np.float64)
    n = x.shape[0]
    fca = np.broadcast_to(np.asarray(fc, dtype=np.float64), (n,))
    y = np.empty_like(x)
    state = np.zeros(x.shape[1:])
    s = 0
    while s < n:
        f = min(max(float(fca[s]), 5.0), 0.45 * SR)
        a = 1.0 - math.exp(-TWO_PI * f / SR)
        b = 1.0 - a
        lb = math.log(b)
        m = int(min(n - s, CHUNK_MAX, max(1.0, 18.0 / -lb)))
        pw = np.exp(np.arange(m, dtype=np.float64) * lb)
        if x.ndim > 1:
            pw = pw[:, None]
        yy = pw * (b * state + a * np.cumsum(x[s:s + m] / pw, axis=0))
        y[s:s + m] = yy
        state = yy[-1]
        s += m
    return y


def hp1(x, fc):
    x = np.asarray(x, dtype=np.float64)
    return x - lp1(x, fc)


# ------------------------------------------------------------------ instruments

def _pad_stack(freq, t, detunes, p, spread):
    """Detuned band-limited saws spread across the stereo field. Returns (n, 2)."""
    out = np.zeros((t.shape[0], 2))
    k = len(detunes)
    for i, c in enumerate(detunes):
        f = freq * 2.0 ** (c / 1200.0)
        x = osc(f, t, "saw", p, phase=0.37 * i) / k
        pan = spread * (2.0 * i / max(1, k - 1) - 1.0)
        th = (pan + 1.0) * math.pi / 4.0
        out[:, 0] += x * math.cos(th)
        out[:, 1] += x * math.sin(th)
    return out


def pad_note(freq, dur, attack, rel, detunes=(-9.0, -3.0, 3.0, 9.0), p=1.4, spread=0.7):
    env = adsr(dur, attack, rel)
    return _pad_stack(freq, _t(env.shape[0]), detunes, p, spread) * env[:, None]


def supersaw_note(freq, dur, rel=0.1, attack=0.004, cents=10.0):
    env = adsr(dur, attack, rel)
    detunes = (-cents, -0.5 * cents, 0.0, 0.5 * cents, cents)
    return _pad_stack(freq, _t(env.shape[0]), detunes, 1.0, 0.9) * env[:, None]


def brass_note(freq, dur, rel=0.1, attack=0.02):
    """Saw with a filter-style brightness opening: dark spectrum at onset, bright after."""
    env = adsr(dur, attack, rel)
    t = _t(env.shape[0])
    w = 1.0 - np.exp(-t / 0.06)
    dark = wt_read(wavetable(freq, "saw", 2.2), t * freq)
    bright = wt_read(wavetable(freq, "saw", 0.9), t * freq)
    return ((1.0 - w) * dark + w * bright) * env * 0.6


def saw_note(freq, dur, rel=0.1, attack=0.02, p=1.0):
    env = adsr(dur, attack, rel)
    return osc(freq, _t(env.shape[0]), "saw", p) * env


def sub_note(freq, dur, rel=0.03, attack=0.004):
    env = adsr(dur, attack, rel)
    ph = _t(env.shape[0]) * freq
    return (np.sin(TWO_PI * ph) + 0.12 * np.sin(TWO_PI * 2.0 * ph)) * env


def dist_bass_note(freq, dur, rel=0.04, drive=3.0):
    env = adsr(dur, 0.005, rel)
    t = _t(env.shape[0])
    x = osc(freq, t, "square", 1.0)
    x = np.tanh(drive * x) / math.tanh(drive)
    return (0.8 * x + 0.4 * np.sin(TWO_PI * freq * t)) * env


CHOIR = ((730.0, 90.0, 1.0), (1090.0, 120.0, 0.55), (2440.0, 200.0, 0.22))


def _choir_table(f0):
    kmax = int(max(1, min(MAX_HARM_HZ // f0, TBL // 2 - 2)))
    k = np.arange(1, kmax + 1, dtype=np.float64)
    fk = k * f0
    amp = np.zeros(kmax)
    for centre, width, w in CHOIR:
        amp += w * np.exp(-0.5 * ((fk - centre) / width) ** 2)
    amp = amp / np.sqrt(k) + 0.02 / k
    return _table(("choir", round(f0, 2)), amp)


def choir_note(freq, dur, attack=0.6, rel=1.2):
    env = adsr(dur, attack, rel)
    n = env.shape[0]
    t = _t(n)
    vib = 1.0 + 0.004 * np.sin(TWO_PI * 5.0 * t) * np.clip((t - 0.5) / 1.0, 0.0, 1.0)
    out = np.zeros((n, 2))
    for i, c in enumerate((-6.0, 0.0, 6.0)):
        f = freq * 2.0 ** (c / 1200.0)
        cyc = np.cumsum(f * vib) / SR + 0.31 * i
        x = wt_read(_choir_table(f), cyc) / 3.0
        th = ((i - 1) * 0.5 + 1.0) * math.pi / 4.0
        out[:, 0] += x * math.cos(th)
        out[:, 1] += x * math.sin(th)
    return out * env[:, None]


BELL = ((1.0, 1.0, 1.1), (2.0, 0.45, 0.6), (2.76, 0.30, 0.35), (5.40, 0.14, 0.18), (8.93, 0.06, 0.08))


def bell_note(freq, decay=1.0, level=1.0):
    n = _n(3.2 * decay)
    t = _t(n)
    x = np.zeros(n)
    for ratio, amp, tau in BELL:
        f = freq * ratio
        if f < 9000.0:
            x += amp * np.sin(TWO_PI * f * t) * np.exp(-t / (tau * decay))
    return _fade(x * level, 0.0015, 0.1)


KEYS = ((1.0, 1.0, 0.9), (2.0, 0.42, 0.42), (3.0, 0.16, 0.2), (4.0, 0.06, 0.1))


def keys_note(freq, dur, decay=1.0, rel=0.3):
    env = adsr(dur, 0.003, rel)
    t = _t(env.shape[0])
    x = np.zeros(env.shape[0])
    for ratio, amp, tau in KEYS:
        f = freq * ratio
        if f < 9000.0:
            x += amp * np.sin(TWO_PI * f * t) * np.exp(-t / (tau * decay))
    return x * env


def pluck_note(freq, dur, rng, decay=0.9975, rel=0.2):
    """Karplus-Strong string: a noise burst circulating in a delay line with averaging loss."""
    D = max(2, int(round(SR / freq - 0.5)))
    env = adsr(dur, 0.002, rel)
    n = env.shape[0]
    y = np.zeros(n + 1)            # y[0] is the zero sample before the note starts
    y[1:D + 1] = rng.uniform(-1.0, 1.0, D)
    for s in range(D, n, D):       # blocks of D samples only read data from earlier blocks
        e = min(n, s + D)
        y[s + 1:e + 1] = decay * 0.5 * (y[s + 1 - D:e + 1 - D] + y[s - D:e - D])
    return y[1:] * env


# ------------------------------------------------------------------ drum kit

def make_kick():
    n = _n(0.5)
    t = _t(n)
    f = 46.0 + 96.0 * np.exp(-t / 0.035)
    body = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / 0.24)
    click = hp1(rng_for("kick").standard_normal(n), 2500.0) * np.exp(-t / 0.0025)
    x = body + 0.35 * click
    x = np.tanh(1.5 * x) / math.tanh(1.5)
    return _fade(x, 0.0008, 0.01)


def make_snare(name, tail=0.8, length=0.3, level=1.0):
    rng = rng_for(name)
    n = _n(length)
    t = _t(n)
    tone = np.sin(TWO_PI * 190.0 * t) * np.exp(-t / 0.07) + 0.6 * np.sin(TWO_PI * 311.0 * t) * np.exp(-t / 0.045)
    noise = lp1(hp1(rng.standard_normal(n), 1100.0), 8500.0)
    x = 0.5 * tone + tail * noise * np.exp(-t / 0.12)
    return _fade(x * level, 0.0006, 0.01)


def make_hat(name, tau=0.03, length=0.12, fc=7000.0, level=1.0):
    rng = rng_for(name)
    n = _n(length)
    t = _t(n)
    x = hp1(rng.standard_normal(n), fc) * np.exp(-t / tau)
    return _fade(x * level, 0.0005, 0.01)


def make_crash():
    rng = rng_for("crash")
    n = _n(1.6)
    t = _t(n)
    x = hp1(rng.standard_normal(n), 2800.0) * np.exp(-t / 0.55) * 0.8
    for ratio, amp in ((1.0, 1.0), (1.59, 0.5), (2.14, 0.35), (2.92, 0.25)):
        x += 0.12 * amp * np.sin(TWO_PI * 430.0 * ratio * t) * np.exp(-t / 0.4)
    return _fade(x, 0.001, 0.05)


def make_drums():
    return {
        "kick": make_kick(),
        "snare": make_snare("snare"),
        "snare_soft": make_snare("snare_soft", tail=0.5, length=0.2, level=0.55),
        "hat": make_hat("hat", tau=0.025, length=0.1, level=0.9),
        "hat_soft": make_hat("hat_soft", tau=0.02, length=0.07, level=0.6),
        "hat_open": make_hat("hat_open", tau=0.12, length=0.3, fc=6000.0, level=0.7),
        "crash": make_crash(),
    }


# ------------------------------------------------------------------ loop builder

def add_wrapped(buf, sig, start):
    """Add sig into buf at index start, wrapping modulo buf length (sig may exceed one loop)."""
    L = buf.shape[0]
    n = sig.shape[0]
    start %= L
    pos = 0
    while pos < n:
        take = min(n - pos, L - start)
        buf[start:start + take] += sig[pos:pos + take]
        pos += take
        start = 0


class Loop:
    """Collects notes on a bar grid into named stereo groups; every group wraps at the loop end."""

    def __init__(self, name, bpm, bars):
        self.name = name
        self.bpm = bpm
        self.bars = bars
        self.beat_s = 60.0 / bpm
        self.bar_s = 4.0 * self.beat_s
        self.L = int(round(bars * self.bar_s * SR))
        self.rng = rng_for(name)
        self.groups = {}

    def buf(self, group):
        if group not in self.groups:
            self.groups[group] = np.zeros((self.L, 2))
        return self.groups[group]

    def at(self, group, beat, sig, gain=1.0, pan=0.0):
        if sig.ndim == 1:
            th = (pan + 1.0) * math.pi / 4.0
            sig = np.stack([sig * math.cos(th), sig * math.sin(th)], axis=1)
        add_wrapped(self.buf(group), sig * gain, int(round(beat * self.beat_s * SR)))

    def secs(self, beats):
        return beats * self.beat_s

    def t_loop(self):
        return np.arange(self.L, dtype=np.float64) / SR


def loop_filter(x, fc, pre=int(0.5 * SR)):
    """Apply a one-pole lowpass to a loop buffer (L, 2) with a per-sample cutoff of length L.
    The filter is primed with the periodic tail of the loop, so the result is seamless."""
    L = x.shape[0]
    fc = np.broadcast_to(np.asarray(fc, dtype=np.float64), (L,))
    P = min(pre, L)
    xe = np.concatenate([x[L - P:], x], axis=0)
    fe = np.concatenate([fc[L - P:], fc])
    return lp1(xe, fe)[P:]


def _comb(x, D, g):
    """Feedback comb y[n] = x[n] + g y[n-D], evaluated in blocks of D samples."""
    n = x.shape[0]
    y = np.zeros_like(x)
    for s in range(0, n, D):
        e = min(n, s + D)
        if s == 0:
            y[0:e] = x[0:e]
        else:
            y[s:e] = x[s:e] + g * y[s - D:e - D]
    return y


def _allpass(x, D, g):
    """Schroeder allpass y[n] = -g x[n] + x[n-D] + g y[n-D], evaluated in blocks of D samples."""
    n = x.shape[0]
    y = np.zeros_like(x)
    for s in range(0, n, D):
        e = min(n, s + D)
        if s == 0:
            y[0:e] = -g * x[0:e]
        else:
            y[s:e] = -g * x[s:e] + x[s - D:e - D] + g * y[s - D:e - D]
    return y


def loop_reverb(x, room):
    """Parallel combs into series allpasses, one network per channel, circular over the loop."""
    L = x.shape[0]
    P = min(L, int(6 * SR))
    xe = np.concatenate([x[L - P:], x], axis=0)
    out = np.zeros_like(xe)
    for ch in (0, 1):
        spread = 23 * ch
        src = xe[:, ch] * (1.0 - room)
        acc = np.zeros_like(src)
        for D in (1116, 1188, 1277, 1356):
            acc += _comb(src, D + spread, room)
        acc *= 0.25
        for D in (556, 441):
            acc = _allpass(acc, D + spread, 0.5)
        out[:, ch] = acc
    return out[P:]


def loop_echo(x, D, fb):
    """Echo tail only (dry removed): repeats every D samples with feedback fb."""
    L = x.shape[0]
    P = min(L, int(6 * SR))
    xe = np.concatenate([x[L - P:], x], axis=0)
    out = np.zeros_like(xe)
    for ch in (0, 1):
        src = xe[:, ch]
        out[:, ch] = _comb(src, D + 7 * ch, fb) - src
    return out[P:]


def master(x, target_db=-16.0, ceiling=0.75):
    """Remove DC, soft-clip with tanh under a ceiling, and set the RMS to target_db."""
    x = x - x.mean(axis=0, keepdims=True)
    target = 10.0 ** (target_db / 20.0)

    def rms_for(g):
        y = ceiling * np.tanh(g * x / ceiling)
        return math.sqrt(float(np.mean(y * y)))

    lo, hi = math.log(1e-3), math.log(1e3)
    for _ in range(32):
        mid = 0.5 * (lo + hi)
        if rms_for(math.exp(mid)) < target:
            lo = mid
        else:
            hi = mid
    g = math.exp(0.5 * (lo + hi))
    return ceiling * np.tanh(g * x / ceiling)


def finish_track(lb, levels, verb=None, room=0.85, verb_wet=0.3,
                 echo=None, echo_samples=0, echo_fb=0.35, echo_wet=0.2):
    L = lb.L
    out = np.zeros((L, 2))
    for g, gain in levels.items():
        out += gain * lb.buf(g)
    if verb:
        snd = np.zeros((L, 2))
        for g in verb:
            snd += lb.buf(g)
        out += verb_wet * loop_reverb(snd, room)
    if echo:
        snd = np.zeros((L, 2))
        for g in echo:
            snd += lb.buf(g)
        out += echo_wet * loop_echo(snd, echo_samples, echo_fb)
    return master(out)


# ------------------------------------------------------------------ music

def build_menu(kit):
    lb = Loop("music_menu", 72, 20)
    span = 16.0  # beats in a 4-bar cell
    cells = [
        ([57, 60, 64, 69], 45),   # Am
        ([53, 57, 60, 64], 41),   # Fmaj7
        ([50, 53, 57, 60], 38),   # Dm7
        ([52, 55, 59, 64], 40),   # Em
        ([57, 60, 64, 69], 45),   # Am
    ]
    for ci, (voicing, root) in enumerate(cells):
        b0 = ci * span
        dur = lb.secs(span)
        for m in voicing:
            lb.at("pad", b0, pad_note(midi_hz(m), dur, attack=1.6, rel=2.5, p=1.6))
        lb.at("sub", b0, sub_note(midi_hz(root), dur, rel=2.0, attack=0.8), gain=0.9)
        tones = [m + 12 for m in voicing[1:]]
        for bar in range(4):
            for off in (0.0, 1.5, 2.25, 3.0):
                if lb.rng.random() < 0.8:
                    m = tones[int(lb.rng.integers(len(tones)))]
                    pan = float(lb.rng.uniform(-0.7, 0.7))
                    lb.at("bell", b0 + bar * 4 + off, bell_note(midi_hz(m), decay=1.6), gain=0.5, pan=pan)
    cycle = TWO_PI * np.arange(lb.L) / lb.L        # one slow sweep per loop keeps the seam closed
    lb.groups["pad"] = loop_filter(lb.buf("pad"), 1100.0 + 350.0 * np.sin(cycle))
    noise = lb.rng.standard_normal((lb.L, 2))
    lb.groups["wind"] = loop_filter(noise, 380.0 + 200.0 * np.sin(cycle)) * 0.2
    return finish_track(
        lb, {"pad": 0.8, "sub": 0.8, "bell": 0.7, "wind": 3.0},
        verb=["pad", "bell", "wind"], room=0.93, verb_wet=0.5,
        echo=["bell"], echo_samples=int(0.75 * lb.beat_s * SR), echo_fb=0.35, echo_wet=0.25)


def build_calm(kit):
    lb = Loop("music_calm", 96, 26)
    cell = 8.0  # beats in a 2-bar cell
    voicings = [
        ([57, 60, 64, 67], 45),   # Am7
        ([53, 57, 60, 64], 41),   # Fmaj7
        ([52, 55, 60, 64], 36),   # C/E
        ([55, 59, 62, 67], 43),   # G
    ]
    for ci in range(13):
        vo, root = voicings[ci % 4]
        b0 = ci * cell
        for m in vo:
            lb.at("pad", b0, pad_note(midi_hz(m), lb.secs(cell), attack=0.12, rel=0.5,
                                      detunes=(-8.0, 0.0, 8.0), p=1.0, spread=0.6))
        tones = [m + 12 for m in vo[:3]] + [vo[3] + 12]
        pattern = [0, 1, 2, 3, 2, 1, 3, 1]
        for i in range(16):
            m = tones[pattern[i % 8]]
            pan = 0.4 if i % 2 == 0 else -0.4
            lb.at("arp", b0 + 0.5 * i, pluck_note(midi_hz(m), 0.9, lb.rng), gain=0.45, pan=pan)
        for off in (0.0, 1.5, 2.0, 3.5, 4.0, 5.5, 6.0, 7.5):
            m = root + (12 if off in (2.0, 6.0) else 0)
            lb.at("bass", b0 + off, sub_note(midi_hz(m), lb.secs(0.45), rel=0.05), gain=0.9)
    for bar in range(26):
        b = bar * 4.0
        lb.at("drums", b, kit["kick"], 0.75)
        lb.at("drums", b + 2.0, kit["kick"], 0.7)
        lb.at("drums", b + 1.0, kit["snare_soft"], 0.9)
        lb.at("drums", b + 3.0, kit["snare_soft"], 0.9)
        for i in range(8):
            gain = 0.22 if i % 2 == 1 else 0.14
            lb.at("drums", b + 0.5 * i, kit["hat_soft"], gain, pan=0.3 if i % 2 else -0.3)
    t = lb.t_loop()
    pad_fc = 1500.0 + 700.0 * np.sin(TWO_PI * t / (2.0 * lb.bar_s))
    lb.groups["pad"] = loop_filter(lb.buf("pad"), pad_fc)
    lb.groups["bass"] = loop_filter(lb.buf("bass"), 450.0)
    return finish_track(
        lb, {"pad": 0.6, "arp": 3.2, "bass": 0.7, "drums": 1.3},
        verb=["pad", "arp"], room=0.85, verb_wet=0.25,
        echo=["arp"], echo_samples=int(0.75 * lb.beat_s * SR), echo_fb=0.35, echo_wet=0.18)


def build_combat(kit):
    lb = Loop("music_combat", 128, 34)
    roots = [33, 29, 36, 31]                       # A1 F1 C2 G1, sub-bass per chord
    stabs = [[69, 72, 76], [65, 69, 72], [67, 72, 76], [67, 71, 74]]
    gate = [1, 0, 1, 1, 0, 1, 1, 0, 1, 0, 1, 1, 0, 1, 0, 1]
    for ci in range(17):                           # 2-bar chord cells
        k = ci % 4
        for bi in range(2):
            bar = 2 * ci + bi
            b = bar * 4.0
            phrase_bar = bar % 8
            for q in range(4):
                lb.at("drums", b + q, kit["kick"], 1.0)
            lb.at("drums", b + 1.0, kit["snare"], 1.4)
            lb.at("drums", b + 3.0, kit["snare"], 1.4)
            for i in range(8):
                lb.at("drums", b + 0.5 * i, kit["hat"], 0.85 if i % 2 else 0.6, pan=0.25 if i % 2 else -0.25)
            if phrase_bar in (6, 7):
                for i in range(8):
                    lb.at("drums", b + 0.5 * i + 0.25, kit["hat_soft"], 0.2, pan=0.1)
            for i in range(16):
                if gate[(i + 4 * bi) % 16]:
                    m = roots[k] + (12 if i in (6, 14) else 0)
                    lb.at("bass", b + 0.25 * i, sub_note(midi_hz(m), lb.secs(0.2), rel=0.02), gain=1.0)
            for beat in (0.5, 2.5):
                for m in stabs[k]:
                    pan = float(lb.rng.uniform(-0.5, 0.5))
                    lb.at("lead", b + beat, supersaw_note(midi_hz(m), lb.secs(0.4), rel=0.08), gain=0.4, pan=pan)
            if phrase_bar == 0:
                lb.at("drums", b, kit["crash"], 0.6)
            if phrase_bar == 7:
                for i in range(8):
                    g = 0.3 + 0.6 * i / 7.0
                    lb.at("drums", b + 2.0 + 0.25 * i, kit["snare_soft"], g)
    # rising riser at bars 6 of every 8-bar phrase (2 bars long)
    rise_rng = rng_for("combat_riser")
    n = _n(2.0 * lb.bar_s)
    u = _t(n) / (2.0 * lb.bar_s)
    riser = lp1(rise_rng.standard_normal(n), 300.0 * (9000.0 / 300.0) ** u) * (0.2 + 0.8 * u ** 2) * 0.8
    riser_st = np.stack([riser * 0.71, riser * 0.71], axis=1)
    for phrase in range(5):
        bar = 8 * phrase + 6
        if bar < 34:
            add_wrapped(lb.buf("fx"), riser_st, int(round(bar * lb.bar_s * SR)))
    # tension: the lead filter opens across every 8-bar phrase, then resets
    bars_f = lb.t_loop() / lb.bar_s
    lead_fc = 350.0 * (5200.0 / 350.0) ** (np.mod(bars_f, 8.0) / 8.0)
    lb.groups["lead"] = loop_filter(lb.buf("lead"), lead_fc)
    return finish_track(
        lb, {"drums": 1.0, "bass": 0.9, "lead": 8.0, "fx": 2.5},
        verb=["lead", "fx"], room=0.8, verb_wet=0.2,
        echo=["lead"], echo_samples=int(0.75 * lb.beat_s * SR), echo_fb=0.3, echo_wet=0.15)


def build_boss(kit):
    lb = Loop("music_boss", 140, 36)
    choir = [[50, 57, 62, 65], [46, 53, 58, 62], [43, 50, 58, 62], [45, 52, 61, 64]]   # Dm Bb Gm A
    brass = [[62, 65, 69], [58, 62, 65], [55, 58, 62], [61, 64, 69]]
    roots = [38, 46, 43, 45]
    for ci in range(9):                            # 4-bar cells
        k = ci % 4
        b0 = ci * 16.0
        for m in choir[k]:
            lb.at("choir", b0, choir_note(midi_hz(m), lb.secs(16.0), attack=0.7, rel=1.5), gain=0.35)
        for bar_in in (0, 2):
            b = b0 + 4.0 * bar_in
            for beat in (0.0, 2.5):
                for m in brass[k]:
                    lb.at("brass", b + beat, brass_note(midi_hz(m), lb.secs(0.5), rel=0.12), gain=0.5)
        for bar_in in range(4):
            b = b0 + 4.0 * bar_in
            for off in (0.0, 1.5, 2.5, 3.5):
                m = roots[k] + (12 if off == 2.5 else 0)
                lb.at("bass", b + off, dist_bass_note(midi_hz(m), lb.secs(0.5)), gain=0.9)
    for bar in range(36):                          # half-time groove
        b = bar * 4.0
        lb.at("drums", b, kit["kick"], 1.0)
        if bar % 2 == 1:
            lb.at("drums", b + 2.5, kit["kick"], 0.7)
            lb.at("drums", b + 2.0, kit["snare"], 1.0)
        for i in range(8):
            lb.at("drums", b + 0.5 * i, kit["hat_soft"], 0.16)
    for phrase in range(5):                        # siren drone in the first bar of each 8-bar phrase
        lb.at("siren", 32.0 * phrase, saw_note(midi_hz(38), lb.secs(4.0), rel=0.15), gain=0.5)
    t = lb.t_loop()
    bars_f = t / lb.bar_s
    tri = 1.0 - np.abs(2.0 * np.mod(2.0 * np.mod(bars_f, 1.0), 1.0) - 1.0)
    siren_fc = 170.0 * (2600.0 / 170.0) ** tri
    lb.groups["siren"] = loop_filter(lb.buf("siren"), siren_fc)
    return finish_track(
        lb, {"choir": 0.8, "brass": 2.8, "bass": 0.9, "drums": 1.0, "siren": 2.3},
        verb=["choir", "brass", "siren"], room=0.92, verb_wet=0.45)


def build_victory(kit):
    lb = Loop("music_victory", 110, 7)
    chords = [
        (0.0, 2.0, [60, 64, 67, 72], [67, 72, 76]),   # C
        (2.0, 2.0, [57, 60, 65, 69], [65, 69, 72]),   # F
        (4.0, 2.0, [59, 62, 67, 71], [67, 71, 74]),   # G
        (6.0, 1.0, [60, 64, 67, 72], [67, 72, 76]),   # C
    ]
    for bar0, nbars, voicing, stab in chords:
        dur = lb.secs(4.0 * nbars)
        for m in voicing:
            lb.at("pad", 4.0 * bar0, pad_note(midi_hz(m), dur, attack=0.05, rel=1.0, p=1.0), gain=0.6)
        for bar in range(int(bar0), int(bar0 + nbars)):
            for beat in (0.0, 2.0):
                for m in stab:
                    lb.at("brass", 4.0 * bar + beat, brass_note(midi_hz(m), lb.secs(1.5), rel=0.25), gain=0.5)
    melody = [
        (0, 0, 1, 79), (0, 1, 1, 76), (0, 2, 2, 72),
        (1, 0, 1, 76), (1, 1, 1, 79), (1, 2, 2, 84),
        (2, 0, 1, 77), (2, 1, 1, 72), (2, 2, 2, 69),
        (3, 0, 1, 72), (3, 1, 1, 77), (3, 2, 1, 81), (3, 3, 1, 84),
        (4, 0, 1, 79), (4, 1, 1, 74), (4, 2, 2, 71),
        (5, 0, 1, 74), (5, 1, 1, 79), (5, 2, 2, 83),
        (6, 0, 2, 76), (6, 2, 2, 72),
    ]
    for bar, beat, dur_b, m in melody:
        lb.at("lead", 4.0 * bar + beat, supersaw_note(midi_hz(m), lb.secs(dur_b), rel=0.1, cents=8.0), gain=0.5)
    for bar in range(7):
        b = 4.0 * bar
        lb.at("drums", b, kit["kick"], 0.9)
        lb.at("drums", b + 2.0, kit["kick"], 0.8)
        lb.at("drums", b + 1.0, kit["snare"], 0.7)
        lb.at("drums", b + 3.0, kit["snare"], 0.7)
        for i in range(8):
            lb.at("drums", b + 0.5 * i, kit["hat_soft"], 0.3)
    lb.at("drums", 0.0, kit["crash"], 0.5)
    lb.at("drums", 16.0, kit["crash"], 0.4)
    return finish_track(
        lb, {"pad": 0.7, "brass": 1.0, "lead": 1.5, "drums": 0.9},
        verb=["pad", "brass", "lead"], room=0.85, verb_wet=0.35,
        echo=["lead"], echo_samples=int(0.75 * lb.beat_s * SR), echo_fb=0.3, echo_wet=0.15)


def build_defeat(kit):
    lb = Loop("music_defeat", 60, 3)
    motif = [(0.0, 3.0, 69), (3.0, 3.0, 67), (6.0, 3.0, 65), (9.0, 3.0, 64)]
    for beat, dur_b, m in motif:
        lb.at("keys", beat, keys_note(midi_hz(m), lb.secs(dur_b), decay=1.6, rel=2.0), gain=0.9)
    for bars, beats, voicing, root in ((0.0, 8.0, [57, 60, 64], 45), (8.0, 4.0, [52, 55, 59], 40)):
        dur = lb.secs(beats)
        for m in voicing:
            lb.at("pad", bars, pad_note(midi_hz(m), dur, attack=1.2, rel=2.5, p=1.8), gain=0.5)
        lb.at("sub", bars, sub_note(midi_hz(root), dur, rel=2.0, attack=0.8), gain=0.7)
    return finish_track(
        lb, {"keys": 0.9, "pad": 0.6, "sub": 0.7},
        verb=["keys", "pad"], room=0.95, verb_wet=0.65,
        echo=["keys"], echo_samples=int(0.75 * lb.beat_s * SR), echo_fb=0.4, echo_wet=0.25)


# ------------------------------------------------------------------ sound effects

def _blip(f, dur, tau, harm=0.25):
    n = _n(dur)
    t = _t(n)
    x = np.sin(TWO_PI * f * t) + harm * np.sin(TWO_PI * 2.0 * f * t)
    return _fade(x * np.exp(-t / tau), 0.0015, 0.004)


def _glide(f0, f1, dur, harm=(1.0,)):
    """Exponential pitch glide with harmonic amplitudes harm[k-1]. Keep f1*len(harm) under 8 kHz."""
    n = _n(dur)
    t = _t(n)
    f = f0 * (f1 / f0) ** np.clip(t / dur, 0.0, 1.0)
    ph = TWO_PI * np.cumsum(f) / SR
    return sum(a * np.sin(k * ph) for k, a in enumerate(harm, start=1))


def _metal(f0, dur, rng, gain=1.0):
    n = _n(dur)
    t = _t(n)
    x = np.zeros(n)
    for ratio, amp, tau in ((1.0, 1.0, 0.09), (2.32, 0.5, 0.05), (4.25, 0.25, 0.03), (6.63, 0.12, 0.02)):
        x += amp * np.sin(TWO_PI * f0 * ratio * t) * np.exp(-t / tau)
    click = hp1(rng.standard_normal(n), 3000.0) * np.exp(-t / 0.002)
    return _fade((x + 0.5 * click) * gain, 0.0005, 0.01)


def _whirr(f0, f1, dur, click_at, rng):
    n = _n(dur)
    t = _t(n)
    u = np.clip(t / dur, 0.0, 1.0)
    f = f0 * (f1 / f0) ** u
    ph = TWO_PI * np.cumsum(f) / SR
    tone = (np.sin(ph) + 0.4 * np.sin(2.0 * ph)) * (0.6 + 0.4 * np.sin(TWO_PI * 45.0 * t))
    gear = lp1(hp1(rng.standard_normal(n), 1800.0), 4200.0) * 0.35
    env = np.minimum(1.0, t / 0.02) * (1.0 - 0.3 * u)
    x = (0.5 * tone + gear) * env
    click = hp1(rng.standard_normal(n), 3000.0) * np.exp(-np.abs(t - click_at) / 0.004)
    return x + 0.6 * click


def _noise_clicks(rng, dur, count, lo, hi, tau, gain, fc=2500.0):
    n = _n(dur)
    out = np.zeros(n)
    for _ in range(count):
        t0 = lo + (hi - lo) * rng.random()
        m = _n(min(0.05, tau * 6))
        burst = hp1(rng.standard_normal(m), fc) * np.exp(-_t(m) / tau)
        _place(out, burst * gain * (0.5 + rng.random()), t0)
    return out


def _boom(f0, f1, dur, tau):
    n = _n(dur)
    t = _t(n)
    f = f0 * (f1 / f0) ** np.clip(t / dur, 0.0, 1.0)
    x = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / tau)
    return _fade(x, 0.002, 0.02)


def s_ui_click(rng):
    n = _n(0.06)
    t = _t(n)
    tone = np.sin(TWO_PI * 1900.0 * t) * np.exp(-t / 0.012)
    click = hp1(rng.standard_normal(n), 4000.0) * np.exp(-t / 0.002)
    return 0.9 * tone + 0.5 * click


def s_ui_select(rng):
    out = np.zeros(_n(0.18))
    _place(out, _blip(880.0, 0.1, 0.05), 0.0)
    _place(out, _blip(1320.0, 0.14, 0.06), 0.06)
    return out


def s_ui_back(rng):
    x = _glide(760.0, 420.0, 0.16, harm=(1.0, 0.2))
    return x * np.exp(-_t(x.shape[0]) / 0.08)


def s_ui_error(rng):
    out = np.zeros(_n(0.3))
    _place(out, _wave_seg(155.0, 0.13, "square", 0.08), 0.0)
    _place(out, _wave_seg(116.0, 0.16, "square", 0.08), 0.14)
    return out


def _wave_seg(f, dur, shape, tau):
    n = _n(dur)
    t = _t(n)
    return _fade(osc(f, t, shape, 1.0) * np.exp(-t / tau), 0.001, 0.01)


def s_wave_start(rng):
    n = _n(1.2)
    t = _t(n)
    u = np.clip(t / 1.1, 0.0, 1.0)
    f = 220.0 * 6.0 ** u
    ph = TWO_PI * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.35 * np.sin(2.0 * ph) + 0.12 * np.sin(3.0 * ph)
    env = np.minimum(1.0, t / 0.12) * np.exp(-np.maximum(0.0, t - 1.0) / 0.12)
    riser = hp1(rng.standard_normal(n), 800.0 * 7.5 ** u) * (u ** 2) * 0.5 * np.minimum(1.0, t / 0.2)
    x = 0.55 * tone * env + riser
    _place(x, bell_note(1320.0, decay=0.25, level=0.6), 1.0)
    return x


def s_sector_clear(rng):
    out = np.zeros(_n(2.2))
    for i, m in enumerate((72, 76, 79, 84)):
        _place(out, brass_note(midi_hz(m), 0.14, rel=0.2), 0.16 * i)
    for m in (72, 76, 79, 84):
        _place(out, brass_note(midi_hz(m), 1.0, rel=0.5, attack=0.03), 0.64)
    for m in (84, 88, 91):
        _place(out, bell_note(midi_hz(m), decay=0.8, level=0.35), 0.64)
    return out


def s_upgrade_pick(rng):
    out = np.zeros(_n(0.9))
    for i, f in enumerate((1046.5, 1318.5, 1568.0, 2093.0)):
        _place(out, bell_note(f, decay=0.6, level=0.8), 0.11 * i)
    return out


def s_boss_warning(rng):
    n = _n(2.4)
    t = _t(n)
    sq = np.tanh(3.0 * np.sin(TWO_PI * t / 0.8)) / math.tanh(3.0)
    f = 540.0 + 240.0 * (sq + 1.0) / 2.0
    ph = TWO_PI * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.5 * np.sin(2.0 * ph) + 0.33 * np.sin(3.0 * ph) + 0.25 * np.sin(4.0 * ph)
    amp = np.minimum(1.0, t / 0.02) * np.minimum(1.0, (2.4 - t) / 0.12) * (0.85 + 0.15 * np.sin(TWO_PI * 6.0 * t))
    return tone * amp


def s_game_over(rng):
    out = np.zeros(_n(2.0))
    for i, m in enumerate((67, 64, 62, 60)):
        _place(out, keys_note(midi_hz(m), 0.55, decay=1.5, rel=0.4), 0.42 * i)
    drone = _glide(196.0, 98.0, 2.0, harm=(1.0, 0.4, 0.15))
    t = _t(drone.shape[0])
    out[:drone.shape[0]] += 0.5 * drone * np.exp(-t / 1.3) * np.minimum(1.0, t / 0.03)
    return out


def s_reload_done(rng):
    out = np.zeros(_n(0.45))
    _place(out, _metal(1100.0, 0.4, rng), 0.0)
    _place(out, _metal(1650.0, 0.3, rng, gain=0.6), 0.17)
    return out


def s_fire_pulse(rng):
    n = _n(0.12)
    t = _t(n)
    f = 2300.0 * 0.5 ** (t / 0.12)
    ph = TWO_PI * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.5 * np.sin(2.0 * ph)
    gate = np.abs(np.sin(TWO_PI * 95.0 * t)) ** 0.6
    noise = hp1(rng.standard_normal(n), 1500.0) * 0.6
    return (0.6 * tone + 0.5 * noise) * gate * np.exp(-t / 0.06)


def s_fire_lance(rng):
    n = _n(0.6)
    t = _t(n)
    crack = hp1(rng.standard_normal(n), 1200.0) * np.exp(-t / 0.012) * 0.8
    thump_f = 50.0 + 90.0 * np.exp(-t / 0.02)
    thump = np.sin(TWO_PI * np.cumsum(thump_f) / SR) * np.exp(-t / 0.05) * 0.9
    tail = _glide(350.0, 1400.0, 0.6, harm=(1.0, 0.3))
    tail = tail * np.exp(-t / 0.25) * np.minimum(1.0, t / 0.01)
    return crack + thump + 0.55 * tail


def s_lance_charge(rng):
    n = _n(1.6)
    t = _t(n)
    u = np.clip(t / 1.5, 0.0, 1.0)
    f = 240.0 * 6.25 ** u
    ph = TWO_PI * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.5 * np.sin(2.0 * ph) + 0.25 * np.sin(3.0 * ph)
    hiss = hp1(rng.standard_normal(n), 4500.0) * 0.12
    env = (1.0 - np.exp(-t / 0.06)) * (0.8 + 0.2 * t / 1.6) * np.minimum(1.0, (1.6 - t) / 0.12)
    return (0.55 * tone + hiss) * env


def s_fire_flak(rng):
    n = _n(0.5)
    t = _t(n)
    thump_f = 110.0 * (42.0 / 110.0) ** np.clip(t / 0.12, 0.0, 1.0)
    thump = (np.sin(TWO_PI * np.cumsum(thump_f) / SR) + 0.2 * np.sin(TWO_PI * np.cumsum(2 * thump_f) / SR)) * np.exp(-t / 0.12)
    noise = hp1(rng.standard_normal(n), 1800.0)
    whoosh = lp1(noise, 2600.0 * 0.2 ** np.clip(t / 0.35, 0.0, 1.0)) * np.exp(-t / 0.16) * 0.7
    return _fade(thump + whoosh, 0.005, 0.01)


def s_fire_swarm(rng):
    n = _n(0.7)
    t = _t(n)
    hiss = lp1(hp1(rng.standard_normal(n), 2000.0), 7000.0)
    hiss *= np.minimum(1.0, t / 0.25) * np.exp(-np.maximum(0.0, t - 0.25) / 0.25) * 0.6
    out = hiss + 0.25 * _glide(180.0, 330.0, 0.7, harm=(1.0, 0.3)) * np.exp(-t / 0.4)
    out += _noise_clicks(rng, 0.7, 7, 0.05, 0.6, 0.004, 0.5)
    return out


def s_fire_empty(rng):
    n = _n(0.05)
    t = _t(n)
    return np.sin(TWO_PI * 1600.0 * t) * np.exp(-t / 0.004) + 0.7 * hp1(rng.standard_normal(n), 3000.0) * np.exp(-t / 0.0015)


def s_overheat(rng):
    n = _n(1.2)
    t = _t(n)
    alarm = osc(1020.0, t, "square", 1.0)
    on = np.clip((0.15 - np.mod(t, 0.25)) / 0.004, 0.0, 1.0)
    hiss = lp1(hp1(rng.standard_normal(n), 3000.0), 8000.0)
    hiss *= np.minimum(1.0, t / 0.1) * (0.6 + 0.2 * np.sin(TWO_PI * 2.0 * t))
    return 0.35 * alarm * on + 0.55 * hiss


def s_hit_enemy(rng):
    n = _n(0.08)
    t = _t(n)
    return 0.8 * np.sin(TWO_PI * 1700.0 * t) * np.exp(-t / 0.012) + 0.5 * hp1(rng.standard_normal(n), 3500.0) * np.exp(-t / 0.003)


def s_hit_crit(rng):
    out = np.zeros(_n(0.25))
    _place(out, bell_note(2600.0, decay=0.35, level=0.9), 0.0)
    _place(out, _blip(4300.0, 0.08, 0.03), 0.0)
    return out


def s_kill_small(rng):
    n = _n(0.2)
    t = _t(n)
    pop = lp1(rng.standard_normal(n), 600.0) * np.exp(-t / 0.015) * 1.2
    blip = _glide(950.0, 360.0, 0.18, harm=(1.0, 0.2))
    out = pop
    out[:blip.shape[0]] += 0.8 * blip * np.exp(-_t(blip.shape[0]) / 0.07)
    return out


def s_kill_big(rng):
    n = _n(1.4)
    t = _t(n)
    boom = _boom(95.0, 32.0, 1.4, 0.3)
    transient = lp1(rng.standard_normal(n), 300.0) * np.exp(-t / 0.05)
    debris = lp1(rng.standard_normal(n), 1600.0) * np.exp(-t / 0.45) * 0.5
    return boom + 0.6 * transient + debris + _noise_clicks(rng, 1.4, 14, 0.05, 1.1, 0.012, 0.5, fc=1200.0)


def s_explosion(rng):
    n = _n(0.9)
    t = _t(n)
    air = lp1(hp1(rng.standard_normal(n), 400.0), 3500.0) * np.exp(-t / 0.18)
    body_f = 170.0 * (60.0 / 170.0) ** np.clip(t / 0.12, 0.0, 1.0)
    body = np.sin(TWO_PI * np.cumsum(body_f) / SR) * np.exp(-t / 0.12) * 0.7
    out = air + body + _noise_clicks(rng, 0.9, 20, 0.0, 0.42, 0.003, 0.4, fc=3000.0)
    _place(out, bell_note(640.0, decay=0.25, level=0.35), 0.02)
    return out


def s_boss_die(rng):
    n = _n(2.5)
    t = _t(n)
    f = 50.0 - 18.0 * (t / 2.5) + 2.5 * np.sin(TWO_PI * 3.5 * t)
    sub = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / 1.2) * np.minimum(1.0, t / 0.02)
    rumble = lp1(rng.standard_normal(n), 260.0) * np.exp(-t / 1.0) * 1.2 * (0.7 + 0.3 * np.sin(TWO_PI * 2.1 * t))
    out = sub + rumble
    for t0, gain in ((0.55, 0.6), (1.1, 0.5), (1.7, 0.45)):
        _place(out, _boom(72.0, 30.0, 0.9, 0.3) * gain, t0)
    out += _noise_clicks(rng, 2.5, 12, 0.3, 2.0, 0.015, 0.5, fc=900.0)
    return out


def s_snap(rng):
    n = _n(0.3)
    t = _t(n)
    f = 1100.0 * (1500.0 / 1100.0) ** np.clip(t / 0.07, 0.0, 1.0)
    glide = np.sin(TWO_PI * np.cumsum(f) / SR) * np.exp(-t / 0.09)
    out = glide * 0.6
    _place(out, bell_note(1500.0, decay=0.15, level=0.6), 0.0)
    return out


def s_combo_up(rng):
    x = _glide(600.0, 1250.0, 0.18, harm=(1.0, 0.25))
    t = _t(x.shape[0])
    return x * np.exp(-t / 0.08)


def s_pickup(rng):
    out = np.zeros(_n(0.4))
    _place(out, bell_note(1318.5, decay=0.35, level=0.8), 0.0)
    _place(out, bell_note(1760.0, decay=0.35, level=0.8), 0.13)
    return out


def s_enemy_beam(rng):
    n = _n(0.45)
    t = _t(n)
    f = 2000.0 * 0.1 ** np.clip(t / 0.35, 0.0, 1.0)
    ph = TWO_PI * np.cumsum(f) / SR
    saw = sum(np.sin(k * ph) / k for k in range(1, 5))
    gate = 0.75 + 0.25 * np.sign(np.sin(TWO_PI * 70.0 * t))
    crackle = hp1(rng.standard_normal(n), 3000.0) * (0.5 + 0.5 * np.sin(TWO_PI * 47.0 * t) ** 2) * 0.5
    return (0.6 * saw + crackle) * np.minimum(1.0, t / 0.002) * np.exp(-t / 0.3) * gate


def s_enemy_shell(rng):
    n = _n(1.1)
    t = _t(n)
    f = 2200.0 * (300.0 / 2200.0) ** np.clip(t / 1.1, 0.0, 1.0)
    f = f * (1.0 + 0.01 * np.sin(TWO_PI * 7.0 * t))
    ph = TWO_PI * np.cumsum(f) / SR
    whistle = np.sin(ph) + 0.15 * np.sin(2.0 * ph)
    airy = hp1(rng.standard_normal(n), 2500.0) * 0.2
    env = np.minimum(1.0, t / 0.08) * (0.4 + 0.6 * (t / 1.1) ** 2)
    return _fade((whistle + airy) * env, 0.002, 0.1)


def s_shield_hit(rng):
    n = _n(0.35)
    t = _t(n)
    buzz = osc(100.0, t, "square", 1.0)
    impulses = (rng.random(n) < 0.02) * rng.standard_normal(n)
    crackle = lp1(impulses, 6000.0)
    crackle = crackle / (float(np.max(np.abs(crackle))) + 1e-12)
    return (0.5 * buzz + 0.7 * crackle) * np.exp(-t / 0.12)


def s_hull_hit(rng):
    n = _n(0.6)
    t = _t(n)
    clang = np.zeros(n)
    for ratio, amp, tau in ((1.0, 1.0, 0.5), (2.32, 0.55, 0.3), (4.25, 0.3, 0.15), (6.63, 0.15, 0.08)):
        clang += amp * np.sin(TWO_PI * 380.0 * ratio * t) * np.exp(-t / tau)
    thud_f = 45.0 + 90.0 * np.exp(-t / 0.03)
    thud = np.sin(TWO_PI * np.cumsum(thud_f) / SR) * np.exp(-t / 0.08) * 0.9
    trans = hp1(rng.standard_normal(n), 2500.0) * np.exp(-t / 0.004) * 0.6
    return clang * 0.7 + thud + trans


def s_dodge(rng):
    n = _n(0.35)
    t = _t(n)
    env = np.sin(np.pi * t / 0.35) ** 2
    noise = rng.standard_normal(n)
    hi = hp1(noise, 900.0 + 2400.0 * np.sin(np.pi * t / 0.35) ** 2)
    return lp1(hi, 5000.0) * env * 0.9


def s_lock_tone(rng):
    env = adsr(0.09, 0.003, 0.03)
    t = _t(env.shape[0])
    return (np.sin(TWO_PI * 1760.0 * t) + 0.12 * np.sin(TWO_PI * 5280.0 * t)) * env


def s_scope_in(rng):
    return _whirr(180.0, 420.0, 0.4, 0.36, rng)


def s_scope_out(rng):
    return _whirr(420.0, 160.0, 0.3, 0.0, rng)


def s_focus_on(rng):
    n = _n(0.9)
    t = _t(n)
    f = 900.0 * (220.0 / 900.0) ** np.clip(t / 0.9, 0.0, 1.0) * (1.0 + 0.03 * np.sin(TWO_PI * 7.0 * t))
    ph = TWO_PI * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.3 * np.sin(2.0 * ph) + 0.1 * np.sin(3.0 * ph)
    sub = 0.4 * np.sin(TWO_PI * 90.0 * t)
    env = np.minimum(1.0, t / 0.05) * (1.0 - np.clip((t - 0.7) / 0.2, 0.0, 1.0))
    return (0.6 * tone + sub) * env


def s_focus_off(rng):
    n = _n(0.5)
    t = _t(n)
    f = 220.0 * (900.0 / 220.0) ** np.clip(t / 0.5, 0.0, 1.0) * (1.0 + 0.03 * np.sin(TWO_PI * 9.0 * t))
    ph = TWO_PI * np.cumsum(f) / SR
    tone = np.sin(ph) + 0.3 * np.sin(2.0 * ph)
    return tone * np.minimum(1.0, t / 0.02) * np.exp(-t / 0.25)


SFX = [
    ("ui_click", s_ui_click, 0.55),
    ("ui_select", s_ui_select, 0.6),
    ("ui_back", s_ui_back, 0.6),
    ("ui_error", s_ui_error, 0.7),
    ("wave_start", s_wave_start, 0.8),
    ("sector_clear", s_sector_clear, 0.85),
    ("upgrade_pick", s_upgrade_pick, 0.8),
    ("boss_warning", s_boss_warning, 0.85),
    ("game_over", s_game_over, 0.8),
    ("reload_done", s_reload_done, 0.7),
    ("fire_pulse", s_fire_pulse, 0.7),
    ("fire_lance", s_fire_lance, 0.9),
    ("lance_charge", s_lance_charge, 0.6),
    ("fire_flak", s_fire_flak, 0.9),
    ("fire_swarm", s_fire_swarm, 0.7),
    ("fire_empty", s_fire_empty, 0.5),
    ("overheat", s_overheat, 0.8),
    ("hit_enemy", s_hit_enemy, 0.5),
    ("hit_crit", s_hit_crit, 0.75),
    ("kill_small", s_kill_small, 0.7),
    ("kill_big", s_kill_big, 0.9),
    ("explosion", s_explosion, 0.9),
    ("boss_die", s_boss_die, 0.9),
    ("snap", s_snap, 0.6),
    ("combo_up", s_combo_up, 0.6),
    ("pickup", s_pickup, 0.7),
    ("enemy_beam", s_enemy_beam, 0.75),
    ("enemy_shell", s_enemy_shell, 0.7),
    ("shield_hit", s_shield_hit, 0.75),
    ("hull_hit", s_hull_hit, 0.9),
    ("dodge", s_dodge, 0.6),
    ("lock_tone", s_lock_tone, 0.5),
    ("scope_in", s_scope_in, 0.6),
    ("scope_out", s_scope_out, 0.55),
    ("focus_on", s_focus_on, 0.7),
    ("focus_off", s_focus_off, 0.6),
]


def sfx_out(x, level):
    """DC-block, fade the ends, normalise the peak to level, and return stereo."""
    x = np.asarray(x, dtype=np.float64)
    x = _fade(x - lp1(x, 12.0), 0.002, 0.005)
    pk = float(np.max(np.abs(x)))
    if pk > 0:
        x = x * (level / pk)
    return np.stack([x, x], axis=1)


# ------------------------------------------------------------------ encoding

def encode_ogg(ffmpeg, path, stereo):
    data = np.ascontiguousarray(stereo, dtype="<f4").tobytes()
    cmd = [ffmpeg, "-y", "-loglevel", "error", "-f", "f32le", "-ar", "44100", "-ac", "2",
           "-i", "-", "-c:a", "libvorbis", "-q:a", "5", str(path)]
    proc = subprocess.run(cmd, input=data, capture_output=True)
    if proc.returncode != 0:
        raise SystemExit("ffmpeg failed for %s: %s" % (path, proc.stderr.decode(errors="replace")))


def main(argv=None):
    ap = argparse.ArgumentParser(description="Generate Picket Line music and sound effects as OGG.")
    ap.add_argument("--out", default=str(DEFAULT_OUT), help="output directory (default: picket-line/assets/audio)")
    args = ap.parse_args(argv)

    ffmpeg = shutil.which("ffmpeg") or "/usr/bin/ffmpeg"
    out_dir = pathlib.Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    kit = make_drums()
    tracks = [
        ("music_menu", build_menu),
        ("music_calm", build_calm),
        ("music_combat", build_combat),
        ("music_boss", build_boss),
        ("music_victory", build_victory),
        ("music_defeat", build_defeat),
    ]
    for name, builder in tracks:
        stereo = builder(kit)
        path = out_dir / (name + ".ogg")
        encode_ogg(ffmpeg, path, stereo)
        print("wrote %s  %.2f s  stereo" % (path.name, stereo.shape[0] / SR))

    for key, fn, level in SFX:
        mono = fn(rng_for("sfx_" + key))
        stereo = sfx_out(mono, level)
        path = out_dir / ("sfx_" + key + ".ogg")
        encode_ogg(ffmpeg, path, stereo)
        print("wrote %s  %.3f s  stereo" % (path.name, stereo.shape[0] / SR))


if __name__ == "__main__":
    sys.exit(main())
