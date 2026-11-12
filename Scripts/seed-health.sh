#!/bin/zsh
# Fills or clears a simulator's Apple Health store with sample weights.
#
#   Scripts/seed-health.sh [seed|wipe|reseed] [simulator name or UDID]
#
#   seed    write ~4 years of sample weights (default)
#   wipe    delete every weight WeightMe has written to that simulator's Health
#   reseed  wipe, then seed
#
# The simulator defaults to the booted iPhone. Simulators only: this never targets a real device.
# Approve Health access in the app once on that simulator first (Connect Apple Health).
set -euo pipefail
cd "$(dirname "$0")/.."

action=${1:-seed}
case $action in seed|wipe|reseed) ;; *) echo "usage: $0 [seed|wipe|reseed] [simulator]" >&2; exit 2 ;; esac

sim=${2:-$(xcrun simctl list devices booted | grep -E 'iPhone|iPad' | head -1 | grep -oE '[0-9A-F-]{36}' || true)}
if [[ -z $sim ]]; then echo "No booted iPhone simulator; pass a simulator name or UDID." >&2; exit 1; fi
if [[ $sim =~ ^[0-9A-F-]{36}$ ]]; then dest="platform=iOS Simulator,id=$sim"; else dest="platform=iOS Simulator,name=$sim"; fi

# xcodebuild hands TEST_RUNNER_-prefixed variables to the tests (without the prefix).
log=$(mktemp -t seed-health)
TEST_RUNNER_SEED_HEALTH=$action xcodebuild test \
  -project WeightMe.xcodeproj -scheme WeightMe -destination "$dest" \
  -only-testing:WeightMeTests/HealthSeeding > "$log" 2>&1 && rc=0 || rc=$?
grep -E "^(Seeded|Deleted|Already seeded|WeightMe now has)|can't write|error:|✘" "$log" || true
if (( rc != 0 )); then echo "Failed; full log: $log" >&2; exit $rc; fi
rm -f "$log"
