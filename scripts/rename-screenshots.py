#!/usr/bin/env python3
"""Give exported xcresult attachments readable, unique names.

`xcrun xcresulttool export attachments` writes files named by UUID plus a
manifest.json. Named screenshots (MacScreenshotTests: "01-explore-light")
keep their name; anything else is prefixed with its test, e.g.
testSpotDetail-03-failure.png. Text attachments get the same treatment.

    rename-screenshots.py <export-dir>
"""
import json
import pathlib
import re
import sys

out = pathlib.Path(sys.argv[1])
manifest = json.loads((out / "manifest.json").read_text())
count = 0
for test in manifest:
    # "LayoutTests/testSpotDetail()" -> "testSpotDetail"
    test_name = re.sub(r"\(\)$", "", str(test.get("testIdentifier", "test")).split("/")[-1])
    for index, att in enumerate(test.get("attachments", []), start=1):
        src = out / att["exportedFileName"]
        if not src.exists():
            continue
        name = att.get("suggestedHumanReadableName") or src.name
        stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", pathlib.Path(name).stem)
        stem = re.sub(r"[^A-Za-z0-9._-]+", "-", stem).strip("-")
        if not re.match(r"^\d\d-", stem):
            stem = f"{test_name}-{index:02d}-{stem}"
        dst = out / f"{stem}{src.suffix}"
        n = 2
        while dst.exists():
            dst = out / f"{stem}-{n}{src.suffix}"
            n += 1
        src.rename(dst)
        count += 1
print(f"{count} attachments renamed")
