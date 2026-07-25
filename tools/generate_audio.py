#!/usr/bin/env python3
"""Generate the original Suma Nook sound set (pure-python synthesis, no deps).

Gentle, non-piercing feedback tones + short ambient loops. Re-runnable;
deterministic. Output: audio/generated/*.wav (44.1 kHz 16-bit mono).
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44_100
ROOT = Path(__file__).resolve().parents[1] / "audio" / "generated"
ROOT.mkdir(parents=True, exist_ok=True)


def env(t: float, dur: float, attack=0.012, release=0.14) -> float:
    return min(1.0, t / max(attack, 1e-4)) * min(1.0, (dur - t) / max(release, 1e-4))


def write(name: str, samples: list[float]) -> None:
    peak = max(0.001, max(abs(s) for s in samples))
    scale = min(1.0, 0.92 / peak)
    frames = bytearray()
    for s in samples:
        frames += struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767))
    with wave.open(str(ROOT / f"{name}.wav"), "wb") as f:
        f.setnchannels(1)
        f.setsampwidth(2)
        f.setframerate(RATE)
        f.writeframes(bytes(frames))
    print(f"[audio] {name}.wav")


def tone(freqs, dur, vol=0.22, noise=0.0, sweep=0.0, attack=0.012, release=0.14, seed=1, tremolo=0.0):
    rng = random.Random(seed)
    out = []
    phases = [0.0] * len(freqs)
    for i in range(int(RATE * dur)):
        t = i / RATE
        e = env(t, dur, attack, release)
        s = 0.0
        for j, f in enumerate(freqs):
            cur = f * (1.0 + sweep * t)
            phases[j] += 2 * math.pi * cur / RATE
            s += math.sin(phases[j]) / (j + 1)
        if noise:
            s += rng.uniform(-1, 1) * noise
        if tremolo:
            e *= 1.0 - tremolo * 0.5 * (1 + math.sin(2 * math.pi * 6.0 * t))
        out.append(s * vol * e)
    return out


def chirp(f0, f1, dur, vol=0.2, seed=1):
    out = []
    phase = 0.0
    for i in range(int(RATE * dur)):
        t = i / RATE
        f = f0 + (f1 - f0) * (t / dur)
        phase += 2 * math.pi * f / RATE
        out.append(math.sin(phase) * vol * env(t, dur, 0.008, 0.05))
    return out


def noise_burst(dur, vol=0.2, lowpass=0.25, seed=1, attack=0.004, release=0.1):
    rng = random.Random(seed)
    out, prev = [], 0.0
    for i in range(int(RATE * dur)):
        t = i / RATE
        prev += (rng.uniform(-1, 1) - prev) * lowpass
        out.append(prev * vol * env(t, dur, attack, release))
    return out


def mix(*layers):
    n = max(len(l) for l in layers)
    return [sum(l[i] if i < len(l) else 0.0 for l in layers) for i in range(n)]


def delay(samples, seconds):
    return [0.0] * int(RATE * seconds) + samples


# UI
write("ui_hover", tone([880], 0.05, 0.08, attack=0.004, release=0.03))
write("ui_confirm", mix(tone([620], 0.09, 0.16), delay(tone([930], 0.1, 0.14), 0.05)))
write("ui_cancel", tone([420, 300], 0.12, 0.13, sweep=-0.3))
write("panel_open", mix(tone([520], 0.1, 0.12), delay(tone([780], 0.12, 0.1), 0.04)))
write("panel_close", mix(tone([780], 0.08, 0.1), delay(tone([520], 0.1, 0.1), 0.04)))
write("craft", mix(noise_burst(0.08, 0.12, 0.5, 3), delay(tone([740, 1110], 0.14, 0.14), 0.05)))
write("discovery", mix(tone([660], 0.12, 0.14), delay(tone([880], 0.12, 0.13), 0.09), delay(tone([1100], 0.2, 0.12), 0.18)))

# Character / movement
for i, s in enumerate([11, 12, 13]):
    write(f"footstep_grass_{i}", noise_burst(0.07, 0.1, 0.14, s, release=0.05))
    write(f"footstep_stone_{i}", mix(noise_burst(0.05, 0.1, 0.4, s + 10, release=0.04), tone([190], 0.05, 0.05, seed=s)))
write("tool_equip", mix(noise_burst(0.06, 0.1, 0.5, 21), delay(tone([500], 0.07, 0.1), 0.03)))
write("hurt", tone([300, 210], 0.16, 0.2, sweep=-0.4, noise=0.05, seed=5))
write("dodge", noise_burst(0.12, 0.12, 0.3, 6, release=0.09))
write("levelup", mix(tone([523], 0.16, 0.16), delay(tone([659], 0.16, 0.15), 0.1), delay(tone([784], 0.2, 0.15), 0.2), delay(tone([1047], 0.34, 0.13), 0.3)))

# Fishing
write("fish_cast", chirp(700, 250, 0.3, 0.12, 7))
write("fish_splash", mix(noise_burst(0.16, 0.16, 0.2, 8), tone([320], 0.1, 0.08, seed=8)))
write("fish_bite", mix(tone([540], 0.06, 0.16), delay(tone([540], 0.06, 0.16), 0.09)))
write("fish_catch", mix(noise_burst(0.1, 0.12, 0.25, 9), delay(chirp(400, 900, 0.18, 0.13, 9), 0.06)))
write("reward_common", tone([720, 1080], 0.14, 0.13))
write("reward_rare", mix(tone([660], 0.14, 0.14), delay(tone([880], 0.14, 0.14), 0.09), delay(tone([1174], 0.26, 0.14), 0.18), delay(tone([1568], 0.3, 0.1), 0.28)))

# Woodcutting
write("chop_windup", noise_burst(0.09, 0.06, 0.3, 30, release=0.07))
for i, s in enumerate([31, 32, 33]):
    write(f"chop_impact_{i}", mix(noise_burst(0.07, 0.2, 0.5, s, release=0.05), tone([160 + 12 * i], 0.09, 0.15, seed=s)))
write("leaf_rustle", noise_burst(0.25, 0.08, 0.1, 34, attack=0.03, release=0.18))
write("pickup", tone([840], 0.07, 0.12, attack=0.005))
write("grove_rest", mix(tone([420], 0.3, 0.1, tremolo=0.4), delay(tone([315], 0.4, 0.09, tremolo=0.4), 0.15)))

# Building
write("build_preview", tone([560], 0.05, 0.07))
write("build_rotate", tone([620, 700], 0.06, 0.09))
write("place_grass", mix(noise_burst(0.12, 0.14, 0.14, 40), delay(tone([240], 0.14, 0.13), 0.04)))
write("place_stone", mix(noise_burst(0.09, 0.16, 0.5, 41), delay(tone([150], 0.16, 0.16), 0.03)))
write("place_wood", mix(noise_burst(0.08, 0.14, 0.4, 42), delay(tone([310], 0.1, 0.13), 0.03)))
write("place_water", mix(noise_burst(0.18, 0.14, 0.16, 43), delay(tone([420], 0.14, 0.1), 0.06)))
write("build_invalid", tone([220, 208], 0.16, 0.13, tremolo=0.6))
write("undo", chirp(600, 420, 0.12, 0.1, 44))
write("redo", chirp(420, 600, 0.12, 0.1, 45))
write("store", mix(noise_burst(0.07, 0.1, 0.35, 46), delay(tone([500, 380], 0.1, 0.1), 0.04)))

# Parcels
write("parcel_appear", mix(tone([540], 0.2, 0.12), delay(tone([810], 0.24, 0.1), 0.12)))
write("parcel_open", mix(noise_burst(0.12, 0.1, 0.3, 50), delay(tone([600, 900], 0.2, 0.12), 0.08)))
write("parcel_reveal", mix(tone([720], 0.1, 0.1), delay(tone([960], 0.12, 0.1), 0.08)))
write("parcel_select", mix(tone([620], 0.12, 0.14), delay(tone([930], 0.18, 0.13), 0.09)))
write("reroll", chirp(500, 800, 0.2, 0.11, 51))

# Combat
write("attack_swing", noise_burst(0.1, 0.13, 0.55, 60, release=0.08))
write("enemy_telegraph", tone([260], 0.3, 0.12, tremolo=0.7, seed=61))
write("enemy_hit", mix(noise_burst(0.06, 0.16, 0.5, 62), tone([200], 0.07, 0.12, seed=62)))
write("enemy_defeat", mix(noise_burst(0.14, 0.14, 0.25, 63), delay(chirp(500, 200, 0.2, 0.1, 63), 0.05)))
write("guardian_defeat", mix(noise_burst(0.25, 0.16, 0.3, 64), delay(tone([392], 0.2, 0.13), 0.15), delay(tone([523], 0.2, 0.13), 0.3), delay(tone([659], 0.36, 0.13), 0.45)))
write("landmark_reclaimed", mix(tone([392], 0.24, 0.13), delay(tone([494], 0.24, 0.12), 0.16), delay(tone([587], 0.26, 0.12), 0.32), delay(tone([784], 0.5, 0.12), 0.48)))


# Ambience loops (fade-in/out so looping reads as breathing, not clicking)
def wind_loop(dur=6.0, vol=0.05, seed=70):
    rng = random.Random(seed)
    out, prev = [], 0.0
    n = int(RATE * dur)
    for i in range(n):
        t = i / RATE
        prev += (rng.uniform(-1, 1) - prev) * 0.02
        swell = 0.6 + 0.4 * math.sin(2 * math.pi * t / dur * 2)
        fade = min(1.0, min(i, n - i) / (RATE * 0.5))
        out.append(prev * vol * swell * fade * 3.0)
    return out


write("ambience_wind", wind_loop())
write("ambience_rain", [s * 2.2 for s in wind_loop(5.0, 0.05, 71)])
write("bird_1", mix(chirp(2200, 2600, 0.09, 0.06, 72), delay(chirp(2500, 2100, 0.11, 0.05, 72), 0.13)))
write("bird_2", mix(chirp(1900, 2400, 0.07, 0.05, 73), delay(chirp(2300, 2000, 0.08, 0.05, 73), 0.1), delay(chirp(2100, 2500, 0.09, 0.04, 73), 0.22)))
write("water_lap", noise_burst(0.5, 0.05, 0.06, 74, attack=0.15, release=0.3))
write("fire_crackle", mix(noise_burst(0.06, 0.08, 0.5, 75), delay(noise_burst(0.05, 0.06, 0.5, 76), 0.14), delay(noise_burst(0.07, 0.07, 0.45, 77), 0.3)))

print("AUDIO GENERATION COMPLETE")
