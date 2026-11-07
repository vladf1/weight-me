#!/bin/bash
# Selects the newest Xcode on a GitHub macOS runner. WeightMe needs Xcode 26+ (iOS 26 SDK).
set -euo pipefail
xcode=$(ls -d /Applications/Xcode_*.app 2>/dev/null | sort -V | tail -1 || true)
if [ -n "$xcode" ]; then
  sudo xcode-select -s "$xcode/Contents/Developer"
fi
version=$(xcodebuild -version | head -1)
echo "Using $version ($(xcode-select -p))"
major=$(echo "$version" | sed -E 's/Xcode ([0-9]+).*/\1/')
if [ "$major" -lt 26 ]; then
  echo "::error::WeightMe needs Xcode 26+, this runner has: $(ls -d /Applications/Xcode*.app | xargs -n1 basename | tr '\n' ' ')"
  exit 1
fi
