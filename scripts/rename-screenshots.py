#!/usr/bin/env python3
"""Give exported xcresult attachments their test-given names.

`xcrun xcresulttool export attachments` writes files named by UUID plus a
manifest.json; this renames each one to its attachment name (e.g.
01-explore-light.png) so the CI artifact is readable.

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
    for att in test.get("attachments", []):
        src = out / att["exportedFileName"]
        if not src.exists():
            continue
        # suggestedHumanReadableName looks like "01-explore-light_0_<UUID>.png".
        name = att.get("suggestedHumanReadableName") or src.name
        stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", pathlib.Path(name).stem)
        dst = out / f"{stem}{src.suffix}"
        src.rename(dst)
        count += 1
        print(dst.name)
print(f"{count} screenshots")
