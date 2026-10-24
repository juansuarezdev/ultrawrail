#!/usr/bin/env bash
# Builds build/Linkr.app. Set SIGN_IDENTITY to a stable identity (for example an
# "Apple Development" certificate) so the Accessibility grant survives rebuilds;
# the default ad-hoc signature changes on every build.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${CONFIG:-release}"
IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Linkr.app"

swift build -c "$CONFIG"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/$CONFIG/LinkrApp" "$APP/Contents/MacOS/Linkr"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign "$IDENTITY" --identifier dev.linkr.app "$APP"

echo "Built $APP"
