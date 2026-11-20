#!/usr/bin/env python3
"""Fail when a shipped language has strings without a translation.

Reads the .xcloc bundles written by
  xcodebuild -exportLocalizations -localizationPath <dir> -exportLanguage nl ...
Xcode extracts every localizable string from the code itself, so a string
added or reworded in Swift shows up here as untranslated until the catalog
(Shared/Localizable.xcstrings, MyApp/InfoPlist.xcstrings) has it.
"""
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

NS = {"x": "urn:oasis:names:tc:xliff:document:1.2"}


def main(root: Path) -> int:
    bundles = sorted(root.glob("*.xcloc"))
    if not bundles:
        print(f"no .xcloc bundles in {root}")
        return 1
    missing = 0
    for xcloc in bundles:
        for xliff in (xcloc / "Localized Contents").glob("*.xliff"):
            lang = xliff.stem
            for unit in ET.parse(xliff).getroot().iterfind(".//x:trans-unit", NS):
                if unit.get("translate") == "no":
                    continue
                target = unit.find("x:target", NS)
                state = target.get("state") if target is not None else None
                if target is None or not (target.text or "").strip() or state in ("new", "needs-translation"):
                    source = unit.findtext("x:source", default="", namespaces=NS)
                    print(f"[{lang}] untranslated: {source!r}  (id {unit.get('id')!r})")
                    missing += 1
    if missing:
        print(f"\n{missing} untranslated string(s). Add them to Shared/Localizable.xcstrings.")
        return 1
    print(f"all strings translated in {', '.join(b.stem for b in bundles)}")
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1] if len(sys.argv) > 1 else "build/loc")))
