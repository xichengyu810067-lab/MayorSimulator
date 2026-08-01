"""Generate original, dependency-free PCM audio for the storybook UI.

The synthesis is deterministic and uses only Python's standard library.  It
keeps the project free of third-party music/SFX licensing requirements.
"""

from __future__ import annotations

import math
import random
import struct
import wave
from pathlib import Path

RATE = 22_050
ROOT = Path(__file__).resolve().parents[2] / "assets" / "audio" / "storybook_v1"


def envelope(t: float, duration: float, attack: float = 0.02, release: float = 0.18) -> float:
    if t < 0.0 or t >= duration:
        return 0.0
    return min(1.0, t / max(attack, 0.001), (duration - t) / max(release, 0.001))


def sine(freq: float, t: float) -> float:
    return math.sin(math.tau * freq * t)


def triangle(freq: float, t: float) -> float:
    return 2.0 / math.pi * math.asin(math.sin(math.tau * freq * t))


def note(freq: float, t: float, duration: float, bell: bool = False) -> float:
    env = envelope(t, duration, 0.012 if bell else 0.14, 0.30 if bell else 0.45)
    if bell:
        decay = math.exp(-3.2 * t / max(duration, 0.01))
        return env * decay * (sine(freq, t) + 0.35 * sine(freq * 2.01, t) + 0.16 * sine(freq * 3.99, t))
    return env * (0.68 * triangle(freq, t) + 0.32 * sine(freq * 0.5, t))


def write_wav(path: Path, samples: list[float]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    peak = max(1.0, max(abs(value) for value in samples) * 1.02)
    with wave.open(str(path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        frames = bytearray()
        for value in samples:
            limited = math.tanh(value / peak * 1.35) * 0.82
            frames.extend(struct.pack("<h", int(max(-1.0, min(1.0, limited)) * 32767)))
        output.writeframes(frames)


def music() -> list[float]:
    bar_seconds = 4.0
    chords = [
        (130.81, 164.81, 196.00),  # C
        (110.00, 130.81, 164.81),  # Am
        (87.31, 130.81, 174.61),   # F
        (98.00, 146.83, 196.00),   # G
        (130.81, 164.81, 196.00),
        (98.00, 146.83, 196.00),
    ]
    duration = len(chords) * bar_seconds
    result: list[float] = []
    for index in range(int(duration * RATE)):
        t = index / RATE
        bar = min(len(chords) - 1, int(t / bar_seconds))
        local = t - bar * bar_seconds
        chord = chords[bar]
        pad = sum(note(freq, local, bar_seconds, False) for freq in chord) * 0.11
        bass = note(chord[0] * 0.5, local, bar_seconds, False) * 0.13
        beat = int(local / 0.5)
        note_local = local - beat * 0.5
        arp_freq = chord[beat % 3] * 2.0
        arpeggio = note(arp_freq, note_local, 0.48, True) * 0.12
        high_bell = 0.0
        if beat in (0, 6):
            high_bell = note(chord[2] * 4.0, note_local, 0.9, True) * 0.055
        result.append(pad + bass + arpeggio + high_bell)
    fade = int(0.08 * RATE)
    for i in range(fade):
        result[i] *= i / fade
        result[-1 - i] *= i / fade
    return result


def ui_click() -> list[float]:
    duration = 0.11
    return [
        envelope(t := i / RATE, duration, 0.003, 0.09)
        * (0.34 * sine(880, t) + 0.16 * sine(1320, t))
        for i in range(int(duration * RATE))
    ]


def page_turn() -> list[float]:
    rng = random.Random(20_260_731)
    duration = 0.38
    result = []
    previous = 0.0
    for i in range(int(duration * RATE)):
        t = i / RATE
        noise = rng.uniform(-1.0, 1.0)
        previous = previous * 0.82 + noise * 0.18
        sweep = sine(420 + 680 * t / duration, t)
        result.append(envelope(t, duration, 0.035, 0.15) * (previous * 0.22 + sweep * 0.08))
    return result


def success() -> list[float]:
    duration = 0.75
    notes = [(0.00, 659.25), (0.14, 783.99), (0.30, 1046.50)]
    return [
        sum(note(freq, t - start, 0.45, True) * 0.20 for start, freq in notes)
        for i in range(int(duration * RATE))
        for t in [i / RATE]
    ]


def construction_complete() -> list[float]:
    duration = 0.90
    notes = [(0.00, 523.25), (0.10, 659.25), (0.22, 783.99), (0.38, 1046.50)]
    return [
        sum(note(freq, t - start, 0.55, True) * 0.18 for start, freq in notes)
        + (note(130.81, t, 0.80, False) * 0.08)
        for i in range(int(duration * RATE))
        for t in [i / RATE]
    ]


def warning() -> list[float]:
    duration = 0.34
    return [
        envelope(t := i / RATE, duration, 0.008, 0.20)
        * (0.20 * sine(246.94, t) + 0.14 * sine(233.08, t))
        for i in range(int(duration * RATE))
    ]


def main() -> None:
    outputs = {
        "mayors-dawn-loop.wav": music(),
        "ui-click.wav": ui_click(),
        "page-turn.wav": page_turn(),
        "success-chime.wav": success(),
        "construction-complete.wav": construction_complete(),
        "warning-soft.wav": warning(),
    }
    for filename, samples in outputs.items():
        write_wav(ROOT / filename, samples)
        print(f"{filename}: {len(samples) / RATE:.2f}s")


if __name__ == "__main__":
    main()
