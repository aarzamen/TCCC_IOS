#!/bin/bash
# Archive the Release build and export a signed IPA named TCCC-<version>-<sha>.ipa.
#
# Usage:
#   scripts/archive_and_export.sh [--method debugging|release-testing] [--team TEAM_ID]
#                                 [--out DIR] [--without-offline-models]
#                                 [--allow-provisioning-updates]
#
#   --method   Export method. "debugging" is Xcode's name for a development
#              export (default); "release-testing" is ad hoc. Both install on
#              registered devices only; neither touches App Store Connect.
#   --team     Apple Developer team ID. Otherwise TCCC_DEVELOPMENT_TEAM, otherwise
#              DEVELOPMENT_TEAM from Config/Signing.xcconfig (untracked; copy
#              Config/Signing.xcconfig.example). Never written to a tracked file.
#   --out      Output folder (default build/export, ignored by git).
#   --without-offline-models
#              Release builds require TCCC_OFFLINE_MODELS_DIR (the verified
#              offline model pack, see tools/embed_offline_models.sh). This flag
#              builds without it: new installs then download models on demand.
#   --allow-provisioning-updates
#              Passes -allowProvisioningUpdates to xcodebuild. Off by default:
#              APPLE_DEVELOPER_WARNING.md rule 2 requires the owner's explicit OK
#              in the same session before anything touches the developer account.
#
# Steps: xcodegen generate → xcodebuild archive (Release, generic iOS)
#        → ExportOptions.plist written into the output folder (it carries the
#        team ID, so it is generated, never committed) → xcodebuild -exportArchive
#        → rename to TCCC-<version>-<sha>.ipa, print size and SHA-256.
#
# <version> is CFBundleShortVersionString from the archived app (1.0 for the tag);
# <sha> is the short git SHA with a trailing "+" when the tree is dirty, the same
# identity the in-app build stamp shows. With only the Qwen weights embedded the
# IPA should be about 1 to 1.5 GB, under GitHub's 2 GB per-file release limit.
set -euo pipefail

METHOD="debugging"
TEAM="${TCCC_DEVELOPMENT_TEAM:-}"
OUT="build/export"
REQUIRE_MODELS="YES"
PROVISIONING=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) METHOD="$2"; shift 2 ;;
    --team) TEAM="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --without-offline-models) REQUIRE_MODELS="NO"; shift ;;
    --allow-provisioning-updates) PROVISIONING=(-allowProvisioningUpdates); shift ;;
    -h|--help) sed -n '2,36p' "$0"; exit 0 ;;
    *) echo "error: unknown argument $1" >&2; exit 2 ;;
  esac
done
case "$METHOD" in
  debugging|release-testing) ;;
  development) METHOD="debugging" ;;
  ad-hoc) METHOD="release-testing" ;;
  *) echo "error: --method must be debugging (development) or release-testing (ad hoc)" >&2; exit 2 ;;
esac

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

if [[ -z "$TEAM" && -f Config/Signing.xcconfig ]]; then
  TEAM="$(sed -n 's/^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*\([A-Za-z0-9]*\).*/\1/p' Config/Signing.xcconfig | head -1)"
fi
if [[ -z "$TEAM" || "$TEAM" == "YOUR_TEAM_ID" ]]; then
  echo "error: no team ID. Pass --team, set TCCC_DEVELOPMENT_TEAM, or create Config/Signing.xcconfig" >&2
  echo "       from Config/Signing.xcconfig.example (see APPLE_DEVELOPER_WARNING.md)." >&2
  exit 2
fi
if [[ "$REQUIRE_MODELS" == "YES" && -z "${TCCC_OFFLINE_MODELS_DIR:-}" ]]; then
  echo "error: Release builds embed the verified offline model pack and need TCCC_OFFLINE_MODELS_DIR." >&2
  echo "       Set it (see tools/embed_offline_models.sh) or pass --without-offline-models." >&2
  exit 2
fi

SHA="$(git rev-parse --short HEAD)"
if [[ -n "$(git status --porcelain)" ]]; then SHA="${SHA}+"; fi
STAMP="$(date +%Y%m%d-%H%M%S)"
mkdir -p "$OUT"
ARCHIVE="$OUT/TCCC-${STAMP}-${SHA}.xcarchive"
EXPORT_DIR="$OUT/TCCC-${STAMP}-${SHA}-export"

echo "→ xcodegen generate"
xcodegen generate

echo "→ archiving Release (team $TEAM, method $METHOD)"
xcodebuild archive \
  -project TCCC_IOS.xcodeproj -scheme TCCC_IOS -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -skipMacroValidation "${PROVISIONING[@]}" \
  DEVELOPMENT_TEAM="$TEAM" TCCC_REQUIRE_OFFLINE_MODELS="$REQUIRE_MODELS"

APP_PLIST="$ARCHIVE/Products/Applications/TCCC_IOS.app/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PLIST")"

OPTIONS="$OUT/ExportOptions-${STAMP}.plist"
cat > "$OPTIONS" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTD/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>${METHOD}</string>
  <key>teamID</key><string>${TEAM}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>destination</key><string>export</string>
  <key>compileBitcode</key><false/>
  <key>stripSwiftSymbols</key><true/>
  <key>thinning</key><string>&lt;none&gt;</string>
</dict>
</plist>
PLIST

echo "→ exporting IPA"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$OPTIONS" -exportPath "$EXPORT_DIR" "${PROVISIONING[@]}"

IPA_SRC="$(find "$EXPORT_DIR" -maxdepth 1 -name '*.ipa' | head -1)"
if [[ -z "$IPA_SRC" ]]; then echo "error: export produced no .ipa in $EXPORT_DIR" >&2; exit 1; fi
IPA="$OUT/TCCC-${VERSION}-${SHA}.ipa"
mv -f "$IPA_SRC" "$IPA"

SIZE_MB=$(( $(stat -f%z "$IPA") / 1048576 ))
echo "✓ $IPA"
echo "  version $VERSION build $BUILD sha $SHA method $METHOD · ${SIZE_MB} MB"
echo "  sha256 $(shasum -a 256 "$IPA" | cut -d' ' -f1)"
if (( SIZE_MB > 2000 )); then echo "  warning: over GitHub's 2 GB per-file release limit"; fi
echo "  archive kept at $ARCHIVE (ExportOptions in $OPTIONS; both under the ignored build/ folder)"
