#!/usr/bin/env python3
"""Print the UDID of an available simulator, from `simctl list devices -j`.

    xcrun simctl list devices available -j | pick-simulator.py <family> [<name part>]

The newest iOS runtime first; the first device whose name starts with
<family> (iPhone, iPad) and contains <name part>. Exits non-zero when none
matches, listing what there is.
"""
import json
import sys

family = sys.argv[1]
part = sys.argv[2] if len(sys.argv) > 2 else ""
devices = json.load(sys.stdin)["devices"]
def version(runtime):  # "com.apple.CoreSimulator.SimRuntime.iOS-26-1" -> (26, 1)
    return tuple(int(p) for p in runtime.rsplit("iOS-", 1)[-1].split("-") if p.isdigit())


runtimes = sorted((r for r in devices if "iOS" in r), key=version, reverse=True)
for runtime in runtimes:
    for d in devices[runtime]:
        if d["name"].startswith(family) and part in d["name"]:
            print(d["udid"])
            sys.exit(0)
names = sorted({d["name"] for r in runtimes for d in devices[r] if d["name"].startswith(family)})
sys.exit(f"no {family} simulator with '{part}' in its name; available: {', '.join(names)}")
