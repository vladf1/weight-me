# WeightMe — App Store listing

Source of truth for what's entered in App Store Connect (app id 6832146393). Screenshots are in
`screenshots/`, regenerated with `Scripts/app-store-screenshots.sh`.

## App information

| Field | Value |
| --- | --- |
| Name | WeightMe |
| Subtitle (≤30) | Weight log & trend for Health |
| Primary category | Health & Fitness |
| Content rights | No third-party content |
| Age rating | 4+ (every questionnaire answer "None"/"No") |
| Price | Free, all countries and regions |
| Privacy policy URL | https://github.com/vladf1/weight-me/blob/main/PRIVACY.md |
| App privacy | Data Not Collected |
| Support URL | https://github.com/vladf1/weight-me/issues |
| Marketing URL | https://github.com/vladf1/weight-me |
| Copyright | 2026 Vladimir Fridman |

## Promotional text (≤170)

Log your weight in a second, see the trend behind the day-to-day swings, and keep every reading in the Health app.

## Description

WeightMe is a simple weight tracker built on the Health app. Log a weight in a second and see where it's really heading.

LOG FAST
• Your latest weight is front and center: drag the ruler or tap the number and save
• Log from Apple Watch with the Digital Crown
• Home Screen and Lock Screen widgets, plus Siri and Shortcuts ("Log my weight in WeightMe")

SEE THE TREND, NOT THE NOISE
• 7-, 30- and 90-day averages and a smoothed trend line, as in The Hacker's Diet
• Ranges from a week to all time
• Lowest, highest, average, change and weekly rate for any range
• Set a goal and see when you'd reach it at your current pace

YOUR DATA STAYS YOURS
• Your weights live in the Health app: no account, no sign-up
• Works with readings from your smart scale or any other app
• WeightMe collects nothing and sends nothing anywhere

BRING YOUR HISTORY
• Import a CSV from Lose It! or another app, with a full review before anything is written and one-tap undo
• Export everything to CSV any time

## Keywords (≤100, comma-separated)

weight tracker,weight loss,scale,diet,trend,log,body,goal,average,widget,watch,pounds,kg,hacker

## App Review notes

WeightMe reads and writes body weight (HKQuantityTypeIdentifierBodyMass) in HealthKit; it has no account or server.
On first launch tap "Connect Apple Health" and allow Weight. With no weight history the Summary shows an empty
state: drag the ruler or tap the number and tap Save to log one. Settings › Import from CSV accepts a Lose It!
export (columns Date, Weight, Last Updated, Deleted). The Apple Watch app shows the latest weight and logs a new
one with the Digital Crown. Siri: "Log my weight in WeightMe".

## TestFlight test information

| Field | Value |
| --- | --- |
| Beta description | Weight tracker built on the Health app: quick logging, trend chart, goal projection, widgets, Apple Watch logging and CSV import from Lose It!. |
| Feedback email | vova_f@yahoo.com |
| What to test | Logging (phone, watch, widget, Siri), the chart and stats, CSV import and undo. |
