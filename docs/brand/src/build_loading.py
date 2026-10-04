#!/usr/bin/env python3
"""Draws the loading animation: the rooster whistling along to its headphones.

The traced mark (logo/mark.svg, from build_brand.py) is cut into parts, and
each frame poses them: a slow, cosy lofi bop with its eyes closed and its
beak pursed, the comb and wattle swaying a little behind, and a music note
floating up off the beak on every beat. The frames are rasterised with
build_brand's Chrome renderer and packed into one animated WebP, which the
app (lib/ui/pages/loading/loading_page.dart) and the web splash
(web/index.html) both play. Needs headless Chrome, ImageMagick and ffmpeg.

    python3 docs/brand/src/build_loading.py
"""

import math
import os
import re
import subprocess
import tempfile

from build_brand import APP, BRAND, COMB, INK, YOLK, svg, render

OUT = os.path.join(APP, "assets", "images", "loading", "rooster_vibing.webp")

FRAMES = 40       # 12.5 fps on a 3.2 s loop: four beats at 75 bpm
PER_BEAT = 10
SIZE = 400        # shown at about 220 px, so sharp at 2x
VIEW = (-40, -140, 1220, 1220)  # room above the beak for the notes

# Where the parts hinge, in mark units.
BASE = (500, 910)       # the bottom of the neck: the bop and the sway
COMB_ROOT = (560, 470)
WATTLE_ROOT = (745, 600)
BEAK_ROOT = (742, 548)
BEAK_TIP = (882, 543)
EYE = (638, 511)

# A note leaves the beak every other beat and floats up for this many frames.
NOTE_EVERY = 2 * PER_BEAT
NOTE_LIFE = 36
NOTE_COLOURS = (YOLK, COMB)

# Drawn around the note head, stems up.
EIGHTH = ('<ellipse rx="24" ry="17" transform="rotate(-25)"/>'
          '<rect x="15" y="-92" width="9" height="90" rx="4"/>'
          '<path d="M19 -92 C48 -80 60 -58 46 -32 C50 -56 38 -66 19 -68 Z"/>')
BEAMED = ('<ellipse rx="22" ry="16" transform="rotate(-25)"/>'
          '<ellipse cx="62" cy="-12" rx="22" ry="16" transform="rotate(-25 62 -12)"/>'
          '<rect x="14" y="-96" width="9" height="94" rx="4"/>'
          '<rect x="75" y="-108" width="9" height="94" rx="4"/>'
          '<path d="M14 -100 L84 -112 L84 -88 L14 -76 Z"/>')


def parts():
    """The mark's colour layers, cut into subpaths: {layer: [(d, fill)]}."""
    text = open(os.path.join(BRAND, "logo", "mark.svg")).read()
    names = ["rim", "comb", "feather", "yolk", "ink"]
    found = re.findall(r'd="([^"]*)" fill="([^"]*)"', text)
    return {name: ([s for s in re.split(r"(?=M)", d) if s.strip()], fill)
            for name, (d, fill) in zip(names, found)}


def rotated(point, origin, degrees):
    a = math.radians(degrees)
    x, y = point[0] - origin[0], point[1] - origin[1]
    return (origin[0] + x * math.cos(a) - y * math.sin(a),
            origin[1] + x * math.sin(a) + y * math.cos(a))


def rotate(degrees, origin):
    return 'transform="rotate(%.2f %g %g)"' % ((degrees,) + origin)


def notes(f):
    """The notes in the air at frame f, oldest first."""
    out = []
    for n, born in enumerate(range(0, FRAMES, NOTE_EVERY)):
        age = (f - born) % FRAMES
        if age >= NOTE_LIFE:
            continue
        life = age / NOTE_LIFE
        x = 905 + 80 * life + 25 * math.sin(2 * math.pi * life * 1.2 + 2 * n)
        y = 500 - 560 * life
        turn = 14 * math.sin(2 * math.pi * life + 2 * n)
        scale = 0.7 + 0.8 * min(life / 0.35, 1)
        fade = min(life / 0.15, 1, (1 - life) / 0.4)
        shape = BEAMED if n % 2 else EIGHTH
        out.append('<g transform="translate(%.1f %.1f) rotate(%.1f) scale(%.3f)" '
                   'fill="%s" opacity="%.2f">%s</g>'
                   % (x, y, turn, scale, NOTE_COLOURS[n % 2], fade, shape))
    return "".join(out)


def frame(f, mark):
    t = f / FRAMES
    beat = (f % PER_BEAT) / PER_BEAT
    hit = math.cos(2 * math.pi * beat)   # 1 on the beat, -1 between beats
    sway = math.sin(2 * math.pi * 2 * t)  # one side, then the other

    # The whole rooster, barely: a soft nod on the beat and a slow sway,
    # leaning back a touch to whistle.
    sx, sy = 1 + 0.008 * hit, 0.995 - 0.015 * hit
    lean = -2 + 2.5 * sway + 1 * max(hit, 0)
    body = ('transform="translate(%g %g) rotate(%.2f) scale(%.4f %.4f) '
            'translate(%g %g)"' % (BASE + (lean, sx, sy) + (-BASE[0], -BASE[1])))

    # The comb and wattle follow a little behind.
    comb_turn = -2 * math.sin(2 * math.pi * (2 * t - 0.12)) - 1 * hit
    wattle_turn = 3 * math.sin(2 * math.pi * (2 * t - 0.2)) + 1 * hit

    rim, rim_fill = mark["rim"]
    (wattle, crown), comb_fill = mark["comb"]
    feather, feather_fill = mark["feather"]
    (beak,), yolk_fill = mark["yolk"]
    ink, ink_fill = mark["ink"]

    def path(d, fill, extra=""):
        return '<path d="%s" fill="%s" %s/>' % (d, fill, extra)

    out = [path("".join(rim), rim_fill)]
    out.append(path(crown, comb_fill, rotate(comb_turn, COMB_ROOT)))
    out.append(path(wattle, comb_fill, rotate(wattle_turn, WATTLE_ROOT)))
    # Eyes closed: no eye, and no hole in the face where it was.
    out.append(path("".join(s for i, s in enumerate(feather) if i != 3),
                    feather_fill))

    # The beak, pursed to whistle: the halves only just part.
    up, down = -2.5, 3.5
    a, b = rotated(BEAK_TIP, BEAK_ROOT, up), rotated(BEAK_TIP, BEAK_ROOT, down)
    out.append('<path d="M%g %g L%.1f %.1f L%.1f %.1f Z" fill="%s"/>'
               % (BEAK_ROOT + a + b + (INK,)))
    out.append('<g %s><path d="%s" fill="%s" clip-path="url(#upper)"/></g>'
               % (rotate(up, BEAK_ROOT), beak, yolk_fill))
    out.append('<g %s><path d="%s" fill="%s" clip-path="url(#lower)"/></g>'
               % (rotate(down, BEAK_ROOT), beak, yolk_fill))

    out.append(path("".join(s for i, s in enumerate(ink) if i != 4), ink_fill))
    # The closed eye, content.
    x, y = EYE
    out.append('<path d="M%g %g Q%g %g %g %g" fill="none" stroke="%s" '
               'stroke-width="17" stroke-linecap="round"/>'
               % (x - 34, y, x, y + 30, x + 34, y, INK))

    clips = ('<defs>'
             '<clipPath id="upper"><path d="M690 380 L920 380 L920 %g L%g %g Z"/></clipPath>'
             '<clipPath id="lower"><path d="M%g %g L920 %g L920 680 L690 680 Z"/></clipPath>'
             '</defs>' % (BEAK_TIP[1], BEAK_ROOT[0] - 50, BEAK_ROOT[1],
                          BEAK_ROOT[0] - 50, BEAK_ROOT[1], BEAK_TIP[1]))
    return svg(VIEW, clips + '<g %s>%s</g>' % (body, "".join(out)) + notes(f))


def main():
    mark = parts()
    with tempfile.TemporaryDirectory() as tmp:
        for f in range(FRAMES):
            render(frame(f, mark), os.path.join(tmp, "frame%02d.png" % f), SIZE)
        os.makedirs(os.path.dirname(OUT), exist_ok=True)
        # ffmpeg, not ImageMagick: ImageMagick blends each frame over the
        # last, so the notes leave trails.
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error",
                        "-framerate", "12.5", "-i", os.path.join(tmp, "frame%02d.png"),
                        "-c:v", "libwebp_anim", "-pix_fmt", "yuva420p",
                        "-quality", "82", "-loop", "0", OUT], check=True)
    print(OUT)


if __name__ == "__main__":
    main()
