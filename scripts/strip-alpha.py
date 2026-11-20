#!/usr/bin/env python3
"""Rewrite RGBA PNGs as RGB, in place (App Store Connect refuses screenshots
with an alpha channel). Standard library only: the runners have no Pillow.

    strip-alpha.py <png> [<png> ...]

Pixels that aren't fully opaque (window corners, shadows) are composited
onto the canvas gray the Mac shots are padded with (#ECECEC); opaque ones
are kept as they are. PNGs already without alpha are left alone.
8-bit, non-interlaced RGBA only; anything else is reported and skipped.
"""
import struct
import sys
import zlib


def chunks(data):
    i = 8
    while i < len(data):
        (n,) = struct.unpack(">I", data[i:i + 4])
        yield data[i + 4:i + 8], data[i + 8:i + 8 + n]
        i += 12 + n


def chunk(kind, body):
    return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body))


def paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def unfilter(raw, width, height, bpp):
    stride = width * bpp
    out = bytearray(stride * height)
    prev = bytearray(stride)
    pos = 0
    for y in range(height):
        kind = raw[pos]
        line = bytearray(raw[pos + 1:pos + 1 + stride])
        pos += 1 + stride
        if kind == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 0xFF
        elif kind == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 0xFF
        elif kind == 3:
            for x in range(stride):
                left = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 0xFF
        elif kind == 4:
            for x in range(stride):
                left = line[x - bpp] if x >= bpp else 0
                up_left = prev[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + paeth(left, prev[x], up_left)) & 0xFF
        elif kind != 0:
            raise ValueError(f"unknown filter {kind}")
        out[y * stride:(y + 1) * stride] = line
        prev = line
    return out


def strip(path):
    data = open(path, "rb").read()
    parts = list(chunks(data))
    width, height, depth, color, _, _, interlace = struct.unpack(">IIBBBBB", parts[0][1])
    if color != 6:
        return "no alpha"
    if depth != 8 or interlace:
        return f"skipped (depth {depth}, interlace {interlace})"
    pixels = unfilter(zlib.decompress(b"".join(b for k, b in parts if k == b"IDAT")), width, height, 4)
    alpha = pixels[3::4]
    rgb = bytearray(len(pixels) // 4 * 3)
    rgb[0::3], rgb[1::3], rgb[2::3] = pixels[0::4], pixels[1::4], pixels[2::4]
    blended = 0
    for i, a in enumerate(alpha):
        if a < 255:
            for c in range(3):
                rgb[i * 3 + c] = (pixels[i * 4 + c] * a + BACKGROUND * (255 - a) + 127) // 255
            blended += 1
    stride = width * 3
    raw = b"".join(b"\x00" + bytes(rgb[y * stride:(y + 1) * stride]) for y in range(height))
    header = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    keep = [chunk(k, b) for k, b in parts[1:] if k not in (b"IDAT", b"IEND") and k[:1].islower()]
    with open(path, "wb") as f:
        f.write(data[:8] + chunk(b"IHDR", header) + b"".join(keep)
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))
    return f"alpha removed ({blended} pixels composited)" if blended else "alpha removed"


BACKGROUND = 0xEC  # #ECECEC, the padding gray in ci.yml

failed = 0
for name in sys.argv[1:]:
    result = strip(name)
    failed += result.startswith("skipped")
    print(f"{name}: {result}")
sys.exit(1 if failed else 0)
