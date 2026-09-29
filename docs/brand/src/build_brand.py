#!/usr/bin/env python3
"""Builds the Cockhouse logo, wordmark and every platform icon from code.

The shapes live here, not in hand-edited SVGs, so each size and colourway
comes from the same geometry. Needs fontTools (for the wordmark), ImageMagick
and headless Chrome (to rasterise).

    python3 docs/brand/src/build_brand.py            # docs/brand/ only
    python3 docs/brand/src/build_brand.py --install  # also the app's icons
"""

import math
import os
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BRAND = os.path.join(ROOT, "docs", "brand")
APP = os.path.join(ROOT, "cockhouse")
FONTS = os.path.join(APP, "assets", "font")
SORA = os.path.join(FONTS, "sora", "Sora-VariableFont_wght.ttf")

# The palette. Keep in sync with docs/brand/README.md and the tiamat themes.
HEARTH = "#2B1A14"    # the house
TIMBER = "#3D2A22"
WALNUT = "#6B3A22"
ASH = "#5F5557"
PLASTER = "#EADFCF"
EGGSHELL = "#F6EDE0"  # the tile
FEATHER = "#FFFAF3"   # the rooster
COMB = "#E4573A"
WATTLE = "#D9472F"
EMBER = "#E8813A"
YOLK = "#F6B65A"
BEAK = "#F4A23A"
MOSS = "#5E8F4E"
DUSK = "#3F4F6E"
PINE = "#2F5B4B"


# ------------------------------------------------------------------ the mark
#
# A dark house with a rooster looking out of it, headphones on. The comb
# sweeps back under the roof, the head fills the lower half, and the door
# opens at the bottom of the rooster's neck. Drawn on a 618 x 696 grid.

MARK_BOX = (0, 36, 618, 562)
ROOSTER_BOX = (84, 150, 416, 434)

HOUSE = ("M284 58 Q298 44 312 58 L598 272 Q614 286 598 300 L556 322 V566 "
         "Q556 590 532 590 H80 Q56 590 56 566 V322 L20 300 Q4 286 20 272 Z")
CHIMNEY = '<rect x="350" y="48" width="34" height="120" rx="12"/>'
def _lobe(base, tip, r_base, r_tip):
    """A comb lobe: narrow where it grows out of the head, round at the tip.

    The hull of a small circle at base and a big one set back from tip.
    """
    bx, by = base
    dx, dy = tip[0] - bx, tip[1] - by
    length = math.hypot(dx, dy)
    ux, uy = dx / length, dy / length
    cx, cy = tip[0] - ux * r_tip, tip[1] - uy * r_tip
    d = math.hypot(cx - bx, cy - by)
    theta = math.atan2(cy - by, cx - bx)
    alpha = math.acos((r_base - r_tip) / d)
    pts = []
    for sign in (1, -1):
        a = theta + sign * alpha
        pts.append(((bx + r_base * math.cos(a), by + r_base * math.sin(a)),
                    (cx + r_tip * math.cos(a), cy + r_tip * math.sin(a))))
    (b1, t1), (b2, t2) = pts
    return ('<path d="M%.1f %.1f L%.1f %.1f A%g %g 0 1 0 %.1f %.1f '
            'L%.1f %.1f A%g %g 0 0 0 %.1f %.1f Z"/>'
            % (b1 + t1 + (r_tip, r_tip) + t2 + b2 + (r_base, r_base) + b1))


# The comb: four big rounded lobes fanning back from the crown, as in the
# concept. Every lobe grows out of a point inside the head, which is drawn
# over it, so the comb sits on the head instead of floating above it.
CROWN = (326, 350)
COMB_SHAPES = (
    _lobe(CROWN, (392, 170), 36, 50)     # front, standing up
    + _lobe(CROWN, (236, 158), 36, 52)   # top, leaning back
    + _lobe(CROWN, (124, 240), 34, 48)   # back
    + _lobe(CROWN, (104, 350), 32, 42))  # lowest, trailing over the ear
HEAD = ("M160 590 C 164 530 174 468 190 420 C 206 350 262 306 330 306 "
        "C 372 306 402 330 414 372 L 408 430 C 404 480 404 540 406 590 Z")
# The head without a house under it ends in a rounded neck, not the ground.
HEAD_ALONE = ("M188 548 C 172 500 172 460 190 420 C 196 350 262 306 330 306 "
              "C 372 306 402 330 414 372 L 408 430 C 404 480 406 520 402 548 "
              "C 380 584 210 584 188 548 Z")
DOOR = "M279 590 V549 A34 34 0 0 1 347 549 V590 Z"
EYE = '<circle cx="355" cy="381" r="15"/>'
BEAK_D = "M410 370 L480 392 Q490 396 480 402 L412 422 Z"
WATTLE_D = "M408 440 C 446 440 466 480 458 516 C 452 540 420 540 410 516 Z"
# Headphones, seen from the side: the cup sits on the cheek behind the eye,
# and the band curves up out of it and forward over the crown
# and passes behind the head. It is clipped to the head outline, so it ends
# exactly where the head does.
CUP = (264, 414)
CUP_R = 56
BAND = "M262 380 C 260 344 280 314 330 288"
_ids = [0]


def _uid(prefix):
    _ids[0] += 1
    return "%s%d" % (prefix, _ids[0])


def headphones(head, dark=HEARTH, ring=FEATHER):
    """head: the outline the band is clipped to."""
    cx, cy = CUP
    clip = _uid("band")
    return ('<clipPath id="%s"><path d="%s"/></clipPath>' % (clip, head)
            + '<path d="%s" fill="none" stroke="%s" stroke-width="26" '
              'clip-path="url(#%s)"/>' % (BAND, dark, clip)
            + '<circle cx="%d" cy="%d" r="%d" fill="%s"/>' % (cx, cy, CUP_R, dark)
            + '<circle cx="%d" cy="%d" r="%d" fill="none" stroke="%s" '
              'stroke-width="11"/>' % (cx, cy, CUP_R - 15, ring))


def mark_elements(house=HEARTH, feather=FEATHER):
    """The full-colour mark: house, comb, head, headphones, door, face."""
    return (
        '<g fill="%s">%s</g>' % (house, CHIMNEY)
        + '<path d="%s" fill="%s"/>' % (HOUSE, house)
        + '<g fill="%s">%s</g>' % (COMB, COMB_SHAPES)
        + '<path d="%s" fill="%s"/>' % (HEAD, feather)
        + headphones(HEAD, house, feather)
        + '<path d="%s" fill="%s"/>' % (DOOR, house)
        + '<g fill="%s">%s</g>' % (house, EYE)
        + '<path d="%s" fill="%s"/>' % (BEAK_D, BEAK)
        + '<path d="%s" fill="%s"/>' % (WATTLE_D, WATTLE))


def rooster_elements(feather=FEATHER, eye=HEARTH):
    """Just the rooster, for dark backgrounds where the house would vanish."""
    return (
        '<g fill="%s">%s</g>' % (COMB, COMB_SHAPES)
        + '<path d="%s" fill="%s"/>' % (HEAD_ALONE, feather)
        + headphones(HEAD_ALONE, eye, feather)
        + '<g fill="%s">%s</g>' % (eye, EYE)
        + '<path d="%s" fill="%s"/>' % (BEAK_D, BEAK)
        + '<path d="%s" fill="%s"/>' % (WATTLE_D, WATTLE))


def mono_elements(color="currentColor", uid="m"):
    """One colour: the house with the rooster cut out of it.

    A thin gap keeps the comb and the head apart; the headphones, the eye
    and the door are filled back in so they still read.
    """
    return (
        '<defs><mask id="%(u)s" maskUnits="userSpaceOnUse" x="0" y="0" '
        'width="618" height="618">'
        '<path d="%(house)s" fill="#fff"/><g fill="#fff">%(chimney)s</g>'
        '<g fill="#000">%(comb)s</g>'
        '<path d="%(head)s" fill="#000" stroke="#fff" stroke-width="12"/>'
        '<path d="%(beak)s" fill="#000" stroke="#fff" stroke-width="10"/>'
        '<path d="%(wattle)s" fill="#000" stroke="#fff" stroke-width="10"/>'
        '%(phones)s'
        '<path d="%(door)s" fill="#fff"/><g fill="#fff">%(eye)s</g>'
        '</mask></defs>'
        '<rect width="618" height="618" fill="%(c)s" mask="url(#%(u)s)"/>'
        % {"u": uid, "house": HOUSE, "chimney": CHIMNEY, "comb": COMB_SHAPES,
           "head": HEAD, "beak": BEAK_D, "wattle": WATTLE_D,
           "phones": headphones(HEAD, "#fff", "#000"), "door": DOOR, "eye": EYE,
           "c": color})


def svg(view, body):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="%g %g %g %g">'
            '%s</svg>\n' % (tuple(view) + (body,)))


def fit(box, into):
    """transform= that centres box (in mark units) inside into=(x, y, w, h)."""
    bx, by, bw, bh = box
    x, y, w, h = into
    s = min(w / bw, h / bh)
    tx = x + (w - bw * s) / 2 - bx * s
    ty = y + (h - bh * s) / 2 - by * s
    return 'transform="translate(%.3f %.3f) scale(%.5f)"' % (tx, ty, s)


def tile(shape, fill):
    return {
        "rounded": '<rect width="1024" height="1024" rx="224" fill="%s"/>',
        "square": '<rect width="1024" height="1024" fill="%s"/>',
        "circle": '<circle cx="512" cy="512" r="512" fill="%s"/>',
        "none": "",
    }[shape].replace("%s", fill)


def app_icon_svg(shape="rounded", inset=112, background=EGGSHELL):
    """The mark on a cream tile. shape: rounded | square | circle | none."""
    area = (inset, inset, 1024 - 2 * inset, 1024 - 2 * inset)
    return svg((0, 0, 1024, 1024), tile(shape, background)
               + '<g %s>%s</g>' % (fit(MARK_BOX, area), mark_elements()))


def rooster_icon_svg(shape="rounded", inset=150):
    """The rooster alone on a hearth-brown tile."""
    area = (inset, inset, 1024 - 2 * inset, 1024 - 2 * inset)
    return svg((0, 0, 1024, 1024), tile(shape, HEARTH)
               + '<g %s>%s</g>' % (fit(ROOSTER_BOX, area), rooster_elements()))


def mono_icon_svg(color, inset=112, uid="m"):
    area = (inset, inset, 1024 - 2 * inset, 1024 - 2 * inset)
    return svg((0, 0, 1024, 1024),
               '<g %s>%s</g>' % (fit(MARK_BOX, area), mono_elements(color, uid)))


# ---------------------------------------------------------------- wordmark


_SORA = {}


def sora(weight):
    """Sora at a fixed weight (the file is variable)."""
    if weight not in _SORA:
        from fontTools.ttLib import TTFont
        from fontTools.varLib.instancer import instantiateVariableFont
        _SORA[weight] = instantiateVariableFont(TTFont(SORA), {"wght": weight})
    return _SORA[weight]


def text_path(text, weight=800, tracking=-24):
    """Outlines for text set in Sora. Returns (d, advance), baseline at y=0,
    in font units (1000 per em)."""
    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.pens.transformPen import TransformPen

    font = sora(weight)
    glyphs = font.getGlyphSet()
    cmap = font.getBestCmap()
    kern = _kerning(font)
    pen = SVGPathPen(glyphs)
    x = 0
    prev = None
    for ch in text:
        name = cmap[ord(ch)]
        if prev is not None:
            x += kern(prev, name)
        # Font units are y-up, SVG is y-down: flip about the baseline.
        glyphs[name].draw(TransformPen(pen, (1, 0, 0, -1, x, 0)))
        x += glyphs[name].width + tracking
        prev = name
    return pen.getCommands(), x - tracking


def _kerning(font):
    """Pair kerning from GPOS pair adjustment lookups (formats 1 and 2)."""
    pairs, classes = {}, []
    if "GPOS" in font:
        for lookup in font["GPOS"].table.LookupList.Lookup:
            subs = lookup.SubTable
            if lookup.LookupType == 9:
                subs = [s.ExtSubTable for s in subs]
            for sub in subs:
                if getattr(sub, "LookupType", 2) != 2 and lookup.LookupType != 2:
                    continue
                if sub.Format == 1:
                    for first, pset in zip(sub.Coverage.glyphs, sub.PairSet):
                        for rec in pset.PairValueRecord:
                            v = getattr(rec.Value1, "XAdvance", 0) if rec.Value1 else 0
                            if v:
                                pairs.setdefault((first, rec.SecondGlyph), v)
                elif sub.Format == 2:
                    classes.append(sub)

    def lookup(a, b):
        if (a, b) in pairs:
            return pairs[(a, b)]
        for sub in classes:
            if a not in sub.Coverage.glyphs:
                continue
            c1 = sub.ClassDef1.classDefs.get(a, 0)
            c2 = sub.ClassDef2.classDefs.get(b, 0)
            rec = sub.Class1Record[c1].Class2Record[c2]
            v = getattr(rec.Value1, "XAdvance", 0) if rec.Value1 else 0
            if v:
                return v
        return 0

    return lookup


CAP = 730   # Sora cap height, font units
NAME = "Cockhouse"
TAGLINE = "Your crew’s place on the internet."


def wordmark_svg(color):
    d, width = text_path(NAME)
    pad = 40
    return svg((-pad, -CAP - pad, width + 2 * pad, CAP + 200 + 2 * pad),
               '<path d="%s" fill="%s"/>' % (d, color))


def lockup_svg(ink, tagline_ink=None, rooster=False):
    """Mark left, name right, optional tagline under the name.

    rooster=True uses the house-less rooster, for dark backgrounds.
    """
    box = ROOSTER_BOX if rooster else MARK_BOX
    mark = rooster_elements() if rooster else mark_elements()
    mark_h = 360.0
    ms = mark_h / box[3]
    d, width = text_path(NAME)
    word_s = (mark_h * 0.42) / CAP
    gap = 36
    word_x = box[2] * ms + gap
    baseline = mark_h * (0.62 if tagline_ink else 0.71)
    body = ('<g transform="scale(%.5f) translate(%g %g)">%s</g>'
            % (ms, -box[0], -box[1], mark))
    body += ('<path transform="translate(%.2f %.2f) scale(%.5f)" d="%s" fill="%s"/>'
             % (word_x, baseline, word_s, d, ink))
    total_w = word_x + width * word_s
    if tagline_ink:
        td, tw = text_path(TAGLINE, weight=500, tracking=0)
        ts = min(word_s * 0.36, width * word_s / tw)
        body += ('<path transform="translate(%.2f %.2f) scale(%.5f)" d="%s" fill="%s"/>'
                 % (word_x + 6, baseline + CAP * word_s * 0.62, ts, td, tagline_ink))
    pad = 24
    return svg((-pad, -pad, total_w + 2 * pad, mark_h + 2 * pad), body)


def stacked_svg(ink):
    """Mark over the name, centred."""
    mark_h = 360.0
    ms = mark_h / MARK_BOX[3]
    mw = MARK_BOX[2] * ms
    d, width = text_path(NAME)
    word_s = (mark_h * 0.30) / CAP
    ww = width * word_s
    w = max(mw, ww)
    body = ('<g transform="translate(%.2f 0) scale(%.5f) translate(%g %g)">%s</g>'
            % ((w - mw) / 2, ms, -MARK_BOX[0], -MARK_BOX[1], mark_elements()))
    baseline = mark_h + 36 + CAP * word_s
    body += ('<path transform="translate(%.2f %.2f) scale(%.5f)" d="%s" fill="%s"/>'
             % ((w - ww) / 2, baseline, word_s, d, ink))
    pad = 24
    return svg((-pad, -pad, w + 2 * pad, baseline + 60 * word_s + 2 * pad), body)


def little_rooster(color, accent=None):
    """A small sitting rooster in profile, facing right, feet at (0, 0).

    One colour for screen printing; accent (if given) fills comb and wattle.
    """
    accent = accent or color
    return (
        '<g fill="none" stroke="%(c)s" stroke-linecap="round">'
        '<path d="M-30 -28 C -52 -32 -60 -52 -54 -72" stroke-width="10"/>'
        '<path d="M-30 -20 C -60 -18 -74 -38 -74 -58" stroke-width="9"/>'
        '<path d="M-30 -12 C -60 -6 -80 -22 -84 -40" stroke-width="8"/>'
        '</g>'
        '<ellipse cx="-4" cy="-26" rx="30" ry="22" fill="%(c)s"/>'
        '<path d="M6 -38 C 6 -56 14 -64 26 -64 C 40 -64 44 -52 40 -38 C 36 -26 20 -20 10 -24 Z" fill="%(c)s"/>'
        '<circle cx="28" cy="-66" r="17" fill="%(c)s"/>'
        '<g fill="%(a)s"><circle cx="19" cy="-83" r="7"/><circle cx="28" cy="-87" r="8"/>'
        '<circle cx="38" cy="-83" r="7"/></g>'
        '<path d="M43 -70 L60 -64 L43 -59 Z" fill="%(c)s"/>'
        '<ellipse cx="44" cy="-51" rx="4.5" ry="7" fill="%(a)s"/>'
        '<path d="M-10 -5 V4 M8 -5 V4" stroke="%(c)s" stroke-width="4" stroke-linecap="round"/>'
        % {"c": color, "a": accent})


def merch_tee_svg(color, accent=None):
    """COCKHOUSE in caps, with a little rooster sitting on a roofline above."""
    tracking = 30
    d, width = text_path("COCKHOUSE", tracking=tracking)
    s = 0.2
    w = width * s
    cap = CAP * s
    roof_y = -cap - 46
    body = '<path transform="scale(%g)" d="%s" fill="%s"/>' % (s, d, color)
    # A roofline over HOUSE, where the house is.
    house_x = (text_path("COCK", tracking=tracking)[1] + tracking) * s
    mid = (house_x + w) / 2
    half = (w - house_x) / 2 + 10
    body += ('<path d="M%g %g L%g %g L%g %g" fill="none" stroke="%s" '
             'stroke-width="12" stroke-linecap="round" stroke-linejoin="round"/>'
             % (mid - half, roof_y + 44, mid, roof_y - 50, mid + half, roof_y + 44, color))
    body += ('<g transform="translate(%g %g) scale(1.3)">%s</g>'
             % (mid + 8, roof_y - 52, little_rooster(color, accent)))
    pad = 40
    return svg((-pad, roof_y - 140, w + 2 * pad, cap + 140 + 46 + 40 + pad), body)


PALETTE = [
    ("Hearth", HEARTH, EGGSHELL), ("Walnut", WALNUT, EGGSHELL),
    ("Comb", COMB, FEATHER), ("Ember", EMBER, HEARTH),
    ("Yolk", YOLK, HEARTH), ("Eggshell", EGGSHELL, HEARTH),
    ("Moss", MOSS, FEATHER), ("Pine", PINE, FEATHER),
    ("Dusk", DUSK, FEATHER), ("Timber", TIMBER, EGGSHELL),
    ("Ash", ASH, EGGSHELL), ("Plaster", PLASTER, HEARTH),
]


def palette_svg():
    """Swatches with name and hex, in the brand's own type."""
    w, h, gap = 150, 170, 12
    body = ""
    for i, (name, fill, ink) in enumerate(PALETTE):
        x = (i % 6) * (w + gap)
        y = (i // 6) * (h + gap)
        body += ('<rect x="%d" y="%d" width="%d" height="%d" rx="18" fill="%s"%s/>'
                 % (x, y, w, h, fill,
                    ' stroke="%s" stroke-width="2"' % PLASTER if fill == EGGSHELL else ""))
        body += ('<text x="%d" y="%d" font-family="Sora, sans-serif" '
                 'font-weight="700" font-size="20" fill="%s">%s</text>'
                 % (x + 16, y + h - 44, ink, name))
        body += ('<text x="%d" y="%d" font-family="JetBrains Mono, monospace" '
                 'font-size="15" fill="%s" opacity=".8">%s</text>'
                 % (x + 16, y + h - 20, ink, fill))
    return svg((-20, -20, 6 * w + 5 * gap + 40, 2 * h + gap + 40),
               '<rect x="-20" y="-20" width="100%%" height="100%%" fill="%s"/>%s'
               % ("#FBF6EF", body))


# -------------------------------------------------------------- rasterising


def render(svg_text, out_png, size, background=None):
    """Rasterise at size x size with Chrome, then crop to the exact size."""
    w, h = size if isinstance(size, tuple) else (size, size)
    with tempfile.TemporaryDirectory() as tmp:
        html = os.path.join(tmp, "page.html")
        bg = background or "transparent"
        inner = svg_text.replace("<svg ", '<svg width="%d" height="%d" ' % (w, h), 1)
        faces = "".join(
            "@font-face{font-family:'%s';src:url('file://%s')}" % (name, os.path.join(FONTS, path))
            for name, path in (
                ("Sora", "sora/Sora-VariableFont_wght.ttf"),
                ("Nunito Sans", "nunito/NunitoSans-VariableFont_YTLC,opsz,wdth,wght.ttf"),
                ("JetBrains Mono", "code/JetBrainsMono-Regular.ttf")))
        with open(html, "w") as f:
            f.write('<html><head><style>%s</style></head>'
                    '<body style="margin:0;background:%s">%s</body></html>'
                    % (faces, bg, inner))
        shot = os.path.join(tmp, "shot.png")
        subprocess.run(
            ["google-chrome", "--headless=new", "--disable-gpu",
             "--hide-scrollbars", "--force-device-scale-factor=1",
             "--virtual-time-budget=1500", "--allow-file-access-from-files",
             "--default-background-color=00000000",
             "--window-size=%d,%d" % (max(w, 400), h + 200),
             "--screenshot=" + shot, "file://" + html],
            check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.makedirs(os.path.dirname(out_png) or ".", exist_ok=True)
        subprocess.run(["convert", shot, "-crop", "%dx%d+0+0" % (w, h),
                        "+repage", "PNG32:" + out_png], check=True)


def downscale(src, out, size):
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    subprocess.run(["convert", src, "-filter", "Lanczos", "-resize",
                    "%dx%d" % (size, size), "PNG32:" + out], check=True)


def ico(pngs, out):
    subprocess.run(["convert"] + pngs + [out], check=True)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as f:
        f.write(text)


# ------------------------------------------------------------------- builds


def build_brand(tmp):
    logo = os.path.join(BRAND, "logo")
    for stale in ("mark-small-on-dark.svg", "mark-small-on-light.svg",
                  "app-icon-small.svg"):
        if os.path.exists(os.path.join(logo, stale)):
            os.remove(os.path.join(logo, stale))
    files = {
        "mark.svg": svg(MARK_BOX, mark_elements()),
        "rooster.svg": svg(ROOSTER_BOX, rooster_elements()),
        "mark-mono.svg": svg(MARK_BOX, mono_elements()),
        "app-icon.svg": app_icon_svg(),
        "app-icon-dark.svg": rooster_icon_svg(),
        "app-icon-comb.svg": app_icon_svg(background=COMB),
        "wordmark-on-dark.svg": wordmark_svg(EGGSHELL),
        "wordmark-on-light.svg": wordmark_svg(HEARTH),
        "lockup-on-light.svg": lockup_svg(HEARTH),
        "lockup-on-dark.svg": lockup_svg(EGGSHELL, rooster=True),
        "lockup-tagline-on-light.svg": lockup_svg(HEARTH, tagline_ink=ASH),
        "lockup-stacked-on-light.svg": stacked_svg(HEARTH),
    }
    for old in ("mark-on-dark.svg", "mark-on-light.svg"):
        if os.path.exists(os.path.join(logo, old)):
            os.remove(os.path.join(logo, old))
    for name, text in files.items():
        write(os.path.join(logo, name), text)
    merch = os.path.join(BRAND, "merch")
    write(os.path.join(merch, "tee-on-dark.svg"), merch_tee_svg(EGGSHELL, COMB))
    write(os.path.join(merch, "tee-on-light.svg"), merch_tee_svg(HEARTH, COMB))
    write(os.path.join(merch, "tee-one-colour.svg"), merch_tee_svg(EGGSHELL))
    render(files["app-icon.svg"], os.path.join(logo, "app-icon-1024.png"), 1024)
    write(os.path.join(BRAND, "palette.svg"), palette_svg())

    # PNG previews for the guide.
    preview = os.path.join(BRAND, "preview")
    for old in ("mark-on-dark.png", "mark-on-light.png"):
        if os.path.exists(os.path.join(preview, old)):
            os.remove(os.path.join(preview, old))
    shots = [
        ("logo/lockup-tagline-on-light.svg", "lockup-tagline.png", (900, 260), "#FBF6EF"),
        ("logo/lockup-on-light.svg", "lockup-on-light.png", (900, 260), "#FBF6EF"),
        ("logo/lockup-on-dark.svg", "lockup-on-dark.png", (900, 260), "#221A17"),
        ("logo/lockup-stacked-on-light.svg", "lockup-stacked.png", (400, 400), "#FBF6EF"),
        ("logo/mark-mono.svg", "mark-mono.png", (400, 386), "#FBF6EF"),
        ("merch/tee-on-dark.svg", "tee-on-dark.png", (900, 380), HEARTH),
        ("palette.svg", "palette.png", (1012, 390), None),
        ("illustrations/roof-rooster.svg", "roof-rooster.png", (800, 600), None),
        ("illustrations/motifs.svg", "motifs.png", (960, 300), None),
    ]
    for src, out, size, bg in shots:
        with open(os.path.join(BRAND, src)) as f:
            render(f.read(), os.path.join(preview, out), size, background=bg)

    # The icon family, as in the concept board.
    fam = []
    for i, text in enumerate([rooster_icon_svg(), app_icon_svg(),
                              app_icon_svg(background=COMB),
                              svg((0, 0, 1024, 1024), tile("rounded", PLASTER)
                                  + '<g %s>%s</g>' % (fit(MARK_BOX, (112, 112, 800, 800)),
                                                      mono_elements(HEARTH, "f"))),
                              svg((0, 0, 1024, 1024), tile("rounded", HEARTH)
                                  + '<g %s>%s</g>' % (fit(MARK_BOX, (112, 112, 800, 800)),
                                                      mono_elements(EGGSHELL, "g")))]):
        p = os.path.join(tmp, "fam%d.png" % i)
        render(text, p, 200)
        fam.append(p)
    subprocess.run(["convert"] + fam + ["-background", "none", "-gravity", "east",
                    "-splice", "20x0", "+append",
                    "PNG32:" + os.path.join(preview, "icon-family.png")], check=True)

    big = os.path.join(tmp, "big.png")
    render(files["app-icon.svg"], big, 512)
    sizes = []
    for s in (16, 32, 48, 128):
        p = os.path.join(tmp, "s%d.png" % s)
        downscale(big, p, s)
        sizes.append(p)
    subprocess.run(["convert"] + sizes + ["-background", "none", "-gravity",
                    "southeast", "-splice", "24x0", "+append",
                    "PNG32:" + os.path.join(preview, "icon-sizes.png")], check=True)


def build_app(tmp):
    """Every icon the platforms ship, from the same few renders."""
    big = os.path.join(tmp, "rounded.png")
    render(app_icon_svg(), big, 1024)
    # Below 48 px the tile's margin costs too much: fill more of it.
    small = os.path.join(tmp, "rounded-small.png")
    render(app_icon_svg(inset=56), small, 256)

    def icon_at(size, out):
        downscale(big if size >= 48 else small, out, size)

    # Flutter assets: login/about page SVG, notification and widget PNGs.
    icons = os.path.join(APP, "assets", "images", "app_icon")
    write(os.path.join(icons, "icon.svg"), app_icon_svg())
    render(app_icon_svg("square"), os.path.join(icons, "app_icon_filled.png"), 1024)
    render(app_icon_svg("rounded"), os.path.join(icons, "app_icon_rounded.png"), 1024)
    # Android adaptive foreground: the mark inside the 66/108 safe zone.
    render(app_icon_svg("none", inset=215), os.path.join(icons, "app_icon_transparent.png"), 1024)
    render(app_icon_svg("none", inset=24), os.path.join(icons, "app_icon_transparent_cropped.png"), 512)

    # Web.
    web = os.path.join(APP, "web")
    for s in (16, 32, 96):
        icon_at(s, os.path.join(web, "favicon-%dx%d.png" % (s, s)))
    for s in (192, 512):
        icon_at(s, os.path.join(web, "icons", "Icon-%d.png" % s))
        # Maskable: full bleed, the mark inside the 80% safe circle.
        render(app_icon_svg("square", inset=240),
               os.path.join(web, "icons", "Icon-maskable-%d.png" % s), s)
    splashes = {
        "dark": svg((0, 0, 1024, 1024), '<g %s>%s</g>' % (
            fit(ROOSTER_BOX, (150, 150, 724, 724)), rooster_elements())),
        "light": svg((0, 0, 1024, 1024), '<g %s>%s</g>' % (
            fit(MARK_BOX, (112, 112, 800, 800)), mark_elements())),
    }
    for theme, splash in splashes.items():
        for i, s in enumerate((661, 1323, 1984, 2646), start=1):
            render(splash, os.path.join(web, "splash", "img", "%s-%dx.png" % (theme, i)), s)

    # Windows.
    sizes = [16, 20, 24, 32, 40, 48, 64, 256]
    pngs = []
    for s in sizes:
        p = os.path.join(tmp, "win-%d.png" % s)
        icon_at(s, p)
        pngs.append(p)
    ico(pngs, os.path.join(APP, "windows", "runner", "resources", "app_icon.ico"))

    # Tray (idle state; live and muted are the mic glyphs).
    tray = os.path.join(APP, "assets", "images", "tray")
    circ = os.path.join(tmp, "tray-circle.png")
    render(app_icon_svg("circle", inset=150), circ, 256)
    downscale(circ, os.path.join(tray, "idle.png"), 64)
    tray_pngs = []
    for s in sizes:
        p = os.path.join(tmp, "tray-%d.png" % s)
        downscale(circ, p, s)
        tray_pngs.append(p)
    ico(tray_pngs, os.path.join(tray, "idle.ico"))

    # Linux.
    hicolor = os.path.join(APP, "linux", "debian", "usr", "share", "icons", "hicolor")
    for s in (16, 32, 64, 128, 256, 512):
        icon_at(s, os.path.join(hicolor, "%dx%d" % (s, s), "apps", "cockhouse.png"))
    icon_at(512, os.path.join(APP, "linux", "flatpak", "icon.png"))

    # Android.
    res = os.path.join(APP, "android", "app", "src", "main", "res")
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    fg = os.path.join(tmp, "android-fg.png")
    render(app_icon_svg("none", inset=215), fg, 432)
    # Themed icon (Android 13+): the one-colour mark in the same safe zone.
    mono_fg = os.path.join(tmp, "android-mono.png")
    render(mono_icon_svg("#FFFFFF", inset=215), mono_fg, 432)
    # Status bar: white on transparent, drawn by the system, as big as fits.
    note = os.path.join(tmp, "android-note.png")
    render(mono_icon_svg("#FFFFFF", inset=40), note, 192)
    for d, k in dens.items():
        icon_at(int(48 * k), os.path.join(res, "mipmap-" + d, "ic_launcher.png"))
        downscale(fg, os.path.join(res, "drawable-" + d, "ic_launcher_foreground.png"),
                  int(108 * k))
        downscale(mono_fg, os.path.join(res, "drawable-" + d, "ic_launcher_monochrome.png"),
                  int(108 * k))
        downscale(note, os.path.join(res, "drawable-" + d, "notification_icon.png"),
                  int(48 * k))
    vector = os.path.join(res, "drawable", "ic_launcher_monochrome.xml")
    if os.path.exists(vector):
        os.remove(vector)  # replaced by the PNGs above; one name, one resource
    colors = os.path.join(res, "values", "colors.xml")
    write(colors, '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
                  '    <color name="ic_launcher_background">%s</color>\n'
                  '</resources>\n' % EGGSHELL)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        build_brand(tmp)
        if "--install" in sys.argv:
            build_app(tmp)


if __name__ == "__main__":
    main()
