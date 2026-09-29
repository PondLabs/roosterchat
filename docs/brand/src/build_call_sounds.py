#!/usr/bin/env python3
"""Builds the screen share and camera sounds of a voice room from code.

They follow the mute and unmute sounds (cockhouse/assets/sound/muted.ogg,
unmuted.ogg): soft, low, filtered plucks with a small click on the attack,
struck about 85 ms apart, with a tail of most of a second. Rising turns
something on, falling turns it off, as unmute and mute do. The screen share
is three strikes up or down a D major chord; the camera two strikes, a
little higher, where the first is damped when the second lands so the one
left ringing tells on from off: up an octave to turn it on, down a fifth to
turn it off. Plain Python for the samples, ffmpeg
(libvorbis) for the Ogg files.

    python3 docs/brand/src/build_call_sounds.py
"""

import math
import os
import random
import struct
import subprocess
import tempfile
import wave

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
SOUNDS = os.path.join(ROOT, "cockhouse", "assets", "sound")

RATE = 44100
LENGTH = 1.1
# The mute and unmute sounds sit around -32 dBFS RMS over their first
# second, and peak no higher than -10 dBFS.
RMS = 10 ** (-32 / 20)
PEAK = 10 ** (-10 / 20)
# The time between strikes in the mute and unmute sounds.
GAP = 0.085

D3 = 146.83
FS3 = 185.00
A3 = 220.00
E3 = 164.81
E4 = 329.63


def pluck(freq, start, out, damp_at=None):
    """A warm pluck: a strong fundamental and a few harmonics that die away
    faster the higher they are (a closing low-pass), and a short low-passed
    click of noise on the attack. With [damp_at] (seconds after the strike)
    it is muted there over a few tens of milliseconds."""
    n0 = int(start * RATE)
    for i in range(len(out) - n0):
        t = i / RATE
        attack = min(1.0, t / 0.003)
        if damp_at is not None and t > damp_at:
            attack *= math.exp(-(t - damp_at) / 0.015)
            if t > damp_at + 0.1:
                break
        s = 0.0
        for k in range(1, 7):
            if freq * k > 3000:
                break
            s += (math.sin(2 * math.pi * freq * k * t) / k ** 1.4
                  * math.exp(-t * (5 + 9 * (k - 1))))
        out[n0 + i] += s * attack
    rng = random.Random(int(freq))
    lp = 0.0
    for i in range(int(0.02 * RATE)):
        lp += 0.25 * (rng.uniform(-1, 1) - lp)
        out[n0 + i] += 0.6 * lp * math.exp(-i / RATE / 0.004)


def render(freqs, name, damped=False):
    out = [0.0] * int(LENGTH * RATE)
    for n, f in enumerate(freqs):
        last = n == len(freqs) - 1
        pluck(f, n * GAP, out, damp_at=GAP if damped and not last else None)
    # Fade the tail to silence.
    fade = int(0.15 * RATE)
    for i in range(fade):
        out[-fade + i] *= 1 - i / fade
    head = out[:RATE]
    rms = math.sqrt(sum(s * s for s in head) / len(head))
    scale = min(RMS / rms, PEAK / max(abs(s) for s in out))
    frames = b"".join(
        struct.pack("<hh", v, v)
        for v in (int(s * scale * 32767) for s in out)
    )
    path = os.path.join(SOUNDS, name)
    with tempfile.TemporaryDirectory() as tmp:
        wav = os.path.join(tmp, "sound.wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(2)
            w.setsampwidth(2)
            w.setframerate(RATE)
            w.writeframes(frames)
        subprocess.run(
            ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", wav,
             "-c:a", "libvorbis", "-q:a", "5", path],
            check=True,
        )
    print(path)


if __name__ == "__main__":
    render([D3, FS3, A3], "screenshare_started.ogg")
    render([A3, FS3, D3], "screenshare_stopped.ogg")
    render([E3, E4], "camera_on.ogg", damped=True)
    render([E4, A3], "camera_off.ogg", damped=True)
