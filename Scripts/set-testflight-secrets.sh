#!/bin/zsh
# Stores the TestFlight workflow's signing secrets in the GitHub repository (see docs/TESTFLIGHT.md).
#
#   Scripts/set-testflight-secrets.sh                 # just WeightMe's two App Store profiles
#   Scripts/set-testflight-secrets.sh \
#     --p12 Distribution.p12 --p12-password '…' \
#     --p8 AuthKey_ABC123XYZ.p8 --issuer 69a6de7e-…     # also the shared certificate and API key
#
# Profiles are looked up among the ones Xcode has downloaded (Xcode › Settings › Accounts ›
# Download Manual Profiles), or pass --app-profile / --widget-profile with .mobileprovision files.
set -euo pipefail

REPO=vladf1/weight-me
TEAM=32R3YRS5WJ
APP_ID=me.fridman.weightme
WIDGET_ID=me.fridman.weightme.widgets

p12="" p12_password="" p8="" issuer="" app_profile="" widget_profile=""
while (( $# )); do
  case $1 in
    --p12) p12=$2; shift 2 ;;
    --p12-password) p12_password=$2; shift 2 ;;
    --p8) p8=$2; shift 2 ;;
    --issuer) issuer=$2; shift 2 ;;
    --app-profile) app_profile=$2; shift 2 ;;
    --widget-profile) widget_profile=$2; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

gh auth status >/dev/null

# Newest unexpired App Store (no device list) profile for a bundle ID.
find_profile() {
  local bundle=$1 best="" best_created="" file info
  for file in "$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"/*.mobileprovision(N) \
              "$HOME/Library/MobileDevice/Provisioning Profiles"/*.mobileprovision(N); do
    info=$(security cms -D -i "$file" 2>/dev/null) || continue
    [[ $(plutil -extract Entitlements.application-identifier raw - <<<"$info") == "$TEAM.$bundle" ]] || continue
    plutil -extract ProvisionedDevices raw - <<<"$info" >/dev/null 2>&1 && continue      # development / ad hoc
    [[ $(plutil -extract ProvisionsAllDevices raw - <<<"$info" 2>/dev/null) == true ]] && continue  # enterprise
    local expires=$(plutil -extract ExpirationDate raw - <<<"$info")
    [[ $expires > $(date -u +%Y-%m-%dT%H:%M:%SZ) ]] || continue
    local created=$(plutil -extract CreationDate raw - <<<"$info")
    if [[ -z $best || $created > $best_created ]]; then best=$file; best_created=$created; fi
  done
  echo "$best"
}

describe() { security cms -D -i "$1" | plutil -extract Name raw -; }

[[ -n $app_profile ]] || app_profile=$(find_profile $APP_ID)
[[ -n $widget_profile ]] || widget_profile=$(find_profile $WIDGET_ID)
if [[ -z $app_profile || -z $widget_profile ]]; then
  echo "Couldn't find App Store profiles for $APP_ID and $WIDGET_ID." >&2
  echo "Create them on developer.apple.com (docs/TESTFLIGHT.md), then Xcode › Settings › Accounts ›" >&2
  echo "Download Manual Profiles, or pass --app-profile/--widget-profile." >&2
  exit 1
fi
echo "App profile:    $(describe "$app_profile")"
echo "Widget profile: $(describe "$widget_profile")"
base64 -i "$app_profile" | gh secret set WEIGHTME_APP_STORE_PROFILE -R $REPO
base64 -i "$widget_profile" | gh secret set WEIGHTME_WIDGET_APP_STORE_PROFILE -R $REPO

if [[ -n $p12 ]]; then
  [[ -n $p12_password ]] || { echo "--p12 needs --p12-password" >&2; exit 2; }
  base64 -i "$p12" | gh secret set APP_STORE_CERTIFICATES -R $REPO
  printf '%s' "$p12_password" | gh secret set APP_STORE_CERTIFICATES_PASSWORD -R $REPO
fi
if [[ -n $p8 ]]; then
  [[ -n $issuer ]] || { echo "--p8 needs --issuer" >&2; exit 2; }
  key_id=$(basename "$p8" .p8); key_id=${key_id#AuthKey_}
  gh secret set NOTARY_API_KEY -R $REPO < "$p8"
  printf '%s' "$key_id" | gh secret set NOTARY_API_KEY_ID -R $REPO
  printf '%s' "$issuer" | gh secret set NOTARY_API_ISSUER -R $REPO
fi

echo "Done. Secrets now set on $REPO:"
gh secret list -R $REPO
echo "Start an upload with: gh workflow run testflight.yml --ref main -R $REPO"
