#!/bin/bash
# ---------------------------------------------------------------------------
# Export (and optionally upload) the newest tvOS archive for App Store Connect.
#
# Exists because Xcode 27 beta 5 has no Apple Account UI at all: Distribute →
# Upload dies at "No Accounts", and manual signing fails because the tvOS
# provisioning profile predates the 29 Aug 2026 distribution certificate.
# xcodebuild can use the App Store Connect API key that Xcode's UI refuses,
# and -allowProvisioningUpdates repairs that profile on the way through.
#
#   ./tools/export-tvos.sh            # export only  → then send with Transporter
#   ./tools/export-tvos.sh --upload   # export AND deliver to App Store Connect
#
# Nothing here is secret: the key ID and issuer ID are identifiers. The .p8
# itself is the credential — keep it out of this repo.
# ---------------------------------------------------------------------------
set -euo pipefail

TEAM_ID="KDH93W2EVA"
KEY_ID="Y396TPFNTS"
ISSUER_ID="69a6de6e-e8bf-47e3-e053-5b8c7c11a4d1"
BUNDLE_ID="app.rork.guidestream-tv"
OUT_DIR="$HOME/Desktop/gs-tvos-export"

DESTINATION="export"
[ "${1:-}" = "--upload" ] && DESTINATION="upload"

# Use the beta toolchain if it is installed — it is what created the archive.
if [ -d "/Applications/Xcode-beta.app" ]; then
  export DEVELOPER_DIR="/Applications/Xcode-beta.app/Contents/Developer"
fi
echo "▸ xcodebuild: $(xcodebuild -version | head -1)"

# --- 1. newest tvOS archive ------------------------------------------------
ARCHIVE=$(find "$HOME/Library/Developer/Xcode/Archives" -maxdepth 2 -type d \
            -name "GuideStreamTVTV*.xcarchive" -print0 2>/dev/null \
          | xargs -0 -I{} stat -f "%m %N" {} 2>/dev/null \
          | sort -rn | head -1 | cut -d' ' -f2-)
if [ -z "$ARCHIVE" ]; then
  echo "✗ No GuideStreamTVTV archive found under ~/Library/Developer/Xcode/Archives" >&2
  exit 1
fi
echo "▸ Archive: $ARCHIVE"
echo "▸ Version: $(/usr/libexec/PlistBuddy -c 'print :ApplicationProperties:CFBundleShortVersionString' "$ARCHIVE/Info.plist" 2>/dev/null) ($(/usr/libexec/PlistBuddy -c 'print :ApplicationProperties:CFBundleVersion' "$ARCHIVE/Info.plist" 2>/dev/null))"

# --- 2. the .p8 key --------------------------------------------------------
# The key ID is ALWAYS derived from the filename (AuthKey_<ID>.p8) unless
# GS_KEY_ID overrides it. Passing a path but keeping a stale ID is the exact
# mistake that produced "Your Apple Account or password was entered
# incorrectly" — that error means the ID and the file disagree, not that a
# password is wrong anywhere.
#
#   GS_KEY_PATH=/path/AuthKey_XXXX.p8 ./tools/export-tvos.sh --upload
#
# The issuer ID is per-team, not per-key, so a replacement key on the same
# team keeps the same issuer. Override with GS_ISSUER_ID only if it differs.
KEY_PATH="${GS_KEY_PATH:-}"
if [ -n "$KEY_PATH" ] && [ ! -f "$KEY_PATH" ]; then
  echo "✗ GS_KEY_PATH is set but no file there: $KEY_PATH" >&2; exit 1
fi
if [ -z "$KEY_PATH" ]; then
  for d in "$HOME/private_keys" "$HOME/.appstoreconnect/private_keys" \
           "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop"; do
    if [ -f "$d/AuthKey_${KEY_ID}.p8" ]; then KEY_PATH="$d/AuthKey_${KEY_ID}.p8"; break; fi
  done
fi
if [ -z "$KEY_PATH" ]; then
  KEY_PATH=$(find "$HOME" -maxdepth 5 -name "AuthKey_*.p8" -not -path "*/Library/Caches/*" 2>/dev/null | head -1)
fi
if [ -z "$KEY_PATH" ]; then
  echo "✗ Could not find an AuthKey_*.p8." >&2
  echo "  Looked in: ~/private_keys ~/.appstoreconnect/private_keys ~/Downloads ~/Documents ~/Desktop," >&2
  echo "  then anywhere under \$HOME. Point at it directly with:" >&2
  echo "    GS_KEY_PATH=/full/path/AuthKey_XXXX.p8 ./tools/export-tvos.sh --upload" >&2
  echo "  If it is lost, generate a new key at appstoreconnect.apple.com →" >&2
  echo "  Users and Access → Integrations → App Store Connect API (downloadable once only)." >&2
  exit 1
fi

DERIVED_ID=$(basename "$KEY_PATH" .p8); DERIVED_ID="${DERIVED_ID#AuthKey_}"
if [ -n "$DERIVED_ID" ] && [ "$DERIVED_ID" != "$KEY_ID" ]; then
  echo "▸ Key ID from filename: $DERIVED_ID (script default was $KEY_ID)"
  KEY_ID="$DERIVED_ID"
fi
KEY_ID="${GS_KEY_ID:-$KEY_ID}"
ISSUER_ID="${GS_ISSUER_ID:-$ISSUER_ID}"
echo "▸ API key: $KEY_PATH"
echo "▸ Key ID:  $KEY_ID   Issuer: $ISSUER_ID"

# --- 3. export options -----------------------------------------------------
PLIST=$(mktemp -t gs-export).plist
cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>${DESTINATION}</string>
  <key>teamID</key><string>${TEAM_ID}</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
</dict>
</plist>
PLISTEOF
echo "▸ Destination: $DESTINATION"

# --- 4. go -----------------------------------------------------------------
rm -rf "$OUT_DIR"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$OUT_DIR" \
  -exportOptionsPlist "$PLIST" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$KEY_ID" \
  -authenticationKeyIssuerID "$ISSUER_ID"

echo
if [ "$DESTINATION" = "upload" ]; then
  echo "✓ Delivered to App Store Connect. It appears in TestFlight after processing."
else
  echo "✓ Exported to: $OUT_DIR"
  ls -la "$OUT_DIR" 2>/dev/null | sed 's/^/    /'
  echo
  echo "  Next: Transporter → + → cmd+shift+G → paste the .ipa path above → Deliver."
  echo "  Or re-run this script with --upload to skip Transporter entirely."
fi
