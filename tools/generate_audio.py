#!/usr/bin/env python3
"""Generate original, gentle tilegarden feedback tones and ambience."""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 44_100
ROOT = Path(__file__).resolve().parents[1] / "audio" / "generated"
ROOT.mkdir(parents=True, exist_ok=True)


def envelope(t: float, duration: float, attack: float = 0.02, release: float = 0.16) -> float:
    return min(1.0, t / max(attack, 0.001)) * min(1.0, (duration - t) / max(release, 0.001))


def write_tone(
    name: str,
    frequencies: tuple[float, ...],
    duration: float,
    *,
    volume: float = 0.22,
    noise: float = 0.0,
    sweep: float = 0.0,
    attack: float = 0.015,
    release: float = 0.14,
    seed: int = 1,
) -> None:
    rng = random.Random(seed)
    frames = bytearray()
    phases = [0.0 for _ in frequencies]
    for index in range(int(RATE * duration)):
        t = index / RATE
        env = envelope(t, duration, attack, release)
        sample = 0.0
        for note, base in enumerate(frequencies):
            freq = base * (1.0 + sweep * (t / duration - 0.5))
            phases[note] += math.tau * freq / RATE
            sample += math.sin(phases[note]) * (1.0 / (note + 1))
        sample /= max(1.0, sum(1.0 / (n + 1) for n in range(len(frequencies))))
        if noise:
            sample += (rng.random() * 2.0 - 1.0) * noise
        sample *= env * volume
        frames.extend(struct.pack("<h", max(-32767, min(32767, int(sample * 32767)))))
    with wave.open(str(ROOT / name), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(frames)


PROFILES = {
    "ui_hover.wav": ((720,), 0.07, 0.11, 0.00, 0.15),
    "ui_confirm.wav": ((520, 780), 0.12, 0.16, 0.00, 0.10),
    "ui_close.wav": ((520, 350), 0.11, 0.14, 0.00, -0.15),
    "mote_click.wav": ((460, 690), 0.16, 0.16, 0.01, 0.18),
    "mote_chirp_a.wav": ((640, 910), 0.23, 0.15, 0.00, 0.26),
    "mote_chirp_b.wav": ((590, 840), 0.25, 0.14, 0.00, 0.20),
    "mote_chirp_c.wav": ((720, 1020), 0.19, 0.13, 0.00, 0.30),
    "seed_appears.wav": ((820, 1230), 0.25, 0.15, 0.00, 0.25),
    "seed_travel.wav": ((460, 920), 0.44, 0.11, 0.01, 0.45),
    "seed_lands.wav": ((760, 1140, 1520), 0.32, 0.19, 0.00, -0.06),
    "seed_offered.wav": ((390, 585), 0.28, 0.16, 0.02, -0.30),
    "grove_inhale.wav": ((190, 285), 0.38, 0.18, 0.05, 0.55),
    "grove_pulse.wav": ((260, 390, 520), 0.55, 0.20, 0.02, 0.14),
    "reward_reveal.wav": ((520, 780, 1040), 0.62, 0.19, 0.01, 0.20),
    "discovery.wav": ((660, 990, 1320), 0.72, 0.17, 0.00, 0.08),
    "place_wood.wav": ((175, 260), 0.18, 0.13, 0.10, -0.18),
    "place_stone.wav": ((110, 165), 0.22, 0.16, 0.14, -0.22),
    "place_vegetation.wav": ((300, 450), 0.24, 0.12, 0.08, 0.08),
    "place_ground.wav": ((130, 195), 0.30, 0.15, 0.18, -0.20),
    "rotate.wav": ((410, 615), 0.10, 0.11, 0.01, 0.20),
    "pickup.wav": ((330, 495), 0.18, 0.13, 0.01, 0.36),
    "valid_drop.wav": ((420, 630), 0.16, 0.14, 0.03, -0.05),
    "invalid_drop.wav": ((180, 145), 0.24, 0.12, 0.07, -0.30),
    "storage.wav": ((300, 450, 600), 0.26, 0.13, 0.02, -0.12),
    "recycling.wav": ((240, 480, 720), 0.48, 0.15, 0.04, 0.38),
    "collection_open.wav": ((440, 660, 880), 0.34, 0.14, 0.01, 0.12),
    "camera_rotate.wav": ((250, 375), 0.16, 0.10, 0.03, 0.22),
    "undo.wav": ((520, 390), 0.23, 0.13, 0.02, -0.22),
    "redo.wav": ((390, 585), 0.23, 0.13, 0.02, 0.22),
    "save.wav": ((510, 765, 1020), 0.40, 0.15, 0.01, 0.08),
}

for idx, (name, (freq, duration, volume, noise, sweep)) in enumerate(PROFILES.items()):
    write_tone(name, freq, duration, volume=volume, noise=noise, sweep=sweep, seed=idx + 17)


def write_ambience() -> None:
    rng = random.Random(730291)
    duration = 8.0
    frames = bytearray()
    low = 0.0
    bird_phase = 0.0
    for index in range(int(RATE * duration)):
        t = index / RATE
        white = rng.random() * 2.0 - 1.0
        low = low * 0.997 + white * 0.003
        breeze = low * (0.55 + 0.25 * math.sin(t * math.tau / 5.3))
        bird = 0.0
        for start in (1.4, 4.9, 6.7):
            local = t - start
            if 0.0 <= local <= 0.38:
                bird_phase += math.tau * (1450 + 260 * local) / RATE
                bird += math.sin(bird_phase) * envelope(local, 0.38, 0.04, 0.13) * 0.12
        sample = (breeze * 0.16 + bird) * 0.45
        frames.extend(struct.pack("<h", max(-32767, min(32767, int(sample * 32767)))))
    with wave.open(str(ROOT / "forest_ambience.wav"), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(frames)


write_ambience()
print(f"Generated {len(PROFILES) + 1} original WAV files in {ROOT}")

