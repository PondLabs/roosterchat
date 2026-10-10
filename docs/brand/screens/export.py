#!/usr/bin/env python3
"""Turns capture.mjs's captures into the landing page's images: crops them,
scales them to the two widths each one is shown at, and encodes WebP and
AVIF into website/media/shots.

Crops are in CSS pixels of the capture (the captures are at 2x). A capture
that isn't there is skipped and its images are left as they are; the
self-repair notice (card-health) was caught live, and capture.mjs doesn't
stage it. Needs ImageMagick's magick and avifenc.

Usage: export.py
"""
import json
import os
import subprocess
import tempfile

WORK = os.environ.get("ROOSTER_SHOTS", "/tmp/rooster-shots")
CAPS = os.path.join(WORK, "caps")
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
OUT = os.path.join(ROOT, "website", "media", "shots")


def side_file(name):
    path = os.path.join(CAPS, name + ".json")
    return json.load(open(path)) if os.path.exists(path) else {}


# name on the page, capture, crop (x, y, width, height) or None, widths
IMAGES = [
    ("hero", "call-dj-listener", [0, 0, 1294, 891], [960, 1920]),
    ("call-lounge", "call", None, [960, 1920]),
    ("call-share", "call-share", None, [960, 1920]),
    ("call-soundboard", "call-soundboard", None, [960, 1920]),
    ("call-dj", "priya-dj", None, [960, 1920]),
    ("chat-general", "chat-up", None, [960, 1920]),
    ("laptop", "chat", None, [960, 1920]),
    ("space", "space", None, [960, 1920]),
    ("phone-call", "phone-call", None, [402, 804]),
    ("phone-chat", "phone-chat", None, [402, 804]),
    ("card-volume", "volume", side_file("volume").get("crop", [405, 175, 330, 220]), [420, 660]),
    ("card-around", "phone-around", [71, 0, 291, 330], [300, 582]),
    ("card-health", "health", [572, 809, 368, 64], [372, 736]),
]


def encode(name, source, crop, widths, scale=2):
    for width in widths:
        tmp = os.path.join(tempfile.gettempdir(), f"rooster-export-{name}-{width}.png")
        cmd = ["magick", source]
        if crop:
            x, y, w, h = crop
            cmd += ["-crop", f"{w * scale}x{h * scale}+{x * scale}+{y * scale}", "+repage"]
        subprocess.run(cmd + ["-filter", "Lanczos", "-resize", f"{width}x", "-strip", tmp], check=True)
        base = os.path.join(OUT, f"{name}-{width}")
        subprocess.run(["magick", tmp, "-quality", "82", "-define", "webp:method=6", base + ".webp"], check=True)
        subprocess.run(["avifenc", "-s", "4", "-q", "62", tmp, base + ".avif"], check=True, stdout=subprocess.DEVNULL)
        os.remove(tmp)
        print(f"{name}-{width}: {os.path.getsize(base + '.webp') // 1024} KB webp, {os.path.getsize(base + '.avif') // 1024} KB avif")


os.makedirs(OUT, exist_ok=True)
for name, capture, crop, widths in IMAGES:
    source = os.path.join(CAPS, capture + ".png")
    if not os.path.exists(source):
        print(f"{name}: no {capture}.png, left as it is")
        continue
    encode(name, source, crop, widths)
