#!/usr/bin/env python3
"""Generate procedural placeholder audio for every cue in the manifest.

Pure-stdlib synthesis (no numpy/ffmpeg) so it runs anywhere. Output: mono
16-bit WAV, peak-normalized, loop-crossfaded where the manifest says loop.
These are original works (see ASSETS.md) meant to make the game fully
playable until the curated/final sound pass replaces them file-by-file.

Usage: python3 Tools/generate_placeholder_audio.py
"""
import math
import os
import random
import struct
import wave

SR = 32000
OUT_DIR = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets", "Audio"))
random.seed(7)

# ---------------------------------------------------------------- primitives

def silence(dur):
    return [0.0] * int(dur * SR)


def mix(dst, src, at=0.0, gain=1.0):
    start = int(at * SR)
    for i, sample in enumerate(src):
        j = start + i
        if 0 <= j < len(dst):
            dst[j] += sample * gain
    return dst


def tone(freq, dur, gain=1.0, partials=((1, 1.0),), attack=0.01, decay=None,
         vibrato=0.0, vib_rate=5.0, sweep_to=None):
    n = int(dur * SR)
    out = [0.0] * n
    phase = 0.0
    for i in range(n):
        t = i / SR
        f = freq if sweep_to is None else freq + (sweep_to - freq) * (t / dur)
        if vibrato:
            f *= 1.0 + vibrato * math.sin(2 * math.pi * vib_rate * t)
        phase += 2 * math.pi * f / SR
        s = sum(g * math.sin(phase * m) for m, g in partials)
        env = min(1.0, t / attack) if attack > 0 else 1.0
        if decay is not None:
            env *= math.exp(-t / decay)
        else:
            env *= min(1.0, max(0.0, (dur - t) / 0.02))
        out[i] = s * env * gain
    return out


def white(dur, gain=1.0):
    return [random.uniform(-1.0, 1.0) * gain for _ in range(int(dur * SR))]


def lowpass(sig, cutoff):
    rc = 1.0 / (2 * math.pi * cutoff)
    dt = 1.0 / SR
    alpha = dt / (rc + dt)
    out, y = [], 0.0
    for x in sig:
        y += alpha * (x - y)
        out.append(y)
    return out


def highpass(sig, cutoff):
    lp = lowpass(sig, cutoff)
    return [x - l for x, l in zip(sig, lp)]


def bandpass(sig, low, high):
    return highpass(lowpass(sig, high), low)


def shaped(sig, func):
    return [s * func(i / SR) for i, s in enumerate(sig)]


def fade_edges(sig, dur=0.05):
    n = int(dur * SR)
    for i in range(min(n, len(sig))):
        a = i / n
        sig[i] *= a
        sig[-1 - i] *= a
    return sig


def loopify(sig, fade=0.4):
    """Crossfade the tail into a copy of the head so wrap-around is smooth."""
    n = int(fade * SR)
    total = len(sig)
    for i in range(min(n, total // 2)):
        a = i / n
        sig[total - n + i] = sig[total - n + i] * (1 - a) + sig[i] * a
    return sig


def normalize(sig, peak=0.8):
    m = max(max(sig), -min(sig), 1e-9)
    return [s * peak / m for s in sig]


def write_wav(name, sig, peak=0.8):
    sig = normalize(sig, peak)
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(SR)
        frames = bytearray()
        for s in sig:
            frames += struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767))
        f.writeframes(bytes(frames))
    print(f"  {name}  ({len(sig) / SR:.1f}s, {os.path.getsize(path) // 1024} KB)")


# ------------------------------------------------------------- scene sounds

def wind_leaves_loop():
    base = lowpass(white(6.0), 500)
    rustle = bandpass(white(6.0), 1500, 4000)
    sig = [b * (0.7 + 0.3 * math.sin(2 * math.pi * (1 / 3.0) * i / SR))
           + r * 0.18 * (0.5 + 0.5 * math.sin(2 * math.pi * (1 / 2.0) * i / SR + 1.3))
           for i, (b, r) in enumerate(zip(base, rustle))]
    return loopify(sig)


def crickets_loop():
    sig = silence(6.0)
    for start, freq in [(0.2, 4300), (1.4, 4600), (2.7, 4300), (4.0, 4600), (5.1, 4300)]:
        for k in range(12):
            chirp = tone(freq, 0.022, gain=0.5, attack=0.004, vibrato=0.02)
            mix(sig, chirp, at=start + k * 0.041)
    return loopify(lowpass(sig, 6000), fade=0.3)


def companion_call():
    sig = silence(4.0)
    mix(sig, tone(660, 0.35, partials=((1, 1.0), (2, 0.35)), vibrato=0.03, vib_rate=7, attack=0.04, decay=0.25), at=0.3)
    mix(sig, tone(784, 0.45, partials=((1, 1.0), (2, 0.35)), vibrato=0.03, vib_rate=7, attack=0.04, decay=0.3), at=0.7)
    return sig


def river_loop():
    sig = bandpass(white(6.0), 300, 2600)
    bubble = lowpass(white(6.0), 8)
    sig = [s * (0.75 + 0.5 * b) for s, b in zip(sig, bubble)]
    return loopify(sig)


def creak(freq_from, freq_to, dur=0.9):
    body = tone(freq_from, dur, partials=((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)),
                attack=0.08, sweep_to=freq_to)
    rough = [s * (0.6 + 0.4 * math.sin(2 * math.pi * 26 * i / SR)) for i, s in enumerate(body)]
    return fade_edges(lowpass(rough, 900), 0.06)


def oak_creak_loop():
    sig = silence(7.0)
    mix(sig, creak(70, 130, 1.1), at=0.6)
    mix(sig, creak(95, 65, 0.9), at=3.8, gain=0.8)
    return loopify(sig, fade=0.3)


def bell(freq, dur=2.0, gain=1.0):
    sig = silence(dur)
    mix(sig, tone(freq, dur, attack=0.004, decay=0.55), gain=gain)
    mix(sig, tone(freq * 2.7, dur, attack=0.004, decay=0.3), gain=gain * 0.4)
    mix(sig, tone(freq * 4.1, dur, attack=0.004, decay=0.18), gain=gain * 0.2)
    return sig


def acorn_chime_loop():
    sig = silence(5.0)
    mix(sig, bell(2093, 2.0), at=0.2)
    mix(sig, bell(2093, 1.6), at=2.8, gain=0.45)
    return loopify(sig, fade=0.25)


def bridge_creak_loop():
    sig = mix(silence(6.0), bandpass(white(6.0), 300, 1800), gain=0.06)
    bubble = lowpass(white(6.0), 8)
    sig = [s * (0.8 + 0.4 * b) for s, b in zip(sig, bubble)]
    mix(sig, creak(110, 170, 0.8), at=1.2, gain=0.9)
    mix(sig, creak(140, 95, 0.7), at=4.2, gain=0.7)
    return loopify(sig, fade=0.3)


def chick_chirp(freq):
    return tone(freq, 0.09, attack=0.01, decay=0.05, sweep_to=freq * 0.82, gain=0.6)


def chicks_quiet_loop():
    sig = silence(6.0)
    for at, f in [(0.5, 3800), (0.68, 3500), (0.9, 3650), (3.2, 3700), (3.4, 3450), (5.0, 3600)]:
        mix(sig, chick_chirp(f), at=at)
    return loopify([s * 0.5 for s in sig], fade=0.3)


def stream_quiet_loop():
    sig = bandpass(white(6.0), 700, 3400)
    bubble = lowpass(white(6.0), 12)
    sig = [s * (0.6 + 0.6 * b) * 0.5 for s, b in zip(sig, bubble)]
    return loopify(sig)


# ------------------------------------------------------- Crystal Caves cues

def waterfall_loop():
    sig = bandpass(white(6.0), 150, 4500)
    swirl = lowpass(white(6.0), 5)
    sig = [s * (0.8 + 0.3 * w) for s, w in zip(sig, swirl)]
    return loopify(sig)


def cave_hum_loop():
    sig = tone(58, 7.0, partials=((1, 1.0), (2, 0.4), (3, 0.15)), attack=0.5,
               vibrato=0.01, vib_rate=0.3)
    breath = lowpass(white(7.0), 120)
    sig = [a * (0.75 + 0.25 * math.sin(2 * math.pi * (1 / 5.0) * i / SR)) + b * 0.1
           for i, (a, b) in enumerate(zip(sig, breath))]
    return loopify(sig, fade=0.6)


def cave_drips_loop():
    sig = silence(7.0)
    for at, f in [(0.4, 1900), (1.7, 1500), (2.3, 2200), (3.9, 1700), (5.2, 2000), (6.1, 1600)]:
        drip = tone(f, 0.5, attack=0.002, decay=0.12, sweep_to=f * 0.7, gain=0.6)
        mix(sig, drip, at=at)
        mix(sig, tone(f * 0.5, 0.6, attack=0.01, decay=0.25, gain=0.15), at=at + 0.04)
    return loopify(sig, fade=0.3)


def crystal_chime_loop():
    sig = silence(6.0)
    for at, f in [(0.3, 1568), (1.1, 2093), (2.6, 1760), (4.2, 2349), (5.0, 1976)]:
        mix(sig, bell(f, 1.8), at=at, gain=0.55)
    return loopify(sig, fade=0.3)


def guardian_snore_loop():
    sig = silence(6.0)
    for at in [0.4, 3.4]:
        inhale = tone(75, 1.2, partials=((1, 1.0), (2, 0.5), (3, 0.25)),
                      attack=0.3, sweep_to=105, gain=0.8)
        rough = [s * (0.65 + 0.35 * math.sin(2 * math.pi * 22 * i / SR))
                 for i, s in enumerate(inhale)]
        mix(sig, lowpass(rough, 500), at=at)
        mix(sig, tone(95, 0.9, attack=0.1, decay=0.5, sweep_to=65, gain=0.5), at=at + 1.4)
    return loopify(sig, fade=0.3)


def moonstone_shimmer_loop():
    sig = silence(5.0)
    for at, f in [(0.2, 3136), (0.9, 3520), (1.8, 3951), (2.9, 3520), (3.8, 3136)]:
        mix(sig, bell(f, 1.0), at=at, gain=0.3)
    return loopify([s * 0.55 for s in sig], fade=0.25)


# --------------------------------------------------------- companion sounds

def yip(freq_from=600, freq_to=1400):
    return tone(freq_from, 0.13, partials=((1, 1.0), (2, 0.5)), attack=0.008,
                decay=0.09, sweep_to=freq_to)


def ember_greeting():
    sig = silence(1.2)
    mix(sig, yip(), at=0.1)
    mix(sig, yip(650, 1500), at=0.45)
    return sig


def ember_celebrate():
    sig = silence(1.8)
    for i, at in enumerate([0.1, 0.4, 0.7, 1.15]):
        mix(sig, yip(600 + i * 60, 1400 + i * 120), at=at)
    return sig


def ember_sniffing():
    sig = silence(1.5)
    for at in [0.1, 0.32, 0.54, 0.9, 1.12]:
        mix(sig, fade_edges(lowpass(white(0.07), 900), 0.02), at=at, gain=0.8)
    return sig


def soft_thud(body_freq=150, gain=1.0):
    sig = tone(body_freq, 0.16, attack=0.003, decay=0.05, sweep_to=body_freq * 0.6, gain=gain)
    mix(sig, lowpass(white(0.03), 1200), gain=0.25 * gain)
    return sig


def ember_padding():
    sig = silence(3.0)
    at = 0.1
    while at < 2.8:
        mix(sig, soft_thud(160), at=at, gain=0.7)
        mix(sig, soft_thud(150), at=at + 0.16, gain=0.55)
        at += 0.62
    return loopify(sig, fade=0.2)


def ember_hum():
    return tone(220, 1.5, partials=((1, 1.0), (2, 0.3)), attack=0.15, decay=0.8,
                vibrato=0.02, vib_rate=4)


def petal_greeting():
    sig = silence(1.5)
    for i, f in enumerate([1568, 1760, 2093]):
        mix(sig, bell(f, 1.0), at=0.1 + i * 0.18, gain=0.7)
    flutter = [w * (0.5 + 0.5 * math.sin(2 * math.pi * 14 * i / SR))
               for i, w in enumerate(bandpass(white(0.8), 800, 2400))]
    mix(sig, fade_edges(flutter, 0.1), at=0.5, gain=0.12)
    return sig


def petal_celebrate():
    sig = silence(2.0)
    for i, f in enumerate([1047, 1175, 1319, 1568, 2093]):
        mix(sig, bell(f, 1.2), at=0.1 + i * 0.2, gain=0.7)
    return sig


def flutter_noise(dur, rate=12, low=700, high=2600):
    sig = bandpass(white(dur), low, high)
    return [s * (0.45 + 0.55 * math.sin(2 * math.pi * rate * i / SR)) for i, s in enumerate(sig)]


def petal_flutter_up():
    sig = flutter_noise(1.2, rate=14)
    sig = shaped(sig, lambda t: 0.4 + 0.6 * (t / 1.2))
    return fade_edges(sig, 0.1)


def petal_wings():
    return loopify([s * 0.5 for s in flutter_noise(3.0, rate=9)], fade=0.3)


def petal_chime():
    sig = bell(1319, 1.5)
    mix(sig, bell(1976, 1.2), at=0.05, gain=0.3)
    return sig


def clover_greeting():
    sig = silence(1.3)
    for at in [0.1, 0.3]:
        mix(sig, fade_edges(lowpass(white(0.09), 700), 0.02), at=at, gain=0.55)
    mix(sig, tone(900, 0.1, attack=0.01, decay=0.06, sweep_to=1100), at=0.65, gain=0.5)
    return sig


def clover_thump():
    sig = silence(1.2)
    mix(sig, soft_thud(95), at=0.15)
    mix(sig, soft_thud(95), at=0.5, gain=0.85)
    return sig


def clover_ear_wiggle():
    sig = silence(0.8)
    for at in [0.08, 0.24, 0.4]:
        mix(sig, fade_edges(bandpass(white(0.06), 1200, 3600), 0.015), at=at, gain=0.5)
    return sig


def clover_hops():
    sig = silence(3.0)
    at = 0.15
    while at < 2.7:
        mix(sig, soft_thud(110), at=at, gain=0.55)
        mix(sig, soft_thud(100), at=at + 0.12, gain=0.4)
        at += 0.85
    return loopify(sig, fade=0.2)


def clover_soft_hum():
    return tone(196, 1.5, partials=((1, 1.0), (2, 0.25)), attack=0.2, decay=0.8,
                vibrato=0.015, vib_rate=3.5, gain=0.8)


# ------------------------------------------------------------- UI and notes

def earcon_listen_start():
    sig = silence(0.55)
    mix(sig, tone(660, 0.16, attack=0.01, decay=0.12), at=0.05)
    mix(sig, tone(880, 0.22, attack=0.01, decay=0.16), at=0.22)
    return sig


def earcon_listen_stop():
    sig = silence(0.55)
    mix(sig, tone(880, 0.16, attack=0.01, decay=0.12), at=0.05)
    mix(sig, tone(660, 0.22, attack=0.01, decay=0.16), at=0.22)
    return sig


def earcon_freeze():
    sig = silence(1.3)
    mix(sig, tone(392, 1.2, partials=((1, 1.0), (2, 0.4), (3, 0.2)), attack=0.01, decay=0.45), at=0.05)
    mix(sig, tone(587, 1.0, attack=0.01, decay=0.35), at=0.08, gain=0.4)
    return sig


def celebrate_step():
    sig = silence(1.1)
    for i, f in enumerate([1047, 1319, 1568]):
        mix(sig, bell(f, 0.9), at=0.05 + i * 0.12, gain=0.8)
    return sig


def celebrate_quest():
    sig = silence(2.3)
    for i, f in enumerate([262, 330, 392, 523]):
        mix(sig, tone(f, 1.4, partials=((1, 1.0), (2, 0.45), (3, 0.2)),
                      attack=0.02, decay=0.5), at=0.1 + i * 0.22, gain=0.8)
    mix(sig, bell(2093, 1.2), at=0.95, gain=0.35)
    return sig


NOTE_FREQS = {
    "do": 261.63, "re": 293.66, "mi": 329.63, "fa": 349.23,
    "sol": 392.00, "la": 440.00, "ti": 493.88,
}


def solfege_note(freq):
    return tone(freq, 1.3, partials=((1, 1.0), (2, 0.35), (3, 0.12)),
                attack=0.015, decay=0.45)


# --------------------------------------------------------------------- main

CUES = {
    "wind_leaves_loop.wav": wind_leaves_loop,
    "crickets_loop.wav": crickets_loop,
    "companion_call.wav": companion_call,
    "river_loop.wav": river_loop,
    "oak_creak_loop.wav": oak_creak_loop,
    "acorn_chime_loop.wav": acorn_chime_loop,
    "bridge_creak_loop.wav": bridge_creak_loop,
    "chicks_quiet_loop.wav": chicks_quiet_loop,
    "stream_quiet_loop.wav": stream_quiet_loop,
    "waterfall_loop.wav": waterfall_loop,
    "cave_hum_loop.wav": cave_hum_loop,
    "cave_drips_loop.wav": cave_drips_loop,
    "crystal_chime_loop.wav": crystal_chime_loop,
    "guardian_snore_loop.wav": guardian_snore_loop,
    "moonstone_shimmer_loop.wav": moonstone_shimmer_loop,
    "ember_greeting.wav": ember_greeting,
    "ember_celebrate.wav": ember_celebrate,
    "ember_sniffing.wav": ember_sniffing,
    "ember_padding.wav": ember_padding,
    "ember_hum.wav": ember_hum,
    "petal_greeting.wav": petal_greeting,
    "petal_celebrate.wav": petal_celebrate,
    "petal_flutter_up.wav": petal_flutter_up,
    "petal_wings.wav": petal_wings,
    "petal_chime.wav": petal_chime,
    "clover_greeting.wav": clover_greeting,
    "clover_thump.wav": clover_thump,
    "clover_ear_wiggle.wav": clover_ear_wiggle,
    "clover_hops.wav": clover_hops,
    "clover_soft_hum.wav": clover_soft_hum,
    "earcon_listen_start.wav": earcon_listen_start,
    "earcon_listen_stop.wav": earcon_listen_stop,
    "earcon_freeze.wav": earcon_freeze,
    "celebrate_step.wav": celebrate_step,
    "celebrate_quest.wav": celebrate_quest,
}


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Generating placeholder audio into {OUT_DIR}")
    for name, builder in CUES.items():
        write_wav(name, builder())
    for note, freq in NOTE_FREQS.items():
        write_wav(f"note_{note}.wav", solfege_note(freq), peak=0.7)
    print("Done.")


if __name__ == "__main__":
    main()
