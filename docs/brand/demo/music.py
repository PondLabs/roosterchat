#!/usr/bin/env python3
"""The demo's music and sound effects, synthesized, but for the soundboard.

120 bpm in C, I-V-vi-IV. The arrangement follows demo.html's timeline:
pads and a riser under the logo, the groove from the app's entrance, a
breakdown under the Matrix scene, a hit on the outro. Sound effects land on
the same times as the animation (clicks, the soundboard, the DJ); the
soundboard presses play the app's own sounds.

    python3 music.py out.wav [duration] [cues]

[cues] picks the timeline from CUES: `demo` (the 55 s landscape video, the
default) or `reel` (the 32 s vertical one).
"""

import os
import subprocess
import sys
import wave

import numpy as np
from scipy import signal

SR = 48000
BPM = 120
BEAT = 60 / BPM
DUR = float(sys.argv[2]) if len(sys.argv) > 2 else 55.0

# When things happen in each video, in seconds: the sections of the song
# and the sound effects, matched to the animation. presses are soundboard
# buttons clicked on screen, played with the app's own sounds. quiet is the
# noise suppression scene, where mic plays (when, file, from, seconds): the
# typing as the microphone hears it, then what the room hears.
CUES = {
    "demo": dict(
        groove=4, brk=47.4, hit=52.9, pads_until=56, fade_from=58.3,
        risers=[(2.4, 1.6, .7), (51.5, 1.4, .55)],
        whooshes=[(3.6, .6, .8), (9.4, .5, .5), (17.2, .5, .5), (21.4, .5, .5),
                  (24.8, .5, .5), (29.2, .5, .5), (35.2, .5, .5), (41.0, .5, .5),
                  (47.2, .9, .7)],
        # the Lounge filling up
        chimes=[4.4, 4.9, 5.4, 5.9, 6.4, 6.9, 7.4],
        quiet=(9.9, 17.6),
        mic=[(10.2, "noisy_48k.wav", 0.0, 3.6), (13.8, "clean_48k.wav", 3.6, 3.6)],
        ticks=[13.8, 37.4, 39.3], presses=[(37.42, "rooster"), (39.32, "bonk")],
        scratch=29.8),
    "reel": dict(
        groove=2.6, brk=33.4, hit=33.6, pads_until=36, fade_from=37.3,
        risers=[(0.6, 1.4, .5), (32.2, 1.4, .55)],
        whooshes=[(2.2, .5, .8), (6.4, .45, .5), (12.6, .45, .5),
                  (16.2, .45, .5), (19.8, .45, .5), (24.2, .45, .5), (29.0, .45, .5)],
        chimes=[],
        quiet=(6.9, 12.9),
        mic=[(7.1, "noisy_48k.wav", 0.0, 2.8), (9.9, "clean_48k.wav", 2.8, 2.8)],
        ticks=[9.9, 26.0, 27.6], presses=[(26.02, "rooster"), (27.62, "bonk")],
        scratch=20.4),
}
C = CUES[sys.argv[3] if len(sys.argv) > 3 else "demo"]
N = int(SR * DUR)
rng = np.random.default_rng(7)

L = np.zeros(N)
R = np.zeros(N)
VERB = np.zeros(N)  # reverb send (mono)


def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def at(t):
    return int(t * SR)


def env(n, a=.005, d=.2, s=0.0, r=.05, hold=None):
    """Attack/decay/sustain/release envelope over n samples."""
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-6), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-6)))
    if hold is not None:
        rel = t > hold
        e[rel] *= np.exp(-(t[rel] - hold) / max(r, 1e-6))
    return e


def add(x, t, gain=1.0, pan=0.0, verb=0.0):
    i = at(t)
    if i >= N:
        return
    x = x[: N - i]
    lg, rg = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
    L[i:i + len(x)] += x * gain * lg * 1.414
    R[i:i + len(x)] += x * gain * rg * 1.414
    VERB[i:i + len(x)] += x * gain * verb


def saw(f, n, detune=0.0):
    t = np.arange(n) / SR
    ph = (t * f * 2 ** (detune / 1200)) % 1.0
    return 2 * ph - 1


def lp(x, cutoff, order=2):
    b, a = signal.butter(order, min(cutoff, SR / 2 - 100) / (SR / 2), "low")
    return signal.lfilter(b, a, x)


def hp(x, cutoff, order=2):
    b, a = signal.butter(order, cutoff / (SR / 2), "high")
    return signal.lfilter(b, a, x)


def bp(x, lo, hi):
    b, a = signal.butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
    return signal.lfilter(b, a, x)


# ------------------------------------------------------------ instruments

def kick():
    n = at(.42)
    t = np.arange(n) / SR
    f = 46 + 110 * np.exp(-t / .035)
    body = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / .16)
    click = hp(rng.standard_normal(n), 3000) * np.exp(-t / .004) * .3
    return np.tanh((body + click) * 1.6)


def clap():
    n = at(.35)
    t = np.arange(n) / SR
    noise = bp(rng.standard_normal(n), 900, 5000)
    e = np.zeros(n)
    for k, off in enumerate([0, .011, .022]):
        m = t >= off
        e[m] += np.exp(-(t[m] - off) / (.008 if k < 2 else .09))
    return noise * e * .6


def hat(open_=False):
    n = at(.25 if open_ else .06)
    t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7500) * np.exp(-t / (.07 if open_ else .014)) * .35


def crash():
    n = at(2.0)
    t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 4000) * np.exp(-t / .6) * .3


def pluck(m, length=.28):
    n = at(length)
    t = np.arange(n) / SR
    f = hz(m)
    mod = np.sin(2 * np.pi * f * 2 * t) * 1.2 * np.exp(-t / .05)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t / .09)


def bell(m, length=.9):
    n = at(length)
    t = np.arange(n) / SR
    f = hz(m)
    mod = np.sin(2 * np.pi * f * 3.5 * t) * 2.0 * np.exp(-t / .2)
    return np.sin(2 * np.pi * f * t + mod) * np.exp(-t / .3)


def pad_chord(notes, length):
    n = at(length)
    x = np.zeros(n)
    for m in notes:
        for d in (-8, 0, 8):
            x += saw(hz(m), n, d)
    x = lp(x / (len(notes) * 3), 1500)
    return x * env(n, a=.25, d=10, s=1, r=.4, hold=length - .4)


def bass_note(m, length):
    n = at(length)
    x = saw(hz(m), n) + .5 * np.sin(2 * np.pi * hz(m) * np.arange(n) / SR)
    return lp(x, 520) * env(n, a=.004, d=.18, s=.55, r=.04, hold=length - .05)


# ------------------------------------------------------------ the song

CHORDS = [  # per bar: pad voicing, bass root
    ([60, 64, 67, 72], 36),  # C
    ([59, 62, 67, 71], 43),  # G
    ([60, 64, 69, 72], 45),  # Am
    ([60, 65, 69, 72], 41),  # F
]
BAR = 4 * BEAT
bars = int(DUR / BAR) + 1


def section(t):
    if t < C["groove"]:
        return "intro"
    if t < C["brk"]:
        return "groove"
    if t < C["hit"]:
        return "break"
    return "outro"


for b in range(bars):
    t0 = b * BAR
    if t0 >= DUR:
        break
    notes, root = CHORDS[b % 4]
    sec = section(t0)
    # pads everywhere but the very end
    if t0 < C["pads_until"]:
        add(pad_chord(notes, BAR + .3), t0, gain=.16 if sec != "groove" else .11, verb=.5)
    # arpeggio: 16ths over the chord, two octaves
    if sec in ("intro", "groove", "break"):
        arp = [notes[0] + 12, notes[1] + 12, notes[2] + 12, notes[3] + 12,
               notes[2] + 12, notes[1] + 12, notes[3] + 12, notes[1] + 24]
        for k in range(16):
            tt = t0 + k * BEAT / 4
            if sec == "intro" and tt < min(1.0, C["groove"] / 2):
                continue
            g = .09 if sec == "groove" else .07
            add(pluck(arp[k % 8]), tt, gain=g, pan=(.45 if k % 2 else -.45), verb=.35)
    for k in range(4):
        tb = t0 + k * BEAT
        if section(tb) == "groove":
            add(kick(), tb, gain=.9)
            if k in (1, 3):
                add(clap(), tb, gain=.55, verb=.25)
            add(hat(open_=(k == 3)), tb + BEAT / 2, gain=.6, pan=.2)
            add(hat(), tb + BEAT / 4, gain=.25, pan=-.2)
            add(hat(), tb + 3 * BEAT / 4, gain=.25, pan=-.2)
            # bass: root on the beat, octave on the off-beat
            add(bass_note(root, BEAT / 2 - .02), tb, gain=.5)
            add(bass_note(root + 12, BEAT / 2 - .02), tb + BEAT / 2, gain=.32)
    if sec == "break":
        # a heartbeat of a kick, filtered, on beat one
        add(lp(kick(), 300), t0, gain=.6)

# the outro: one big hit, then the chord rings out
HIT = C["hit"]
add(kick(), HIT, gain=1.0)
add(crash(), HIT, gain=.8, verb=.6)
add(pad_chord([48, 60, 64, 67, 72, 76], 3.6), HIT, gain=.22, verb=.7)
for k, m in enumerate([72, 76, 79, 84]):
    add(bell(m, 1.6), HIT + k * .12, gain=.12, pan=(-.4 + .27 * k), verb=.6)

# ------------------------------------------------------------ sound effects

def riser(length):
    n = at(length)
    t = np.arange(n) / SR
    x = rng.standard_normal(n)
    out = np.zeros(n)
    # sweep a band up by processing in chunks
    chunk = 1024
    zi = None
    for i in range(0, n, chunk):
        frac = i / n
        lo, hi = 300 + 3000 * frac, 900 + 9000 * frac
        b, a = signal.butter(2, [lo / (SR / 2), hi / (SR / 2)], "band")
        if zi is None or len(zi) != max(len(a), len(b)) - 1:
            zi = signal.lfilter_zi(b, a) * 0
        out[i:i + chunk], zi = signal.lfilter(b, a, x[i:i + chunk], zi=zi)
    return out * (t / length) ** 2 * .5


def whoosh(length=.5):
    n = at(length)
    t = np.arange(n) / SR
    x = bp(rng.standard_normal(n), 400, 4000)
    return x * np.sin(np.pi * t / length) ** 2 * .35


def chime(i):
    base = [76, 79, 81, 84][i % 4]
    first = bell(base, .7)
    second = np.pad(bell(base + 7, .6), (at(.07), 0))
    second = np.pad(second, (0, max(0, len(first) - len(second))))[:len(first)]
    return first * .6 + second * .5


def tick():
    n = at(.03)
    t = np.arange(n) / SR
    return np.sin(2 * np.pi * 2600 * t) * np.exp(-t / .006) * .5


SOUNDS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..",
                      "rooster", "assets", "soundboard")


def sample(name):
    """A sound from the app's soundboard (CC0, see its CREDITS.md), mono."""
    path = next(os.path.join(SOUNDS, f) for f in sorted(os.listdir(SOUNDS))
                if f.startswith(name + "-"))
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", path, "-ac", "1",
                          "-ar", str(SR), "-f", "f32le", "-"],
                         check=True, capture_output=True).stdout
    x = np.frombuffer(raw, dtype="<f4").astype(float)
    return x[: at(2.2)] * np.minimum(1, (at(2.2) - np.arange(len(x[: at(2.2)]))) / at(.3))


def scratch():
    n = at(.45)
    t = np.arange(n) / SR
    speed = np.sin(2 * np.pi * 6 * t) * np.exp(-t / .3)
    x = rng.standard_normal(n)
    out = np.zeros(n)
    chunk = 512
    for i in range(0, n, chunk):
        c = 800 + 3000 * abs(speed[i])
        out[i:i + chunk] = bp(x[i:i + chunk], c * .5, c)
    return out * np.abs(speed) * .6


for tr, length, g in C["risers"]:
    add(riser(length), tr, gain=g, verb=.3)
for i, (tw, length, g) in enumerate(C["whooshes"]):
    add(whoosh(length), tw, gain=g, pan=(-.2 if i % 2 == 0 else .2))
for i, tj in enumerate(C["chimes"]):
    add(chime(i), tj, gain=.35, pan=(-.3 + .2 * i), verb=.4)
for tc in C["ticks"]:
    add(tick(), tc, gain=.5)
for i, (tp, name) in enumerate(C["presses"]):
    add(sample(name), tp, gain=.75, pan=(-.15 if i % 2 == 0 else .15), verb=.15)
add(scratch(), C["scratch"], gain=.5, verb=.1)

# ------------------------------------------------------------ mix

# the music ducks under the kick a little (sidechain pump on pads/arp is
# approximated by ducking the whole bed on groove beats)
duck = np.ones(N)
for b in range(int(DUR / BEAT)):
    tb = b * BEAT
    if C["groove"] <= tb < C["brk"]:
        i = at(tb)
        k = np.arange(min(at(.25), N - i)) / SR
        duck[i:i + len(k)] = np.minimum(duck[i:i + len(k)], 1 - .25 * np.exp(-k / .08))

# reverb: a decaying noise tail, a little different per side
ir_n = at(1.8)
irt = np.arange(ir_n) / SR
ir_l = rng.standard_normal(ir_n) * np.exp(-irt / .45)
ir_r = rng.standard_normal(ir_n) * np.exp(-irt / .45)
v = lp(VERB, 6000)
L += signal.fftconvolve(v, ir_l)[:N] * .018
R += signal.fftconvolve(v, ir_r)[:N] * .018

L, R = L * duck, R * duck

# The noise suppression scene: the music all but stops, and a microphone
# plays, first as it is (someone talking over a keyboard), then as the voice
# DSP sends it (media.sh makes both from the same recording).
q0, q1 = C["quiet"]
hush = np.ones(N)
tt = np.arange(N) / SR
hush -= .88 * np.clip(np.minimum((tt - q0) / .4, (q1 - tt) / .4), 0, 1)
L, R = L * hush, R * hush
WORK = os.environ.get("DEMO_WORK", "/tmp/rooster-demo")
for tm, name, start, dur in C["mic"]:
    with wave.open(os.path.join(WORK, name)) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(float) / 32768
    x = x[at(start): at(start + dur)].copy()
    ramp = min(at(.03), len(x) // 2)
    x[:ramp] *= np.linspace(0, 1, ramp)
    x[-ramp:] *= np.linspace(1, 0, ramp)
    i = at(tm)
    x = x[: max(0, N - i)]
    L[i:i + len(x)] += x * 1.6
    R[i:i + len(x)] += x * 1.6

# fade in from silence and out at the end
fade = np.ones(N)
fade[: at(.05)] = np.linspace(0, 1, at(.05))
tail = at(DUR - C["fade_from"])
if tail > 0:
    fade[-tail:] = np.linspace(1, 0, tail) ** 2

L, R = np.tanh(L * 1.1) * fade, np.tanh(R * 1.1) * fade
peak = max(np.abs(L).max(), np.abs(R).max())
L, R = L / peak * .89, R / peak * .89

pcm = (np.stack([L, R], axis=1) * 32767).astype("<i2")
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2)
    w.setsampwidth(2)
    w.setframerate(SR)
    w.writeframes(pcm.tobytes())
print(sys.argv[1])
