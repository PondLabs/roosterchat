# Image metadata fixtures

Pictures for `unit_test/image_metadata/`, which checks that the attach
dialog removes metadata without changing what is drawn.

**Origin and licence.** Every file here is written by `generate.py` in this
folder (Python 3 with Pillow 12, WebP enabled). The pictures are drawn by
the script (a colour gradient, a yellow bar at the top left, a blue disc at
the bottom right) and all the metadata is made up: no photograph, no real
person or place. The files and the script are released under
[CC0 1.0](https://creativecommons.org/publicdomain/zero/1.0/). Running the
script again gives the same bytes.

| File | What it holds |
|---|---|
| `gps_exif.jpg` | JFIF with a 4 by 3 embedded thumbnail; Exif with camera, artist, date, GPS and a JPEG thumbnail in IFD1; a comment; an ICC profile with linear tone curves |
| `gps_xmp.jpg` | GPS and creator only in XMP (`http://ns.adobe.com/xap/1.0/`), no Exif |
| `iptc.jpg` | Photoshop APP13 with an IPTC block (by-line, city, country); progressive scans |
| `mpf.jpg` | Exif, APP2 `MPF` naming a second, flipped picture stored after the first EOI |
| `motion_photo.jpg` | Exif, XMP with Google's `MicroVideoOffset`, and an MP4 header with data after the EOI |
| `cmyk.jpg` | CMYK, stored inverted with APP14 `Adobe`; Exif with GPS |
| `orientation_3.jpg`, `orientation_6.jpg`, `orientation_8.jpg` | Exif orientation 3, 6 and 8 beside GPS |
| `text_exif.png` | RGBA with a transparent left edge; `tEXt`, `zTXt`, `iTXt`, `eXIf` (orientation 6 and GPS), `tIME`, a private `prVt` chunk, bytes after IEND |
| `animated_exif.webp` | Three frames; `EXIF` (orientation 6 and GPS, raw TIFF as the WebP spec writes it) and `XMP ` |
| `animated_exif_prefixed.webp` | The same with `Exif\0\0` before the TIFF, as Pillow writes it |
| `truncated_decodable.jpg` | A progressive 256 by 192 JPEG with Exif, cut after 70% of its bytes: no EOI, still decodes |
| `truncated_undecodable.jpg` | The same file cut before its frame header: does not decode |
