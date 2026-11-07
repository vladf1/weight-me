# WeightMe

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
- **Entries table** — grouped list on iPhone, sortable multi-column table on iPad. Entries WeightMe wrote can be edited or deleted; entries from other apps are read-only (a HealthKit rule).
- **CSV export** — WeightMe's own format with exact timestamps, units and sources.
- **CSV import** (Lose It! export or WeightMe export) built to be hard to get wrong:
  - never overwrites — any day already in Apple Health is skipped
  - rows marked deleted in Lose It are skipped; duplicate days in the file keep the most recently updated row
  - review screen with counts, warnings (e.g. "these look like pounds"), a preview chart and every row
  - confirm in an alert, then type the number of entries to confirm
  - every import can be undone later as a unit (Settings › Import History)
- **Widgets** — Home Screen (small/medium) and Lock Screen (rectangular/circular/inline); tap to log.
- **Siri & Shortcuts** — "Log my weight in WeightMe", "What's my weight in WeightMe", and an "Open Log Weight" action for the Action button.

## Requirements

- Xcode 27.2+, iOS 27+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) if you change `project.yml`

## Building

```sh
xcodegen generate        # only needed after editing project.yml
open WeightMe.xcodeproj
```

Set your own team in `project.yml` (`DEVELOPMENT_TEAM`) and change the bundle ID prefix / app group if you fork this.

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
# undo, log/delete) plus chart gestures. Use a dedicated simulator — they write Health data.
xcodebuild -project WeightMe.xcodeproj -scheme WeightMeUITests -destination 'platform=iOS Simulator,name=iPhone 18 Pro' test
```

The import UI test expects a Lose It-style `LoseIt-weights.csv` in the app's Documents folder on the simulator and is
skipped otherwise.

### Notes

- **iOS 27 Health history scope**: when granting access, iOS 27 asks whether to share the past 30 days or all recorded
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
| `Shared` | Code compiled into both the app and the widget |
| `Scripts/make-icon.swift` | Renders the app icon |
