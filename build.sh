#!/bin/bash
# Builds ProDisplay.app into ./build using SwiftPM (no Xcode required).
# Usage: ./build.sh            build only
#        ./build.sh install    build, then replace /Applications/ProDisplay.app and relaunch
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

# Assemble and sign outside this folder: iCloud Drive adds Finder attributes
# to bundles in Documents, which codesign rejects.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ProDisplay.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/ProDisplay "$APP/Contents/MacOS/ProDisplay"
cp Resources/Info.plist "$APP/Contents/Info.plist"
xattr -cr "$APP"

# Sign with the local self-signed certificate when present, so macOS permissions
# (Accessibility) survive rebuilds; otherwise fall back to ad-hoc signing.
IDENTITY="ProDisplay Local Signing"
if security find-identity -p codesigning | grep -q "\"$IDENTITY\""; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    echo "warning: '$IDENTITY' certificate not found; signing ad-hoc"
    codesign --force --sign - "$APP"
fi

mkdir -p build
rm -rf build/ProDisplay.app
ditto "$APP" build/ProDisplay.app
echo "Built build/ProDisplay.app"

if [[ "${1:-}" == "install" ]]; then
    pkill -x ProDisplay && sleep 1 || true
    rm -rf /Applications/ProDisplay.app
    ditto "$APP" /Applications/ProDisplay.app
    open /Applications/ProDisplay.app
    echo "Installed /Applications/ProDisplay.app"
fi
