# WeightMe

[![CI](https://github.com/vladf1/weight-me/actions/workflows/ci.yml/badge.svg)](https://github.com/vladf1/weight-me/actions/workflows/ci.yml)

A deliberately simple weight tracker for iPhone, iPad and iPhone Duo — a replacement for Lose It! that does one thing: track your weight, with **Apple Health as the source of truth** and very good graphs.

## Features

- **Apple Health native** — reads every weight in Health (any app or smart scale) and writes new entries back. Nothing is stored anywhere else.
- **Fast** — a local mirror of your Health data is kept in sync with an anchored HealthKit query, so the app opens instantly and only fetches changes.
- **Graphs**
  - Ranges: week, month, 3 / 6 months, year, 2 years, all time; scroll back through history and pinch to zoom
  - 7-, 30- and 90-day rolling averages (time-based, broken across gaps instead of bridging them)
  - Smoothed trend line (exponential moving average à la *The Hacker's Diet*)
  - Monthly min/max range bars
  - Goal line and projected goal date from your recent trend
  - Press-and-hold to inspect any reading with the averages at that moment
  - "In View" stats that follow the visible range: change, weekly rate, low, high, average, count
- **History table** — grouped list on iPhone, sortable multi-column table on iPad. Entries WeightMe wrote can be edited or deleted; entries from other apps are read-only (a HealthKit rule).
- **CSV export** — WeightMe's own format with exact timestamps, units and sources.
- **CSV import** (Lose It! export or WeightMe export) built to be hard to get wrong:
  - never overwrites — any day already in Apple Health is skipped
  - rows marked deleted in Lose It are skipped; duplicate days in the file keep the most recently updated row
  - review screen with counts, warnings (e.g. "these look like pounds"), a preview chart and every row
  - confirm in an alert, then type the number of entries to confirm
  - every import can be undone later as a unit (Settings › Import History)
- **Widgets** — Home Screen (small/medium) and Lock Screen (rectangular/circular/inline); tap to log.
- **Apple Watch** — shows your latest weight and logs a new one with the Digital Crown, straight into Apple Health
  on the watch (no phone needed; Health syncs it to the iPhone).
- **Siri & Shortcuts** — "Log my weight in WeightMe", "What's my weight in WeightMe", and an "Open Log Weight" action for the Action button.

## Requirements

- iOS / iPadOS 26+
- Xcode 26 or newer (CI builds with the newest Xcode on GitHub's stable `macos-26` runner; local development works in Xcode 27)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) if you change `project.yml`

## Building

```sh
xcodegen generate        # only needed after editing project.yml
open WeightMe.xcodeproj
```

Bundle IDs are `me.fridman.weightme` / `me.fridman.weightme.widgets` with app group `group.me.fridman.weightme`
(team `32R3YRS5WJ`); change them in `project.yml` and `Shared/SharedStorage.swift` if you fork this.

### TestFlight and CI

Every push runs [CI](.github/workflows/ci.yml) (build + unit tests). TestFlight uploads are started by hand
([workflow](.github/workflows/testflight.yml)); one-time setup is in [docs/TESTFLIGHT.md](docs/TESTFLIGHT.md).
Privacy policy: [PRIVACY.md](PRIVACY.md).

### Demo mode

Launch with the `-demo` argument to run on generated multi-year sample data without touching HealthKit
(useful in the simulator, whose Health store starts empty). In Debug builds, Settings › Developer can also seed the
simulator's Health store with the same sample data.

Other Debug-only launch arguments, handy for screenshots: `-tab entries|settings`, `-openAdd`, `-openExport`,
`-openImport <file in Documents>`, `-widgetGallery` (renders every widget size in-app), `-selectDaysAgo N`
(preselects a chart point), `-reseedHealth` (wipes and reseeds WeightMe's data in the simulator's Health store).
Any setting can also be overridden from the command line, e.g. `-chartRange Y -goalKg 80 -chartLayers '(readings,trend,goal)'`.

### Tests

```sh
# Unit tests: CSV parsing, Lose It import planning, analytics
xcodebuild -project WeightMe.xcodeproj -scheme WeightMe -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test

# UI tests: real HealthKit end to end (permission sheet, seeding, import with every confirmation gate,
# undo, log/delete) plus chart gestures and a 15-year performance check. Use a dedicated simulator — they write Health data.
xcodebuild -project WeightMe.xcodeproj -scheme WeightMeUITests -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

```sh
# Watch UI test (skips until Health access is approved once by hand in the watch simulator)
xcodebuild -project WeightMe.xcodeproj -scheme WeightMeWatch -destination 'platform=watchOS Simulator,name=Apple Watch Series 12 (46mm)' test
```

The import UI test expects a Lose It-style `LoseIt-weights.csv` in the app's Documents folder on the simulator and is
skipped otherwise.

### Notes

- **iOS 27 Health history scope**: when granting access, iOS 27 (not 26) asks whether to share the past 30 days or all recorded
  data. WeightMe needs *All Recorded Data*; the onboarding says so and the chart shows a hint if it looks limited.
- Entries from other apps (Lose It, scales…) are read-only: HealthKit only lets the app that wrote a sample delete it.

## Layout

| Path | What |
| --- | --- |
| `WeightMe/Health` | HealthKit wrapper (anchored queries, save/delete, background delivery) |
| `WeightMe/Model` | `WeightStore` (local mirror + cache), settings, demo data |
| `WeightMe/Analytics` | Rolling averages, trend, regression, stats — pure functions |
| `WeightMe/Import`, `WeightMe/Export` | CSV parsing, Lose It detection, import planning, export |
| `WeightMe/Views` | SwiftUI screens |
| `WeightMe/Intents` | App Intents / Siri |
| `WeightMeWidgets` | WidgetKit extension (reads a snapshot the app writes to the app group) |
| `WeightMeWatch` | Apple Watch app (latest weight + Crown logging, HealthKit on the watch) |
| `Shared` | Code compiled into both the app and the widget |
| `Scripts/make-icon.swift` | Renders the app icon |
| `Scripts/set-testflight-secrets.sh` | Stores TestFlight signing secrets in GitHub |
| `.github/` | CI and TestFlight workflows |
