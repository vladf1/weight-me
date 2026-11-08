#!/bin/zsh
# Captures App Store screenshots from simulators using the built-in demo data.
#
#   Scripts/app-store-screenshots.sh [output-dir]     (default: AppStore/screenshots)
#
# Builds the Debug app (the screen-jump launch flags are debug-only), then for each device boots it,
# pins the status bar to 9:41 / full battery, launches each screen and saves a PNG.
# Sizes (what App Store Connect asks for): iPhone 6.3" (1206×2622), iPad 13" (2064×2752), Apple Watch 46mm.
set -euo pipefail
cd "${0:A:h}/.."

OUT=${1:-AppStore/screenshots}
IPHONE=${IPHONE:-"iPhone 18 Pro"}
IPAD=${IPAD:-"iPad Pro 13-inch (M5)"}
WATCH=${WATCH:-"Apple Watch Series 12 (46mm)"}
BUNDLE=me.fridman.weightme
WATCH_BUNDLE=me.fridman.weightme.watchkitapp
DD=build/ScreenshotsDD

udid() { xcrun simctl list devices available | grep -F "    $1 (" | head -1 | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/'; }
boot() { xcrun simctl boot "$1" 2>/dev/null || true; xcrun simctl bootstatus "$1" -b >/dev/null; }
pin_status_bar() {
  xcrun simctl status_bar "$1" override --time 9:41 --dataNetwork wifi --wifiMode active --wifiBars 3 \
    --cellularMode active --cellularBars 4 --batteryState charged --batteryLevel 100 2>/dev/null || true
}
shot() {  # device file appearance args...
  local dev=$1 file=$2 look=$3 bundle=$4; shift 4
  [[ $look == - ]] || xcrun simctl ui "$dev" appearance "$look"
  xcrun simctl terminate "$dev" "$bundle" 2>/dev/null || true
  xcrun simctl launch "$dev" "$bundle" "$@" >/dev/null
  sleep ${SHOT_WAIT:-4}
  xcrun simctl io "$dev" screenshot --type=png "$OUT/$file.png" >/dev/null 2>&1
  echo "  $file.png  $(sips -g pixelWidth -g pixelHeight "$OUT/$file.png" | awk '/pixel/{printf "%s ", $2}')"
}

if [[ -z ${WATCH_ONLY:-} ]]; then
echo "Building…"
xcodebuild -project WeightMe.xcodeproj -scheme WeightMe -configuration Debug \
  -destination "generic/platform=iOS Simulator" -derivedDataPath $DD build >/dev/null
APP=$DD/Build/Products/Debug-iphonesimulator/WeightMe.app
WATCH_APP=$DD/Build/Products/Debug-watchsimulator/WeightMeWatch.app
mkdir -p "$OUT"

DEMO=(-demo -goalKg 80)
for name in $IPHONE $IPAD; do
  dev=$(udid "$name"); [[ -n $dev ]] || { echo "No simulator named $name" >&2; exit 1; }
  prefix=$([[ $name == iPad* ]] && echo ipad || echo iphone)
  echo "$name ($dev)"
  boot $dev; pin_status_bar $dev
  xcrun simctl install $dev $APP
  shot $dev "$prefix-1-summary" light $BUNDLE $DEMO -chartRange 3M
  shot $dev "$prefix-2-trend-year" light $BUNDLE $DEMO -chartRange Y
  shot $dev "$prefix-3-history" light $BUNDLE $DEMO -tab history
  shot $dev "$prefix-4-summary-dark" dark $BUNDLE $DEMO -chartRange 6M
  shot $dev "$prefix-5-widgets" light $BUNDLE $DEMO -widgetGallery
  xcrun simctl ui $dev appearance light
  xcrun simctl status_bar $dev clear
done
fi
WATCH_APP=$DD/Build/Products/Debug-watchsimulator/WeightMeWatch.app
mkdir -p "$OUT"

dev=$(udid "$WATCH"); [[ -n $dev ]] || { echo "No simulator named $WATCH" >&2; exit 1; }
echo "$WATCH ($dev)"
boot $dev
xcrun simctl install $dev $WATCH_APP
SHOT_WAIT=15
shot $dev "watch-1-latest" - $WATCH_BUNDLE -demo
shot $dev "watch-2-log" - $WATCH_BUNDLE -demo -openLog

echo "Saved to $OUT"
