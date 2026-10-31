#!/usr/bin/env python3
"""Generate Quietude's original ambient audio layers.

Every sound in Quietude is synthesized here from noise, oscillators, and
physical-ish models. No third-party recordings are used. The output is a set of
40-second, seamlessly loopable 32 kHz stereo AAC files, small enough to
bundle and high enough quality for long, quiet listening. AAC containers
preserve exact gapless loop length, unlike IMA4 at the loop seam.

Run:  python3 Tools/generate_audio.py
"""

from __future__ import annotations

import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path

import numpy as np

SR = 32_000
LOOP_SECONDS = 40.0
TAIL_SECONDS = 1.5
GEN_SECONDS = LOOP_SECONDS + TAIL_SECONDS
GEN_N = int(SR * GEN_SECONDS)
OUT_N = int(SR * LOOP_SECONDS)
FADE_N = int(SR * TAIL_SECONDS)
ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "Assets" / "Audio"

rng_global = np.random.default_rng(20261028)


# ---------------------------------------------------------------------------
# Small DSP toolkit
# ---------------------------------------------------------------------------


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)) + 1e-20))


def db_to_amp(db: float) -> float:
    return 10.0 ** (db / 20.0)


def shaped_noise(
    n: int,
    rng: np.random.Generator,
    *,
    low: float | None = None,
    high: float | None = None,
    order: int = 2,
    tilt: float = 0.0,
) -> np.ndarray:
    """Gaussian noise with a smooth analytic spectral shape.

    FFT-domain shaping keeps the result perfectly circular, which is exactly
    what a loop wants.
    """
    white = rng.standard_normal(n)
    spectrum = np.fft.rfft(white)
    freqs = np.fft.rfftfreq(n, 1 / SR)
    mag = np.ones_like(freqs)
    safe = np.maximum(freqs, 1.0)
    if low is not None:
        ratio = safe / low
        mag *= (ratio ** order) / np.sqrt(1.0 + ratio ** (2 * order))
    if high is not None:
        ratio = safe / high
        mag /= np.sqrt(1.0 + ratio ** (2 * order))
    if tilt:
        mag *= (safe / 1000.0) ** tilt
    mag[0] = 0.0
    # Do not let the very top octave become brittle on small speakers.
    top = freqs > SR * 0.43
    mag[top] *= np.linspace(1.0, 0.55, int(top.sum()))
    result = np.fft.irfft(spectrum * mag, n)
    return result / (np.max(np.abs(result)) + 1e-12)


def bandpass(x: np.ndarray, low: float, high: float, order: int = 2) -> np.ndarray:
    if x.ndim == 2:
        return np.stack([bandpass(channel, low, high, order=order) for channel in x])
    spectrum = np.fft.rfft(x)
    freqs = np.fft.rfftfreq(len(x), 1 / SR)
    safe = np.maximum(freqs, 1.0)
    lo = (safe / low) ** order / np.sqrt(1.0 + (safe / low) ** (2 * order))
    hi = 1.0 / np.sqrt(1.0 + (safe / high) ** (2 * order))
    return np.fft.irfft(spectrum * lo * hi, len(x))


def slow_lfo(
    n: int,
    rng: np.random.Generator,
    *,
    min_cycles: int = 1,
    max_cycles: int = 4,
    components: int = 3,
) -> np.ndarray:
    """A smooth, loop-friendly LFO in roughly [-1, 1].

    Cycles are counted across the 40 second loop so the modulation is periodic.
    """
    t = np.arange(n) / SR
    out = np.zeros(n)
    for _ in range(components):
        cycles = int(rng.integers(min_cycles, max_cycles + 1))
        phase = float(rng.uniform(0, 2 * math.pi))
        out += np.sin(2 * math.pi * cycles * t / LOOP_SECONDS + phase) * rng.uniform(0.3, 1.0)
    out /= np.max(np.abs(out)) + 1e-12
    return out


def quantized_frequency(freq: float) -> float:
    """Snap a tone so it completes a whole number of cycles in the loop."""
    cycles = max(1, round(freq * LOOP_SECONDS))
    return cycles / LOOP_SECONDS


def loopify(x: np.ndarray) -> np.ndarray:
    """Crossfade the final 1.5 s into the head and return exactly 40 s."""
    fade = FADE_N
    ramp = 0.5 - 0.5 * np.cos(np.linspace(0, math.pi, fade, endpoint=False))
    # Equal-power crossfade for uncorrelated ambience.
    ramp = np.sin(ramp * math.pi / 2)
    body = x[..., :OUT_N].copy()
    tail = x[..., OUT_N : OUT_N + fade]
    head = x[..., :fade]
    body[..., :fade] = head * ramp + tail * (1.0 - ramp)
    return body


def normalize(x: np.ndarray, target_rms_db: float, peak_db: float) -> np.ndarray:
    x = x - np.mean(x, axis=1, keepdims=True)
    level = db_to_amp(target_rms_db) / (rms(x) + 1e-12)
    x = x * level
    peak = float(np.max(np.abs(x)))
    ceiling = db_to_amp(peak_db)
    if peak > ceiling:
        # Preserve the waveform; give up a little loudness rather than add
        # distortion to a sound meant for long listening.
        x = x * (ceiling / peak)
    return x


def reverb(
    x: np.ndarray,
    rng: np.random.Generator,
    *,
    decay: float = 0.9,
    mix: float = 0.16,
    high: float = 5200.0,
) -> np.ndarray:
    """Cheap circular stereo reverb, so tails wrap cleanly at the loop seam."""
    n = x.shape[1]
    wet = np.empty_like(x)
    ir_n = max(int(decay * SR), 16)
    t = np.arange(ir_n) / SR
    for channel in range(2):
        ir = rng.standard_normal(ir_n) * np.exp(-t / (decay * 0.38))
        ir = bandpass(np.pad(ir, (0, n - ir_n)), 80, high)[:ir_n]
        ir[0] += 1.0
        ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
        ir_pad = np.zeros(n)
        ir_pad[:ir_n] = ir
        wet[channel] = np.fft.irfft(np.fft.rfft(x[channel]) * np.fft.rfft(ir_pad), n)
    wet_level = rms(wet)
    dry_level = rms(x)
    if wet_level > 1e-9:
        wet *= (dry_level / wet_level) * 0.7
    return x * (1 - mix) + wet * mix


def pan_gains(pan: float) -> tuple[float, float]:
    pan = float(np.clip(pan, -1, 1))
    angle = (pan + 1) * math.pi / 4
    return math.cos(angle), math.sin(angle)


def add_wrapped(
    buffer: np.ndarray,
    signal: np.ndarray,
    start_seconds: float,
    gain: float = 1.0,
    pan: float = 0.0,
) -> None:
    n = buffer.shape[1]
    stereo = signal.ndim == 2
    length = signal.shape[-1]
    start = int(start_seconds * SR) % n
    left, right = pan_gains(pan)
    gain = float(gain)
    sig = signal * gain
    end = start + length

    def add(slice_start: int, slice_end: int, source_start: int, source_end: int) -> None:
        segment = sig[:, source_start:source_end] if stereo else sig[source_start:source_end]
        if stereo:
            buffer[0, slice_start:slice_end] += segment[0] * left
            buffer[1, slice_start:slice_end] += segment[1] * right
        else:
            buffer[0, slice_start:slice_end] += segment * left
            buffer[1, slice_start:slice_end] += segment * right

    if end <= n:
        add(start, end, 0, length)
    else:
        first = n - start
        add(start, n, 0, first)
        add(0, length - first, first, length)


def damped_ping(
    rng: np.random.Generator,
    freq: float,
    decay: float,
    *,
    noise: float = 0.0,
) -> np.ndarray:
    n = max(int(decay * SR * 6), 64)
    t = np.arange(n) / SR
    attack = np.minimum(1.0, t / 0.002)
    env = attack * np.exp(-t / max(decay, 0.004))
    phase = 2 * math.pi * freq * t
    sig = np.sin(phase) + 0.28 * np.sin(phase * 2.03 + 0.7) + 0.1 * np.sin(phase * 3.07)
    if noise:
        sig += shaped_noise(n, rng, high=freq * 3.2, order=1) * noise * 3.2
    return sig * env


# ---------------------------------------------------------------------------
# Rainy Cabin
# ---------------------------------------------------------------------------


def build_rain(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    left = shaped_noise(n, rng, low=260, high=9200, order=2, tilt=-0.18)
    right = shaped_noise(n, rng, low=260, high=9200, order=2, tilt=-0.18)
    roof = shaped_noise(n, rng, low=70, high=500, order=2)
    lfo = 0.5 + 0.5 * slow_lfo(n, rng, min_cycles=1, max_cycles=3)
    left = left * (0.84 + 0.16 * lfo) + roof * 0.34
    right = right * (0.84 + 0.16 * lfo[::-1]) + roof * 0.34

    rain = np.stack([left, right])
    # Individual drops give the hiss a surface without making it hissy.
    drop_count = int(GEN_SECONDS * 12)
    for _ in range(drop_count):
        freq = float(rng.uniform(1400, 7200))
        ping = damped_ping(rng, freq, float(rng.uniform(0.006, 0.028)), noise=0.4)
        add_wrapped(
            rain,
            ping,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.008, 0.05)),
            pan=float(rng.uniform(-0.9, 0.9)),
        )
    # A low, soft patter on the roof.
    for _ in range(int(GEN_SECONDS * 3)):
        ping = damped_ping(rng, float(rng.uniform(90, 260)), float(rng.uniform(0.02, 0.06)), noise=0.6)
        add_wrapped(
            rain,
            ping,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.01, 0.045)),
            pan=float(rng.uniform(-0.5, 0.5)),
        )
    return reverb(rain, rng, decay=0.35, mix=0.08, high=7000)


def thunder_event(rng: np.random.Generator, duration: float) -> np.ndarray:
    n = int(duration * SR)
    t = np.arange(n) / SR
    attack = np.minimum(1.0, t / 0.22)
    body = np.exp(-t / (duration * 0.45))
    swell = 0.55 + 0.45 * np.sin(2 * math.pi * 0.22 * t + rng.uniform(0, 1))
    env = attack * body * swell
    rumble = shaped_noise(n, rng, low=20, high=170, order=2) * 2.4
    sub = np.sin(2 * math.pi * (30 + 10 * np.exp(-t / 1.4)) * t + rng.uniform(0, 1))
    crackle = shaped_noise(n, rng, low=130, high=650, order=1) * 0.35
    mono = (rumble + sub * 0.55 + crackle) * env
    left = mono * 0.94
    right = np.roll(mono, int(0.011 * SR)) * 0.9
    return np.stack([left, right])


def build_thunder(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    out = np.zeros((2, n))
    for start in (4.2, 19.8, 33.6):
        duration = float(rng.uniform(7.0, 10.0))
        event = thunder_event(rng, duration)
        add_wrapped(
            out,
            event,
            start + float(rng.uniform(-1.2, 1.2)),
            gain=float(rng.uniform(0.45, 0.85)),
            pan=float(rng.uniform(-0.55, 0.25)),
        )
    return reverb(out, rng, decay=1.9, mix=0.24, high=1200)


def build_fireplace(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    bed = shaped_noise(n, rng, low=40, high=420, order=2) * 1.2
    bed += shaped_noise(n, rng, low=300, high=1900, order=2) * 0.10
    lfo = 0.75 + 0.25 * slow_lfo(n, rng, min_cycles=2, max_cycles=6)
    out = np.stack([bed * lfo, np.roll(bed, int(0.07 * SR)) * lfo[::-1]])

    # Fine crackle.
    for _ in range(int(GEN_SECONDS * 7)):
        freq = float(rng.uniform(600, 4200))
        ping = damped_ping(rng, freq, float(rng.uniform(0.004, 0.02)), noise=0.9)
        add_wrapped(
            out,
            ping,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.01, 0.16)),
            pan=float(rng.uniform(-0.7, 0.7)),
        )
    # Occasional larger pops and settling logs.
    for _ in range(int(GEN_SECONDS * 0.7)):
        ping = damped_ping(rng, float(rng.uniform(180, 620)), float(rng.uniform(0.03, 0.09)), noise=0.5)
        add_wrapped(
            out,
            ping,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.12, 0.28)),
            pan=float(rng.uniform(-0.4, 0.4)),
        )
    for _ in range(int(GEN_SECONDS * 0.28)):
        thump = damped_ping(rng, float(rng.uniform(48, 90)), 0.35, noise=0.8)
        add_wrapped(
            out,
            thump,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.05, 0.12)),
            pan=float(rng.uniform(-0.3, 0.3)),
        )
    return reverb(out, rng, decay=0.6, mix=0.14, high=4500)


# ---------------------------------------------------------------------------
# Train
# ---------------------------------------------------------------------------


def rail_clack(rng: np.random.Generator) -> np.ndarray:
    thump = damped_ping(
        rng,
        float(rng.uniform(48, 78)),
        float(rng.uniform(0.05, 0.10)),
        noise=0.9,
    )
    tick = damped_ping(
        rng,
        float(rng.uniform(900, 1800)),
        float(rng.uniform(0.008, 0.020)),
        noise=0.5,
    )
    return mix_signals(thump, tick, gain=0.35)


def build_rail_rhythm(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    rolling = shaped_noise(n, rng, low=30, high=720, order=2) * 1.0
    rolling2 = shaped_noise(n, rng, low=30, high=780, order=2) * 1.0
    lfo = 0.82 + 0.18 * slow_lfo(n, rng, min_cycles=1, max_cycles=4)
    out = np.stack([
        rolling * lfo,
        np.roll(rolling2, int(0.04 * SR)) * lfo[::-1],
    ])

    # Joints pass under both bogies in a steady, gently human rhythm.
    period = 1.72
    count = int(GEN_SECONDS / period)
    for index in range(count):
        start = index * period + float(rng.uniform(-0.012, 0.012))
        for offset in (0.0, 0.16):
            add_wrapped(
                out,
                rail_clack(rng),
                start + offset,
                gain=float(rng.uniform(0.16, 0.26)),
                pan=float(rng.uniform(-0.28, 0.28)),
            )
    return reverb(out, rng, decay=0.6, mix=0.10, high=4500)


def build_carriage(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    rumble = shaped_noise(n, rng, low=24, high=320, order=2) * 1.2
    air = shaped_noise(n, rng, low=320, high=2200, order=2) * 0.06
    t = np.arange(n) / SR
    hum = 0.008 * np.sin(2 * math.pi * 48 * t) + 0.004 * np.sin(2 * math.pi * 96 * t + 0.5)
    lfo = 0.80 + 0.20 * slow_lfo(n, rng, min_cycles=1, max_cycles=4)
    out = np.stack([
        (rumble + air) * lfo + hum,
        (np.roll(rumble, int(0.15 * SR)) + air * 0.9) * lfo[::-1] + hum,
    ])

    # The body of the carriage creaks and settles.
    for _ in range(int(GEN_SECONDS * 0.7)):
        creak = damped_ping(
            rng,
            float(rng.uniform(120, 420)),
            float(rng.uniform(0.18, 0.55)),
            noise=0.25,
        )
        add_wrapped(
            out,
            creak,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.012, 0.040)),
            pan=float(rng.uniform(-0.6, 0.6)),
        )
    # Small rattles from fittings and glass.
    for _ in range(int(GEN_SECONDS * 1.6)):
        duration = float(rng.uniform(0.03, 0.12))
        length = int(duration * SR)
        rattle = shaped_noise(length, rng, low=400, high=2800, order=2)
        rattle *= np.sin(np.linspace(0, math.pi, length)) ** 2
        add_wrapped(
            out,
            rattle,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.004, 0.016)),
            pan=float(rng.uniform(-0.8, 0.8)),
        )
    return reverb(out, rng, decay=0.7, mix=0.15, high=3600)


def train_horn_event(rng: np.random.Generator, duration: float = 3.4) -> np.ndarray:
    n = int(duration * SR)
    t = np.arange(n) / SR
    attack = np.clip(t / 0.55, 0, 1)
    release = np.clip((duration - t) / 1.5, 0, 1)
    env = attack * release

    tone = np.zeros(n)
    for index, freq in enumerate([233.1, 277.2, 349.2]):
        vibrato = 1 + 0.004 * np.sin(2 * math.pi * 5.1 * t + index)
        tone += np.sin(2 * math.pi * freq * t * vibrato + index * 0.6) * (0.6 / (index + 1) ** 0.5)
    tone += 0.18 * np.sin(2 * math.pi * 233.1 * 2 * t)
    tone *= env
    return np.stack([tone * 0.96, tone])


def build_horn(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    out = np.zeros((2, n))
    for start, gain in ((5.6, 0.55), (26.2, 0.38)):
        event = train_horn_event(rng)
        add_wrapped(
            out,
            event,
            start,
            gain=gain,
            pan=float(rng.uniform(-0.25, 0.25)),
        )
    # A barely-there night bed so the silence between horns has an air.
    bed = shaped_noise(n, rng, low=30, high=600, order=2) * 0.035
    out[0] += bed
    out[1] += np.roll(bed, int(0.2 * SR))
    return reverb(out, rng, decay=3.0, mix=0.34, high=2200)


def build_ui_click(rng: np.random.Generator) -> np.ndarray:
    """A crisp, professional mouse click.

    A real mouse click is mostly transient: a tiny plastic contact tick, a
    short resonant body, and a soft low thump from the button. It is over in
    well under a tenth of a second, has no musical pitch, and carries no
    reverb, so it reads as a control rather than an effect.
    """
    n = GEN_N
    out = np.zeros((2, n))

    length = int(0.14 * SR)
    t = np.arange(length) / SR

    # Contact tick: high, dry, and gone almost immediately.
    tick = shaped_noise(length, rng, low=2200, high=9800, order=1)
    tick *= np.exp(-t * 420.0) * (1.0 - np.exp(-t * 9000.0))

    # The hollow plastic body of the button, with two close resonances.
    body = (
        np.sin(2 * math.pi * 1180.0 * t)
        + 0.42 * np.sin(2 * math.pi * 2140.0 * t + 0.6)
        + 0.24 * np.sin(2 * math.pi * 560.0 * t + 1.1)
    )
    body *= np.exp(-t * 78.0) * (1.0 - np.exp(-t * 3200.0))

    # A quiet low thump gives the click weight without turning it into a knock.
    thump = np.sin(2 * math.pi * 148.0 * t) * np.exp(-t * 62.0)
    thump *= 1.0 - np.exp(-t * 1800.0)

    signal = tick * 0.95 + body * 0.52 + thump * 0.30

    # A second, much quieter release tick as the button comes back up.
    release_start = int(0.020 * SR)
    release_len = int(0.012 * SR)
    release = shaped_noise(release_len, rng, low=3200, high=10000, order=1)
    release_t = np.arange(release_len) / SR
    release *= np.exp(-release_t * 520.0) * 0.18
    signal[release_start:release_start + release_len] += release

    # Hard fade to zero before the file ends.
    tail = int(0.004 * SR)
    signal[-tail:] *= np.linspace(1.0, 0.0, tail)

    out[0, :length] = signal * 0.99
    out[1, :length] = signal * 0.96
    return out


# ---------------------------------------------------------------------------
# Sakura Night
# ---------------------------------------------------------------------------


def cricket_chirp(
    carrier: float,
    duration: float,
    pulse_rate: float,
) -> np.ndarray:
    n = max(int(duration * SR), 16)
    t = np.arange(n) / SR
    tone = np.sin(2 * math.pi * carrier * t)
    tone += 0.32 * np.sin(2 * math.pi * carrier * 1.51 * t + 0.4)
    pulse = 0.5 + 0.5 * np.sin(2 * math.pi * pulse_rate * t - math.pi / 2)
    env = np.sin(np.pi * t / duration) ** 1.6
    return tone * pulse * env


def build_sakura_petals(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    base = shaped_noise(n, rng, low=90, high=1500, order=2, tilt=-0.12)
    base2 = shaped_noise(n, rng, low=90, high=1600, order=2, tilt=-0.12)
    leaf = shaped_noise(n, rng, low=1800, high=6800, order=2) * 0.10
    leaf2 = shaped_noise(n, rng, low=1800, high=6800, order=2) * 0.10
    breeze = 0.34 + 0.66 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=1, max_cycles=4))
    breeze2 = 0.34 + 0.66 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=1, max_cycles=4))
    out = np.stack([
        base * breeze + leaf * (0.4 + 0.6 * breeze),
        base2 * breeze2 + leaf2 * (0.4 + 0.6 * breeze2[::-1]),
    ])

    # Soft petals brushing past, not sharp ticks.
    for _ in range(int(GEN_SECONDS * 2.2)):
        ping = damped_ping(rng, float(rng.uniform(900, 2600)), float(rng.uniform(0.02, 0.06)), noise=0.85)
        add_wrapped(
            out,
            ping,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.003, 0.010)),
            pan=float(rng.uniform(-0.9, 0.9)),
        )
    return reverb(out, rng, decay=1.1, mix=0.18, high=6000)


def build_sakura_stream(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    water = shaped_noise(n, rng, low=280, high=3200, order=2) * 0.34
    water2 = shaped_noise(n, rng, low=280, high=3400, order=2) * 0.34
    burble = shaped_noise(n, rng, low=70, high=520, order=2) * 0.30
    flow = 0.62 + 0.38 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=7))
    out = np.stack([
        water * flow + burble,
        water2 * flow[::-1] + np.roll(burble, int(0.13 * SR)) * 0.8,
    ])

    # Small stones and droplets.
    for _ in range(int(GEN_SECONDS * 8)):
        ping = damped_ping(rng, float(rng.uniform(700, 3400)), float(rng.uniform(0.008, 0.035)), noise=0.35)
        add_wrapped(
            out,
            ping,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.004, 0.018)),
            pan=float(rng.uniform(-0.8, 0.8)),
        )
    return reverb(out, rng, decay=1.2, mix=0.22, high=5200)


def build_sakura_chimes(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    out = np.zeros((2, n))
    # A restrained pentatonic koto / glass figure.
    scale = [523.25, 587.33, 659.25, 783.99, 880.0, 1046.5]
    for index in range(26):
        note = scale[int(rng.integers(0, len(scale)))]
        start = float(rng.uniform(0, GEN_SECONDS))
        decay = float(rng.uniform(1.1, 2.8))
        ping = damped_ping(rng, note, decay, noise=0.02)
        add_wrapped(out, ping, start, gain=float(rng.uniform(0.010, 0.028)), pan=float(rng.uniform(-0.6, 0.6)))
        # A quiet upper partial makes it read as glass rather than a pure sine.
        add_wrapped(out, damped_ping(rng, note * 2.01, decay * 0.45, noise=0.01), start, gain=0.006, pan=float(rng.uniform(-0.4, 0.4)))

    # A few night insects, far off.
    for _ in range(42):
        chirp = cricket_chirp(
            float(rng.uniform(3600, 4600)),
            float(rng.uniform(0.05, 0.08)),
            float(rng.uniform(36, 50)),
        )
        add_wrapped(
            out,
            chirp,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.003, 0.009)),
            pan=float(rng.uniform(-0.9, 0.9)),
        )
    return reverb(out, rng, decay=2.2, mix=0.30, high=6200)


# ---------------------------------------------------------------------------
# Cloud Library
# ---------------------------------------------------------------------------


def build_library_rain(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    roof = shaped_noise(n, rng, low=45, high=480, order=2) * 0.72
    hiss = shaped_noise(n, rng, low=600, high=5200, order=2) * 0.12
    hiss2 = shaped_noise(n, rng, low=600, high=5200, order=2) * 0.12
    lfo = 0.74 + 0.26 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=6))
    out = np.stack([
        (roof + hiss) * lfo,
        (np.roll(roof, int(0.09 * SR)) + hiss2) * lfo[::-1],
    ])
    for _ in range(int(GEN_SECONDS * 9)):
        ping = damped_ping(rng, float(rng.uniform(800, 3800)), float(rng.uniform(0.006, 0.025)), noise=0.6)
        add_wrapped(
            out,
            ping,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.003, 0.014)),
            pan=float(rng.uniform(-0.9, 0.9)),
        )
    return reverb(out, rng, decay=1.0, mix=0.18, high=4800)


def build_library_pages(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    out = np.zeros((2, n))
    # Room tone.
    air = shaped_noise(n, rng, low=40, high=900, order=2) * 0.055
    out[0] += air
    out[1] += np.roll(air, int(0.10 * SR)) * 0.85

    # Page turns: a short filtered paper sweep.
    for _ in range(int(GEN_SECONDS * 0.42)):
        duration = float(rng.uniform(0.18, 0.42))
        length = int(duration * SR)
        t = np.arange(length) / SR
        paper = shaped_noise(length, rng, low=1400, high=7800, order=2)
        envelope = np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 1.6
        start = float(rng.uniform(0, GEN_SECONDS))
        add_wrapped(out, paper * envelope * 0.28, start, gain=float(rng.uniform(0.06, 0.16)), pan=float(rng.uniform(-0.5, 0.5)))

    # A distant clock and settling shelves, very quiet.
    for second in range(0, int(GEN_SECONDS), 2):
        tick = damped_ping(rng, 1250.0, 0.018, noise=0.05)
        add_wrapped(out, tick, float(second) + 0.25, gain=0.012, pan=0.15)
    for _ in range(int(GEN_SECONDS * 0.18)):
        creak = damped_ping(rng, float(rng.uniform(90, 220)), float(rng.uniform(0.08, 0.22)), noise=0.7)
        add_wrapped(out, creak, float(rng.uniform(0, GEN_SECONDS)), gain=float(rng.uniform(0.008, 0.020)), pan=float(rng.uniform(-0.7, 0.7)))

    return reverb(out, rng, decay=0.8, mix=0.16, high=5600)


def build_library_hush(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    t = np.arange(n) / SR
    # A warm D major add9 pad, moving slowly across the loop.
    chord = [146.83, 185.00, 220.00, 293.66, 329.63]
    left = np.zeros(n)
    right = np.zeros(n)
    for index, freq in enumerate(chord):
        f = quantized_frequency(freq)
        amp = 0.16 / (index + 1) ** 0.30
        breathe = 0.55 + 0.45 * np.sin(2 * math.pi * (index + 1) * t / LOOP_SECONDS + index * 0.9)
        tone = np.sin(2 * math.pi * f * t + index * 0.6) + 0.10 * np.sin(2 * math.pi * f * 2 * t + index)
        left += tone * amp * breathe
        right += tone * amp * (0.60 + 0.40 * breathe[::-1])

    room = shaped_noise(n, rng, low=35, high=520, order=2) * 0.22
    left += room
    right += np.roll(room, int(0.12 * SR)) * 0.8

    out = np.stack([left, right])

    # A few quiet hearth-like crackles.
    for _ in range(int(GEN_SECONDS * 0.9)):
        ping = damped_ping(rng, float(rng.uniform(500, 2600)), float(rng.uniform(0.006, 0.025)), noise=0.8)
        add_wrapped(out, ping, float(rng.uniform(0, GEN_SECONDS)), gain=float(rng.uniform(0.002, 0.008)), pan=0.0)
    out = bandpass(out, 35, 3000, order=2)
    return reverb(out, rng, decay=2.0, mix=0.26, high=3200)


# ---------------------------------------------------------------------------
# Sunset Drive
# ---------------------------------------------------------------------------


def build_sunset_road(rng: np.random.Generator) -> np.ndarray:
    """The car itself: engine, tires, wind, and traffic passing the other way."""
    n = GEN_N
    t = np.arange(n) / SR

    # Engine: a low, even hum with a few harmonics and a slow load drift.
    load = 0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=4)
    engine = np.zeros(n)
    for harmonic, amp in ((1, 0.42), (2, 0.20), (3, 0.09), (4, 0.04)):
        drift = 1.0 + 0.0016 * np.sin(2 * math.pi * (0.11 + 0.02 * harmonic) * t)
        phase = 2 * math.pi * np.cumsum(44.0 * harmonic * drift) / SR
        engine += amp * np.sin(phase + harmonic * 0.7)
    engine *= 0.55 + 0.45 * load

    # Tire roar and wind, decorrelated between the ears.
    tire_l = shaped_noise(n, rng, low=70.0, high=1150.0, order=2, tilt=-0.16)
    tire_r = shaped_noise(n, rng, low=70.0, high=1200.0, order=2, tilt=-0.16)
    wind_l = shaped_noise(n, rng, low=260.0, high=4800.0, order=2)
    wind_r = shaped_noise(n, rng, low=260.0, high=4900.0, order=2)
    speed_l = 0.55 + 0.45 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=5))
    speed_r = 0.55 + 0.45 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=5))

    out = np.stack([
        engine * 0.30 + tire_l * 0.115 * (0.6 + 0.4 * speed_l) + wind_l * 0.050 * speed_l,
        engine * 0.30 + tire_r * 0.115 * (0.6 + 0.4 * speed_r) + wind_r * 0.050 * speed_r,
    ])

    # Expansion joints and the seam between asphalt sections.
    for _ in range(int(GEN_SECONDS * 1.5)):
        thump = damped_ping(rng, float(rng.uniform(46, 88)), float(rng.uniform(0.03, 0.085)), noise=0.20)
        add_wrapped(
            out,
            thump,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.014, 0.038)),
            pan=float(rng.uniform(-0.30, 0.30)),
        )

    # A car passing the other way: a swell that crosses the stereo field.
    for start in (4.2, 12.8, 21.6, 30.4, 37.4):
        duration = float(rng.uniform(2.4, 3.2))
        length = int(duration * SR)
        tt = np.arange(length) / SR
        envelope = np.sin(np.pi * np.clip(tt / duration, 0, 1)) ** 1.5
        body = shaped_noise(length, rng, low=90.0, high=2400.0, order=2, tilt=-0.10)
        low = shaped_noise(length, rng, low=35.0, high=220.0, order=2)
        pass_by = (body * 0.9 + low * 0.7) * envelope
        direction = 1.0 if rng.random() > 0.5 else -1.0
        start_pan = -0.75 * direction
        end_pan = 0.75 * direction
        for index, pan in enumerate((start_pan, end_pan)):
            pan = float(pan)
            add_wrapped(
                out,
                pass_by if index == 0 else np.roll(pass_by, int(0.06 * SR)),
                start + 0.04 * index,
                gain=float(rng.uniform(0.016, 0.028)),
                pan=pan,
            )

    # A soft gust through the open window.
    for _ in range(int(GEN_SECONDS * 0.8)):
        duration = float(rng.uniform(0.8, 2.2))
        length = int(duration * SR)
        gust = shaped_noise(length, rng, low=240.0, high=4200.0, order=2)
        gust *= np.sin(np.linspace(0, math.pi, length)) ** 2
        add_wrapped(
            out,
            gust,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.005, 0.018)),
            pan=float(rng.uniform(-0.8, 0.8)),
        )
    return reverb(out, rng, decay=0.9, mix=0.12, high=5200.0)


def midi_hz(note: float) -> float:
    return 440.0 * 2.0 ** ((note - 69.0) / 12.0)


def ep_note(
    rng: np.random.Generator,
    freq: float,
    duration: float,
    velocity: float = 1.0,
) -> np.ndarray:
    """A warm FM electric piano: bell-like tine, then a mellow body."""
    n = max(int(duration * SR), 32)
    t = np.arange(n) / SR
    attack = np.clip(t / 0.006, 0.0, 1.0)
    release = np.clip((duration - t) / 0.30, 0.0, 1.0)
    # The modulation index falls away quickly, so the note blooms then softens.
    index = 0.85 * np.exp(-t / 0.22) + 0.10
    mod = np.sin(2 * math.pi * freq * 2.0 * t + 0.4) * index
    carrier = np.sin(2 * math.pi * freq * t + mod)
    body = 0.22 * np.sin(2 * math.pi * freq * t + 0.15)
    tine = 0.09 * np.sin(2 * math.pi * freq * 6.98 * t) * np.exp(-t / 0.05)
    tremolo = 1.0 + 0.035 * np.sin(2 * math.pi * 4.2 * t + float(rng.uniform(0, 6)))
    decay = np.exp(-t / max(duration * 1.9, 0.5))
    return (carrier + body + tine) * attack * release * tremolo * decay * velocity


def pluck_note(
    rng: np.random.Generator,
    freq: float,
    duration: float,
    velocity: float = 1.0,
    brightness: float = 0.55,
) -> np.ndarray:
    """A nylon-string pluck: inharmonic partials plus a short pick transient."""
    n = max(int(duration * SR), 32)
    t = np.arange(n) / SR
    attack = np.clip(t / 0.0035, 0.0, 1.0)
    release = np.clip((duration - t) / 0.16, 0.0, 1.0)
    sig = np.zeros(n)
    for partial in range(1, 9):
        amp = (1.0 / partial ** 1.35) * (brightness ** (partial - 1))
        decay = 1.5 + 1.8 * partial
        sig += amp * np.sin(2 * math.pi * freq * partial * t + 0.13 * partial) * np.exp(-t * decay)
    pick = shaped_noise(n, rng, low=freq * 2.0, high=9000.0, order=1) * np.exp(-t / 0.007) * 0.22
    return (sig + pick) * attack * release * velocity


def string_pad_note(
    rng: np.random.Generator,
    freq: float,
    duration: float,
    velocity: float = 1.0,
) -> np.ndarray:
    """Bowed strings: slow swell, gentle vibrato, slightly detuned partials."""
    n = max(int(duration * SR), 32)
    t = np.arange(n) / SR
    attack = np.clip(t / 0.62, 0.0, 1.0) ** 1.4
    release = np.clip((duration - t) / 0.70, 0.0, 1.0) ** 1.1
    vibrato = 1.0 + 0.0022 * np.sin(2 * math.pi * 4.5 * t + float(rng.uniform(0, 6)))
    phase = 2 * math.pi * np.cumsum(freq * vibrato) / SR
    sig = np.zeros(n)
    for partial in range(1, 9):
        detune = 1.0 + (0.0012 if partial % 2 else -0.0010)
        sig += (1.0 / partial ** 1.45) * np.sin(phase * partial * detune + 0.37 * partial)
    return sig * attack * release * velocity


def flute_note(
    rng: np.random.Generator,
    freq: float,
    duration: float,
    velocity: float = 1.0,
    glide_from: float | None = None,
) -> np.ndarray:
    """A soft wooden flute, with a breathy attack and a late vibrato."""
    n = max(int(duration * SR), 32)
    t = np.arange(n) / SR
    attack = np.clip(t / 0.10, 0.0, 1.0)
    release = np.clip((duration - t) / 0.40, 0.0, 1.0)
    depth = 0.0042 * np.clip((t - 0.16) / 0.7, 0.0, 1.0)
    vibrato = 1.0 + depth * np.sin(2 * math.pi * 5.1 * t)
    if glide_from is None:
        contour = np.full(n, freq)
    else:
        contour = glide_from + (freq - glide_from) * (1.0 - np.exp(-t / 0.085))
    phase = 2 * math.pi * np.cumsum(contour * vibrato) / SR
    tone = (
        np.sin(phase)
        + 0.16 * np.sin(2 * phase + 0.2)
        + 0.07 * np.sin(3 * phase + 0.7)
        + 0.025 * np.sin(4 * phase + 0.4)
    )
    breath = shaped_noise(n, rng, low=1800.0, high=6200.0, order=1) * 0.020 * np.exp(-t / 0.45)
    return (tone + breath) * attack * release * velocity


def soft_kick(rng: np.random.Generator, duration: float = 0.42) -> np.ndarray:
    n = max(int(duration * SR), 32)
    t = np.arange(n) / SR
    freq = 96.0 * np.exp(-t / 0.055) + 43.0
    phase = 2 * math.pi * np.cumsum(freq) / SR
    env = np.clip(t / 0.004, 0.0, 1.0) * np.exp(-t / 0.13)
    click = shaped_noise(n, rng, low=220.0, high=3200.0, order=1) * np.exp(-t / 0.006) * 0.14
    return (np.sin(phase) + click) * env


def shaker(rng: np.random.Generator, duration: float = 0.09) -> np.ndarray:
    n = max(int(duration * SR), 16)
    t = np.arange(n) / SR
    noise = shaped_noise(n, rng, low=3600.0, high=11000.0, order=1)
    env = np.clip(t / 0.002, 0.0, 1.0) * np.exp(-t / 0.026)
    return noise * env


def rim_click(rng: np.random.Generator, duration: float = 0.13) -> np.ndarray:
    n = max(int(duration * SR), 16)
    t = np.arange(n) / SR
    noise = shaped_noise(n, rng, low=1300.0, high=5200.0, order=1)
    tone = np.sin(2 * math.pi * 1720.0 * t) * 0.35
    env = np.exp(-t / 0.017)
    return (noise * 0.8 + tone) * env


def bass_note(rng: np.random.Generator, freq: float, duration: float) -> np.ndarray:
    n = max(int(duration * SR), 16)
    t = np.arange(n) / SR
    attack = np.clip(t / 0.05, 0.0, 1.0)
    release = np.clip((duration - t) / 0.30, 0.0, 1.0)
    env = attack * release
    phase = 2 * math.pi * freq * t
    tone = np.sin(phase) + 0.18 * np.sin(phase * 2 + 0.4)
    return tone * env


def brush_hit(rng: np.random.Generator, duration: float = 0.20) -> np.ndarray:
    n = max(int(duration * SR), 16)
    t = np.arange(n) / SR
    noise = shaped_noise(n, rng, low=1400, high=9000, order=1)
    env = np.exp(-t * 28.0) * (1.0 - np.exp(-t * 220.0))
    return noise * env


def gull_call(rng: np.random.Generator, duration: float = 0.55) -> np.ndarray:
    n = max(int(duration * SR), 16)
    t = np.arange(n) / SR
    start = float(rng.uniform(1050, 1450))
    end = start * float(rng.uniform(0.58, 0.72))
    freq = np.linspace(start, end, n)
    phase = 2 * math.pi * np.cumsum(freq) / SR
    env = np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 2
    tone = np.sin(phase) + 0.26 * np.sin(phase * 2.01 + 0.4)
    return tone * env


def ride_cymbal(rng: np.random.Generator, duration: float = 0.85) -> np.ndarray:
    n = max(int(duration * SR), 32)
    t = np.arange(n) / SR
    noise = shaped_noise(n, rng, low=3800.0, high=12000.0, order=1)
    bell = 0.16 * np.sin(2 * math.pi * 3150.0 * t) + 0.09 * np.sin(2 * math.pi * 4720.0 * t + 0.6)
    env = np.clip(t / 0.004, 0.0, 1.0) * np.exp(-t / 0.24)
    return (noise * 0.9 + bell) * env


def build_sunset_song(rng: np.random.Generator) -> np.ndarray:
    """An original 40-second ballad for the drive, in F major at 72 BPM.

    Twelve bars, three four-bar phrases, a real chord progression
    (Fmaj9 - Am7 - Bbmaj7 - Cadd9 - Dm9 - Bbmaj7 - Gm9 - C7sus4 -
    Fmaj9 - Am7 - Bbmaj7/C7 - Fmaj9), a composed melody, and a
    fingerpicked guitar, electric piano, upright bass, strings and
    brushed drums. The loop opens and closes quietly so it can repeat
    for an hour without a seam.
    """
    n = GEN_N
    out = np.zeros((2, n))

    bpm = 72.0
    beat = 60.0 / bpm
    bar = beat * 4.0

    # One voicing per bar. Bar 11 changes chord halfway through.
    f_maj9 = [53, 57, 60, 64, 67]      # F3 A3 C4 E4 G4
    a_min7 = [57, 60, 64, 67]          # A3 C4 E4 G4
    bb_maj7 = [58, 62, 65, 69]         # Bb3 D4 F4 A4
    c_add9 = [60, 64, 67, 74]          # C4 E4 G4 D5
    d_min9 = [50, 53, 57, 60, 64]      # D3 F3 A3 C4 E4
    g_min9 = [55, 58, 62, 65, 69]      # G3 Bb3 D4 F4 A4
    c_7sus4 = [60, 65, 67, 70]         # C4 F4 G4 Bb4
    c_7 = [60, 64, 67, 70]             # C4 E4 G4 Bb4

    bars: list[tuple[list[int], list[tuple[float, list[int]]]]] = [
        (f_maj9, [(0.0, f_maj9)]),
        (a_min7, [(0.0, a_min7)]),
        (bb_maj7, [(0.0, bb_maj7)]),
        (c_add9, [(0.0, c_add9)]),
        (d_min9, [(0.0, d_min9)]),
        (bb_maj7, [(0.0, bb_maj7)]),
        (g_min9, [(0.0, g_min9)]),
        (c_7sus4, [(0.0, c_7sus4)]),
        (f_maj9, [(0.0, f_maj9)]),
        (a_min7, [(0.0, a_min7)]),
        (bb_maj7, [(0.0, bb_maj7), (2.0, c_7)]),
        (f_maj9, [(0.0, f_maj9)]),
    ]

    bass_roots = [41, 45, 46, 48, 50, 46, 43, 48, 41, 45, 46, 41]  # F2 A2 Bb2 C3 D3 Bb2 G2 C3 F2 A2 Bb2 F2

    # --- Electric piano -----------------------------------------------------
    for bar_index, (_, changes) in enumerate(bars):
        for change_beat, voicing in changes:
            start = bar_index * bar + change_beat * beat
            span = bar * (1.0 if change_beat == 0.0 else 0.5)
            for hit, hit_beat, scale in ((0, 0.0, 1.0), (1, 2.0, 0.48)):
                if change_beat == 2.0 and hit_beat > 0.0:
                    continue
                for note_index, midi in enumerate(voicing):
                    velocity = float(rng.uniform(0.85, 1.0)) * scale / (1.0 + note_index * 0.14)
                    add_wrapped(
                        out,
                        ep_note(rng, midi_hz(midi), span * 0.96, velocity),
                        start + hit_beat * beat + note_index * 0.014,
                        gain=0.022,
                        pan=float(rng.uniform(-0.34, 0.10)),
                    )

    # --- Fingerpicked guitar -------------------------------------------------
    for bar_index, (voicing, _) in enumerate(bars):
        start = bar_index * bar
        root, third, fifth = voicing[0], voicing[1], voicing[2]
        seventh = voicing[3] if len(voicing) > 3 else voicing[2] + 3
        ninth = voicing[4] if len(voicing) > 4 else voicing[1] + 12
        pattern = [
            (root + 12, 0.0),
            (fifth, 0.5),
            (ninth, 1.0),
            (third + 12, 1.5),
            (seventh + 12, 2.0),
            (fifth + 12, 2.5),
            (third + 12, 3.0),
            (ninth, 3.5),
        ]
        for index, (midi, offset) in enumerate(pattern):
            humanized = offset * beat + float(rng.uniform(-0.014, 0.014))
            add_wrapped(
                out,
                pluck_note(
                    rng,
                    midi_hz(midi),
                    float(rng.uniform(0.85, 1.35)),
                    float(rng.uniform(0.72, 0.95)),
                ),
                start + humanized,
                gain=0.050 if index % 4 == 0 else 0.036,
                pan=0.24 + float(rng.uniform(-0.12, 0.12)),
            )

    # --- Upright bass --------------------------------------------------------
    for bar_index, root in enumerate(bass_roots):
        start = bar_index * bar
        add_wrapped(out, bass_note(rng, midi_hz(root), beat * 1.85), start, gain=0.062, pan=-0.04)
        if bar_index < 11:
            add_wrapped(
                out,
                bass_note(rng, midi_hz(root + 7), beat * 1.35),
                start + 2.0 * beat,
                gain=0.038,
                pan=-0.04,
            )

    # --- Strings -------------------------------------------------------------
    for bar_index, (voicing, _) in enumerate(bars):
        start = bar_index * bar
        span = bar * 1.05 if bar_index < 11 else bar
        for note_index, midi in enumerate(voicing[1:]):
            add_wrapped(
                out,
                string_pad_note(rng, midi_hz(midi + 12), span, float(rng.uniform(0.55, 0.75))),
                start + 0.02 * note_index,
                gain=0.0085,
                pan=-0.42 + 0.20 * note_index,
            )

    # --- Brushed drums -------------------------------------------------------
    for bar_index in range(2, 12):
        start = bar_index * bar
        light = bar_index >= 10
        for offset in (0.0, 2.0):
            add_wrapped(out, soft_kick(rng), start + offset * beat, gain=0.044 if not light else 0.034)
        for offset in (1.0, 3.0):
            add_wrapped(
                out,
                brush_hit(rng),
                start + offset * beat,
                gain=0.0105 if not light else 0.0075,
                pan=float(rng.uniform(-0.22, 0.22)),
            )
        if bar_index < 10:
            for offset in (0.0, 2.0):
                add_wrapped(
                    out,
                    ride_cymbal(rng),
                    start + offset * beat,
                    gain=0.0042,
                    pan=0.36,
                )
        if bar_index >= 4:
            for eighth in range(8):
                if eighth % 2 == 1 and bar_index < 10:
                    continue
                add_wrapped(
                    out,
                    shaker(rng),
                    start + eighth * beat * 0.5 + float(rng.uniform(-0.006, 0.006)),
                    gain=0.0042 if eighth % 2 == 0 else 0.0028,
                    pan=0.30 if eighth % 2 == 0 else -0.24,
                )
    add_wrapped(out, rim_click(rng), 7 * bar + 3.0 * beat, gain=0.012, pan=0.10)

    # --- Composed melody -----------------------------------------------------
    # (bar, beat, MIDI note, length in beats)
    melody = [
        (0, 0.0, 69, 2.0), (0, 2.0, 72, 1.0), (0, 3.0, 77, 1.55),
        (1, 0.5, 76, 0.95), (1, 1.5, 74, 0.95), (1, 2.5, 72, 1.75),
        (2, 0.0, 74, 1.15), (2, 1.4, 77, 1.15), (2, 2.8, 79, 1.55),
        (3, 0.0, 76, 1.35), (3, 1.6, 74, 0.95), (3, 2.8, 72, 1.75),
        (4, 0.0, 77, 1.75), (4, 2.0, 76, 0.95), (4, 3.0, 74, 0.95),
        (5, 0.0, 72, 1.35), (5, 1.6, 74, 1.15), (5, 3.0, 77, 1.35),
        (6, 0.0, 79, 1.55), (6, 2.0, 77, 0.95), (6, 3.0, 74, 1.15),
        (7, 0.0, 76, 1.15), (7, 1.4, 74, 1.15), (7, 2.6, 72, 2.15),
        (8, 0.0, 72, 0.85), (8, 1.1, 77, 1.55), (8, 2.9, 79, 1.15),
        (9, 0.0, 76, 1.55), (9, 2.0, 72, 0.95), (9, 3.0, 74, 1.15),
        (10, 0.0, 77, 1.15), (10, 1.4, 74, 1.15), (10, 2.8, 76, 1.15),
        (11, 0.0, 77, 2.6),
    ]
    previous: float | None = None
    for bar_index, beat_offset, midi, length_beats in melody:
        freq = midi_hz(midi)
        glide = previous if previous is not None and abs(previous - freq) < 90 else None
        add_wrapped(
            out,
            flute_note(
                rng,
                freq,
                length_beats * beat * 0.98,
                float(rng.uniform(0.85, 1.0)),
                glide_from=glide,
            ),
            bar_index * bar + beat_offset * beat,
            gain=0.108,
            pan=0.04 + float(rng.uniform(-0.05, 0.05)),
        )
        add_wrapped(
            out,
            flute_note(
                rng,
                freq * 1.0035,
                length_beats * beat * 0.98,
                0.55,
                glide_from=None if glide is None else glide * 1.0035,
            ),
            bar_index * bar + beat_offset * beat + 0.012,
            gain=0.038,
            pan=-0.14,
        )
        previous = freq

    # A quiet lower line under the last phrase, like a second player.
    for bar_index, beat_offset, midi, length_beats in (
        (8, 0.0, 65, 2.0),
        (9, 0.0, 64, 2.0),
        (10, 0.0, 65, 2.0),
        (11, 0.0, 65, 3.0),
    ):
        add_wrapped(
            out,
            flute_note(rng, midi_hz(midi), length_beats * beat, 0.45),
            bar_index * bar + beat_offset * beat,
            gain=0.032,
            pan=-0.18,
        )

    # --- Tape air and a little stereo width ----------------------------------
    air = shaped_noise(n, rng, low=180.0, high=2600.0, order=2, tilt=-0.12) * 0.010
    out[0] += air
    out[1] += np.roll(air, int(0.17 * SR)) * 0.90

    # A gentle bus glue, a little air above 2 kHz, then a warm room.
    out = np.tanh(out * 1.15) / 1.15
    spectrum = np.fft.rfft(out, axis=1)
    freqs = np.fft.rfftfreq(out.shape[1], 1 / SR)
    shelf = 1.0 / (1.0 + (2200.0 / np.maximum(freqs, 1.0)) ** 2)
    spectrum *= (10.0 ** (2.4 / 20.0)) ** shelf
    out = np.fft.irfft(spectrum, out.shape[1], axis=1)
    return reverb(out, rng, decay=2.1, mix=0.26, high=5600.0)


def buoy_bell(rng: np.random.Generator, duration: float = 3.2) -> np.ndarray:
    n = max(int(duration * SR), 32)
    t = np.arange(n) / SR
    env = np.clip(t / 0.01, 0.0, 1.0) * np.exp(-t / 0.75)
    tone = (
        np.sin(2 * math.pi * 523.0 * t)
        + 0.45 * np.sin(2 * math.pi * 786.0 * t + 0.4)
        + 0.22 * np.sin(2 * math.pi * 1180.0 * t + 0.9)
    )
    return tone * env * 0.4


def build_sunset_air(rng: np.random.Generator) -> np.ndarray:
    """Coastal air: breeze, surf, gulls, and a far buoy keeping time."""
    n = GEN_N
    breeze = shaped_noise(n, rng, low=120.0, high=5200.0, order=2, tilt=-0.05) * 0.20
    breeze2 = shaped_noise(n, rng, low=120.0, high=5400.0, order=2, tilt=-0.05) * 0.20
    surf = shaped_noise(n, rng, low=55.0, high=950.0, order=2) * 0.13
    surf2 = shaped_noise(n, rng, low=55.0, high=980.0, order=2) * 0.13
    gust = 0.45 + 0.55 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=6))
    gust2 = 0.45 + 0.55 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=6))
    out = np.stack([
        breeze * gust + surf,
        breeze2 * gust2[::-1] + np.roll(surf2, int(0.21 * SR)) * 0.86,
    ])

    # Distant waves arriving and drawing back.
    for start in (2.4, 9.6, 17.1, 24.4, 31.8):
        duration = float(rng.uniform(3.0, 5.0))
        length = int(duration * SR)
        tt = np.arange(length) / SR
        swell = shaped_noise(length, rng, low=100.0, high=2600.0, order=2)
        envelope = np.sin(np.pi * np.clip(tt / duration, 0, 1)) ** 1.7
        add_wrapped(
            out,
            swell * envelope,
            start + float(rng.uniform(-0.30, 0.30)),
            gain=float(rng.uniform(0.045, 0.085)),
            pan=float(rng.uniform(-0.45, 0.45)),
        )

    # A few far-off gulls, never close enough to pull focus.
    for start in (6.4, 18.7, 30.2):
        add_wrapped(
            out,
            gull_call(rng),
            start,
            gain=float(rng.uniform(0.008, 0.014)),
            pan=float(rng.uniform(-0.65, 0.65)),
        )
        add_wrapped(
            out,
            gull_call(rng, duration=float(rng.uniform(0.35, 0.50))),
            start + float(rng.uniform(0.55, 0.90)),
            gain=float(rng.uniform(0.005, 0.010)),
            pan=float(rng.uniform(-0.65, 0.65)),
        )

    # A buoy bell, far out beyond the headland.
    for start in (5.5, 18.5, 31.5):
        add_wrapped(out, buoy_bell(rng), start, gain=0.006, pan=float(rng.uniform(-0.5, 0.5)))

    return reverb(out, rng, decay=1.7, mix=0.18, high=5000.0)


# ---------------------------------------------------------------------------
# Seaside Records
# ---------------------------------------------------------------------------


def build_seaside_vinyl(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    t = np.arange(n) / SR

    # A warm room hum and the low hiss of a record between tracks.
    hum = 0.010 * np.sin(2 * math.pi * 55.0 * t)
    hum += 0.004 * np.sin(2 * math.pi * 110.0 * t + 0.5)
    hiss = shaped_noise(n, rng, low=900, high=6800, order=2) * 0.045
    room = shaped_noise(n, rng, low=35, high=700, order=2) * 0.10
    out = np.stack([
        hum + hiss + room,
        hum * 0.94 + np.roll(hiss, int(0.08 * SR)) * 0.85 + room,
    ])

    # Fine surface crackle, dense but very quiet.
    for _ in range(int(GEN_SECONDS * 13)):
        ping = damped_ping(
            rng,
            float(rng.uniform(1500, 6800)),
            float(rng.uniform(0.001, 0.007)),
            noise=1.0,
        )
        add_wrapped(
            out,
            ping,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.0015, 0.011)),
            pan=float(rng.uniform(-0.85, 0.85)),
        )

    # A few larger pops and dust clicks.
    for _ in range(int(GEN_SECONDS * 1.3)):
        pop = damped_ping(
            rng,
            float(rng.uniform(180, 950)),
            float(rng.uniform(0.008, 0.032)),
            noise=0.85,
        )
        add_wrapped(
            out,
            pop,
            float(rng.uniform(0, GEN_SECONDS)),
            gain=float(rng.uniform(0.008, 0.042)),
            pan=float(rng.uniform(-0.55, 0.55)),
        )
    return reverb(out, rng, decay=0.6, mix=0.08, high=7200)


def build_seaside_waves(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    base = shaped_noise(n, rng, low=28, high=1300, order=2, tilt=-0.05)
    base2 = shaped_noise(n, rng, low=28, high=1400, order=2, tilt=-0.05)
    wash = shaped_noise(n, rng, low=320, high=5200, order=2) * 0.09
    wash2 = shaped_noise(n, rng, low=320, high=5200, order=2) * 0.09
    tide = 0.44 + 0.56 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=5))
    tide2 = 0.44 + 0.56 * (0.5 + 0.5 * slow_lfo(n, rng, min_cycles=2, max_cycles=5))
    out = np.stack([
        base * tide + wash * tide,
        base2 * tide2 + wash2 * tide2[::-1],
    ])

    # Individual waves arriving and drawing back.
    for start in (1.8, 7.4, 13.1, 19.6, 26.0, 32.2, 37.4):
        duration = float(rng.uniform(3.2, 5.4))
        length = int(duration * SR)
        t = np.arange(length) / SR
        swell = shaped_noise(length, rng, low=110, high=3000, order=2)
        envelope = np.sin(np.pi * np.clip(t / duration, 0, 1)) ** 1.8
        add_wrapped(
            out,
            swell * envelope,
            start + float(rng.uniform(-0.35, 0.35)),
            gain=float(rng.uniform(0.07, 0.15)),
            pan=float(rng.uniform(-0.55, 0.55)),
        )

    # A low, soft sea rumble.
    rumble = shaped_noise(n, rng, low=24, high=140, order=2) * 0.22
    out[0] += rumble
    out[1] += np.roll(rumble, int(0.23 * SR)) * 0.9
    return reverb(out, rng, decay=1.8, mix=0.20, high=4800)


def piano_note(rng: np.random.Generator, freq: float, duration: float) -> np.ndarray:
    n = max(int(duration * SR), 64)
    t = np.arange(n) / SR
    attack = 1.0 - np.exp(-t * 210.0)
    signal = np.zeros(n)
    partials = [(1.0, 1.00, 1.00), (2.0, 0.44, 0.68), (3.0, 0.22, 0.50), (4.0, 0.11, 0.38), (5.0, 0.055, 0.28)]
    for ratio, amp, decay_scale in partials:
        signal += (
            amp
            * np.sin(2 * math.pi * freq * ratio * t + ratio * 0.35)
            * np.exp(-t * (2.4 / decay_scale))
        )
    hammer = shaped_noise(n, rng, high=4200, order=1) * np.exp(-t * 95.0) * 0.05
    return (signal * attack + hammer) * np.exp(-t * 0.35)


def build_seaside_piano(rng: np.random.Generator) -> np.ndarray:
    n = GEN_N
    out = np.zeros((2, n))

    # Warm, slightly nostalgic voicings: Cmaj7, Am9, Fmaj7, G6.
    chords = [
        (1.6, [261.63, 329.63, 392.00, 493.88]),
        (8.4, [220.00, 261.63, 329.63, 392.00, 493.88]),
        (16.2, [174.61, 220.00, 261.63, 329.63]),
        (24.0, [196.00, 246.94, 293.66, 329.63]),
        (31.8, [261.63, 329.63, 392.00, 493.88]),
    ]
    for start, notes in chords:
        for index, freq in enumerate(notes):
            note = piano_note(rng, freq, float(rng.uniform(3.2, 5.2)))
            add_wrapped(
                out,
                note,
                start + index * float(rng.uniform(0.03, 0.10)),
                gain=float(rng.uniform(0.030, 0.060)) / (1.0 + index * 0.22),
                pan=float(rng.uniform(-0.45, 0.45)),
            )

    # A quiet room bed beneath the piano.
    room = shaped_noise(n, rng, low=40, high=900, order=2) * 0.040
    out[0] += room
    out[1] += np.roll(room, int(0.11 * SR)) * 0.85
    return reverb(out, rng, decay=2.4, mix=0.30, high=4200)


# ---------------------------------------------------------------------------
# Assembly
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class LayerSpec:
    environment: str
    layer: str
    builder: object
    target_rms_db: float
    peak_db: float
    seed: int


SPECS = [
    LayerSpec("rainy-cabin", "rain", build_rain, -20.0, -5.5, 101),
    LayerSpec("rainy-cabin", "thunder", build_thunder, -32.0, -8.0, 102),
    LayerSpec("rainy-cabin", "fireplace", build_fireplace, -25.0, -10.0, 103),
    LayerSpec("train", "rhythm", build_rail_rhythm, -23.0, -7.0, 601),
    LayerSpec("train", "carriage", build_carriage, -28.0, -11.0, 602),
    LayerSpec("train", "horn", build_horn, -33.0, -10.0, 603),
    LayerSpec("sakura-night", "petals", build_sakura_petals, -29.0, -12.0, 701),
    LayerSpec("sakura-night", "stream", build_sakura_stream, -27.0, -10.0, 702),
    LayerSpec("sakura-night", "chimes", build_sakura_chimes, -32.0, -12.0, 703),
    LayerSpec("cloud-library", "window-rain", build_library_rain, -27.0, -10.0, 711),
    LayerSpec("cloud-library", "pages", build_library_pages, -34.0, -18.0, 712),
    LayerSpec("cloud-library", "hush", build_library_hush, -30.0, -14.0, 713),
    LayerSpec("sunset-drive", "road", build_sunset_road, -27.0, -10.0, 801),
    LayerSpec("sunset-drive", "song", build_sunset_song, -25.0, -9.0, 802),
    LayerSpec("sunset-drive", "air", build_sunset_air, -28.0, -11.0, 803),
    LayerSpec("seaside-records", "vinyl", build_seaside_vinyl, -34.0, -16.0, 811),
    LayerSpec("seaside-records", "waves", build_seaside_waves, -25.0, -9.0, 812),
    LayerSpec("seaside-records", "piano", build_seaside_piano, -33.0, -14.0, 813),
    LayerSpec("ui", "click", build_ui_click, -27.0, -6.5, 901),
]


def mix_signals(a: np.ndarray, b: np.ndarray, gain: float = 1.0) -> np.ndarray:
    length = max(len(a), len(b))
    out = np.zeros(length)
    out[: len(a)] += a
    out[: len(b)] += b * gain
    return out


def float_to_int16(x: np.ndarray, rng: np.random.Generator) -> np.ndarray:
    x = np.clip(x, -1, 1)
    dither = (rng.random(x.shape) - rng.random(x.shape)) / 32768.0
    return np.clip(np.round((x + dither) * 32767.0), -32768, 32767).astype(np.int16)


def write_wav(path: Path, samples: np.ndarray, rng: np.random.Generator) -> None:
    interleaved = float_to_int16(samples, rng).T.reshape(-1)
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(2)
        handle.setsampwidth(2)
        handle.setframerate(SR)
        handle.writeframes(interleaved.tobytes())


def main() -> None:
    # Optional filter: `python3 Tools/generate_audio.py sunset-drive` rebuilds
    # only that ambience and keeps the other manifest entries intact.
    requested = {arg for arg in sys.argv[1:] if not arg.startswith("-")}
    selected = [
        spec
        for spec in SPECS
        if not requested or spec.environment in requested or f"{spec.environment}/{spec.layer}" in requested
    ]
    if requested and not selected:
        raise SystemExit(f"No layers match {sorted(requested)}")

    OUTPUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "description": "Original soundscapes synthesized for Quietude.",
        "license": "CC0 1.0 Universal (public domain dedication)",
        "sample_rate": SR,
        "channels": 2,
        "loop_seconds": LOOP_SECONDS,
        "format": "M4A / AAC 128 kbps",
        "generator": "Tools/generate_audio.py",
        "layers": [],
    }

    manifest_path = OUTPUT / "manifest.json"
    entries: dict[str, dict] = {}
    if manifest_path.exists():
        try:
            for entry in json.loads(manifest_path.read_text()).get("layers", []):
                entries[entry["file"]] = entry
        except (ValueError, KeyError, TypeError):
            entries = {}

    with tempfile.TemporaryDirectory() as temporary:
        temp = Path(temporary)
        for spec in selected:
            rng = np.random.default_rng(spec.seed)
            print(f"building {spec.environment}/{spec.layer} ...", flush=True)
            raw = spec.builder(rng)
            if raw.shape[0] == 1:
                raw = np.repeat(raw, 2, axis=0)
            if spec.environment == "ui":
                # A one-shot at the head of the file must not be faded in by
                # the ambience loop crossfade.
                raw = raw[..., :OUT_N]
            else:
                raw = loopify(raw)
            assert raw.shape == (2, OUT_N), raw.shape
            final = normalize(raw, spec.target_rms_db, spec.peak_db)
            final_peak = float(np.max(np.abs(final)))
            final_rms = rms(final)

            wav_path = temp / f"{spec.environment}-{spec.layer}.wav"
            out_dir = OUTPUT / spec.environment
            out_dir.mkdir(parents=True, exist_ok=True)
            caf_path = out_dir / f"{spec.layer}.m4a"
            write_wav(wav_path, final, rng)
            result = subprocess.run(
                ["afconvert", "-f", "m4af", "-d", "aac", "-b", "128000", "-c", "2", str(wav_path), str(caf_path)],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                raise RuntimeError(f"afconvert failed for {caf_path}: {result.stderr}")
            size = caf_path.stat().st_size
            entry = {
                "file": f"{spec.environment}/{spec.layer}.m4a",
                "rms_dbfs": round(20 * math.log10(final_rms + 1e-12), 2),
                "peak_dbfs": round(20 * math.log10(final_peak + 1e-12), 2),
                "seconds": LOOP_SECONDS,
                "bytes": size,
                "method": spec.builder.__name__,
            }
            entries[entry["file"]] = entry
            print(
                f"  {entry['file']}  {size/1024:.0f} KiB  "
                f"RMS {entry['rms_dbfs']} dBFS  peak {entry['peak_dbfs']} dBFS"
            )

    manifest["layers"] = [
        entries[f"{spec.environment}/{spec.layer}.m4a"]
        for spec in SPECS
        if f"{spec.environment}/{spec.layer}.m4a" in entries
    ]
    missing = len(SPECS) - len(manifest["layers"])
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    total_bytes = sum(layer["bytes"] for layer in manifest["layers"])
    print(f"\n{len(manifest['layers'])} layers, {total_bytes / 1024 / 1024:.1f} MiB total")
    if missing:
        print(f"warning: {missing} layers are not built yet")
    print(f"manifest: {manifest_path}")


if __name__ == "__main__":
    main()
