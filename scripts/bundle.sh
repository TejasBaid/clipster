#!/usr/bin/env bash
# Builds a release binary and wraps it in build/Clipster.app.
#
# Accessibility permission is tied to the app's code signature. With ad-hoc
# signing the signature changes on every build, so macOS forgets the grant.
# If you have an "Apple Development" certificate (free with any Apple ID in
# Xcode → Settings → Accounts) it's picked up automatically and the grant
# survives rebuilds. Override with CLIPSTER_SIGN_IDENTITY="…".
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
APP=build/Clipster.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Clipster" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

IDENTITY="${CLIPSTER_SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development/ {print $2; exit}')}"
if [[ -z "$IDENTITY" ]]; then
    IDENTITY="-"
    echo "note: ad-hoc signing — you'll need to re-grant Accessibility after each rebuild."
fi
codesign --force --sign "$IDENTITY" "$APP"
echo "built $APP (signed: $IDENTITY)"
