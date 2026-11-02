#!/usr/bin/env python3
"""The sound of the made-up crew, synthesized here, nothing sampled:

- voices: babble with formants and talk spurts, for the fake microphones
  (Chrome's --use-file-for-fake-audio-capture), so LiveKit hears people
  talking and the speaking rings light up;
- four songs for Priya to play from the DJ booth (Opus in Ogg, named
  "Artist - Title", which is how the browser DJ titles a file);
- four soundboard clips for The Coop.

Usage: make_media.py <work dir>. Needs numpy and ffmpeg.
"""
import os
import subprocess
import sys
import wave

import numpy as np

SR = 48000
WORK = sys.argv[1]
rng = np.random.default_rng(7)


def write_wav(path, x):
    x = np.clip(x / (np.max(np.abs(x)) + 1e-9) * 0.8, -1, 1)
    with wave.open(path, "wb") as w:
        w.setnchannels(1 if x.ndim == 1 else 2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype(np.int16).tobytes())


def to_ogg(wav, ogg, bitrate):
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libopus", "-b:a", bitrate, ogg], check=True)
    os.remove(wav)


def formant(x, f, bw):
    # Two-pole resonator.
    r = np.exp(-np.pi * bw / SR)
    a1, a2 = -2 * r * np.cos(2 * np.pi * f / SR), r * r
    y = np.zeros_like(x)
    for n in range(2, len(x)):
        y[n] = x[n] - a1 * y[n - 1] - a2 * y[n - 2]
    return y


def babble(seconds, pitch):
    n = int(seconds * SR)
    t = np.arange(n) / SR
    f0 = pitch * (1 + 0.08 * np.sin(2 * np.pi * 0.7 * t) + 0.03 * rng.standard_normal(n).cumsum() / np.sqrt(n))
    phase = np.cumsum(f0) / SR
    src = 2 * (phase % 1) - 1  # a sawtooth for a glottal source
    out = np.zeros(n)
    vowels = [(730, 1090), (270, 2290), (300, 870), (530, 1840), (640, 1190)]
    seg = int(0.18 * SR)
    for i in range(0, n, seg):
        f1, f2 = vowels[rng.integers(len(vowels))]
        chunk = src[i:i + seg]
        out[i:i + seg] = formant(chunk, f1, 90) + 0.6 * formant(chunk, f2, 120)
    # Syllables at about 4.5 a second, in spurts with pauses between them.
    syll = 0.5 * (1 + np.sin(2 * np.pi * 4.5 * t + rng.uniform(0, 6)))
    spurts = np.zeros(n)
    i = 0
    while i < n:
        on = int(rng.uniform(1.2, 3.5) * SR)
        off = int(rng.uniform(0.3, 1.0) * SR)
        spurts[i:i + on] = 1
        i += on + off
    env = np.convolve(syll * spurts, np.ones(400) / 400, mode="same")
    return out * env


def song(seconds, bpm, root, scale, seed):
    r = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    beat = 60 / bpm
    out = np.zeros((n, 2))

    def note(freq, start, dur, amp, kind="tri", pan=0.0):
        s, e = int(start * SR), min(n, int((start + dur) * SR))
        if s >= n:
            return
        tt = np.arange(e - s) / SR
        if kind == "tri":
            w = 2 * np.abs(2 * ((freq * tt) % 1) - 1) - 1
        elif kind == "sq":
            w = np.sign(np.sin(2 * np.pi * freq * tt)) * 0.5
        else:
            w = np.sin(2 * np.pi * freq * tt)
        env = np.minimum(1, tt / 0.01) * np.exp(-tt * (3 / dur))
        sig = w * env * amp
        out[s:e, 0] += sig * (1 - pan) / 2
        out[s:e, 1] += sig * (1 + pan) / 2

    hz = lambda semis: root * 2 ** (semis / 12)
    chords = [[0, 4, 7], [9, 12, 16], [5, 9, 12], [7, 11, 14]]
    for b in range(int(seconds / (4 * beat)) + 1):
        ch = chords[b % 4]
        for k in range(4):
            st = (b * 4 + k) * beat
            note(hz(ch[0] - 12), st, beat * 0.9, 0.5, "sin")
            for j, iv in enumerate(ch):
                note(hz(iv), st + 0.02 * j, beat * 0.8, 0.12, "tri", pan=-0.4 + 0.4 * j)
            for half in range(2):
                note(hz(scale[r.integers(len(scale))] + 12), st + half * beat / 2, beat / 2, 0.18, "sq", 0.3)
            s = int(st * SR)
            kl = int(0.15 * SR)
            if s + kl < n:
                kt = np.arange(kl) / SR
                kick = np.sin(2 * np.pi * (50 + 80 * np.exp(-kt * 30)) * kt) * np.exp(-kt * 18)
                out[s:s + kl] += kick[:, None] * 0.7
            hs = int((st + beat / 2) * SR)
            hl = int(0.04 * SR)
            if hs + hl < n:
                out[hs:hs + hl] += (r.standard_normal(hl) * np.exp(-np.arange(hl) / SR * 120) * 0.15)[:, None]
    fade = np.minimum(1, np.minimum(t / 2, (seconds - t) / 3))
    return out * fade[:, None]


def tone(f, d, kind="saw", decay=3.0):
    t = np.arange(int(d * SR)) / SR
    ph = np.cumsum(np.full_like(t, f) if np.isscalar(f) else f) / SR
    w = 2 * (ph % 1) - 1 if kind == "saw" else np.sin(2 * np.pi * ph)
    return w * np.exp(-t * decay) * np.minimum(1, t / 0.01)


audio = os.path.join(WORK, "audio")
sounds = os.path.join(WORK, "sounds")
os.makedirs(audio, exist_ok=True)
os.makedirs(sounds, exist_ok=True)

for name, pitch in [("voice-low", 115), ("voice-mid", 165), ("voice-high", 215)]:
    write_wav(f"{audio}/{name}.wav", babble(60, pitch))

major, minor = [0, 2, 4, 7, 9], [0, 3, 5, 7, 10]
for name, args in [("The Night Owls - Sunrise Strut", (198, 118, 220.0, major, 1)),
                   ("Low Tide - Coffee Run", (172, 96, 196.0, minor, 2)),
                   ("Barnyard FM - Neon Hen", (205, 124, 246.9, major, 3)),
                   ("Comb & Yolk - Late Checkout", (188, 104, 174.6, minor, 4))]:
    write_wav(f"{audio}/{name}.wav", song(*args))
    to_ogg(f"{audio}/{name}.wav", f"{audio}/{name}.ogg", "128k")

# GG: a little fanfare.
write_wav(f"{sounds}/gg.wav", np.concatenate([tone(523, .14), tone(659, .14), tone(784, .14), tone(1047, .5, decay=2)]))
# Sad trombone: four falling notes, the last one wobbling.
parts = []
for i, f in enumerate([392, 370, 349, 330]):
    d = .35 if i < 3 else .9
    t = np.arange(int(d * SR)) / SR
    fm = f * (1 + .02 * np.sin(2 * np.pi * 6 * t)) if i == 3 else np.full_like(t, f)
    parts.append(tone(fm, d, decay=1.2) * (0.6 + 0.4 * np.sin(np.pi * t / d)))
write_wav(f"{sounds}/sad-trombone.wav", np.concatenate(parts))
# Drumroll, then a crash.
n = int(1.4 * SR)
t = np.arange(n) / SR
roll = rng.standard_normal(n) * (0.4 + 0.6 * (np.sin(2 * np.pi * 22 * t) > 0)) * np.minimum(1, t / 1.2)
crash = rng.standard_normal(SR) * np.exp(-np.arange(SR) / SR * 3)
write_wav(f"{sounds}/drumroll.wav", np.concatenate([roll * .5, crash]))
# Rematch?: two rising boops.
write_wav(f"{sounds}/rematch.wav", np.concatenate([
    tone(440 * (1 + np.linspace(0, .5, int(.22 * SR))), .22, "sin", 2), np.zeros(int(.06 * SR)),
    tone(660 * (1 + np.linspace(0, .5, int(.3 * SR))), .3, "sin", 1.5)]))
for name in ["gg", "sad-trombone", "drumroll", "rematch"]:
    to_ogg(f"{sounds}/{name}.wav", f"{sounds}/{name}.ogg", "96k")
print("media in", audio, "and", sounds)
