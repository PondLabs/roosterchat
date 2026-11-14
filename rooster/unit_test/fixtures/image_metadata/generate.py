#!/usr/bin/env python3
"""Writes the image metadata fixtures next to this script.

Every picture is drawn here (gradients and shapes, no photograph), and every
piece of metadata is made up, so the files are ours and are released under
CC0 1.0 like this script. See README.md for what each file holds.

Needs Pillow with WebP support. Run from anywhere:
    python3 unit_test/fixtures/image_metadata/generate.py
"""

import io
import os
import struct
import zlib

from PIL import Image, ImageDraw, PngImagePlugin

HERE = os.path.dirname(os.path.abspath(__file__))
W, H = 64, 48


def picture(mode="RGB", width=W, height=H, alpha=False):
    """A picture that looks different from each side, so a lost rotation
    or a flip changes its pixels."""
    im = Image.new("RGBA", (width, height))
    px = im.load()
    for y in range(height):
        for x in range(width):
            a = 255
            if alpha:
                a = int(255 * x / (width - 1))
            px[x, y] = (x * 255 // (width - 1), y * 255 // (height - 1), 96, a)
    d = ImageDraw.Draw(im)
    d.rectangle([4, 4, 20, 12], fill=(250, 250, 20, 255))
    d.ellipse([40, 26, 58, 44], fill=(20, 30, 230, 255))
    if not alpha:
        im = im.convert("RGB")
    return im.convert(mode) if mode not in ("RGB", "RGBA") else im


# --- Exif ---------------------------------------------------------------


def rational(num, den=1):
    return struct.pack(">II", num, den)


def tiff(orientation=None, gps=True, thumbnail=None):
    """A big-endian TIFF block with camera tags, GPS and optionally a
    thumbnail in IFD1, the way a phone writes one."""
    entries0 = []  # (tag, type, count, payload bytes)
    entries0.append((0x010F, 2, None, b"Rooster Test Camera\0"))  # Make
    entries0.append((0x0110, 2, None, b"Model T-1\0"))  # Model
    if orientation is not None:
        entries0.append((0x0112, 3, 1, struct.pack(">H", orientation) + b"\0\0"))
    entries0.append((0x0132, 2, None, b"2026:11:14 10:00:00\0"))  # DateTime
    entries0.append((0x013B, 2, None, b"Jane Example\0"))  # Artist
    gps_entries = [
        (0x0000, 1, 4, b"\x02\x03\x00\x00"),  # GPSVersionID
        (0x0001, 2, 2, b"S\0\0\0"),  # GPSLatitudeRef
        (0x0002, 5, 3, rational(23) + rational(33) + rational(1234, 100)),
        (0x0003, 2, 2, b"W\0\0\0"),  # GPSLongitudeRef
        (0x0004, 5, 3, rational(46) + rational(38) + rational(5678, 100)),
    ]

    out = bytearray(b"MM\0*" + struct.pack(">I", 8))

    def ifd_size(entries):
        return 2 + 12 * len(entries) + 4

    def data_size(entries):
        n = 0
        for _, _, _, payload in entries:
            if len(payload) > 4:
                n += len(payload) + (len(payload) & 1)
        return n

    # Layout: IFD0, its data, GPS IFD, its data, IFD1, thumbnail.
    if gps:
        entries0.append((0x8825, 4, 1, b"\0\0\0\0"))  # GPS IFD pointer
    ifd0_at = 8
    ifd0_data_at = ifd0_at + ifd_size(entries0)
    gps_at = ifd0_data_at + data_size(entries0)
    gps_data_at = gps_at + ifd_size(gps_entries)
    ifd1_at = gps_data_at + data_size(gps_entries) if gps else gps_at
    if gps:
        entries0[-1] = (0x8825, 4, 1, struct.pack(">I", gps_at))

    def write_ifd(entries, at, data_at, next_ifd):
        blob = bytearray(struct.pack(">H", len(entries)))
        data = bytearray()
        for tag, typ, count, payload in entries:
            if count is None:
                count = len(payload)
            if len(payload) > 4:
                blob += struct.pack(">HHII", tag, typ, count, data_at + len(data))
                data += payload
                if len(payload) & 1:
                    data += b"\0"
            else:
                blob += struct.pack(">HHI", tag, typ, count) + payload.ljust(4, b"\0")
        blob += struct.pack(">I", next_ifd)
        return bytes(blob + data)

    thumb_entries = []
    if thumbnail is not None:
        thumb_entries = [
            (0x0103, 3, 1, b"\0\x06\0\0"),  # Compression: JPEG
            (0x0201, 4, 1, b"\0\0\0\0"),  # JPEGInterchangeFormat
            (0x0202, 4, 1, struct.pack(">I", len(thumbnail))),
        ]
        thumb_at = ifd1_at + ifd_size(thumb_entries)
        thumb_entries[1] = (0x0201, 4, 1, struct.pack(">I", thumb_at))

    out += write_ifd(entries0, ifd0_at, ifd0_data_at, ifd1_at if thumbnail else 0)
    if gps:
        out += write_ifd(gps_entries, gps_at, gps_data_at, 0)
    if thumbnail is not None:
        out += write_ifd(thumb_entries, ifd1_at, ifd1_at + ifd_size(thumb_entries), 0)
        out += thumbnail
    return bytes(out)


# --- JPEG segments ------------------------------------------------------


def segment(marker, payload):
    return bytes([0xFF, marker]) + struct.pack(">H", len(payload) + 2) + payload


def jpeg(im, **kw):
    buf = io.BytesIO()
    im.save(buf, "JPEG", quality=90, **kw)
    return buf.getvalue()


def split_after_soi(data):
    """Drops whatever Pillow wrote between SOI and the first table, so the
    fixture holds only the segments written here."""
    assert data[:2] == b"\xff\xd8"
    pos = 2
    while data[pos + 1] in (0xE0, 0xE1, 0xE2, 0xED, 0xEE, 0xFE):
        length = struct.unpack(">H", data[pos + 2 : pos + 4])[0]
        if data[pos + 1] in (0xE2, 0xEE):  # keep ICC and Adobe as written
            break
        pos += 2 + length
    return data[pos:]


def jfif(thumbnail_size=None):
    head = b"JFIF\0\x01\x02\x01\x00\x48\x00\x48"
    if thumbnail_size is None:
        return segment(0xE0, head + b"\0\0")
    tw, th = thumbnail_size
    thumb = bytearray()
    for y in range(th):
        for x in range(tw):
            thumb += bytes([255 - x * 40, y * 60, 200])
    return segment(0xE0, head + bytes([tw, th]) + bytes(thumb))


def exif_app1(**kw):
    return segment(0xE1, b"Exif\0\0" + tiff(**kw))


XMP_GPS = b"""<?xpacket begin='\xef\xbb\xbf' id='W5M0MpCehiHzreSzNTczkc9d'?>
<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'>
<rdf:Description rdf:about='' xmlns:exif='http://ns.adobe.com/exif/1.0/' xmlns:dc='http://purl.org/dc/elements/1.1/'
 exif:GPSLatitude='23,33.21S' exif:GPSLongitude='46,38.95W'>
<dc:creator><rdf:Seq><rdf:li>Jane Example</rdf:li></rdf:Seq></dc:creator>
</rdf:Description></rdf:RDF></x:xmpmeta>
<?xpacket end='w'?>"""

XMP_MOTION = b"""<x:xmpmeta xmlns:x='adobe:ns:meta/'><rdf:RDF xmlns:rdf='http://www.w3.org/1999/02/22-rdf-syntax-ns#'>
<rdf:Description rdf:about='' xmlns:GCamera='http://ns.google.com/photos/1.0/camera/'
 GCamera:MotionPhoto='1' GCamera:MotionPhotoVersion='1' GCamera:MicroVideoOffset='%d'/>
</rdf:RDF></x:xmpmeta>"""


def xmp_app1(xmp):
    return segment(0xE1, b"http://ns.adobe.com/xap/1.0/\0" + xmp)


def iptc_app13():
    def dataset(record, tag, value):
        return bytes([0x1C, record, tag]) + struct.pack(">H", len(value)) + value

    iptc = (
        dataset(2, 0, b"\0\x04")
        + dataset(2, 80, b"Jane Example")  # By-line
        + dataset(2, 90, b"Sao Paulo")  # City
        + dataset(2, 101, b"Brazil")  # Country
    )
    resource = b"8BIM" + struct.pack(">H", 0x0404) + b"\0\0" + struct.pack(">I", len(iptc)) + iptc
    if len(iptc) & 1:
        resource += b"\0"
    return segment(0xED, b"Photoshop 3.0\0" + resource)


def mpf_app2(first_size, second_size, second_offset):
    """An MP Index IFD naming two pictures, the second after the first EOI.
    Offsets in MPF count from the start of the TIFF header."""
    entries = [
        (0xB000, 7, 4, b"0100"),  # MPFVersion
        (0xB001, 4, 1, struct.pack(">I", 2)),  # NumberOfImages
        (0xB002, 7, 32, None),  # MPEntry
    ]
    head = b"MM\0*" + struct.pack(">I", 8)
    ifd_len = 2 + 12 * len(entries) + 4
    entry_at = 8 + ifd_len
    blob = bytearray(struct.pack(">H", len(entries)))
    for tag, typ, count, payload in entries:
        if payload is None:
            blob += struct.pack(">HHII", tag, typ, count, entry_at)
        else:
            blob += struct.pack(">HHI", tag, typ, count) + payload.ljust(4, b"\0")
    blob += struct.pack(">I", 0)
    mp_entries = struct.pack(">IIIHH", 0x20030000, first_size, 0, 0, 0)
    mp_entries += struct.pack(">IIIHH", 0x00020002, second_size, second_offset, 0, 0)
    return b"MPF\0" + head + bytes(blob) + mp_entries


def write(name, data):
    with open(os.path.join(HERE, name), "wb") as f:
        f.write(data)


# --- ICC ----------------------------------------------------------------


def icc_linear_profile():
    """A small RGB display profile with linear tone curves and sRGB-like
    primaries. Rendering with it differs visibly from rendering without it,
    so a lost profile shows up as changed pixels."""

    def s15(v):
        return struct.pack(">i", int(round(v * 65536)))

    def xyz(x, y, z):
        return b"XYZ \0\0\0\0" + s15(x) + s15(y) + s15(z)

    curve = b"curv\0\0\0\0" + struct.pack(">I", 1) + struct.pack(">H", 0x0100) + b"\0\0"
    desc_text = b"Linear test RGB\0"
    desc = (
        b"desc\0\0\0\0"
        + struct.pack(">I", len(desc_text))
        + desc_text
        + b"\0" * 4
        + b"\0" * 4
        + b"\0" * 2
        + b"\0"
        + b"\0" * 67
    )
    cprt = b"text\0\0\0\0" + b"CC0\0"
    tags = [
        (b"desc", desc),
        (b"cprt", cprt),
        (b"wtpt", xyz(0.9642, 1.0, 0.8249)),
        (b"rXYZ", xyz(0.4361, 0.2225, 0.0139)),
        (b"gXYZ", xyz(0.3851, 0.7169, 0.0971)),
        (b"bXYZ", xyz(0.1431, 0.0606, 0.7141)),
        (b"rTRC", curve),
        (b"gTRC", curve),
        (b"bTRC", curve),
    ]
    table_len = 4 + 12 * len(tags)
    offset = 128 + table_len
    table = struct.pack(">I", len(tags))
    data = bytearray()
    for sig, body in tags:
        while (offset + len(data)) % 4:
            data += b"\0"
        table += sig + struct.pack(">II", offset + len(data), len(body))
        data += body
    while (128 + table_len + len(data)) % 4:
        data += b"\0"
    size = 128 + table_len + len(data)
    header = bytearray(128)
    header[0:4] = struct.pack(">I", size)
    header[8:12] = b"\x02\x10\0\0"  # version 2.1
    header[12:16] = b"mntr"
    header[16:20] = b"RGB "
    header[20:24] = b"XYZ "
    header[36:40] = b"acsp"
    header[68:80] = s15(0.9642) + s15(1.0) + s15(0.8249)
    return bytes(header) + table + bytes(data)


# --- Fixtures -----------------------------------------------------------


def main():
    base = picture()

    # GPS in Exif, an Exif thumbnail, a JFIF thumbnail, a comment and a
    # colour profile that changes how the picture renders.
    thumb = jpeg(base.resize((16, 12)))
    body = split_after_soi(jpeg(base, icc_profile=icc_linear_profile()))
    write(
        "gps_exif.jpg",
        b"\xff\xd8"
        + jfif(thumbnail_size=(4, 3))
        + exif_app1(orientation=1, thumbnail=thumb)
        + segment(0xFE, b"Shot at Jane's house")
        + body,
    )

    # GPS only in XMP, no Exif.
    plain = split_after_soi(jpeg(base))
    write("gps_xmp.jpg", b"\xff\xd8" + jfif() + xmp_app1(XMP_GPS) + plain)

    # An IPTC block in Photoshop's APP13, progressive scans.
    progressive = split_after_soi(jpeg(base, progressive=True))
    write("iptc.jpg", b"\xff\xd8" + jfif() + iptc_app13() + progressive)

    # MPF: a second picture after the first EOI, named by APP2 MPF.
    second = jpeg(picture(width=32, height=24).transpose(Image.FLIP_LEFT_RIGHT))
    exif = exif_app1(orientation=1)
    mpf_len = len(segment(0xE2, mpf_app2(0, 0, 0)))
    first_size = 2 + len(exif) + mpf_len + len(plain)
    tiff_at = 2 + len(exif) + 4 + 4  # marker, length, "MPF\0"
    mpf = segment(0xE2, mpf_app2(first_size, len(second), first_size - tiff_at))
    write("mpf.jpg", b"\xff\xd8" + exif + mpf + plain + second)

    # A motion photo: a short "video with sound" after EOI, pointed at from
    # XMP the way phones do.
    trailer = (
        struct.pack(">I", 24) + b"ftypmp42" + b"\0\0\0\0" + b"isommp42"
        + struct.pack(">I", 8 + 512) + b"mdat" + bytes(range(256)) * 2
    )
    write(
        "motion_photo.jpg",
        b"\xff\xd8"
        + exif_app1(orientation=1)
        + xmp_app1(XMP_MOTION % len(trailer))
        + plain
        + trailer,
    )

    # CMYK, which Pillow stores inverted with an Adobe APP14 marker.
    cmyk = split_after_soi(jpeg(base.convert("CMYK")))
    write("cmyk.jpg", b"\xff\xd8" + exif_app1(orientation=1) + cmyk)

    # Orientations 3, 6 and 8, with GPS beside them.
    for o in (3, 6, 8):
        write(
            "orientation_%d.jpg" % o,
            b"\xff\xd8" + jfif() + exif_app1(orientation=o) + plain,
        )

    # PNG with transparency, text chunks, eXIf (orientation 6 and GPS), a
    # timestamp and a private chunk.
    rgba = picture(alpha=True)
    info = PngImagePlugin.PngInfo()
    info.add_text("Author", "Jane Example")
    info.add_text("Comment", "Shot at Jane's house", zip=True)
    info.add_itxt("Location", "Sao Paulo", lang="en")
    buf = io.BytesIO()
    rgba.save(buf, "PNG", pnginfo=info, exif=b"Exif\0\0" + tiff(orientation=6))
    png = buf.getvalue()

    def png_chunk(typ, data):
        return struct.pack(">I", len(data)) + typ + data + struct.pack(">I", zlib.crc32(typ + data))

    iend = png.rindex(b"IEND") - 4
    png = (
        png[:iend]
        + png_chunk(b"tIME", b"\x07\xea\x0b\x0e\x0a\x00\x00")
        + png_chunk(b"prVt", b"private vendor data")
        + png[iend:]
        + b"trailing bytes after IEND"
    )
    write("text_exif.png", png)

    # Animated WebP with EXIF (orientation 6 and GPS) and XMP: once with
    # the EXIF chunk as the WebP spec writes it (raw TIFF, like webpmux),
    # once with the "Exif\0\0" prefix Pillow adds.
    frames = [
        picture(),
        picture().transpose(Image.FLIP_TOP_BOTTOM),
        picture().rotate(180),
    ]
    for name, exif in (
        ("animated_exif.webp", tiff(orientation=6)),
        ("animated_exif_prefixed.webp", b"Exif\0\0" + tiff(orientation=6)),
    ):
        buf = io.BytesIO()
        frames[0].save(
            buf,
            "WEBP",
            save_all=True,
            append_images=frames[1:],
            duration=100,
            loop=0,
            lossless=True,
            exif=exif,
            xmp=XMP_GPS,
        )
        write(name, buf.getvalue())

    # Truncated JPEGs: a progressive one cut after 70% of its bytes, which
    # still decodes (the first scans are whole), and one cut before its
    # frame header, which does not.
    big = picture(width=256, height=192)
    full = b"\xff\xd8" + exif_app1(orientation=1) + split_after_soi(
        jpeg(big, progressive=True)
    )
    write("truncated_decodable.jpg", full[: len(full) * 7 // 10])
    sof = full.index(b"\xff\xc2")
    write("truncated_undecodable.jpg", full[:sof])


if __name__ == "__main__":
    main()
