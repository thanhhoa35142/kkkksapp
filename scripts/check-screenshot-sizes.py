#!/usr/bin/env python3
"""Fail when a screenshot is not one of the App Store sizes given.

    check-screenshot-sizes.py <dir> <W>x<H> [<W>x<H> ...]

Reads each PNG's size from its header (no Pillow on the runner) and writes a
table to $GITHUB_STEP_SUMMARY when it is set.
"""
import os
import pathlib
import struct
import sys

folder = pathlib.Path(sys.argv[1])
allowed = {tuple(int(v) for v in s.lower().split("x")) for s in sys.argv[2:]}
rows, bad = [], 0
for png in sorted(folder.glob("*.png")):
    with png.open("rb") as f:
        head = f.read(24)
    w, h = struct.unpack(">II", head[16:24])
    ok = (w, h) in allowed
    bad += not ok
    rows.append(f"| {png.name} | {w}×{h} | {'ok' if ok else 'WRONG SIZE'} |")

want = ", ".join(f"{w}×{h}" for w, h in sorted(allowed))
report = [f"### {folder.name}: {len(rows)} screenshots, App Store size {want}", "",
          "| File | Size | |", "|---|---|---|", *rows, ""]
print("\n".join(report))
if summary := os.environ.get("GITHUB_STEP_SUMMARY"):
    with open(summary, "a") as f:
        f.write("\n".join(report) + "\n")
if not rows:
    sys.exit(f"no screenshots in {folder}")
if bad:
    sys.exit(f"{bad} screenshot(s) not at {want}")
