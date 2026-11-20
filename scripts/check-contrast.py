#!/usr/bin/env python3
"""Fail when an app color misses WCAG AA contrast (4.5:1 for text).

The XCUITest audit's contrast check is unreliable on iOS 26 (it samples
through glass bars and flags Apple's own secondary label colors), so the
app's own colors are checked here, exactly, against every background they
are drawn on. System semantic colors are Apple's responsibility (and darken
with Increase Contrast).

    check-contrast.py            # from the repo root
"""
import json
import sys
from pathlib import Path

MIN = 4.5


def lum(hex6: str) -> float:
    def channel(c: float) -> float:
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex6[i:i + 2], 16) / 255 for i in (0, 2, 4))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def ratio(a: str, b: str) -> float:
    hi, lo = sorted((lum(a), lum(b)), reverse=True)
    return (hi + 0.05) / (lo + 0.05)


def over(fg: str, alpha: float, bg: str) -> str:
    return "".join(f"{round(int(fg[i:i+2], 16) * alpha + int(bg[i:i+2], 16) * (1 - alpha)):02X}" for i in (0, 2, 4))


def colorset(path: str) -> dict:
    """{"light": "RRGGBB", "dark": ..., "high": ..., "dark+high": ...}"""
    out = {}
    for c in json.loads(Path(path, "Contents.json").read_text())["colors"]:
        key = "+".join(sorted(a["value"] for a in c.get("appearances", []))) or "light"
        comp = c["color"]["components"]
        out[key] = "".join(comp[k].replace("0x", "").zfill(2).upper() for k in ("red", "green", "blue"))
    return out


# Backgrounds the brand color is drawn on (iOS system values).
LIGHT = {
    "white cell": "FFFFFF",
    "grouped background": "F2F2F7",
    "bordered button fill": over("787880", 0.16, "FFFFFF"),
}
DARK = {
    "dark cell": "1C1C1E",
    "black": "000000",
    "bordered button fill": over("787880", 0.32, "1C1C1E"),
}

failed = 0
for target in ("MyApp", "PickhourWidget"):
    accent = colorset(f"{target}/Assets.xcassets/AccentColor.colorset")
    checks = [(f"{target} brand (light)", accent["light"], LIGHT),
              (f"{target} brand (dark)", accent["dark"], DARK)]
    if target == "MyApp":
        soft = colorset("MyApp/Assets.xcassets/MeadowSoft.colorset")
        checks.append(("brand on MeadowSoft (light)", accent["light"], {"MeadowSoft": soft["light"]}))
        checks.append(("brand on MeadowSoft (dark)", accent["dark"], {"MeadowSoft": soft["dark"]}))
    for name, fg, backgrounds in checks:
        for bg_name, bg in backgrounds.items():
            r = ratio(fg, bg)
            ok = r >= MIN
            failed += not ok
            print(f"{'ok  ' if ok else 'FAIL'} {r:5.2f}:1  {name} #{fg} on {bg_name} #{bg}")

if failed:
    print(f"\n{failed} color pair(s) under {MIN}:1")
    sys.exit(1)
print(f"\nall app colors ≥ {MIN}:1")
