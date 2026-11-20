#!/usr/bin/env python3
"""Drops EXIF and XMP chunks (eXIf, iTXt) from PNGs in place.

Simulator screenshots of a landscape iPad carry Orientation = 8. Once the
pixels have been rotated upright (sips -r), App Store Connect still honours
that tag and turns the image a second time.
"""
import struct
import sys

DROP = {b"eXIf", b"iTXt"}

for path in sys.argv[1:]:
    with open(path, "rb") as f:
        data = f.read()
    out, i = bytearray(data[:8]), 8
    while i < len(data):
        (length,) = struct.unpack(">I", data[i:i + 4])
        kind = data[i + 4:i + 8]
        if kind not in DROP:
            out += data[i:i + 12 + length]
        i += 12 + length
    with open(path, "wb") as f:
        f.write(out)
