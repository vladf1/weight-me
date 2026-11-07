# Getting WeightMe onto TestFlight

Uploads run in GitHub Actions (`.github/workflows/testflight.yml`), started by hand on `main`. The
workflow runs CI first, archives a Release build signed for the App Store, and uploads it to App Store
Connect with the build number set to the workflow's run number. Until the signing secrets below are
real, it skips the upload and says so in the run's summary.

## Already done in the repo

- Bundle IDs `me.fridman.weightme` (app) and `me.fridman.weightme.widgets` (widget), app group
  `group.me.fridman.weightme`, team `32R3YRS5WJ`.
- Privacy manifests (`PrivacyInfo.xcprivacy`) in the app and the widget; `ITSAppUsesNonExemptEncryption`
  = NO (no export-compliance question per build); `healthkit` as a required device capability.
- App icon without an alpha channel (App Store Connect rejects transparent icons).
- Release archive verified to build; debug-only hooks are compiled out of Release.
- Privacy policy: [PRIVACY.md](../PRIVACY.md) →
  `https://github.com/vladf1/weight-me/blob/main/PRIVACY.md`
- CI (`.github/workflows/ci.yml`): build + unit tests on every push and pull request.
- The seven secrets the upload needs exist in the repo as `STUB …` placeholders.

## One-time steps

Steps 1–3 work in a phone browser. Step 4 is easiest at the Mac.

### 1. Identifiers — developer.apple.com › Certificates, IDs & Profiles › Identifiers

1. **+ › App Groups**: description `WeightMe`, identifier `group.me.fridman.weightme`.
2. **+ › App IDs › App**: description `WeightMe`, explicit bundle ID `me.fridman.weightme`.
   Capabilities: **HealthKit** (leave Clinical Health Records off) and **App Groups** (Configure → pick
   `group.me.fridman.weightme`).
3. **+ › App IDs › App**: description `WeightMe Widgets`, bundle ID `me.fridman.weightme.widgets`.
   Capabilities: **App Groups** (same group).

### 2. Profiles — same site › Profiles

Create two **Distribution › App Store Connect** profiles, both using your existing **Apple Distribution**
certificate (the one Sloppy Tanks' CI signs with):

| App ID | Suggested name |
| --- | --- |
| `me.fridman.weightme` | `WeightMe App Store` |
| `me.fridman.weightme.widgets` | `WeightMe Widgets App Store` |

### 3. App record — appstoreconnect.apple.com

1. **Apps › + › New App**: platform iOS; name `WeightMe` (App Store names are unique — if it's taken,
   try e.g. `WeightMe: Weight Tracker`; the home-screen name stays "WeightMe"); primary language English
   (U.S.); bundle ID `me.fridman.weightme`; SKU `weightme`; full access.
2. **App Information**: category **Health & Fitness**.
3. **App Privacy**: privacy policy URL above; data collection: **Data Not Collected**.
4. **TestFlight › Internal Testing**: create a group (e.g. "Team"), add yourself, turn on automatic
   distribution so every processed build reaches you.

### 4. Real secret values — at the Mac

The first five are **the same values as Sloppy Tanks' secrets of the same names** (same team, same
distribution certificate, same App Store Connect API key). GitHub never shows secret values, so they
come from wherever you keep the original files.

| Secret | Value |
| --- | --- |
| `APP_STORE_CERTIFICATES` | base64 of the `.p12` with the Apple Distribution identity |
| `APP_STORE_CERTIFICATES_PASSWORD` | the `.p12`'s password |
| `NOTARY_API_KEY` | text of the App Store Connect API key (`AuthKey_….p8`) |
| `NOTARY_API_KEY_ID` | the key's ID |
| `NOTARY_API_ISSUER` | the issuer ID (App Store Connect › Users and Access › Integrations) |
| `WEIGHTME_APP_STORE_PROFILE` | base64 of the `WeightMe App Store` profile |
| `WEIGHTME_WIDGET_APP_STORE_PROFILE` | base64 of the `WeightMe Widgets App Store` profile |

The script does the base64 and `gh secret set` for you:

```sh
# Xcode › Settings › Accounts: sign in, select the team, "Download Manual Profiles". Then:
Scripts/set-testflight-secrets.sh \
  --p12 /path/to/AppleDistribution.p12 --p12-password '…' \
  --p8 /path/to/AuthKey_XXXXXXXXXX.p8 --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

No `.p12` at hand? Keychain Access › My Certificates › "Apple Distribution: Vladimir Fridman
(32R3YRS5WJ)" › right-click › Export… as .p12. No `.p8`? It can only be downloaded once; create a new
key in App Store Connect › Users and Access › Integrations › Team Keys (role **Developer** is enough to
upload), and update Sloppy Tanks' secrets too if you retire the old one.

Signing into Xcode also lets local device builds use automatic signing.

### 5. Upload

GitHub › Actions › **TestFlight** › Run workflow (on `main`), or:

```sh
gh workflow run testflight.yml --ref main -R vladf1/weight-me
```

The build shows up in App Store Connect › TestFlight after Apple's processing (usually 5–30 minutes), and
in the TestFlight app on your iPhone/iPad once you're in the internal group.

## Later

- **Version numbers**: `MARKETING_VERSION` in `project.yml` (currently 0.1.0). Bump it after a version is
  released on the App Store; the build number always comes from the workflow run.
- **External testers** need Beta App Review: fill in TestFlight › Test Information (beta description,
  feedback email, privacy policy URL).
- **Yearly**: the distribution certificate and the profiles expire; replace the secrets.
- **When granting Health access**, iOS 27 asks how much history to share; testers should pick
  *All Recorded Data* (the app's onboarding says so).

## Troubleshooting

- *No profiles matching…* / *doesn't include the HealthKit capability*: the App ID was missing a capability
  when the profile was made — edit the App ID, then regenerate and re-upload the profile secret.
- *No suitable application records were found*: create the App Store Connect app record (step 3).
- *Redundant binary upload / bundle version must be higher*: re-run the workflow (new run number).
