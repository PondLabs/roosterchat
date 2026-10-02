#!/usr/bin/env python3
"""Builds the Rooster logo, wordmark and every platform icon from code.

The mark is traced from src/mark.png; everything else is drawn here, so each
size and colourway comes from the same shapes. Needs fontTools (for the
wordmark), Pillow, NumPy and potracer (to trace the mark), ImageMagick and
headless Chrome (to rasterise).

    python3 docs/brand/src/build_brand.py            # docs/brand/ only
    python3 docs/brand/src/build_brand.py --install  # also the app's icons
"""

import os
import subprocess
import sys
import tempfile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
BRAND = os.path.join(ROOT, "docs", "brand")
APP = os.path.join(ROOT, "rooster")
FONTS = os.path.join(APP, "assets", "font")
SORA = os.path.join(FONTS, "sora", "Sora-VariableFont_wght.ttf")

# The palette. Keep in sync with docs/brand/README.md and the tiamat themes.
# Ink, comb, yolk and feather are the colours of the source art.
INK = "#211614"       # headphones, eye and door; the dark tile
COMB = "#E8382A"      # comb and wattle; the primary accent
YOLK = "#F89B17"      # the beak; highlights, away
CREAM = "#F7EDE1"     # the light tile and background, text on dark
STONE = "#8D8178"     # secondary text, the tagline
SPRUCE = "#2E3B33"    # quiet dark accent
FEATHER = "#FCF8F1"   # the rooster's head
COMB_ON_RED = "#FF8466"  # the comb, on a comb-red tile, so it still reads


# ------------------------------------------------------------------ the mark
#
# A rooster's head in profile, facing right, headphones on: it is in a call.
# The mark is drawn in src/mark.png (transparent, four flat colours) and
# traced here into one vector layer per colour, on a 1000-unit grid. To
# change the mark, change the PNG. Needs Pillow, NumPy and potracer.

SOURCE = os.path.join(BRAND, "src", "mark.png")
# Each pixel of the art is whichever of these it is nearest to.
_ART = {"comb": (232, 56, 42), "feather": (252, 248, 241),
        "ink": (33, 22, 20), "yolk": (248, 155, 23)}
_LAYERS = {}


def _grow(mask, r):
    """mask, grown by r pixels (square), so the layer under an edge has no
    hairline gap at it."""
    import numpy as np
    out = mask.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(mask, dy, 0), dx, 1)
    return out


def _open(mask, r):
    """mask without the parts narrower than 2r + 1 pixels."""
    return _grow(~_grow(~mask, r), r)


def _path(mask, scale):
    """SVG path data for mask, traced with potrace."""
    import potrace
    # potracer's Bitmap treats True as background.
    curves = potrace.Bitmap(~mask).trace(turdsize=40, alphamax=1.0,
                                         opticurve=True, opttolerance=0.2)
    d = []
    for curve in curves:
        p = curve.start_point
        d.append("M%.1f %.1f" % (p.x * scale, p.y * scale))
        for seg in curve.segments:
            e = seg.end_point
            if seg.is_corner:
                d.append("L%.1f %.1f L%.1f %.1f" % (seg.c.x * scale, seg.c.y * scale,
                                                   e.x * scale, e.y * scale))
            else:
                d.append("C%.1f %.1f %.1f %.1f %.1f %.1f" % (
                    seg.c1.x * scale, seg.c1.y * scale, seg.c2.x * scale,
                    seg.c2.y * scale, e.x * scale, e.y * scale))
        d.append("Z")
    return " ".join(d)


def layers():
    """The traced mark: {name: path data}, plus "mono" and "box"."""
    if _LAYERS:
        return _LAYERS
    import numpy as np
    from PIL import Image
    art = np.array(Image.open(SOURCE).convert("RGBA")).astype(int)
    # A margin, so nothing touches the edge of the bitmap.
    art = np.pad(art, ((20, 20), (20, 20), (0, 0)))
    solid = art[..., 3] > 128
    names = list(_ART)
    refs = np.array([_ART[n] for n in names])
    nearest = ((art[..., None, :3] - refs) ** 2).sum(-1).argmin(-1)
    masks = {n: solid & (nearest == i) for i, n in enumerate(names)}
    # Anti-aliased edge pixels land on the wrong colour (a dark-to-white
    # edge is nearest to yolk): drop slivers narrower than a few pixels.
    masks = {n: _open(m, 1 if n == "ink" else 3) for n, m in masks.items()}
    scale = 1000.0 / art.shape[1]
    # Drawn bottom to top: comb, head, beak, ink. Each layer under another
    # reaches a little way under it, inside the silhouette.
    _LAYERS["comb"] = _path(_grow(masks["comb"], 3) & solid, scale)
    _LAYERS["feather"] = _path(_grow(masks["feather"], 3) & solid & ~masks["comb"], scale)
    _LAYERS["yolk"] = _path(_grow(masks["yolk"], 2) & solid & ~masks["comb"], scale)
    _LAYERS["ink"] = _path(masks["ink"], scale)
    # A thin ink rim round the outside of the white head, under everything,
    # so the head still has an edge on a light background. On ink it vanishes.
    rim = _grow(masks["feather"], 9) & ~solid
    _LAYERS["rim"] = _path(rim | (_grow(rim, 2) & solid), scale)
    # One colour: the silhouette, without the ink parts, and with a gap where
    # the comb meets the head and the beak, so they still read apart.
    rest = masks["feather"] | masks["yolk"]
    seam = _grow(masks["comb"], 5) & _grow(rest, 5)
    seam |= _grow(masks["yolk"], 4) & _grow(masks["feather"], 4)
    _LAYERS["mono"] = _path(solid & ~_grow(masks["ink"], 1) & ~seam, scale)
    ys, xs = np.nonzero(solid | rim)
    pad = 10
    _LAYERS["box"] = (xs.min() * scale - pad, ys.min() * scale - pad,
                      (xs.max() - xs.min()) * scale + 2 * pad,
                      (ys.max() - ys.min()) * scale + 2 * pad)
    return _LAYERS


def mark_box():
    return layers()["box"]


def _uid(prefix, _ids=[0]):
    _ids[0] += 1
    return "%s%d" % (prefix, _ids[0])


def mark_elements(comb=COMB):
    """The full-colour mark."""
    lay = layers()
    return "".join('<path d="%s" fill="%s"/>' % (lay[name], fill) for name, fill in (
        ("rim", INK), ("comb", comb), ("feather", FEATHER), ("yolk", YOLK),
        ("ink", INK)))


def mono_elements(color="currentColor", uid=None):
    """One colour: the silhouette with the headphones, eye and door cut out."""
    return '<path d="%s" fill="%s" fill-rule="evenodd"/>' % (layers()["mono"], color)


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


def app_icon_svg(shape="rounded", inset=110, background=INK):
    """The mark on a tile. shape: rounded | square | circle | none."""
    area = (inset, inset, 1024 - 2 * inset, 1024 - 2 * inset)
    comb = COMB_ON_RED if background == COMB else COMB
    return svg((0, 0, 1024, 1024), tile(shape, background)
               + '<g %s>%s</g>' % (fit(mark_box(), area), mark_elements(comb=comb)))


def mono_icon_svg(color, inset=110, uid="m", shape="none", background=""):
    """The one-colour mark, on a tile of background if shape is given."""
    area = (inset, inset, 1024 - 2 * inset, 1024 - 2 * inset)
    return svg((0, 0, 1024, 1024), tile(shape, background)
               + '<g %s>%s</g>' % (fit(mark_box(), area), mono_elements(color, uid)))


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
NAME = "Rooster"
TAGLINE = "Talk. Play. Hang out."


def wordmark_svg(color):
    d, width = text_path(NAME)
    pad = 40
    return svg((-pad, -CAP - pad, width + 2 * pad, CAP + 200 + 2 * pad),
               '<path d="%s" fill="%s"/>' % (d, color))


def lockup_svg(ink, tagline_ink=None):
    """Mark left, name right, optional tagline under the name."""
    box = mark_box()
    mark = mark_elements()
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
    ms = mark_h / mark_box()[3]
    mw = mark_box()[2] * ms
    d, width = text_path(NAME)
    word_s = (mark_h * 0.30) / CAP
    ww = width * word_s
    w = max(mw, ww)
    body = ('<g transform="translate(%.2f 0) scale(%.5f) translate(%g %g)">%s</g>'
            % ((w - mw) / 2, ms, -mark_box()[0], -mark_box()[1], mark_elements()))
    baseline = mark_h + 36 + CAP * word_s
    body += ('<path transform="translate(%.2f %.2f) scale(%.5f)" d="%s" fill="%s"/>'
             % ((w - ww) / 2, baseline, word_s, d, ink))
    pad = 24
    return svg((-pad, -pad, w + 2 * pad, baseline + 60 * word_s + 2 * pad), body)


def merch_tee_svg(mono=None):
    """The mark, big, for the front of a shirt. mono: one ink colour, for
    single-ink screen printing."""
    return svg(mark_box(), mono_elements(mono, _uid("tee")) if mono
               else mark_elements())


PALETTE = [
    ("Ink", INK, CREAM), ("Comb", COMB, FEATHER), ("Yolk", YOLK, INK),
    ("Cream", CREAM, INK), ("Stone", STONE, FEATHER), ("Spruce", SPRUCE, CREAM),
]


def palette_svg():
    """Swatches with name and hex, in the brand's own type."""
    w, h, gap = 150, 170, 12
    body = ""
    for i, (name, fill, ink) in enumerate(PALETTE):
        x = i * (w + gap)
        y = 0
        body += ('<rect x="%d" y="%d" width="%d" height="%d" rx="18" fill="%s"%s/>'
                 % (x, y, w, h, fill,
                    ' stroke="%s" stroke-width="2"' % STONE if fill == CREAM else ""))
        body += ('<text x="%d" y="%d" font-family="Sora, sans-serif" '
                 'font-weight="700" font-size="20" fill="%s">%s</text>'
                 % (x + 16, y + h - 44, ink, name))
        body += ('<text x="%d" y="%d" font-family="JetBrains Mono, monospace" '
                 'font-size="15" fill="%s" opacity=".8">%s</text>'
                 % (x + 16, y + h - 20, ink, fill))
    return svg((-20, -20, 6 * w + 5 * gap + 40, h + 40),
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
    # Forms of the old house mark that the rooster's head replaced.
    for stale in ("mark-small-on-dark.svg", "mark-small-on-light.svg",
                  "app-icon-small.svg", "mark-on-dark.svg", "mark-on-light.svg",
                  "rooster.svg", "app-icon-dark.svg"):
        if os.path.exists(os.path.join(logo, stale)):
            os.remove(os.path.join(logo, stale))
    files = {
        "mark.svg": svg(mark_box(), mark_elements()),
        "mark-mono.svg": svg(mark_box(), mono_elements()),
        "app-icon.svg": app_icon_svg(),
        "app-icon-light.svg": app_icon_svg(background=CREAM),
        "app-icon-comb.svg": app_icon_svg(background=COMB),
        "wordmark-on-dark.svg": wordmark_svg(CREAM),
        "wordmark-on-light.svg": wordmark_svg(INK),
        "lockup-on-light.svg": lockup_svg(INK),
        "lockup-on-dark.svg": lockup_svg(CREAM),
        "lockup-tagline-on-light.svg": lockup_svg(INK, tagline_ink=STONE),
        "lockup-stacked-on-light.svg": stacked_svg(INK),
    }
    for name, text in files.items():
        write(os.path.join(logo, name), text)
    merch = os.path.join(BRAND, "merch")
    write(os.path.join(merch, "tee-on-dark.svg"), merch_tee_svg())
    write(os.path.join(merch, "tee-on-light.svg"), merch_tee_svg())
    write(os.path.join(merch, "tee-one-colour.svg"), merch_tee_svg(CREAM))
    render(files["app-icon.svg"], os.path.join(logo, "app-icon-1024.png"), 1024)
    write(os.path.join(BRAND, "palette.svg"), palette_svg())

    # PNG previews for the guide.
    preview = os.path.join(BRAND, "preview")
    for old in ("mark-on-dark.png", "mark-on-light.png", "motifs.png",
                "roof-rooster.png"):
        if os.path.exists(os.path.join(preview, old)):
            os.remove(os.path.join(preview, old))
    shots = [
        ("logo/lockup-tagline-on-light.svg", "lockup-tagline.png", (900, 260), "#FBF6EF"),
        ("logo/lockup-on-light.svg", "lockup-on-light.png", (900, 260), "#FBF6EF"),
        ("logo/lockup-on-dark.svg", "lockup-on-dark.png", (900, 260), INK),
        ("logo/lockup-stacked-on-light.svg", "lockup-stacked.png", (400, 400), "#FBF6EF"),
        ("logo/mark-mono.svg", "mark-mono.png", (334, 400), "#FBF6EF"),
        ("merch/tee-on-dark.svg", "tee-on-dark.png", (334, 400), INK),
        ("palette.svg", "palette.png", (1012, 210), None),
    ]
    for src, out, size, bg in shots:
        with open(os.path.join(BRAND, src)) as f:
            render(f.read(), os.path.join(preview, out), size, background=bg)

    # The icon family, as in the concept board.
    fam = []
    for i, text in enumerate([
            app_icon_svg(), app_icon_svg(background=CREAM),
            app_icon_svg(background=COMB),
            mono_icon_svg(CREAM, uid="f", shape="rounded", background=INK),
            mono_icon_svg(CREAM, uid="g", shape="circle", background=INK),
            mono_icon_svg("#FFFFFF", uid="h", shape="circle", background=COMB)]):
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
    render(app_icon_svg(inset=80), small, 256)

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
        "dark": app_icon_svg("none"),
        "light": app_icon_svg("none"),
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

    # Tray (idle state; live and muted are the mic glyphs). Named for the
    # app: KDE looks a tray icon's file name up in the icon theme first, and
    # themes have an "idle" (Python's IDLE). See lib/utils/voice_tray.dart.
    tray = os.path.join(APP, "assets", "images", "tray")
    circ = os.path.join(tmp, "tray-circle.png")
    render(app_icon_svg("circle", inset=150), circ, 256)
    downscale(circ, os.path.join(tray, "rooster_tray_idle.png"), 64)
    tray_pngs = []
    for s in sizes:
        p = os.path.join(tmp, "tray-%d.png" % s)
        downscale(circ, p, s)
        tray_pngs.append(p)
    ico(tray_pngs, os.path.join(tray, "rooster_tray_idle.ico"))

    # Linux.
    hicolor = os.path.join(APP, "linux", "debian", "usr", "share", "icons", "hicolor")
    for s in (16, 32, 64, 128, 256, 512):
        icon_at(s, os.path.join(hicolor, "%dx%d" % (s, s), "apps", "rooster.png"))
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
                  '</resources>\n' % INK)


def main():
    with tempfile.TemporaryDirectory() as tmp:
        build_brand(tmp)
        if "--install" in sys.argv:
            build_app(tmp)


if __name__ == "__main__":
    main()
