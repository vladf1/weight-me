#!/bin/bash
# Prints the UDID of an available iPhone simulator on the newest iOS runtime, creating one if needed.
set -euo pipefail
xcrun simctl list -j runtimes available devices devicetypes > /tmp/simctl.json
python3 - <<'PY'
import json, subprocess
data = json.load(open("/tmp/simctl.json"))
runtimes = sorted((r for r in data["runtimes"] if r.get("platform") == "iOS" and r.get("isAvailable")),
                  key=lambda r: [int(p) for p in r["version"].split(".")])
if not runtimes:
    raise SystemExit("No iOS simulator runtime installed")
runtime = runtimes[-1]
devices = [d for d in data["devices"].get(runtime["identifier"], [])
           if d.get("isAvailable") and d["name"].startswith("iPhone")]
if devices:
    print(devices[-1]["udid"])
else:
    types = [t for t in data["devicetypes"] if t["name"].startswith("iPhone")]
    udid = subprocess.check_output(["xcrun", "simctl", "create", "CI iPhone", types[-1]["identifier"],
                                    runtime["identifier"]], text=True).strip()
    print(udid)
PY
