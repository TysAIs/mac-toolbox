#!/usr/bin/env python3
"""doctor-json.py — emit social-doctor results as JSON.
Reads lines of `platform<TAB>level<TAB>ok|false<TAB>fix` from stdin.
Prints [{"platform","check_level","ok","fix"}] as JSON."""
import json
import sys

out = []
for line in sys.stdin.read().splitlines():
    parts = line.split("\t")
    if len(parts) != 4:
        continue
    plat, level, ok, fix = parts
    out.append({
        "platform": plat,
        "check_level": level,
        "ok": ok == "true",
        "fix": fix,
    })
json.dump(out, sys.stdout, indent=2)
print()
